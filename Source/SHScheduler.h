#import "SHPrefix.h"

NS_ASSUME_NONNULL_BEGIN

/// Weekly schedule: spoofs the chosen place on the chosen weekdays between
/// two times, and stops at the end of the window. Also schedules local
/// notifications before and at the auto-stop time.
@interface SHScheduler : NSObject

+ (instancetype)shared;
- (void)start;
/// YES while the current spoof was started by the schedule.
@property (nonatomic, readonly, getter=isScheduleActive) BOOL scheduleActive;
/// Human-readable next start / end, for the settings screen.
- (nullable NSString *)nextEventDescription;
/// Asks for notification permission; completion runs on the main thread.
- (void)requestNotificationPermission:(void (^)(BOOL granted))completion;

@end

NS_ASSUME_NONNULL_END
