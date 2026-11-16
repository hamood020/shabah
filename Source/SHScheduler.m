#import "SHScheduler.h"
#import "SHPersistence.h"
#import "SHMovementEngine.h"
#import <UserNotifications/UserNotifications.h>

static NSString *const kAppliedWindowKey = @"SHScheduleAppliedWindow";
static NSString *const kNotifyWarning = @"shabah.expiry.warning";
static NSString *const kNotifyStopped = @"shabah.expiry.stopped";

@implementation SHScheduler {
    NSTimer *_timer;
    NSDate *_scheduledExpiry;   // expiry date the current notifications were built for
}

+ (instancetype)shared {
    static SHScheduler *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (void)start {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_timer) return;
        __weak typeof(self) weakSelf = self;
        self->_timer = [NSTimer scheduledTimerWithTimeInterval:20 repeats:YES block:^(NSTimer *t) { [weakSelf evaluate]; }];
        self->_timer.tolerance = 5;
        [[NSNotificationCenter defaultCenter] addObserverForName:SHStateChangedNotification object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *n) { [weakSelf evaluate]; }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *n) { [weakSelf evaluate]; }];
        [self evaluate];
    });
}

#pragma mark - Schedule

/// Identifies one occurrence of the window, e.g. "2026-11-16@420", so it is applied once
/// and a manual stop in the middle of the window is respected.
- (nullable NSString *)currentWindowKey {
    SHPersistence *store = [SHPersistence shared];
    if (!store.scheduleEnabled || !store.scheduleLocation || store.scheduleDays.count == 0) return nil;

    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *now = [NSDate date];
    NSDateComponents *parts = [cal components:NSCalendarUnitWeekday | NSCalendarUnitHour | NSCalendarUnitMinute fromDate:now];
    NSInteger minutes = parts.hour * 60 + parts.minute;
    NSInteger start = store.scheduleStartMinutes, end = store.scheduleEndMinutes;
    if (start == end) return nil;

    // A window that crosses midnight (e.g. 22:00 to 06:00) belongs to the day it started.
    NSDate *windowDay = now;
    BOOL inside;
    if (start < end) {
        inside = minutes >= start && minutes < end;
    } else {
        inside = minutes >= start || minutes < end;
        if (minutes < end) windowDay = [cal dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:now options:0];
    }
    if (!inside) return nil;

    NSInteger weekday = [cal component:NSCalendarUnitWeekday fromDate:windowDay];
    if (![store.scheduleDays containsObject:@(weekday)]) return nil;

    NSDateComponents *ymd = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:windowDay];
    return [NSString stringWithFormat:@"%04ld-%02ld-%02ld@%ld", (long)ymd.year, (long)ymd.month, (long)ymd.day, (long)start];
}

- (BOOL)isScheduleActive {
    NSString *applied = [[NSUserDefaults standardUserDefaults] stringForKey:kAppliedWindowKey];
    return applied && [applied isEqualToString:[self currentWindowKey]] && [SHPersistence shared].isSpoofing;
}

- (void)evaluate {
    SHPersistence *store = [SHPersistence shared];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *window = [self currentWindowKey];
    NSString *applied = [d stringForKey:kAppliedWindowKey];

    if (window && ![window isEqualToString:applied]) {
        NSDictionary *place = store.scheduleLocation;
        CLLocationCoordinate2D c = CLLocationCoordinate2DMake([place[@"lat"] doubleValue], [place[@"lon"] doubleValue]);
        if (CLLocationCoordinate2DIsValid(c)) {
            [d setObject:window forKey:kAppliedWindowKey];
            [[SHMovementEngine shared] stop];
            [store startSpoofingAt:c];
            [store recordRecent:c name:place[@"name"]];
            SH_LOG(@"schedule started window %@", window);
        }
    } else if (!window && applied) {
        // Window ended: stop only if the schedule was the one that started it.
        [d removeObjectForKey:kAppliedWindowKey];
        NSDictionary *place = store.scheduleLocation;
        CLLocationCoordinate2D scheduled = CLLocationCoordinate2DMake([place[@"lat"] doubleValue], [place[@"lon"] doubleValue]);
        BOOL stillAtScheduledPlace = place && SHDistance(store.coordinate, scheduled) < 100;
        if (store.isSpoofing && stillAtScheduledPlace && [SHMovementEngine shared].mode == SHEngineModeIdle) {
            [store stopSpoofing];
            SH_LOG(@"schedule window ended, stopped");
        }
    }

    [self updateExpiryNotifications];
}

- (NSString *)nextEventDescription {
    SHPersistence *store = [SHPersistence shared];
    if (!store.scheduleEnabled) return nil;
    NSString *(^fmt)(NSInteger) = ^NSString *(NSInteger m) {
        return [NSString stringWithFormat:@"%02ld:%02ld", (long)(m / 60), (long)(m % 60)];
    };
    NSString *window = [self currentWindowKey];
    if (window) return [NSString stringWithFormat:SHText(@"sched_active_until_fmt"), fmt(store.scheduleEndMinutes)];
    return [NSString stringWithFormat:SHText(@"sched_next_fmt"), fmt(store.scheduleStartMinutes)];
}

#pragma mark - Expiry notifications

- (void)requestNotificationPermission:(void (^)(BOOL))completion {
    [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound
        completionHandler:^(BOOL granted, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(granted); });
        }];
}

- (void)updateExpiryNotifications {
    SHPersistence *store = [SHPersistence shared];
    NSDate *expiry = store.isSpoofing && store.expiryNotifications ? store.expiryDate : nil;
    if ((expiry == nil && _scheduledExpiry == nil) || [expiry isEqualToDate:_scheduledExpiry]) return;
    _scheduledExpiry = expiry;

    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center removePendingNotificationRequestsWithIdentifiers:@[kNotifyWarning, kNotifyStopped]];
    if (!expiry) return;

    NSTimeInterval left = expiry.timeIntervalSinceNow;
    if (left > 6 * 60) [self addNotification:kNotifyWarning body:SHText(@"notify_warning") after:left - 5 * 60];
    if (left > 1) [self addNotification:kNotifyStopped body:SHText(@"notify_stopped") after:left];
}

- (void)addNotification:(NSString *)identifier body:(NSString *)body after:(NSTimeInterval)seconds {
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.title = SHText(@"app_name");
    content.body = body;
    content.sound = [UNNotificationSound defaultSound];
    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:MAX(1, seconds) repeats:NO];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:^(NSError *error) {
        if (error) SH_LOG(@"notification error: %@", error.localizedDescription);
    }];
}

@end
