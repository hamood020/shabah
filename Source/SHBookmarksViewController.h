#import "SHPrefix.h"

NS_ASSUME_NONNULL_BEGIN

@interface SHBookmarksViewController : UITableViewController
@property (nonatomic, copy, nullable) void (^onSelect)(CLLocationCoordinate2D coordinate, NSString *name);
@end

NS_ASSUME_NONNULL_END
