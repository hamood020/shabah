#import "SHPrefix.h"

NS_ASSUME_NONNULL_BEGIN

/// Compares SH_VERSION with the latest GitHub release of the project.
@interface SHUpdateChecker : NSObject

/// Without `force`, checks at most once a day and only when the setting is on.
/// `newerVersion` is nil when there is nothing newer (or the check failed).
+ (void)checkForce:(BOOL)force
        completion:(void (^)(NSString *_Nullable newerVersion, NSURL *_Nullable pageURL, BOOL failed))completion;

@end

NS_ASSUME_NONNULL_END
