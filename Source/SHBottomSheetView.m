#import "SHBottomSheetView.h"
#import "SHTheme.h"

@implementation SHBottomSheetView {
    UIView *_content;
    NSLayoutConstraint *_height;
    CGFloat _panStartHeight;
    BOOL _panning;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _collapsedHeight = 130;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = UIColor.clearColor;
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.15;
        self.layer.shadowRadius = 12;
        self.layer.shadowOffset = CGSizeMake(0, -2);

        // Inner view clips the content; the outer view keeps the shadow.
        _content = [UIView new];
        _content.translatesAutoresizingMaskIntoConstraints = NO;
        _content.backgroundColor = UIColor.systemBackgroundColor;
        _content.layer.cornerRadius = 22;
        _content.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        _content.clipsToBounds = YES;
        [self addSubview:_content];

        _headerView = [UIView new];
        _headerView.translatesAutoresizingMaskIntoConstraints = NO;
        [_content addSubview:_headerView];

        UIView *handle = [UIView new];
        handle.translatesAutoresizingMaskIntoConstraints = NO;
        handle.backgroundColor = UIColor.tertiaryLabelColor;
        handle.layer.cornerRadius = 2.5;
        [_headerView addSubview:handle];

        _bodyView = [UIView new];
        _bodyView.translatesAutoresizingMaskIntoConstraints = NO;
        [_content addSubview:_bodyView];

        [NSLayoutConstraint activateConstraints:@[
            [_content.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_content.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_content.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_content.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [_headerView.topAnchor constraintEqualToAnchor:_content.topAnchor],
            [_headerView.leadingAnchor constraintEqualToAnchor:_content.leadingAnchor],
            [_headerView.trailingAnchor constraintEqualToAnchor:_content.trailingAnchor],

            [handle.topAnchor constraintEqualToAnchor:_headerView.topAnchor constant:8],
            [handle.centerXAnchor constraintEqualToAnchor:_headerView.centerXAnchor],
            [handle.widthAnchor constraintEqualToConstant:38],
            [handle.heightAnchor constraintEqualToConstant:5],

            [_bodyView.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
            [_bodyView.leadingAnchor constraintEqualToAnchor:_content.leadingAnchor],
            [_bodyView.trailingAnchor constraintEqualToAnchor:_content.trailingAnchor],
            [_bodyView.bottomAnchor constraintEqualToAnchor:_content.bottomAnchor],
        ]];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [_headerView addGestureRecognizer:pan];
    }
    return self;
}

- (void)installInView:(UIView *)host {
    [host addSubview:self];
    _height = [self.heightAnchor constraintEqualToConstant:_collapsedHeight];
    [NSLayoutConstraint activateConstraints:@[
        [self.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [self.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [self.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
        _height,
    ]];
}

- (CGFloat)heightForDetent:(SHSheetDetent)detent {
    UIView *host = self.superview;
    CGFloat H = CGRectGetHeight(host.bounds);
    UIEdgeInsets safe = host.safeAreaInsets;
    CGFloat collapsed = _collapsedHeight + safe.bottom;
    CGFloat full = MAX(collapsed, H - safe.top - 72);
    switch (detent) {
        case SHSheetDetentCollapsed: return collapsed;
        case SHSheetDetentMedium:    return MIN(full, MAX(collapsed, H * 0.56));
        case SHSheetDetentFull:      return full;
    }
    return collapsed;
}

- (void)setDetent:(SHSheetDetent)detent animated:(BOOL)animated {
    _detent = detent;
    _height.constant = [self heightForDetent:detent];
    void (^changes)(void) = ^{ [self.superview layoutIfNeeded]; };
    if (animated) {
        [UIView animateWithDuration:0.42 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.4
                            options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                         animations:changes completion:nil];
    } else {
        changes();
    }
    if (self.onHeightChange) self.onHeightChange(_height.constant);
}

- (void)relayout {
    if (_panning || !self.superview) return;
    CGFloat target = [self heightForDetent:_detent];
    if (fabs(_height.constant - target) > 0.5) {
        _height.constant = target;
        if (self.onHeightChange) self.onHeightChange(target);
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGFloat minH = [self heightForDetent:SHSheetDetentCollapsed];
    CGFloat maxH = [self heightForDetent:SHSheetDetentFull];
    switch (pan.state) {
        case UIGestureRecognizerStateBegan:
            _panning = YES;
            _panStartHeight = _height.constant;
            [self.superview endEditing:YES];
            break;
        case UIGestureRecognizerStateChanged: {
            CGFloat h = _panStartHeight - [pan translationInView:self.superview].y;
            if (h < minH) h = minH - (minH - h) * 0.3;   // rubber band
            if (h > maxH) h = maxH + (h - maxH) * 0.3;
            _height.constant = h;
            if (self.onHeightChange) self.onHeightChange(h);
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            _panning = NO;
            CGFloat projected = _height.constant - [pan velocityInView:self.superview].y * 0.18;
            SHSheetDetent best = SHSheetDetentCollapsed;
            CGFloat bestDistance = CGFLOAT_MAX;
            for (SHSheetDetent d = SHSheetDetentCollapsed; d <= SHSheetDetentFull; d++) {
                CGFloat distance = fabs([self heightForDetent:d] - projected);
                if (distance < bestDistance) { bestDistance = distance; best = d; }
            }
            [self setDetent:best animated:YES];
            break;
        }
        default:
            break;
    }
}

@end
