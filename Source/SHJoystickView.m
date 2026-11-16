#import "SHJoystickView.h"
#import "SHMovementEngine.h"
#import "SHTheme.h"

static const CGFloat kSize = 140;
static const CGFloat kKnob = 56;

@implementation SHJoystickView {
    UIView *_base;
    UIView *_knob;
    UIButton *_lockButton;
    CGVector _vector;
    BOOL _touching;
}

+ (CGFloat)preferredSize { return kSize; }

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(frame.origin.x, frame.origin.y, kSize, kSize)])) {
        self.backgroundColor = UIColor.clearColor;
        self.multipleTouchEnabled = NO;

        _base = [[UIView alloc] initWithFrame:self.bounds];
        _base.backgroundColor = [UIColor.systemBackgroundColor colorWithAlphaComponent:0.88];
        _base.layer.cornerRadius = kSize / 2;
        _base.layer.borderWidth = 1;
        _base.layer.borderColor = UIColor.separatorColor.CGColor;
        _base.userInteractionEnabled = NO;
        [SHTheme addFloatingShadowToView:_base];
        [self addSubview:_base];

        // Direction ticks (N, E, S, W).
        for (int i = 0; i < 4; i++) {
            UIView *tick = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 4, 10)];
            tick.backgroundColor = UIColor.tertiaryLabelColor;
            tick.layer.cornerRadius = 2;
            double angle = i * M_PI_2;
            tick.center = CGPointMake(kSize / 2 + sin(angle) * (kSize / 2 - 12), kSize / 2 - cos(angle) * (kSize / 2 - 12));
            tick.transform = CGAffineTransformMakeRotation(angle);
            tick.userInteractionEnabled = NO;
            [_base addSubview:tick];
        }

        _knob = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kKnob, kKnob)];
        _knob.center = CGPointMake(kSize / 2, kSize / 2);
        _knob.backgroundColor = [SHTheme accent];
        _knob.layer.cornerRadius = kKnob / 2;
        _knob.userInteractionEnabled = NO;
        UIImageView *ghost = [[UIImageView alloc] initWithImage:[SHTheme ghostImageWithSize:28 color:UIColor.whiteColor]];
        ghost.center = CGPointMake(kKnob / 2, kKnob / 2);
        [_knob addSubview:ghost];
        [self addSubview:_knob];

        _lockButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _lockButton.frame = CGRectMake(kSize - 34, -4, 36, 36);
        _lockButton.backgroundColor = UIColor.systemBackgroundColor;
        _lockButton.layer.cornerRadius = 18;
        _lockButton.tintColor = UIColor.secondaryLabelColor;
        [SHTheme addFloatingShadowToView:_lockButton];
        [_lockButton addTarget:self action:@selector(toggleLock) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_lockButton];
        [self updateLockIcon];
    }
    return self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    _base.layer.borderColor = UIColor.separatorColor.CGColor;
}

- (void)updateLockIcon {
    NSString *name = _locked ? @"lock.fill" : @"lock.open";
    [_lockButton setImage:[UIImage systemImageNamed:name] forState:UIControlStateNormal];
    _lockButton.tintColor = _locked ? [SHTheme accent] : UIColor.secondaryLabelColor;
}

- (void)toggleLock {
    _locked = !_locked;
    [self updateLockIcon];
    [[UISelectionFeedbackGenerator new] selectionChanged];
    if (!_locked && !_touching) [self resetKnob];
}

- (void)resetKnob {
    _vector = CGVectorMake(0, 0);
    [[SHMovementEngine shared] setJoystickVector:_vector];
    [UIView animateWithDuration:0.2 animations:^{
        self->_knob.center = CGPointMake(kSize / 2, kSize / 2);
    }];
}

- (void)updateWithTouch:(UITouch *)touch {
    CGPoint p = [touch locationInView:self];
    CGFloat dx = p.x - kSize / 2, dy = p.y - kSize / 2;
    CGFloat maxR = (kSize - kKnob) / 2;
    CGFloat len = hypot(dx, dy);
    if (len > maxR) { dx *= maxR / len; dy *= maxR / len; }
    _knob.center = CGPointMake(kSize / 2 + dx, kSize / 2 + dy);
    _vector = CGVectorMake(dx / maxR, dy / maxR);
    [[SHMovementEngine shared] setJoystickVector:_vector];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _touching = YES;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [self updateWithTouch:touches.anyObject];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self updateWithTouch:touches.anyObject];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _touching = NO;
    if (!_locked) [self resetKnob];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (CGRectContainsPoint(_lockButton.frame, point)) return YES;
    return hypot(point.x - kSize / 2, point.y - kSize / 2) <= kSize / 2;
}

@end
