#import "SHPrefix.h"

NS_ASSUME_NONNULL_BEGIN

@interface SHSettingsViewController : UITableViewController
/// Called after the language or map style changes, so the map screen can rebuild.
@property (nonatomic, copy, nullable) void (^onChange)(void);
@end

NS_ASSUME_NONNULL_END
