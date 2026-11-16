#import "SHPrefix.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SHButtonStyle) {
    SHButtonStylePrimary,
    SHButtonStyleSecondary,
    SHButtonStyleDanger,
    SHButtonStyleChip,
};

/// Colors, the ghost logo and small view factories shared by every screen.
@interface SHTheme : NSObject

+ (UIColor *)accent;
+ (UIColor *)accentSoft;
+ (UIColor *)success;
+ (UIColor *)warning;

+ (UIImage *)ghostImageWithSize:(CGFloat)size color:(UIColor *)color;

+ (UIButton *)buttonWithStyle:(SHButtonStyle)style title:(nullable NSString *)title symbol:(nullable NSString *)symbol;
+ (void)setTitle:(nullable NSString *)title symbol:(nullable NSString *)symbol forButton:(UIButton *)button;
+ (UIButton *)roundIconButton:(NSString *)symbol;
+ (UIButton *)plainIconButton:(NSString *)symbol;

+ (UILabel *)labelWithSize:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
+ (UITextField *)numberField;
+ (UIView *)fieldBoxWithCaption:(NSString *)caption field:(UITextField *)field;
+ (UIStackView *)rowWithTitle:(NSString *)title accessory:(UIView *)accessory;
+ (UIView *)groupWithRows:(NSArray<UIView *> *)rows;
+ (UISwitch *)switchView;

+ (void)addFloatingShadowToView:(UIView *)view;
/// Applies the current language direction (RTL for Arabic) to a view tree.
+ (void)applyDirectionToView:(UIView *)view;
+ (UISemanticContentAttribute)direction;

@end

NS_ASSUME_NONNULL_END
