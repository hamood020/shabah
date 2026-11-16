#import "SHPrefix.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SHSheetDetent) {
    SHSheetDetentCollapsed,
    SHSheetDetentMedium,
    SHSheetDetentFull,
};

/// Google-Maps-style bottom sheet with three snap heights.
/// Drag the header (or its handle) to resize; the body holds the active tab.
@interface SHBottomSheetView : UIView

@property (nonatomic, readonly) UIView *headerView;
@property (nonatomic, readonly) UIView *bodyView;
@property (nonatomic, readonly) SHSheetDetent detent;
@property (nonatomic) CGFloat collapsedHeight;   // without the bottom safe area
@property (nonatomic, copy, nullable) void (^onHeightChange)(CGFloat height);

- (void)installInView:(UIView *)host;
- (void)setDetent:(SHSheetDetent)detent animated:(BOOL)animated;
/// Recomputes the height after the host view changes size.
- (void)relayout;

@end

NS_ASSUME_NONNULL_END
