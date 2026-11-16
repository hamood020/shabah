#import "SHOverlay.h"
#import "SHPersistence.h"
#import "SHMovementEngine.h"
#import "SHMapPickerViewController.h"
#import "SHJoystickView.h"
#import "SHTheme.h"
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>

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

/// Watches the system volume: three volume-button presses within 1.5 s
/// show / hide the floating button (handy when it was hidden by mistake).
@interface SHVolumeWatcher : NSObject
@property (nonatomic, copy) void (^onTriplePress)(void);
- (void)setEnabled:(BOOL)enabled;
@end

@implementation SHVolumeWatcher {
    BOOL _observing;
    NSMutableArray<NSDate *> *_presses;
}

- (void)setEnabled:(BOOL)enabled {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if (enabled && !_observing) {
        // Volume changes are only reported for an active session. If the host app never
        // configured audio, use the mixing "ambient" category so music keeps playing.
        if ([session.category isEqualToString:AVAudioSessionCategorySoloAmbient]) {
            [session setCategory:AVAudioSessionCategoryAmbient withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
        }
        [session setActive:YES error:nil];
        [session addObserver:self forKeyPath:@"outputVolume" options:NSKeyValueObservingOptionNew context:NULL];
        _observing = YES;
        _presses = [NSMutableArray array];
    } else if (!enabled && _observing) {
        [session removeObserver:self forKeyPath:@"outputVolume"];
        _observing = NO;
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDate *now = [NSDate date];
        [self->_presses addObject:now];
        [self->_presses filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDate *d, NSDictionary *b) {
            return [now timeIntervalSinceDate:d] < 1.5;
        }]];
        if (self->_presses.count >= 3) {
            [self->_presses removeAllObjects];
            if (self.onTriplePress) self.onTriplePress();
        }
    });
}

@end

static SHPassthroughWindow *gWindow;
static UIButton *gButton;
static UIButton *gPill;
static NSTimer *gPillTimer;
static SHVolumeWatcher *gVolume;
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
    [nc addObserverForName:SHEngineUpdateNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        [self refreshPill];
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

    // Status pill: tap toggles spoofing, long-press opens the map, drag to move.
    gPill = [UIButton buttonWithType:UIButtonTypeCustom];
    gPill.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    gPill.contentEdgeInsets = UIEdgeInsetsMake(6, 12, 6, 12);
    gPill.layer.cornerRadius = 14;
    gPill.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.82];
    [gPill setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [SHTheme addFloatingShadowToView:gPill];
    [gPill addTarget:self action:@selector(pillTapped) forControlEvents:UIControlEventTouchUpInside];
    [gPill addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)]];
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(pillHeld:)];
    [gPill addGestureRecognizer:hold];
    gPill.center = CGPointMake(CGRectGetMidX(bounds), MAX(60, gWindow.safeAreaInsets.top + 22));
    [root.view addSubview:gPill];
    gPillTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) { [SHOverlay refreshPill]; }];
    gPillTimer.tolerance = 0.3;

    gVolume = [SHVolumeWatcher new];
    gVolume.onTriplePress = ^{
        gUserHidButton = !gUserHidButton;
        [SHOverlay refresh];
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    };

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
    gButton.alpha = store.buttonOpacity;
    gButton.menu = [self buildMenu];

    CGFloat size = store.buttonSize;
    if (fabs(CGRectGetWidth(gButton.bounds) - size) > 0.5) {
        CGPoint center = gButton.center;
        gButton.bounds = CGRectMake(0, 0, size, size);
        gButton.center = center;
        gButton.layer.cornerRadius = size / 2;
        [gButton setImage:[SHTheme ghostImageWithSize:round(size * 0.58) color:UIColor.whiteColor] forState:UIControlStateNormal];
    }

    gJoystick.hidden = !store.joystickEnabled || gPickerVisible || gUserHidButton;
    [gVolume setEnabled:store.volumeGestureEnabled];
    [self refreshPill];
}

+ (void)refreshPill {
    if (!gPill) return;
    SHPersistence *store = [SHPersistence shared];
    BOOL on = store.isSpoofing;
    gPill.hidden = !store.statusPillEnabled || gPickerVisible || gUserHidButton || !on;
    if (gPill.hidden) return;

    SHMovementEngine *engine = [SHMovementEngine shared];
    NSString *text = SHText(@"status_on");
    if (engine.mode == SHEngineModeRoute) {
        text = [NSString stringWithFormat:@"%@ · %d%%", engine.isPaused ? SHText(@"status_paused") : SHText(@"status_route"),
                (int)lround(engine.progress * 100)];
    } else if (engine.mode == SHEngineModeJoystick) {
        text = SHText(@"status_joystick");
    }
    NSDate *expiry = store.expiryDate;
    if (expiry && expiry.timeIntervalSinceNow > 0) {
        NSInteger left = (NSInteger)expiry.timeIntervalSinceNow;
        NSString *clock = left >= 3600 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)(left / 3600), (long)(left % 3600 / 60), (long)(left % 60)]
                                       : [NSString stringWithFormat:@"%02ld:%02ld", (long)(left / 60), (long)(left % 60)];
        text = [NSString stringWithFormat:@"%@ · %@", text, clock];
    }
    NSString *title = [NSString stringWithFormat:@"● %@", text];
    if (![[gPill titleForState:UIControlStateNormal] isEqualToString:title]) {
        CGPoint center = gPill.center;
        NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:title attributes:@{
            NSFontAttributeName: [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold],
            NSForegroundColorAttributeName: UIColor.whiteColor,
        }];
        [attributed addAttribute:NSForegroundColorAttributeName value:[SHTheme success] range:NSMakeRange(0, 1)];
        [gPill setTitle:title forState:UIControlStateNormal];
        [gPill setAttributedTitle:attributed forState:UIControlStateNormal];
        [gPill sizeToFit];
        gPill.center = center;
    }
}

+ (void)pillTapped {
    SHPersistence *store = [SHPersistence shared];
    if (store.isSpoofing) {
        [[SHMovementEngine shared] stop];
        [store stopSpoofing];
    } else {
        [store resumeLast];
    }
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

+ (void)pillHeld:(UILongPressGestureRecognizer *)hold {
    if (hold.state == UIGestureRecognizerStateBegan) [self presentPicker];
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
    if (view == gButton && (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled)) {
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
