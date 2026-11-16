#import "SHLocationHooks.h"
#import "SHPersistence.h"
#import <objc/runtime.h>
#import <objc/message.h>

// Original implementations.
static IMP gOrigLocation;
static IMP gOrigSetDelegate;
static IMP gOrigStartUpdating;
static IMP gOrigStopUpdating;
static IMP gOrigRequestLocation;
static IMP gOrigRequestState;
static IMP gOrigMKLocation;
static IMP gOrigMKCoordinate;

static SEL gDidUpdateSel;
static SEL gLegacyUpdateSel;
static SEL gEnterSel;
static SEL gExitSel;
static SEL gStateSel;

static NSMutableSet<NSString *> *gSwizzledDelegateClasses;
static NSHashTable<CLLocationManager *> *gActiveManagers;    // currently updating location
static NSHashTable<CLLocationManager *> *gKnownManagers;     // every manager with a delegate
static NSMutableDictionary<NSString *, NSNumber *> *gRegionStates;
static NSTimer *gPushTimer;

/// YES while we call a delegate ourselves, so the wrappers can tell our calls
/// from real Core Location events. Delivery always happens on the main thread.
static BOOL gDelivering;

/// Replaces `sel` on `cls` with `block` and returns the previous IMP.
/// If the method is inherited, it is added to `cls` so the superclass is untouched.
static IMP SHReplace(Class cls, SEL sel, id block) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        SH_LOG(@"method not found: -[%@ %@]", NSStringFromClass(cls), NSStringFromSelector(sel));
        return NULL;
    }
    IMP original = method_getImplementation(m);
    IMP replacement = imp_implementationWithBlock(block);
    if (!class_addMethod(cls, sel, replacement, method_getTypeEncoding(m))) {
        original = method_setImplementation(m, replacement);
    }
    return original;
}

static void SHInstall(Class cls, SEL sel, Method m, id block) {
    IMP replacement = imp_implementationWithBlock(block);
    if (!class_addMethod(cls, sel, replacement, method_getTypeEncoding(m))) {
        method_setImplementation(m, replacement);
    }
}

static BOOL SHSpoofingRegions(CLRegion *region) {
    return [region isKindOfClass:CLCircularRegion.class] && [SHPersistence shared].isSpoofing;
}

#pragma mark - Delegate wrappers

static void SHWrapDidUpdate(Class cls) {
    SEL sel = gDidUpdateSel;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    typedef void (*Fn)(id, SEL, CLLocationManager *, NSArray *);
    Fn original = (Fn)method_getImplementation(m);
    SHInstall(cls, sel, m, ^(id me, CLLocationManager *manager, NSArray *locations) {
        if (!gDelivering && [locations.lastObject isKindOfClass:CLLocation.class]) {
            [SHPersistence shared].lastRealLocation = locations.lastObject;   // for the "real location" pin
        }
        CLLocation *spoof = [[SHPersistence shared] currentSpoofedLocation];
        original(me, sel, manager, spoof ? @[spoof] : locations);
    });
}

/// Old apps still implement the iOS 5 callback.
static void SHWrapLegacyUpdate(Class cls) {
    SEL sel = gLegacyUpdateSel;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    typedef void (*Fn)(id, SEL, CLLocationManager *, CLLocation *, CLLocation *);
    Fn original = (Fn)method_getImplementation(m);
    SHInstall(cls, sel, m, ^(id me, CLLocationManager *manager, CLLocation *newLocation, CLLocation *oldLocation) {
        if (!gDelivering && newLocation) [SHPersistence shared].lastRealLocation = newLocation;
        CLLocation *spoof = [[SHPersistence shared] currentSpoofedLocation];
        original(me, sel, manager, spoof ?: newLocation, spoof ?: oldLocation);
    });
}

/// While spoofing, real geofence events would contradict the fake position, so
/// they are dropped and replaced by events computed from the spoofed point.
static void SHWrapRegionEvents(Class cls) {
    typedef void (*RegionFn)(id, SEL, CLLocationManager *, CLRegion *);
    for (NSValue *boxed in @[[NSValue valueWithPointer:gEnterSel], [NSValue valueWithPointer:gExitSel]]) {
        SEL sel = (SEL)boxed.pointerValue;
        Method m = class_getInstanceMethod(cls, sel);
        if (!m) continue;
        RegionFn original = (RegionFn)method_getImplementation(m);
        SHInstall(cls, sel, m, ^(id me, CLLocationManager *manager, CLRegion *region) {
            if (!gDelivering && SHSpoofingRegions(region)) return;
            original(me, sel, manager, region);
        });
    }

    SEL sel = gStateSel;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    typedef void (*StateFn)(id, SEL, CLLocationManager *, CLRegionState, CLRegion *);
    StateFn original = (StateFn)method_getImplementation(m);
    SHInstall(cls, sel, m, ^(id me, CLLocationManager *manager, CLRegionState state, CLRegion *region) {
        if (!gDelivering && SHSpoofingRegions(region)) return;
        original(me, sel, manager, state, region);
    });
}

static void SHSwizzleDelegateClass(Class cls) {
    if (!cls) return;
    NSString *name = NSStringFromClass(cls);
    @synchronized (gSwizzledDelegateClasses) {
        if ([gSwizzledDelegateClasses containsObject:name]) return;
        [gSwizzledDelegateClasses addObject:name];
    }
    SHWrapDidUpdate(cls);
    SHWrapLegacyUpdate(cls);
    SHWrapRegionEvents(cls);
    SH_LOG(@"hooked delegate %@", name);
}

#pragma mark - Pushing updates

static void SHDeliver(CLLocationManager *manager, CLLocation *location) {
    id<CLLocationManagerDelegate> delegate = manager.delegate;
    gDelivering = YES;
    if ([delegate respondsToSelector:gDidUpdateSel]) {
        [delegate locationManager:manager didUpdateLocations:@[location]];
    } else if ([delegate respondsToSelector:gLegacyUpdateSel]) {
        ((void (*)(id, SEL, CLLocationManager *, CLLocation *, CLLocation *))objc_msgSend)(delegate, gLegacyUpdateSel, manager, location, location);
    }
    gDelivering = NO;
}

static NSString *SHRegionKey(CLLocationManager *manager, CLRegion *region) {
    return [NSString stringWithFormat:@"%p|%@", manager, region.identifier];
}

static void SHDeliverRegionState(CLLocationManager *manager, CLRegion *region, BOOL inside, BOOL transition) {
    id<CLLocationManagerDelegate> delegate = manager.delegate;
    gDelivering = YES;
    if ([delegate respondsToSelector:gStateSel]) {
        [delegate locationManager:manager didDetermineState:(inside ? CLRegionStateInside : CLRegionStateOutside) forRegion:region];
    }
    if (transition) {
        if (inside && [delegate respondsToSelector:gEnterSel]) [delegate locationManager:manager didEnterRegion:region];
        if (!inside && [delegate respondsToSelector:gExitSel]) [delegate locationManager:manager didExitRegion:region];
    }
    gDelivering = NO;
}

/// Sends enter/exit events when the spoofed point crosses a monitored geofence.
static void SHRegionTick(CLLocation *spoof) {
    if (!spoof) {
        [gRegionStates removeAllObjects];   // real events take over again
        return;
    }
    NSArray<CLLocationManager *> *managers;
    @synchronized (gKnownManagers) { managers = gKnownManagers.allObjects; }
    for (CLLocationManager *manager in managers) {
        for (CLRegion *region in manager.monitoredRegions) {
            if (![region isKindOfClass:CLCircularRegion.class]) continue;
            BOOL inside = [(CLCircularRegion *)region containsCoordinate:spoof.coordinate];
            NSString *key = SHRegionKey(manager, region);
            NSNumber *previous = gRegionStates[key];
            if (previous && previous.boolValue == inside) continue;
            gRegionStates[key] = @(inside);
            // First sighting: only report entering, never a fake "exit".
            if (previous || inside) SHDeliverRegionState(manager, region, inside, YES);
        }
    }
}

/// Apps only get callbacks when the real GPS fires. While spoofing we also push
/// the fake location once per second, so apps keep updating indoors or when the
/// real GPS is slow.
static void SHPushTick(void) {
    CLLocation *spoof = [[SHPersistence shared] currentSpoofedLocation];
    SHRegionTick(spoof);
    if (!spoof) return;
    NSArray<CLLocationManager *> *managers;
    @synchronized (gActiveManagers) { managers = gActiveManagers.allObjects; }
    for (CLLocationManager *manager in managers) SHDeliver(manager, spoof);
}

#pragma mark - Install

static void SHInstallCLLocationManagerHooks(void) {
    Class cls = [CLLocationManager class];

    gOrigLocation = SHReplace(cls, @selector(location), ^CLLocation *(CLLocationManager *me) {
        CLLocation *spoof = [[SHPersistence shared] currentSpoofedLocation];
        if (spoof) return spoof;
        return ((CLLocation *(*)(id, SEL))gOrigLocation)(me, @selector(location));
    });

    gOrigSetDelegate = SHReplace(cls, @selector(setDelegate:), ^(CLLocationManager *me, id delegate) {
        if (delegate) {
            SHSwizzleDelegateClass(object_getClass(delegate));
            @synchronized (gKnownManagers) { [gKnownManagers addObject:me]; }
        }
        ((void (*)(id, SEL, id))gOrigSetDelegate)(me, @selector(setDelegate:), delegate);
    });

    gOrigStartUpdating = SHReplace(cls, @selector(startUpdatingLocation), ^(CLLocationManager *me) {
        @synchronized (gActiveManagers) { [gActiveManagers addObject:me]; }
        ((void (*)(id, SEL))gOrigStartUpdating)(me, @selector(startUpdatingLocation));
    });

    gOrigStopUpdating = SHReplace(cls, @selector(stopUpdatingLocation), ^(CLLocationManager *me) {
        @synchronized (gActiveManagers) { [gActiveManagers removeObject:me]; }
        ((void (*)(id, SEL))gOrigStopUpdating)(me, @selector(stopUpdatingLocation));
    });

    gOrigRequestLocation = SHReplace(cls, @selector(requestLocation), ^(CLLocationManager *me) {
        ((void (*)(id, SEL))gOrigRequestLocation)(me, @selector(requestLocation));
        __weak CLLocationManager *weakManager = me;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            CLLocationManager *manager = weakManager;
            CLLocation *spoof = [[SHPersistence shared] currentSpoofedLocation];
            if (manager && spoof) SHDeliver(manager, spoof);
        });
    });

    gOrigRequestState = SHReplace(cls, @selector(requestStateForRegion:), ^(CLLocationManager *me, CLRegion *region) {
        ((void (*)(id, SEL, CLRegion *))gOrigRequestState)(me, @selector(requestStateForRegion:), region);
        if (![region isKindOfClass:CLCircularRegion.class]) return;
        __weak CLLocationManager *weakManager = me;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            CLLocationManager *manager = weakManager;
            CLLocation *spoof = [[SHPersistence shared] currentSpoofedLocation];
            if (!manager || !spoof) return;
            BOOL inside = [(CLCircularRegion *)region containsCoordinate:spoof.coordinate];
            SHDeliverRegionState(manager, region, inside, NO);
        });
    });
}

static void SHInstallMKUserLocationHooks(void) {
    Class cls = [MKUserLocation class];

    gOrigMKLocation = SHReplace(cls, @selector(location), ^CLLocation *(id me) {
        CLLocation *spoof = [[SHPersistence shared] currentSpoofedLocation];
        if (spoof) return spoof;
        return ((CLLocation *(*)(id, SEL))gOrigMKLocation)(me, @selector(location));
    });

    gOrigMKCoordinate = SHReplace(cls, @selector(coordinate), ^CLLocationCoordinate2D(id me) {
        SHPersistence *store = [SHPersistence shared];
        if (store.isSpoofing) return store.coordinate;
        return ((CLLocationCoordinate2D (*)(id, SEL))gOrigMKCoordinate)(me, @selector(coordinate));
    });
}

void SHInstallLocationHooks(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gDidUpdateSel = @selector(locationManager:didUpdateLocations:);
        gLegacyUpdateSel = NSSelectorFromString(@"locationManager:didUpdateToLocation:fromLocation:");
        gEnterSel = @selector(locationManager:didEnterRegion:);
        gExitSel = @selector(locationManager:didExitRegion:);
        gStateSel = @selector(locationManager:didDetermineState:forRegion:);
        gSwizzledDelegateClasses = [NSMutableSet set];
        gActiveManagers = [NSHashTable weakObjectsHashTable];
        gKnownManagers = [NSHashTable weakObjectsHashTable];
        gRegionStates = [NSMutableDictionary dictionary];

        SHInstallCLLocationManagerHooks();
        SHInstallMKUserLocationHooks();

        dispatch_async(dispatch_get_main_queue(), ^{
            gPushTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
                SHPushTick();
            }];
            gPushTimer.tolerance = 0.2;
        });
        SH_LOG(@"location hooks installed");
    });
}
