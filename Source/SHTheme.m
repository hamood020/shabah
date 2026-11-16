#import "SHTheme.h"
#import "SHPersistence.h"

static UIColor *SHDynamic(UInt32 light, UInt32 dark) {
    UIColor *(^make)(UInt32) = ^UIColor *(UInt32 hex) {
        return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                               green:((hex >> 8) & 0xFF) / 255.0
                                blue:(hex & 0xFF) / 255.0
                               alpha:1.0];
    };
    UIColor *l = make(light), *d = make(dark);
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? d : l;
    }];
}

@implementation SHTheme

// Accent palettes: { light, dark }. Index matches SHPersistence.themeIndex.
static const UInt32 kAccents[][2] = {
    { 0x534AB7, 0x8F87E6 },   // ghost purple
    { 0x0F6E56, 0x3CC593 },   // teal
    { 0x185FA5, 0x5A9EE8 },   // blue
    { 0xC2462A, 0xF0896A },   // coral
    { 0x2C2C2A, 0xD3D1C7 },   // graphite
};
static const NSInteger kAccentCount = sizeof(kAccents) / sizeof(kAccents[0]);

+ (NSInteger)themeCount { return kAccentCount; }

+ (UIColor *)accentForTheme:(NSInteger)index {
    NSInteger i = (index >= 0 && index < kAccentCount) ? index : 0;
    return SHDynamic(kAccents[i][0], kAccents[i][1]);
}

+ (NSString *)themeNameAtIndex:(NSInteger)index {
    NSArray *keys = @[@"theme_purple", @"theme_teal", @"theme_blue", @"theme_coral", @"theme_graphite"];
    return SHText(keys[(index >= 0 && index < kAccentCount) ? index : 0]);
}

+ (UIColor *)accent     { return [self accentForTheme:[SHPersistence shared].themeIndex]; }
+ (UIColor *)accentSoft { return [[self accent] colorWithAlphaComponent:0.14]; }
+ (UIColor *)success    { return SHDynamic(0x1D9E75, 0x3CC593); }
+ (UIColor *)warning    { return SHDynamic(0xBA7517, 0xEF9F27); }

+ (UIImage *)ghostImageWithSize:(CGFloat)size color:(UIColor *)color {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGFloat r = size * 0.36;
        CGPoint head = CGPointMake(size / 2.0, size * 0.42);
        CGFloat left = head.x - r, right = head.x + r, bottom = size * 0.90;

        UIBezierPath *body = [UIBezierPath bezierPath];
        [body addArcWithCenter:head radius:r startAngle:M_PI endAngle:0 clockwise:YES];
        [body addLineToPoint:CGPointMake(right, bottom)];
        CGFloat wave = (right - left) / 3.0;
        for (int i = 0; i < 3; i++) {
            CGFloat x0 = right - wave * i;
            [body addQuadCurveToPoint:CGPointMake(x0 - wave, bottom)
                         controlPoint:CGPointMake(x0 - wave / 2.0, bottom - size * 0.13)];
        }
        [body closePath];
        [color setFill];
        [body fill];

        // Eyes are cut out so the ghost works on any background.
        CGContextSetBlendMode(ctx.CGContext, kCGBlendModeClear);
        CGFloat ew = r * 0.30, eh = r * 0.42;
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(head.x - r * 0.45 - ew / 2, head.y - eh / 2, ew, eh)] fill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(head.x + r * 0.45 - ew / 2, head.y - eh / 2, ew, eh)] fill];
    }];
}

#pragma mark - Buttons

+ (UIButton *)buttonWithStyle:(SHButtonStyle)style title:(NSString *)title symbol:(NSString *)symbol {
    UIButtonConfiguration *c;
    switch (style) {
        case SHButtonStylePrimary:
            c = [UIButtonConfiguration filledButtonConfiguration];
            c.baseBackgroundColor = [self accent];
            c.baseForegroundColor = UIColor.whiteColor;
            break;
        case SHButtonStyleSecondary:
            c = [UIButtonConfiguration grayButtonConfiguration];
            c.baseForegroundColor = UIColor.labelColor;
            break;
        case SHButtonStyleDanger:
            c = [UIButtonConfiguration tintedButtonConfiguration];
            c.baseBackgroundColor = UIColor.systemRedColor;
            c.baseForegroundColor = UIColor.systemRedColor;
            break;
        case SHButtonStyleChip:
            c = [UIButtonConfiguration grayButtonConfiguration];
            c.baseForegroundColor = UIColor.labelColor;
            c.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
            c.buttonSize = UIButtonConfigurationSizeSmall;
            break;
    }
    if (style != SHButtonStyleChip) c.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    c.imagePadding = 6;
    c.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attrs) {
        NSMutableDictionary *m = [attrs mutableCopy];
        m[NSFontAttributeName] = [UIFont systemFontOfSize:(style == SHButtonStyleChip ? 13 : 15) weight:UIFontWeightSemibold];
        return m;
    };
    UIButton *button = [UIButton buttonWithConfiguration:c primaryAction:nil];
    [self setTitle:title symbol:symbol forButton:button];
    if (style != SHButtonStyleChip) [button.heightAnchor constraintEqualToConstant:46].active = YES;
    return button;
}

+ (void)setTitle:(NSString *)title symbol:(NSString *)symbol forButton:(UIButton *)button {
    UIButtonConfiguration *c = button.configuration;
    if (!c) {
        [button setTitle:title forState:UIControlStateNormal];
        return;
    }
    c.title = title;
    UIImageSymbolConfiguration *sym = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
    c.image = symbol ? [UIImage systemImageNamed:symbol withConfiguration:sym] : nil;
    button.configuration = c;
}

+ (UIButton *)roundIconButton:(NSString *)symbol {
    UIButtonConfiguration *c = [UIButtonConfiguration plainButtonConfiguration];
    c.image = [UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightMedium]];
    c.baseForegroundColor = UIColor.labelColor;
    c.background.backgroundColor = UIColor.systemBackgroundColor;
    c.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:nil];
    [b.widthAnchor constraintEqualToConstant:44].active = YES;
    [b.heightAnchor constraintEqualToConstant:44].active = YES;
    [self addFloatingShadowToView:b];
    return b;
}

+ (UIButton *)plainIconButton:(NSString *)symbol {
    UIButtonConfiguration *c = [UIButtonConfiguration plainButtonConfiguration];
    c.image = [UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightMedium]];
    c.baseForegroundColor = UIColor.secondaryLabelColor;
    c.contentInsets = NSDirectionalEdgeInsetsMake(6, 6, 6, 6);
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:nil];
    [b.widthAnchor constraintEqualToConstant:36].active = YES;
    [b setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return b;
}

#pragma mark - Labels and fields

+ (UILabel *)labelWithSize:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color {
    UILabel *l = [UILabel new];
    l.font = [UIFont systemFontOfSize:size weight:weight];
    l.textColor = color;
    l.textAlignment = NSTextAlignmentNatural;
    return l;
}

+ (UITextField *)numberField {
    UITextField *f = [UITextField new];
    f.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightRegular];
    f.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.returnKeyType = UIReturnKeyDone;
    f.textAlignment = NSTextAlignmentNatural;
    return f;
}

+ (UIView *)fieldBoxWithCaption:(NSString *)caption field:(UITextField *)field {
    UIView *box = [UIView new];
    box.backgroundColor = UIColor.secondarySystemBackgroundColor;
    box.layer.cornerRadius = 12;
    UILabel *cap = [self labelWithSize:11 weight:UIFontWeightMedium color:UIColor.secondaryLabelColor];
    cap.text = caption;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[cap, field]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 2;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:box.topAnchor constant:8],
        [stack.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-8],
        [stack.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-12],
    ]];
    return box;
}

+ (UIStackView *)rowWithTitle:(NSString *)title accessory:(UIView *)accessory {
    UILabel *label = [self labelWithSize:15 weight:UIFontWeightRegular color:UIColor.labelColor];
    label.text = title;
    label.numberOfLines = 2;
    [label setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [accessory setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [accessory setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[label, accessory]];
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    [row.heightAnchor constraintGreaterThanOrEqualToConstant:46].active = YES;
    return row;
}

+ (UIView *)groupWithRows:(NSArray<UIView *> *)rows {
    UIView *group = [UIView new];
    group.backgroundColor = UIColor.secondarySystemBackgroundColor;
    group.layer.cornerRadius = 14;
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [rows enumerateObjectsUsingBlock:^(UIView *row, NSUInteger i, BOOL *stop) {
        if (i > 0) {
            UIView *line = [UIView new];
            line.backgroundColor = UIColor.separatorColor;
            [line.heightAnchor constraintEqualToConstant:0.5].active = YES;
            [stack addArrangedSubview:line];
        }
        [stack addArrangedSubview:row];
    }];
    [group addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:group.topAnchor constant:2],
        [stack.bottomAnchor constraintEqualToAnchor:group.bottomAnchor constant:-2],
        [stack.leadingAnchor constraintEqualToAnchor:group.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:group.trailingAnchor constant:-14],
    ]];
    return group;
}

+ (UISwitch *)switchView {
    UISwitch *s = [UISwitch new];
    s.onTintColor = [self accent];
    return s;
}

#pragma mark - Misc

+ (void)addFloatingShadowToView:(UIView *)view {
    view.layer.shadowColor = UIColor.blackColor.CGColor;
    view.layer.shadowOpacity = 0.18;
    view.layer.shadowRadius = 8;
    view.layer.shadowOffset = CGSizeMake(0, 2);
}

+ (UISemanticContentAttribute)direction {
    return [SHPersistence shared].arabic ? UISemanticContentAttributeForceRightToLeft
                                         : UISemanticContentAttributeForceLeftToRight;
}

+ (void)applyDirectionToView:(UIView *)view {
    if ([view isKindOfClass:MKMapView.class]) return;   // leave MapKit's own views alone
    view.semanticContentAttribute = [self direction];
    for (UIView *sub in view.subviews) [self applyDirectionToView:sub];
}

@end
