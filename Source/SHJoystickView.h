#import "SHPrefix.h"

NS_ASSUME_NONNULL_BEGIN

/// Circular joystick that drives SHMovementEngine. The lock button keeps the
/// current direction after the finger is lifted.
@interface SHJoystickView : UIView
@property (nonatomic, readonly, getter=isLocked) BOOL locked;
+ (CGFloat)preferredSize;
@end

NS_ASSUME_NONNULL_END
