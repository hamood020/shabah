#import "SHLocationHooks.h"
#import "SHPersistence.h"
#import <objc/runtime.h>

// Original implementations.
static IMP gOrigLocation;
static IMP gOrigSetDelegate;
static IMP gOrigStartUpdating;
static IMP gOrigStopUpdating;
static IMP gOrigRequestLocation;
static IMP gOrigMKLocation;
static IMP gOrigMKCoordinate;

static SEL gDidUpdateSel;
static NSMutableSet<NSString *> *gSwizzledDelegateClasses;
static NSHashTable<CLLocationManager *> *gActiveManagers;
static NSTimer *gPushTimer;

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

#pragma mark - Delegate swizzling

/// Wraps -locationManager:didUpdateLocations: on the delegate's class so every
/// real GPS update is replaced with the spoofed location.
static void SHSwizzleDelegateClass(Class cls) {
    if (!cls) return;
    NSString *name = NSStringFromClass(cls);
    @synchronized (gSwizzledDelegateClasses) {
        if ([gSwizzledDelegateClasses containsObject:name]) return;
        [gSwizzledDelegateClasses addObject:name];
    }

    Method m = class_getInstanceMethod(cls, gDidUpdateSel);
    if (!m) return;

    typedef void (*DidUpdateFn)(id, SEL, CLLocationManager *, NSArray *);
    DidUpdateFn original = (DidUpdateFn)method_getImplementation(m);
    SEL sel = gDidUpdateSel;

    IMP replacement = imp_implementationWithBlock(^(id me, CLLocationManager *manager, NSArray *locations) {
        CLLocation *spoof = [[SHPersistence shared] currentSpoofedLocation];
        original(me, sel, manager, spoof ? @[spoof] : locations);
    });
    if (!class_addMethod(cls, sel, replacement, method_getTypeEncoding(m))) {
        method_setImplementation(m, replacement);
    }
    SH_LOG(@"hooked delegate %@", name);
}

#pragma mark - Pushing updates

static void SHDeliver(CLLocationManager *manager, CLLocation *location) {
    id<CLLocationManagerDelegate> delegate = manager.delegate;
    if ([delegate respondsToSelector:gDidUpdateSel]) {
        [delegate locationManager:manager didUpdateLocations:@[location]];
    }
}

/// Apps only get callbacks when the real GPS fires. While spoofing we also push
/// the fake location once per second, so apps keep updating indoors or when the
/// real GPS is slow.
static void SHPushTick(void) {
    CLLocation *spoof = [[SHPersistence shared] currentSpoofedLocation];
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
        if (delegate) SHSwizzleDelegateClass(object_getClass(delegate));
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
        gSwizzledDelegateClasses = [NSMutableSet set];
        gActiveManagers = [NSHashTable weakObjectsHashTable];

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
