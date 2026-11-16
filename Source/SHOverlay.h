#import "SHPrefix.h"

NS_ASSUME_NONNULL_BEGIN

/// Floating ghost button (tap: map, long-press: quick actions) and the optional
/// joystick, both in a pass-through window above the host app.
/// A three-finger double tap anywhere in the app hides / shows the button.
@interface SHOverlay : NSObject

+ (void)install;
+ (void)presentPicker;
+ (void)pickerDidClose;

@end

NS_ASSUME_NONNULL_END
