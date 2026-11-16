#import "SHOverlay.h"
#import "SHPersistence.h"
#import "SHMovementEngine.h"
#import "SHMapPickerViewController.h"
#import "SHJoystickView.h"
#import "SHTheme.h"
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
static SHJoystickView *gJoystick;
static __weak UIWindow *gPreviousKeyWindow;
static BOOL gUserHidButton;
static BOOL gPickerVisible;
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
    void (^installHandler)(NSNotification *) = ^(NSNotification *note) { [self installIfNeeded]; };
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:installHandler];
    [nc addObserverForName:UISceneDidActivateNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:installHandler];
    void (^refreshHandler)(NSNotification *) = ^(NSNotification *note) { [self refresh]; };
    [nc addObserverForName:SHStateChangedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:refreshHandler];
    [nc addObserverForName:SHPlacesChangedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:refreshHandler];
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

    CGRect bounds = scene.coordinateSpace.bounds;

    gButton = [UIButton buttonWithType:UIButtonTypeCustom];
    gButton.frame = CGRectMake(CGRectGetMaxX(bounds) - 70, CGRectGetMidY(bounds) - 28, 56, 56);
    gButton.layer.cornerRadius = 28;
    gButton.layer.borderWidth = 2;
    [SHTheme addFloatingShadowToView:gButton];
    [gButton setImage:[SHTheme ghostImageWithSize:32 color:UIColor.whiteColor] forState:UIControlStateNormal];
    gButton.showsMenuAsPrimaryAction = NO;   // tap opens the map, long-press shows the menu
    [gButton addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
    [gButton addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)]];
    [root.view addSubview:gButton];

    gJoystick = [[SHJoystickView alloc] initWithFrame:CGRectMake(24, CGRectGetMaxY(bounds) - [SHJoystickView preferredSize] - 120, 0, 0)];
    [root.view addSubview:gJoystick];

    [self refresh];
    SH_LOG(@"overlay installed in %@", NSBundle.mainBundle.bundleIdentifier);
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
    [self refresh];
}

+ (void)refresh {
    if (!gButton) return;
    SHPersistence *store = [SHPersistence shared];
    BOOL on = store.isSpoofing;
    gButton.backgroundColor = on ? [SHTheme accent] : [UIColor colorWithWhite:0.12 alpha:0.88];
    gButton.layer.borderColor = (on ? [SHTheme success] : UIColor.clearColor).CGColor;
    gButton.hidden = gUserHidButton || gPickerVisible;
    gButton.menu = [self buildMenu];
    gJoystick.hidden = !store.joystickEnabled || gPickerVisible || gUserHidButton;
}

+ (UIMenu *)buildMenu {
    SHPersistence *store = [SHPersistence shared];
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];

    if (store.isSpoofing) {
        UIAction *stop = [UIAction actionWithTitle:SHText(@"stop") image:[UIImage systemImageNamed:@"stop.circle"] identifier:nil
            handler:^(UIAction *a) {
                [[SHMovementEngine shared] stop];
                [[SHPersistence shared] stopSpoofing];
            }];
        stop.attributes = UIMenuElementAttributesDestructive;
        [items addObject:stop];
    } else if (store.hasCoordinate) {
        [items addObject:[UIAction actionWithTitle:SHText(@"chip_resume") image:[UIImage systemImageNamed:@"arrow.clockwise"] identifier:nil
            handler:^(UIAction *a) { [[SHPersistence shared] resumeLast]; }]];
    }

    UIAction *joystick = [UIAction actionWithTitle:SHText(@"joystick") image:[UIImage systemImageNamed:@"gamecontroller"] identifier:nil
        handler:^(UIAction *a) {
            SHPersistence *s = [SHPersistence shared];
            if (!s.joystickEnabled && !s.hasCoordinate) return;
            s.joystickEnabled = !s.joystickEnabled;
        }];
    joystick.state = store.joystickEnabled ? UIMenuElementStateOn : UIMenuElementStateOff;
    [items addObject:joystick];

    UIMenu *(^placesMenu)(NSString *, NSString *, NSArray *, NSUInteger) = ^UIMenu *(NSString *title, NSString *icon, NSArray *places, NSUInteger limit) {
        NSMutableArray *actions = [NSMutableArray array];
        for (NSDictionary *place in places) {
            if (actions.count >= limit) break;
            CLLocationCoordinate2D c = CLLocationCoordinate2DMake([place[@"lat"] doubleValue], [place[@"lon"] doubleValue]);
            [actions addObject:[UIAction actionWithTitle:place[@"name"] ?: @"" image:nil identifier:nil handler:^(UIAction *a) {
                [[SHMovementEngine shared] stop];
                [[SHPersistence shared] startSpoofingAt:c];
            }]];
        }
        return actions.count ? [UIMenu menuWithTitle:title image:[UIImage systemImageNamed:icon] identifier:nil options:0 children:actions] : nil;
    };
    UIMenu *bookmarks = placesMenu(SHText(@"bookmarks"), @"star", store.bookmarks, 12);
    UIMenu *recents = placesMenu(SHText(@"recents"), @"clock.arrow.circlepath", store.recents, 6);
    if (bookmarks) [items addObject:bookmarks];
    if (recents) [items addObject:recents];

    [items addObject:[UIAction actionWithTitle:SHText(@"open_map") image:[UIImage systemImageNamed:@"map"] identifier:nil
        handler:^(UIAction *a) { [SHOverlay presentPicker]; }]];

    return [UIMenu menuWithTitle:SHText(@"app_name") children:items];
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

    // Snap to the nearest side when released, like a chat head.
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        CGFloat left = r + safe.left + 8;
        CGFloat right = CGRectGetWidth(container.bounds) - r - safe.right - 8;
        CGFloat x = c.x < CGRectGetMidX(container.bounds) ? left : right;
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:0 animations:^{
            view.center = CGPointMake(x, c.y);
        } completion:nil];
    }
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
    nav.view.semanticContentAttribute = [SHTheme direction];
    nav.navigationBar.tintColor = [SHTheme accent];
    gPickerVisible = YES;
    [self refresh];
    [root presentViewController:nav animated:YES completion:nil];
}

+ (void)pickerDidClose {
    gPickerVisible = NO;
    [gPreviousKeyWindow makeKeyWindow];
    [self refresh];
}

@end
