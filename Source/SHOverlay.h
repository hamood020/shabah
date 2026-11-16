#import "SHPrefix.h"

NS_ASSUME_NONNULL_BEGIN

/// Floating button in its own window that opens the map picker.
/// A three-finger double tap anywhere in the app hides / shows the button.
@interface SHOverlay : NSObject

+ (void)install;
+ (void)presentPicker;
+ (void)pickerDidClose;

@end

NS_ASSUME_NONNULL_END
