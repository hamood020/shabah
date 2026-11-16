#import "SHOverlay.h"
#import "SHPersistence.h"
#import "SHMapPickerViewController.h"
#import <objc/runtime.h>

/// Window that only catches touches on its own controls; everything else
/// falls through to the host app.
@interface SHPassthroughWindow : UIWindow
@end

@implementation SHPassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view) return nil;
    return hit;
}
@end

static SHPassthroughWindow *gWindow;
static UIButton *gButton;
static __weak UIWindow *gPreviousKeyWindow;
static BOOL gUserHidButton;
static const void *kGestureInstalledKey = &kGestureInstalledKey;

static UIWindowScene *SHActiveWindowScene(void) {
    UIWindowScene *fallback = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        if (scene.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)scene;
        if (!fallback) fallback = (UIWindowScene *)scene;
    }
    return fallback;
}

@implementation SHOverlay

+ (void)install {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    void (^handler)(NSNotification *) = ^(NSNotification *note) { [self installIfNeeded]; };
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:handler];
    [nc addObserverForName:UISceneDidActivateNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:handler];
    [nc addObserverForName:SHStateChangedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        [self refreshButton];
    }];
}

+ (void)installIfNeeded {
    UIWindowScene *scene = SHActiveWindowScene();
    if (!scene) return;
    [self installToggleGestureInScene:scene];
    if (gWindow) return;

    gWindow = [[SHPassthroughWindow alloc] initWithWindowScene:scene];
    gWindow.windowLevel = UIWindowLevelAlert + 1;
    gWindow.backgroundColor = UIColor.clearColor;
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.clearColor;
    gWindow.rootViewController = root;
    gWindow.hidden = NO;

    gButton = [UIButton buttonWithType:UIButtonTypeCustom];
    CGRect bounds = scene.coordinateSpace.bounds;
    gButton.frame = CGRectMake(CGRectGetMaxX(bounds) - 66, CGRectGetMidY(bounds) - 26, 52, 52);
    gButton.layer.cornerRadius = 26;
    gButton.layer.shadowColor = UIColor.blackColor.CGColor;
    gButton.layer.shadowOpacity = 0.3;
    gButton.layer.shadowRadius = 6;
    gButton.layer.shadowOffset = CGSizeMake(0, 3);
    gButton.tintColor = UIColor.whiteColor;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold];
    [gButton setImage:[UIImage systemImageNamed:@"location.fill" withConfiguration:cfg] forState:UIControlStateNormal];
    [gButton addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
    [gButton addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)]];
    [root.view addSubview:gButton];

    [self refreshButton];
    SH_LOG(@"overlay installed");
}

/// Three-finger double tap on the app's own windows toggles the floating button.
+ (void)installToggleGestureInScene:(UIWindowScene *)scene {
    for (UIWindow *window in scene.windows) {
        if (window == gWindow || objc_getAssociatedObject(window, kGestureInstalledKey)) continue;
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleToggle:)];
        tap.numberOfTouchesRequired = 3;
        tap.numberOfTapsRequired = 2;
        tap.cancelsTouchesInView = NO;
        [window addGestureRecognizer:tap];
        objc_setAssociatedObject(window, kGestureInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

+ (void)handleToggle:(UITapGestureRecognizer *)tap {
    if (tap.state != UIGestureRecognizerStateRecognized) return;
    gUserHidButton = !gUserHidButton;
    gButton.hidden = gUserHidButton;
}

+ (void)refreshButton {
    BOOL on = [SHPersistence shared].isSpoofing;
    gButton.backgroundColor = on ? [UIColor colorWithRed:0.10 green:0.65 blue:0.45 alpha:0.95]
                                 : [UIColor colorWithWhite:0.15 alpha:0.85];
}

+ (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *view = pan.view;
    UIView *container = view.superview;
    CGPoint t = [pan translationInView:container];
    CGPoint c = CGPointMake(view.center.x + t.x, view.center.y + t.y);
    CGFloat r = CGRectGetWidth(view.bounds) / 2.0;
    UIEdgeInsets safe = container.safeAreaInsets;
    c.x = MAX(r + safe.left, MIN(CGRectGetWidth(container.bounds) - r - safe.right, c.x));
    c.y = MAX(r + safe.top, MIN(CGRectGetHeight(container.bounds) - r - safe.bottom, c.y));
    view.center = c;
    [pan setTranslation:CGPointZero inView:container];
}

+ (void)buttonTapped {
    [self presentPicker];
}

+ (void)presentPicker {
    [self installIfNeeded];
    UIViewController *root = gWindow.rootViewController;
    if (!root || root.presentedViewController) return;

    for (UIWindow *window in gWindow.windowScene.windows) {
        if (window.isKeyWindow && window != gWindow) { gPreviousKeyWindow = window; break; }
    }
    [gWindow makeKeyWindow];   // so the search field can receive the keyboard

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[SHMapPickerViewController new]];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    gButton.hidden = YES;
    [root presentViewController:nav animated:YES completion:nil];
}

+ (void)pickerDidClose {
    gButton.hidden = gUserHidButton;
    [gPreviousKeyWindow makeKeyWindow];
    [self refreshButton];
}

@end
