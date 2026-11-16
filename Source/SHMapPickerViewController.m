#import "SHMapPickerViewController.h"
#import "SHPersistence.h"
#import "SHMovementEngine.h"
#import "SHOverlay.h"
#import "SHTheme.h"
#import "SHBottomSheetView.h"
#import "SHJoystickView.h"
#import "SHLinkParser.h"
#import "SHSettingsViewController.h"
#import "SHUpdateChecker.h"
#import "SHScheduleViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

typedef NS_ENUM(NSInteger, SHTab) {
    SHTabLocation = 0,
    SHTabRoute,
    SHTabJoystick,
    SHTabPlaces,
};

static const NSInteger kAutoStopOptions[] = { 0, 30, 60, 120, 240, 480 };
static const NSInteger kAutoStopCount = 6;
static const CGFloat kSuggestionRowHeight = 52;

static NSString *SHAutoStopTitle(NSInteger minutes) {
    if (minutes <= 0) return SHText(@"never");
    if (minutes == 30) return SHText(@"min30");
    if (minutes == 60) return SHText(@"hour1");
    if (minutes == 120) return SHText(@"hour2");
    return [NSString stringWithFormat:SHText(@"hours_fmt"), (int)(minutes / 60)];
}

static NSString *SHStyleTitle(NSInteger style) {
    switch (style) {
        case 1: return SHText(@"style_satellite");
        case 2: return SHText(@"style_hybrid");
        case 3: return SHText(@"style_night");
        default: return SHText(@"style_standard");
    }
}

/// Numbered route stop on the map.
@interface SHWaypointAnnotation : MKPointAnnotation
@property (nonatomic) NSUInteger number;
@end
@implementation SHWaypointAnnotation
@end

/// Grey pin showing where the device really is while spoofing.
@interface SHRealLocationAnnotation : MKPointAnnotation
@end
@implementation SHRealLocationAnnotation
@end

@interface SHMapPickerViewController () <MKMapViewDelegate, UITextFieldDelegate, MKLocalSearchCompleterDelegate, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) SHRealLocationAnnotation *realPin;
@property (nonatomic, strong) NSTimer *realPinTimer;

// Map and search
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) UIView *searchPill;
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) UITableView *suggestionsTable;
@property (nonatomic, strong) NSLayoutConstraint *suggestionsHeight;
@property (nonatomic, strong) MKLocalSearchCompleter *completer;
@property (nonatomic, copy) NSArray<MKLocalSearchCompletion *> *completions;
@property (nonatomic, strong) UIButton *layersButton;

// Sheet header
@property (nonatomic, strong) SHBottomSheetView *sheet;
@property (nonatomic, strong) UIView *statusDot;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *coordLabel;
@property (nonatomic, strong) UILabel *addressLabel;
@property (nonatomic, strong) UIButton *toggleChip;
@property (nonatomic, strong) UISegmentedControl *tabControl;
@property (nonatomic, strong) NSArray<UIView *> *tabViews;
@property (nonatomic) SHTab tab;

// Location tab
@property (nonatomic, strong) UITextField *latField;
@property (nonatomic, strong) UITextField *lonField;
@property (nonatomic, strong) UITextField *altitudeField;
@property (nonatomic, strong) UISwitch *jitterSwitch;
@property (nonatomic, strong) UISwitch *glideSwitch;
@property (nonatomic, strong) UISlider *radiusSlider;
@property (nonatomic, strong) UILabel *radiusLabel;
@property (nonatomic, strong) UIButton *autoStopButton;

// Route tab
@property (nonatomic, strong) NSMutableArray<NSValue *> *waypoints;
@property (nonatomic, strong) NSMutableArray<SHWaypointAnnotation *> *waypointAnnotations;
@property (nonatomic, strong) UILabel *waypointsLabel;
@property (nonatomic, strong) UISwitch *loopSwitch;
@property (nonatomic, strong) UISwitch *realisticSwitch;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *progressLabel;
@property (nonatomic, strong) UIButton *routeButton;
@property (nonatomic, strong) MKPolyline *routeLine;
@property (nonatomic) BOOL buildingRoute;

// Shared speed controls (route and joystick tabs)
@property (nonatomic, strong) NSMutableArray<UISegmentedControl *> *transportSegments;
@property (nonatomic, strong) NSMutableArray<UISlider *> *speedSliders;
@property (nonatomic, strong) NSMutableArray<UILabel *> *speedLabels;

// Joystick tab
@property (nonatomic, strong) UISwitch *joystickSwitch;
@property (nonatomic, strong) SHJoystickView *mapJoystick;

// Places tab
@property (nonatomic, strong) UITableView *placesTable;
@property (nonatomic, strong) UIButton *placesEditButton;

// Selection
@property (nonatomic, strong) MKPointAnnotation *pin;
@property (nonatomic) BOOL hasSelection;
@property (nonatomic) CLLocationCoordinate2D selection;
@property (nonatomic, copy) NSString *selectionName;
@property (nonatomic, copy) NSString *selectionAddress;
@property (nonatomic, strong) CLGeocoder *geocoder;

@property (nonatomic, strong) NSMutableArray *observers;
@property (nonatomic) BOOL checkedUpdates;
@property (nonatomic) BOOL routeFinishedShown;
@end

@implementation SHMapPickerViewController

- (void)dealloc {
    for (id o in _observers) [[NSNotificationCenter defaultCenter] removeObserver:o];
    [_realPinTimer invalidate];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.waypoints = [NSMutableArray array];
    self.waypointAnnotations = [NSMutableArray array];
    self.geocoder = [CLGeocoder new];
    self.completer = [MKLocalSearchCompleter new];
    self.completer.delegate = self;
    self.completions = @[];

    [self buildUI];

    SHPersistence *store = [SHPersistence shared];
    if (store.hasCoordinate) {
        [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(store.coordinate, 1500, 1500) animated:NO];
    }

    __weak typeof(self) weakSelf = self;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    self.observers = [NSMutableArray array];
    [self.observers addObject:[nc addObserverForName:SHStateChangedNotification object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *n) { [weakSelf refreshStatus]; [weakSelf refreshControls]; }]];
    [self.observers addObject:[nc addObserverForName:SHEngineUpdateNotification object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *n) { [weakSelf engineUpdated:n]; }]];
    [self.observers addObject:[nc addObserverForName:SHPlacesChangedNotification object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *n) { [weakSelf.placesTable reloadData]; }]];
    [self.observers addObject:[nc addObserverForName:UIKeyboardWillChangeFrameNotification object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *n) { [weakSelf keyboardChanged:n]; }]];

    self.realPinTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *t) {
        if (!weakSelf) { [t invalidate]; return; }
        [weakSelf refreshRealLocationPin];
    }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.checkedUpdates) return;
    self.checkedUpdates = YES;
    __weak typeof(self) weakSelf = self;
    [SHUpdateChecker checkForce:NO completion:^(NSString *newer, NSURL *page, BOOL failed) {
        if (!newer) return;
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:SHText(@"app_name")
            message:[NSString stringWithFormat:SHText(@"update_fmt"), newer] preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:SHText(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
        [ac addAction:[UIAlertAction actionWithTitle:SHText(@"open") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            if (page) [UIApplication.sharedApplication openURL:page options:@{} completionHandler:nil];
        }]];
        [weakSelf presentViewController:ac animated:YES completion:nil];
    }];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self.sheet relayout];
}

#pragma mark - Building the UI

- (void)buildUI {
    self.transportSegments = [NSMutableArray array];
    self.speedSliders = [NSMutableArray array];
    self.speedLabels = [NSMutableArray array];

    [self buildMap];
    [self buildMapControls];
    [self buildSheet];
    [self buildMapJoystick];
    [self buildSearch];
    [SHTheme applyDirectionToView:self.view];

    // Restore annotations and the route after a rebuild.
    if (self.hasSelection) {
        self.pin = [MKPointAnnotation new];
        self.pin.coordinate = self.selection;
        self.pin.title = self.selectionName;
        [self.mapView addAnnotation:self.pin];
    }
    for (NSUInteger i = 0; i < self.waypoints.count; i++) [self addWaypointAnnotation:SHUnbox(self.waypoints[i])];
    if (self.routeLine) [self.mapView addOverlay:self.routeLine];

    [self applyMapStyle];
    [self selectTab:self.tab openSheet:NO];
    [self refreshControls];
    [self refreshStatus];
    [self.sheet setDetent:SHSheetDetentCollapsed animated:NO];
}

- (void)rebuildUI {
    MKCoordinateRegion region = self.mapView.region;
    [self.view.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    self.pin = nil;
    self.realPin = nil;
    [self.waypointAnnotations removeAllObjects];
    [self buildUI];
    [self.mapView setRegion:region animated:NO];
}

- (void)buildMap {
    self.mapView = [MKMapView new];
    self.mapView.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapView.delegate = self;
    self.mapView.showsUserLocation = YES;
    self.mapView.showsCompass = YES;
    self.mapView.showsScale = YES;
    [self.view addSubview:self.mapView];
    [NSLayoutConstraint activateConstraints:@[
        [self.mapView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.mapView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.mapView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.mapView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    press.minimumPressDuration = 0.4;
    [self.mapView addGestureRecognizer:press];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.mapView addGestureRecognizer:tap];
}

- (void)buildSearch {
    UIView *pill = [UIView new];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.backgroundColor = UIColor.systemBackgroundColor;
    pill.layer.cornerRadius = 25;
    [SHTheme addFloatingShadowToView:pill];
    [self.view addSubview:pill];
    self.searchPill = pill;

    UIImageView *ghost = [[UIImageView alloc] initWithImage:[SHTheme ghostImageWithSize:26 color:[SHTheme accent]]];
    [ghost setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    self.searchField = [UITextField new];
    self.searchField.placeholder = SHText(@"search");
    self.searchField.font = [UIFont systemFontOfSize:16];
    self.searchField.returnKeyType = UIReturnKeySearch;
    self.searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.searchField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchField.delegate = self;
    self.searchField.textAlignment = NSTextAlignmentNatural;
    [self.searchField addTarget:self action:@selector(searchTextChanged) forControlEvents:UIControlEventEditingChanged];

    UIButton *settings = [SHTheme plainIconButton:@"gearshape"];
    [settings addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    UIButton *close = [SHTheme plainIconButton:@"xmark"];
    [close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ghost, self.searchField, settings, close]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 8;
    [pill addSubview:row];

    self.suggestionsTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.suggestionsTable.translatesAutoresizingMaskIntoConstraints = NO;
    self.suggestionsTable.dataSource = self;
    self.suggestionsTable.delegate = self;
    self.suggestionsTable.rowHeight = kSuggestionRowHeight;
    self.suggestionsTable.layer.cornerRadius = 16;
    self.suggestionsTable.hidden = YES;
    [self.view addSubview:self.suggestionsTable];
    self.suggestionsHeight = [self.suggestionsTable.heightAnchor constraintEqualToConstant:0];

    [NSLayoutConstraint activateConstraints:@[
        [pill.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [pill.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [pill.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [pill.heightAnchor constraintEqualToConstant:50],
        [row.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:14],
        [row.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-6],
        [row.topAnchor constraintEqualToAnchor:pill.topAnchor],
        [row.bottomAnchor constraintEqualToAnchor:pill.bottomAnchor],

        [self.suggestionsTable.topAnchor constraintEqualToAnchor:pill.bottomAnchor constant:6],
        [self.suggestionsTable.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor],
        [self.suggestionsTable.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor],
        self.suggestionsHeight,
    ]];
}

- (void)buildMapControls {
    self.layersButton = [SHTheme roundIconButton:@"square.3.layers.3d"];
    self.layersButton.showsMenuAsPrimaryAction = YES;
    UIButton *recenter = [SHTheme roundIconButton:@"location"];
    [recenter addTarget:self action:@selector(recenter) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[self.layersButton, recenter]];
    column.translatesAutoresizingMaskIntoConstraints = NO;
    column.axis = UILayoutConstraintAxisVertical;
    column.spacing = 10;
    [self.view addSubview:column];
    [NSLayoutConstraint activateConstraints:@[
        [column.leftAnchor constraintEqualToAnchor:self.view.leftAnchor constant:12],
        [column.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:72],
    ]];
}

- (void)buildMapJoystick {
    CGFloat size = [SHJoystickView preferredSize];
    self.mapJoystick = [[SHJoystickView alloc] initWithFrame:CGRectZero];
    self.mapJoystick.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.mapJoystick];
    [NSLayoutConstraint activateConstraints:@[
        [self.mapJoystick.leftAnchor constraintEqualToAnchor:self.view.leftAnchor constant:22],
        [self.mapJoystick.bottomAnchor constraintEqualToAnchor:self.sheet.topAnchor constant:-18],
        [self.mapJoystick.widthAnchor constraintEqualToConstant:size],
        [self.mapJoystick.heightAnchor constraintEqualToConstant:size],
    ]];
}

- (void)buildSheet {
    self.sheet = [SHBottomSheetView new];
    self.sheet.collapsedHeight = 128;
    [self.sheet installInView:self.view];
    __weak typeof(self) weakSelf = self;
    self.sheet.onHeightChange = ^(CGFloat height) {
        weakSelf.mapView.layoutMargins = UIEdgeInsetsMake(0, 0, height, 0);
    };

    // Header: status, address, quick chips and tabs.
    self.statusDot = [UIView new];
    self.statusDot.layer.cornerRadius = 4.5;
    [self.statusDot.widthAnchor constraintEqualToConstant:9].active = YES;
    [self.statusDot.heightAnchor constraintEqualToConstant:9].active = YES;

    self.statusLabel = [SHTheme labelWithSize:17 weight:UIFontWeightSemibold color:UIColor.labelColor];
    [self.statusLabel setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    self.coordLabel = [SHTheme labelWithSize:12 weight:UIFontWeightRegular color:UIColor.secondaryLabelColor];
    self.coordLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    [self.coordLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *statusRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.statusDot, self.statusLabel, self.coordLabel]];
    statusRow.alignment = UIStackViewAlignmentCenter;
    statusRow.spacing = 8;

    self.addressLabel = [SHTheme labelWithSize:13 weight:UIFontWeightRegular color:UIColor.secondaryLabelColor];

    self.toggleChip = [SHTheme buttonWithStyle:SHButtonStyleChip title:nil symbol:nil];
    [self.toggleChip addTarget:self action:@selector(toggleChipTapped) forControlEvents:UIControlEventTouchUpInside];
    UIButton *routeChip = [SHTheme buttonWithStyle:SHButtonStyleChip title:SHText(@"tab_route") symbol:@"point.topleft.down.curvedto.point.bottomright.up"];
    routeChip.tag = SHTabRoute;
    UIButton *joyChip = [SHTheme buttonWithStyle:SHButtonStyleChip title:SHText(@"joystick") symbol:@"gamecontroller"];
    joyChip.tag = SHTabJoystick;
    UIButton *placesChip = [SHTheme buttonWithStyle:SHButtonStyleChip title:SHText(@"tab_places") symbol:@"star"];
    placesChip.tag = SHTabPlaces;
    for (UIButton *chip in @[routeChip, joyChip, placesChip]) {
        [chip addTarget:self action:@selector(tabChipTapped:) forControlEvents:UIControlEventTouchUpInside];
    }
    UIButton *scheduleChip = [SHTheme buttonWithStyle:SHButtonStyleChip title:SHText(@"schedule") symbol:@"calendar.badge.clock"];
    [scheduleChip addTarget:self action:@selector(openSchedule) forControlEvents:UIControlEventTouchUpInside];
    UIButton *copyChip = [SHTheme buttonWithStyle:SHButtonStyleChip title:SHText(@"copy") symbol:@"doc.on.doc"];
    [copyChip addTarget:self action:@selector(copyCoordinatesTapped) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *chips = [[UIStackView alloc] initWithArrangedSubviews:@[self.toggleChip, routeChip, joyChip, placesChip, scheduleChip, copyChip]];
    chips.spacing = 8;
    chips.translatesAutoresizingMaskIntoConstraints = NO;
    UIScrollView *chipScroll = [UIScrollView new];
    chipScroll.showsHorizontalScrollIndicator = NO;
    [chipScroll addSubview:chips];
    [NSLayoutConstraint activateConstraints:@[
        [chips.topAnchor constraintEqualToAnchor:chipScroll.contentLayoutGuide.topAnchor],
        [chips.bottomAnchor constraintEqualToAnchor:chipScroll.contentLayoutGuide.bottomAnchor],
        [chips.leadingAnchor constraintEqualToAnchor:chipScroll.contentLayoutGuide.leadingAnchor],
        [chips.trailingAnchor constraintEqualToAnchor:chipScroll.contentLayoutGuide.trailingAnchor],
        [chips.heightAnchor constraintEqualToAnchor:chipScroll.frameLayoutGuide.heightAnchor],
        [chipScroll.heightAnchor constraintEqualToConstant:34],
    ]];

    self.tabControl = [[UISegmentedControl alloc] initWithItems:@[SHText(@"tab_location"), SHText(@"tab_route"), SHText(@"tab_joystick"), SHText(@"tab_places")]];
    self.tabControl.selectedSegmentIndex = self.tab;
    [self.tabControl addTarget:self action:@selector(tabChanged) forControlEvents:UIControlEventValueChanged];

    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[statusRow, self.addressLabel, chipScroll, self.tabControl]];
    header.axis = UILayoutConstraintAxisVertical;
    header.spacing = 6;
    [header setCustomSpacing:12 afterView:self.addressLabel];
    [header setCustomSpacing:16 afterView:chipScroll];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sheet.headerView addSubview:header];
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.sheet.headerView.topAnchor constant:22],
        [header.leadingAnchor constraintEqualToAnchor:self.sheet.headerView.leadingAnchor constant:16],
        [header.trailingAnchor constraintEqualToAnchor:self.sheet.headerView.trailingAnchor constant:-16],
        [header.bottomAnchor constraintEqualToAnchor:self.sheet.headerView.bottomAnchor constant:-10],
    ]];

    // Body: one view per tab.
    self.tabViews = @[[self buildLocationTab], [self buildRouteTab], [self buildJoystickTab], [self buildPlacesTab]];
    for (UIView *v in self.tabViews) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [self.sheet.bodyView addSubview:v];
        [NSLayoutConstraint activateConstraints:@[
            [v.topAnchor constraintEqualToAnchor:self.sheet.bodyView.topAnchor],
            [v.bottomAnchor constraintEqualToAnchor:self.sheet.bodyView.bottomAnchor],
            [v.leadingAnchor constraintEqualToAnchor:self.sheet.bodyView.leadingAnchor],
            [v.trailingAnchor constraintEqualToAnchor:self.sheet.bodyView.trailingAnchor],
        ]];
    }
}

- (UIScrollView *)scrollTabWithViews:(NSArray<UIView *> *)views {
    UIScrollView *scroll = [UIScrollView new];
    scroll.alwaysBounceVertical = YES;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:views];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:4],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-28],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32],
    ]];
    return scroll;
}

- (UIView *)buildLocationTab {
    self.latField = [SHTheme numberField];
    self.lonField = [SHTheme numberField];
    self.latField.delegate = self;
    self.lonField.delegate = self;
    self.latField.placeholder = @"23.588012";
    self.lonField.placeholder = @"58.382911";
    UIStackView *coords = [[UIStackView alloc] initWithArrangedSubviews:@[
        [SHTheme fieldBoxWithCaption:SHText(@"lat") field:self.latField],
        [SHTheme fieldBoxWithCaption:SHText(@"lon") field:self.lonField],
    ]];
    coords.distribution = UIStackViewDistributionFillEqually;
    coords.spacing = 10;

    self.jitterSwitch = [SHTheme switchView];
    [self.jitterSwitch addTarget:self action:@selector(jitterChanged) forControlEvents:UIControlEventValueChanged];

    self.radiusSlider = [UISlider new];
    self.radiusSlider.minimumValue = 5;
    self.radiusSlider.maximumValue = 100;
    self.radiusSlider.minimumTrackTintColor = [SHTheme accent];
    [self.radiusSlider.widthAnchor constraintEqualToConstant:130].active = YES;
    [self.radiusSlider addTarget:self action:@selector(radiusChanged) forControlEvents:UIControlEventValueChanged];
    self.radiusLabel = [SHTheme labelWithSize:14 weight:UIFontWeightMedium color:UIColor.labelColor];
    [self.radiusLabel.widthAnchor constraintEqualToConstant:48].active = YES;
    UIStackView *radiusAccessory = [[UIStackView alloc] initWithArrangedSubviews:@[self.radiusSlider, self.radiusLabel]];
    radiusAccessory.spacing = 8;
    radiusAccessory.alignment = UIStackViewAlignmentCenter;

    self.altitudeField = [SHTheme numberField];
    self.altitudeField.delegate = self;
    self.altitudeField.textAlignment = NSTextAlignmentCenter;
    self.altitudeField.backgroundColor = UIColor.tertiarySystemFillColor;
    self.altitudeField.layer.cornerRadius = 8;
    [self.altitudeField.widthAnchor constraintEqualToConstant:76].active = YES;
    [self.altitudeField.heightAnchor constraintEqualToConstant:32].active = YES;

    self.autoStopButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.autoStopButton.showsMenuAsPrimaryAction = YES;
    self.autoStopButton.tintColor = [SHTheme accent];

    self.glideSwitch = [SHTheme switchView];
    [self.glideSwitch addTarget:self action:@selector(glideChanged) forControlEvents:UIControlEventValueChanged];

    UIView *settings = [SHTheme groupWithRows:@[
        [SHTheme rowWithTitle:SHText(@"jitter") accessory:self.jitterSwitch],
        [SHTheme rowWithTitle:SHText(@"radius") accessory:radiusAccessory],
        [SHTheme rowWithTitle:SHText(@"altitude") accessory:self.altitudeField],
        [SHTheme rowWithTitle:SHText(@"auto_stop") accessory:self.autoStopButton],
        [SHTheme rowWithTitle:SHText(@"glide") accessory:self.glideSwitch],
    ]];

    UIButton *apply = [SHTheme buttonWithStyle:SHButtonStylePrimary title:SHText(@"apply") symbol:@"location.fill"];
    [apply addTarget:self action:@selector(applyTapped) forControlEvents:UIControlEventTouchUpInside];
    UIButton *star = [SHTheme buttonWithStyle:SHButtonStyleSecondary title:nil symbol:@"star"];
    [star.widthAnchor constraintEqualToConstant:54].active = YES;
    [star addTarget:self action:@selector(saveBookmarkTapped) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[apply, star]];
    buttons.spacing = 10;

    UIButton *stop = [SHTheme buttonWithStyle:SHButtonStyleDanger title:SHText(@"stop") symbol:@"stop.fill"];
    [stop addTarget:self action:@selector(stopTapped) forControlEvents:UIControlEventTouchUpInside];

    return [self scrollTabWithViews:@[coords, settings, buttons, stop]];
}

- (UISegmentedControl *)makeTransportSegment {
    UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[SHText(@"walk"), SHText(@"bike"), SHText(@"car")]];
    [seg addTarget:self action:@selector(transportChanged:) forControlEvents:UIControlEventValueChanged];
    [self.transportSegments addObject:seg];
    return seg;
}

- (UIView *)makeSpeedRow {
    UISlider *slider = [UISlider new];
    slider.minimumValue = 1;
    slider.maximumValue = 200;
    slider.minimumTrackTintColor = [SHTheme accent];
    [slider.widthAnchor constraintEqualToConstant:130].active = YES;
    [slider addTarget:self action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
    UILabel *label = [SHTheme labelWithSize:14 weight:UIFontWeightMedium color:UIColor.labelColor];
    [label.widthAnchor constraintEqualToConstant:66].active = YES;
    [self.speedSliders addObject:slider];
    [self.speedLabels addObject:label];
    UIStackView *accessory = [[UIStackView alloc] initWithArrangedSubviews:@[slider, label]];
    accessory.spacing = 8;
    accessory.alignment = UIStackViewAlignmentCenter;
    return [SHTheme rowWithTitle:SHText(@"speed") accessory:accessory];
}

- (UIView *)buildRouteTab {
    UILabel *hint = [SHTheme labelWithSize:13 weight:UIFontWeightRegular color:UIColor.secondaryLabelColor];
    hint.text = SHText(@"route_hint");
    hint.numberOfLines = 0;

    self.waypointsLabel = [SHTheme labelWithSize:15 weight:UIFontWeightSemibold color:UIColor.labelColor];
    [self.waypointsLabel setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIButton *undo = [SHTheme buttonWithStyle:SHButtonStyleChip title:SHText(@"undo") symbol:@"arrow.uturn.backward"];
    [undo addTarget:self action:@selector(undoWaypoint) forControlEvents:UIControlEventTouchUpInside];
    UIButton *clear = [SHTheme buttonWithStyle:SHButtonStyleChip title:SHText(@"clear") symbol:@"trash"];
    [clear addTarget:self action:@selector(clearWaypoints) forControlEvents:UIControlEventTouchUpInside];
    UIButton *saveRoute = [SHTheme buttonWithStyle:SHButtonStyleChip title:nil symbol:@"square.and.arrow.down.on.square"];
    saveRoute.accessibilityLabel = SHText(@"save_route");
    [saveRoute addTarget:self action:@selector(saveRouteTapped) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stopsRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.waypointsLabel, saveRoute, undo, clear]];
    stopsRow.spacing = 8;
    stopsRow.alignment = UIStackViewAlignmentCenter;

    self.loopSwitch = [SHTheme switchView];
    [self.loopSwitch addTarget:self action:@selector(loopChanged) forControlEvents:UIControlEventValueChanged];
    self.realisticSwitch = [SHTheme switchView];
    [self.realisticSwitch addTarget:self action:@selector(realisticChanged) forControlEvents:UIControlEventValueChanged];

    UIView *settings = [SHTheme groupWithRows:@[
        [self makeSpeedRow],
        [SHTheme rowWithTitle:SHText(@"loop") accessory:self.loopSwitch],
        [SHTheme rowWithTitle:SHText(@"realistic") accessory:self.realisticSwitch],
    ]];

    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.progressTintColor = [SHTheme accent];
    self.progressLabel = [SHTheme labelWithSize:13 weight:UIFontWeightRegular color:UIColor.secondaryLabelColor];

    self.routeButton = [SHTheme buttonWithStyle:SHButtonStylePrimary title:SHText(@"route_start") symbol:@"play.fill"];
    [self.routeButton addTarget:self action:@selector(routeTapped) forControlEvents:UIControlEventTouchUpInside];
    UIButton *stop = [SHTheme buttonWithStyle:SHButtonStyleDanger title:nil symbol:@"stop.fill"];
    [stop.widthAnchor constraintEqualToConstant:54].active = YES;
    [stop addTarget:self action:@selector(stopRouteTapped) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[self.routeButton, stop]];
    buttons.spacing = 10;

    return [self scrollTabWithViews:@[hint, stopsRow, [self makeTransportSegment], settings, self.progressView, self.progressLabel, buttons]];
}

- (UIView *)buildJoystickTab {
    self.joystickSwitch = [SHTheme switchView];
    [self.joystickSwitch addTarget:self action:@selector(joystickToggled) forControlEvents:UIControlEventValueChanged];

    UIView *settings = [SHTheme groupWithRows:@[
        [SHTheme rowWithTitle:SHText(@"joy_show") accessory:self.joystickSwitch],
        [self makeSpeedRow],
    ]];

    UILabel *note = [SHTheme labelWithSize:13 weight:UIFontWeightRegular color:UIColor.secondaryLabelColor];
    note.text = SHText(@"joy_note");
    note.numberOfLines = 0;

    return [self scrollTabWithViews:@[[self makeTransportSegment], settings, note]];
}

- (UIView *)buildPlacesTab {
    UIButton *export = [SHTheme buttonWithStyle:SHButtonStyleChip title:SHText(@"export") symbol:@"square.and.arrow.up"];
    __weak typeof(self) weakSelf = self;
    export.menu = [UIMenu menuWithChildren:@[
        [UIAction actionWithTitle:SHText(@"via_clipboard") image:[UIImage systemImageNamed:@"doc.on.clipboard"] identifier:nil
            handler:^(UIAction *a) { [weakSelf exportPlaces]; }],
        [UIAction actionWithTitle:SHText(@"via_file") image:[UIImage systemImageNamed:@"doc"] identifier:nil
            handler:^(UIAction *a) { [weakSelf shareExportFile]; }],
    ]];
    export.showsMenuAsPrimaryAction = YES;
    UIButton *import = [SHTheme buttonWithStyle:SHButtonStyleChip title:SHText(@"import") symbol:@"square.and.arrow.down"];
    import.menu = [UIMenu menuWithChildren:@[
        [UIAction actionWithTitle:SHText(@"via_clipboard") image:[UIImage systemImageNamed:@"doc.on.clipboard"] identifier:nil
            handler:^(UIAction *a) { [weakSelf importPlaces]; }],
        [UIAction actionWithTitle:SHText(@"via_file") image:[UIImage systemImageNamed:@"doc"] identifier:nil
            handler:^(UIAction *a) { [weakSelf pickImportFile]; }],
    ]];
    import.showsMenuAsPrimaryAction = YES;
    self.placesEditButton = [SHTheme buttonWithStyle:SHButtonStyleChip title:SHText(@"edit") symbol:@"arrow.up.arrow.down"];
    [self.placesEditButton addTarget:self action:@selector(togglePlacesEditing) forControlEvents:UIControlEventTouchUpInside];
    UIView *spacer = [UIView new];
    [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[export, import, spacer, self.placesEditButton]];
    actions.spacing = 8;
    actions.translatesAutoresizingMaskIntoConstraints = NO;

    self.placesTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.placesTable.translatesAutoresizingMaskIntoConstraints = NO;
    self.placesTable.dataSource = self;
    self.placesTable.delegate = self;
    self.placesTable.backgroundColor = UIColor.clearColor;

    UIView *container = [UIView new];
    [container addSubview:actions];
    [container addSubview:self.placesTable];
    [NSLayoutConstraint activateConstraints:@[
        [actions.topAnchor constraintEqualToAnchor:container.topAnchor constant:4],
        [actions.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [actions.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
        [self.placesTable.topAnchor constraintEqualToAnchor:actions.bottomAnchor],
        [self.placesTable.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.placesTable.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.placesTable.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
    return container;
}

#pragma mark - Refreshing

- (void)refreshStatus {
    SHPersistence *store = [SHPersistence shared];
    SHMovementEngine *engine = [SHMovementEngine shared];
    BOOL on = store.isSpoofing;

    NSString *status = SHText(@"status_off");
    UIColor *dot = UIColor.systemGrayColor;
    if (on) {
        dot = [SHTheme success];
        switch (engine.mode) {
            case SHEngineModeRoute:
                status = engine.isPaused ? SHText(@"status_paused") : SHText(@"status_route");
                if (engine.isPaused) dot = [SHTheme warning];
                break;
            case SHEngineModeJoystick: status = SHText(@"status_joystick"); break;
            case SHEngineModeGlide:    status = SHText(@"status_glide"); break;
            case SHEngineModeIdle:     status = SHText(@"status_on"); break;
        }
    }
    self.statusLabel.text = status;
    self.statusDot.backgroundColor = dot;

    if (on) {
        CLLocationCoordinate2D c = store.coordinate;
        self.coordLabel.text = [NSString stringWithFormat:@"%.5f, %.5f", c.latitude, c.longitude];
    } else {
        self.coordLabel.text = @"";
    }

    if (self.hasSelection) {
        self.addressLabel.text = self.selectionAddress ?: self.selectionName ?: [NSString stringWithFormat:@"%.6f, %.6f", self.selection.latitude, self.selection.longitude];
    } else {
        self.addressLabel.text = SHText(@"hint");
    }

    if (on) {
        [SHTheme setTitle:SHText(@"chip_stop") symbol:@"stop.fill" forButton:self.toggleChip];
    } else if (!self.hasSelection && store.hasCoordinate) {
        [SHTheme setTitle:SHText(@"chip_resume") symbol:@"arrow.clockwise" forButton:self.toggleChip];
    } else {
        [SHTheme setTitle:SHText(@"chip_set") symbol:@"mappin.and.ellipse" forButton:self.toggleChip];
    }

    // Route progress and the start/pause button.
    if (engine.mode == SHEngineModeRoute) {
        self.progressView.progress = engine.progress;
        double km = engine.remainingMeters / 1000.0;
        int minutes = (int)ceil(engine.remainingMeters / MAX(0.3, store.speedKmh / 3.6) / 60.0);
        self.progressLabel.text = [NSString stringWithFormat:SHText(@"route_left_fmt"), km, minutes];
        if (engine.isPaused) [SHTheme setTitle:SHText(@"route_resume") symbol:@"play.fill" forButton:self.routeButton];
        else [SHTheme setTitle:SHText(@"route_pause") symbol:@"pause.fill" forButton:self.routeButton];
    } else if (self.buildingRoute) {
        [SHTheme setTitle:SHText(@"route_building") symbol:@"hourglass" forButton:self.routeButton];
    } else {
        if (!self.routeFinishedShown) {
            self.progressView.progress = 0;
            self.progressLabel.text = @"";
        }
        [SHTheme setTitle:SHText(@"route_start") symbol:@"play.fill" forButton:self.routeButton];
    }
}

- (void)refreshControls {
    SHPersistence *store = [SHPersistence shared];
    self.jitterSwitch.on = store.jitterEnabled;
    self.radiusSlider.value = store.jitterRadius;
    self.radiusLabel.text = [NSString stringWithFormat:SHText(@"meters_fmt"), (int)lround(store.jitterRadius)];
    if (!self.altitudeField.isFirstResponder) self.altitudeField.text = [NSString stringWithFormat:@"%.0f", store.altitude];
    self.glideSwitch.on = store.glideEnabled;
    self.loopSwitch.on = store.loopRoute;
    self.realisticSwitch.on = store.realisticMotion;
    self.joystickSwitch.on = store.joystickEnabled;

    // Auto-stop menu. Menus are owned by our buttons, so their blocks capture self weakly.
    __weak typeof(self) weakSelf = self;
    NSMutableArray *actions = [NSMutableArray array];
    for (NSInteger i = 0; i < kAutoStopCount; i++) {
        NSInteger minutes = kAutoStopOptions[i];
        UIAction *a = [UIAction actionWithTitle:SHAutoStopTitle(minutes) image:nil identifier:nil handler:^(UIAction *action) {
            [SHPersistence shared].autoStopMinutes = minutes;
            [weakSelf refreshControls];
        }];
        a.state = store.autoStopMinutes == minutes ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:a];
    }
    self.autoStopButton.menu = [UIMenu menuWithChildren:actions];
    [self.autoStopButton setTitle:SHAutoStopTitle(store.autoStopMinutes) forState:UIControlStateNormal];

    // Map style menu.
    NSMutableArray *styles = [NSMutableArray array];
    for (NSInteger style = 0; style < 4; style++) {
        UIAction *a = [UIAction actionWithTitle:SHStyleTitle(style) image:nil identifier:nil handler:^(UIAction *action) {
            [SHPersistence shared].mapStyle = style;
            [weakSelf applyMapStyle];
            [weakSelf refreshControls];
        }];
        a.state = store.mapStyle == style ? UIMenuElementStateOn : UIMenuElementStateOff;
        [styles addObject:a];
    }
    self.layersButton.menu = [UIMenu menuWithTitle:SHText(@"map_style") children:styles];

    for (UISegmentedControl *seg in self.transportSegments) seg.selectedSegmentIndex = store.transportMode;
    for (UISlider *slider in self.speedSliders) slider.value = store.speedKmh;
    for (UILabel *label in self.speedLabels) label.text = [NSString stringWithFormat:SHText(@"kmh_fmt"), (int)lround(store.speedKmh)];

    self.waypointsLabel.text = [NSString stringWithFormat:SHText(@"stops_fmt"), (unsigned long)self.waypoints.count];
    [SHTheme setTitle:self.placesTable.isEditing ? SHText(@"done") : SHText(@"edit")
               symbol:self.placesTable.isEditing ? @"checkmark" : @"arrow.up.arrow.down"
            forButton:self.placesEditButton];
}

- (void)applyMapStyle {
    switch ([SHPersistence shared].mapStyle) {
        case 1:  self.mapView.mapType = MKMapTypeSatellite; self.mapView.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified; break;
        case 2:  self.mapView.mapType = MKMapTypeHybrid;    self.mapView.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified; break;
        case 3:  self.mapView.mapType = MKMapTypeStandard;  self.mapView.overrideUserInterfaceStyle = UIUserInterfaceStyleDark; break;
        default: self.mapView.mapType = MKMapTypeStandard;  self.mapView.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified; break;
    }
}

- (void)engineUpdated:(NSNotification *)note {
    if ([note.userInfo[@"finished"] boolValue]) {
        self.routeFinishedShown = YES;
        self.progressView.progress = 1;
        self.progressLabel.text = SHText(@"route_done");
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    } else if ([SHMovementEngine shared].mode == SHEngineModeRoute) {
        self.routeFinishedShown = NO;
    }
    [self refreshStatus];
}

#pragma mark - Tabs

- (void)selectTab:(SHTab)tab openSheet:(BOOL)open {
    self.tab = tab;
    self.tabControl.selectedSegmentIndex = tab;
    [self.tabViews enumerateObjectsUsingBlock:^(UIView *v, NSUInteger i, BOOL *stop) { v.hidden = (i != (NSUInteger)tab); }];
    self.mapJoystick.hidden = tab != SHTabJoystick;
    if (tab == SHTabPlaces) [self.placesTable reloadData];
    if (open && self.sheet.detent == SHSheetDetentCollapsed) [self.sheet setDetent:SHSheetDetentMedium animated:YES];
}

- (void)tabChanged {
    [self.view endEditing:YES];
    [self selectTab:(SHTab)self.tabControl.selectedSegmentIndex openSheet:YES];
}

- (void)tabChipTapped:(UIButton *)chip {
    [self selectTab:(SHTab)chip.tag openSheet:YES];
}

#pragma mark - Selection

- (void)selectCoordinate:(CLLocationCoordinate2D)c name:(NSString *)name recenter:(BOOL)recenter {
    if (!CLLocationCoordinate2DIsValid(c)) return;
    self.selection = c;
    self.hasSelection = YES;
    self.selectionName = name;
    self.selectionAddress = nil;
    if (!self.pin) {
        self.pin = [MKPointAnnotation new];
        self.pin.coordinate = c;
        [self.mapView addAnnotation:self.pin];
    }
    self.pin.coordinate = c;
    self.pin.title = name;
    self.latField.text = [NSString stringWithFormat:@"%.6f", c.latitude];
    self.lonField.text = [NSString stringWithFormat:@"%.6f", c.longitude];
    if (recenter) {
        if (self.mapView.region.span.latitudeDelta < 0.05) [self.mapView setCenterCoordinate:c animated:YES];
        else [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(c, 1200, 1200) animated:YES];
    }
    [self refreshStatus];
    [self reverseGeocode:c];
}

- (void)reverseGeocode:(CLLocationCoordinate2D)c {
    [self.geocoder cancelGeocode];
    __weak typeof(self) weakSelf = self;
    CLLocation *location = [[CLLocation alloc] initWithLatitude:c.latitude longitude:c.longitude];
    NSLocale *locale = [NSLocale localeWithLocaleIdentifier:[SHPersistence shared].arabic ? @"ar" : @"en"];
    [self.geocoder reverseGeocodeLocation:location preferredLocale:locale completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
        CLPlacemark *p = placemarks.firstObject;
        if (!p || !weakSelf.hasSelection || SHDistance(weakSelf.selection, c) > 1) return;
        NSMutableArray *parts = [NSMutableArray array];
        if (p.name) [parts addObject:p.name];
        if (p.locality && ![p.locality isEqualToString:p.name]) [parts addObject:p.locality];
        if (p.country) [parts addObject:p.country];
        weakSelf.selectionAddress = [parts componentsJoinedByString:@"، "];
        if (!weakSelf.selectionName.length) weakSelf.selectionName = p.name;
        [weakSelf refreshStatus];
    }];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    CLLocationCoordinate2D c = [self.mapView convertPoint:[g locationInView:self.mapView] toCoordinateFromView:self.mapView];
    [[UISelectionFeedbackGenerator new] selectionChanged];
    if (self.tab == SHTabRoute) [self addWaypoint:c];
    else [self selectCoordinate:c name:nil recenter:NO];
}

- (void)commitFieldEdits {
    double lat = [[self.latField.text stringByReplacingOccurrencesOfString:@"٫" withString:@"."] doubleValue];
    double lon = [[self.lonField.text stringByReplacingOccurrencesOfString:@"٫" withString:@"."] doubleValue];
    CLLocationCoordinate2D c = CLLocationCoordinate2DMake(lat, lon);
    if (self.latField.text.length && self.lonField.text.length && CLLocationCoordinate2DIsValid(c)) {
        if (!self.hasSelection || SHDistance(c, self.selection) > 0.5) [self selectCoordinate:c name:nil recenter:YES];
    }
    double altitude = [self.altitudeField.text doubleValue];
    if (self.altitudeField.text.length) [SHPersistence shared].altitude = altitude;
}

#pragma mark - Waypoints

- (void)addWaypointAnnotation:(CLLocationCoordinate2D)c {
    SHWaypointAnnotation *a = [SHWaypointAnnotation new];
    a.coordinate = c;
    a.number = self.waypointAnnotations.count + 1;
    [self.waypointAnnotations addObject:a];
    [self.mapView addAnnotation:a];
}

- (void)addWaypoint:(CLLocationCoordinate2D)c {
    [self.waypoints addObject:SHBox(c)];
    [self addWaypointAnnotation:c];
    [self refreshControls];
}

- (void)undoWaypoint {
    if (!self.waypoints.count) return;
    [self.waypoints removeLastObject];
    [self.mapView removeAnnotation:self.waypointAnnotations.lastObject];
    [self.waypointAnnotations removeLastObject];
    [self refreshControls];
}

- (void)clearWaypoints {
    [self.waypoints removeAllObjects];
    [self.mapView removeAnnotations:self.waypointAnnotations];
    [self.waypointAnnotations removeAllObjects];
    if (self.routeLine) [self.mapView removeOverlay:self.routeLine];
    self.routeLine = nil;
    if ([SHMovementEngine shared].mode == SHEngineModeRoute) [[SHMovementEngine shared] stop];
    self.routeFinishedShown = NO;
    [self refreshControls];
    [self refreshStatus];
}

#pragma mark - Search

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.searchField) {
        [self performSearch:textField.text ?: @""];
    } else {
        [self commitFieldEdits];
    }
    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (textField == self.searchField) [self hideSuggestions];
    else [self commitFieldEdits];
}

- (void)searchTextChanged {
    NSString *text = self.searchField.text ?: @"";
    if (text.length < 2 || [SHLinkParser coordinateFromText:text coordinate:NULL] || [text containsString:@"http"]) {
        self.completions = @[];
        [self reloadSuggestions];
        return;
    }
    self.completer.region = self.mapView.region;
    self.completer.queryFragment = text;
}

- (void)completerDidUpdateResults:(MKLocalSearchCompleter *)completer {
    NSArray *results = completer.results;
    self.completions = results.count > 5 ? [results subarrayWithRange:NSMakeRange(0, 5)] : results;
    [self reloadSuggestions];
}

- (void)completer:(MKLocalSearchCompleter *)completer didFailWithError:(NSError *)error {
    self.completions = @[];
    [self reloadSuggestions];
}

- (void)reloadSuggestions {
    BOOL show = self.completions.count > 0 && self.searchField.isFirstResponder;
    self.suggestionsHeight.constant = show ? self.completions.count * kSuggestionRowHeight : 0;
    self.suggestionsTable.hidden = !show;
    [self.suggestionsTable reloadData];
}

- (void)hideSuggestions {
    self.completions = @[];
    [self reloadSuggestions];
}

- (void)performSearch:(NSString *)text {
    NSString *query = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!query.length) return;
    [self hideSuggestions];

    CLLocationCoordinate2D c;
    if ([SHLinkParser coordinateFromText:query coordinate:&c]) {
        [self selectCoordinate:c name:nil recenter:YES];
        return;
    }
    if ([SHLinkParser isShortLink:query]) {
        __weak typeof(self) weakSelf = self;
        [SHLinkParser resolveShortLink:query completion:^(BOOL found, CLLocationCoordinate2D coordinate, NSString *placeQuery) {
            if (found) [weakSelf selectCoordinate:coordinate name:placeQuery recenter:YES];
            else if (placeQuery.length) [weakSelf localSearch:placeQuery];
            else [weakSelf showMessage:SHText(@"search_fail")];
        }];
        return;
    }
    [self localSearch:query];
}

- (void)localSearch:(NSString *)query {
    MKLocalSearchRequest *request = [MKLocalSearchRequest new];
    request.naturalLanguageQuery = query;
    request.region = self.mapView.region;
    [self runSearch:request];
}

- (void)runSearch:(MKLocalSearchRequest *)request {
    __weak typeof(self) weakSelf = self;
    [[[MKLocalSearch alloc] initWithRequest:request] startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
        MKMapItem *item = response.mapItems.firstObject;
        if (!item) {
            [weakSelf showMessage:SHText(@"search_fail")];
            return;
        }
        [weakSelf selectCoordinate:item.placemark.coordinate name:item.name recenter:YES];
    }];
}

#pragma mark - Actions

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)close {
    [self.view endEditing:YES];
    [self.navigationController dismissViewControllerAnimated:YES completion:^{
        [SHOverlay pickerDidClose];
    }];
}

- (void)openSettings {
    [self.view endEditing:YES];
    SHSettingsViewController *settings = [[SHSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    __weak typeof(self) weakSelf = self;
    settings.onChange = ^{ [weakSelf rebuildUI]; };
    [self.navigationController pushViewController:settings animated:YES];
}

- (void)recenter {
    SHPersistence *store = [SHPersistence shared];
    CLLocationCoordinate2D c = store.hasCoordinate && store.isSpoofing ? store.coordinate : self.mapView.userLocation.coordinate;
    if (!CLLocationCoordinate2DIsValid(c)) return;
    [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(c, 1000, 1000) animated:YES];
}

- (void)toggleChipTapped {
    SHPersistence *store = [SHPersistence shared];
    if (store.isSpoofing) {
        [self stopTapped];
    } else if (self.hasSelection) {
        [self applyTapped];
    } else if (store.hasCoordinate) {
        [store resumeLast];
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    } else {
        [self showMessage:SHText(@"need_pin")];
    }
}

- (void)applyTapped {
    [self commitFieldEdits];
    if (!self.hasSelection) { [self showMessage:SHText(@"need_pin")]; return; }
    SHPersistence *store = [SHPersistence shared];
    SHMovementEngine *engine = [SHMovementEngine shared];
    if (store.glideEnabled && store.isSpoofing) {
        [engine glideTo:self.selection];
    } else {
        [engine stop];
        [store startSpoofingAt:self.selection];
    }
    [store recordRecent:self.selection name:self.selectionName.length ? self.selectionName : self.selectionAddress];
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    [self.view endEditing:YES];
    [self.sheet setDetent:SHSheetDetentCollapsed animated:YES];
}

- (void)stopTapped {
    [[SHMovementEngine shared] stop];
    [[SHPersistence shared] stopSpoofing];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
}

- (void)saveBookmarkTapped {
    [self commitFieldEdits];
    if (!self.hasSelection) { [self showMessage:SHText(@"need_pin")]; return; }
    CLLocationCoordinate2D c = self.selection;
    NSString *suggested = self.selectionName ?: self.selectionAddress;
    [self askForNameWithTitle:SHText(@"bookmark_name") initial:suggested completion:^(NSString *name) {
        [[SHPersistence shared] addBookmarkNamed:name coordinate:c];
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    }];
}

- (void)jitterChanged    { [SHPersistence shared].jitterEnabled = self.jitterSwitch.on; }
- (void)glideChanged     { [SHPersistence shared].glideEnabled = self.glideSwitch.on; }
- (void)loopChanged      { [SHPersistence shared].loopRoute = self.loopSwitch.on; }
- (void)realisticChanged { [SHPersistence shared].realisticMotion = self.realisticSwitch.on; }

- (void)radiusChanged {
    [SHPersistence shared].jitterRadius = round(self.radiusSlider.value);
    self.radiusLabel.text = [NSString stringWithFormat:SHText(@"meters_fmt"), (int)lround(self.radiusSlider.value)];
}

- (void)transportChanged:(UISegmentedControl *)seg {
    [SHPersistence shared].transportMode = seg.selectedSegmentIndex;
    [self refreshControls];
}

- (void)speedChanged:(UISlider *)slider {
    [SHPersistence shared].speedKmh = round(slider.value);
    for (UISlider *s in self.speedSliders) if (s != slider) s.value = slider.value;
    for (UILabel *l in self.speedLabels) l.text = [NSString stringWithFormat:SHText(@"kmh_fmt"), (int)lround(slider.value)];
}

- (void)joystickToggled {
    SHPersistence *store = [SHPersistence shared];
    if (self.joystickSwitch.on && !store.hasCoordinate) {
        self.joystickSwitch.on = NO;
        [self showMessage:SHText(@"joy_need")];
        return;
    }
    store.joystickEnabled = self.joystickSwitch.on;
}

#pragma mark - Route

- (void)routeTapped {
    SHMovementEngine *engine = [SHMovementEngine shared];
    if (engine.mode == SHEngineModeRoute) {
        if (engine.isPaused) [engine resume];
        else [engine pause];
        [self refreshStatus];
        return;
    }
    if (self.buildingRoute) return;

    SHPersistence *store = [SHPersistence shared];
    NSMutableArray<NSValue *> *stops = [NSMutableArray array];
    if (store.hasCoordinate) [stops addObject:SHBox(store.coordinate)];
    [stops addObjectsFromArray:self.waypoints];
    if (self.waypoints.count == 0 || stops.count < 2) {
        [self showMessage:SHText(@"need_stops")];
        return;
    }

    self.buildingRoute = YES;
    self.routeFinishedShown = NO;
    [self refreshStatus];
    __weak typeof(self) weakSelf = self;
    [self buildLegs:stops index:0 into:[NSMutableArray array] completion:^(NSArray<NSValue *> *coords) {
        weakSelf.buildingRoute = NO;
        if (coords.count < 2) {
            [weakSelf showMessage:SHText(@"route_fail")];
            [weakSelf refreshStatus];
            return;
        }
        [weakSelf startRouteWithCoordinates:coords];
    }];
}

/// Asks Apple Maps for each leg in turn; a leg without a road route becomes a straight line.
- (void)buildLegs:(NSArray<NSValue *> *)stops index:(NSUInteger)index into:(NSMutableArray<NSValue *> *)coords
       completion:(void (^)(NSArray<NSValue *> *coords))completion {
    if (index + 1 >= stops.count) { completion(coords); return; }
    CLLocationCoordinate2D a = SHUnbox(stops[index]), b = SHUnbox(stops[index + 1]);

    MKDirectionsRequest *request = [MKDirectionsRequest new];
    request.source = [[MKMapItem alloc] initWithPlacemark:[[MKPlacemark alloc] initWithCoordinate:a]];
    request.destination = [[MKMapItem alloc] initWithPlacemark:[[MKPlacemark alloc] initWithCoordinate:b]];
    request.transportType = [SHPersistence shared].transportMode == 2 ? MKDirectionsTransportTypeAutomobile : MKDirectionsTransportTypeWalking;

    __weak typeof(self) weakSelf = self;
    [[[MKDirections alloc] initWithRequest:request] calculateDirectionsWithCompletionHandler:^(MKDirectionsResponse *response, NSError *error) {
        MKPolyline *line = response.routes.firstObject.polyline;
        if (line.pointCount >= 2) {
            NSUInteger n = line.pointCount;
            CLLocationCoordinate2D *buffer = malloc(sizeof(CLLocationCoordinate2D) * n);
            [line getCoordinates:buffer range:NSMakeRange(0, n)];
            if (coords.count == 0) [coords addObject:SHBox(a)];
            for (NSUInteger i = 0; i < n; i++) [coords addObject:SHBox(buffer[i])];
            free(buffer);
            [coords addObject:SHBox(b)];
        } else {
            SH_LOG(@"no road route for leg %lu, using a straight line", (unsigned long)index);
            if (coords.count == 0) [coords addObject:SHBox(a)];
            [coords addObject:SHBox(b)];
        }
        [weakSelf buildLegs:stops index:index + 1 into:coords completion:completion];
    }];
}

- (void)startRouteWithCoordinates:(NSArray<NSValue *> *)coords {
    if (self.routeLine) [self.mapView removeOverlay:self.routeLine];
    NSUInteger n = coords.count;
    CLLocationCoordinate2D *buffer = malloc(sizeof(CLLocationCoordinate2D) * n);
    for (NSUInteger i = 0; i < n; i++) buffer[i] = SHUnbox(coords[i]);
    self.routeLine = [MKPolyline polylineWithCoordinates:buffer count:n];
    free(buffer);
    [self.mapView addOverlay:self.routeLine];
    [self.mapView setVisibleMapRect:self.routeLine.boundingMapRect
                        edgePadding:UIEdgeInsetsMake(90, 50, CGRectGetHeight(self.sheet.bounds) + 30, 50)
                           animated:YES];

    [[SHMovementEngine shared] startRouteWithCoordinates:coords];
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    [self refreshStatus];
}

- (void)stopRouteTapped {
    SHMovementEngine *engine = [SHMovementEngine shared];
    if (engine.mode == SHEngineModeRoute) [engine stop];
    self.routeFinishedShown = NO;
    [self refreshStatus];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
}

#pragma mark - Places

- (void)togglePlacesEditing {
    [self.placesTable setEditing:!self.placesTable.isEditing animated:YES];
    [self refreshControls];
}

- (void)exportPlaces {
    UIPasteboard.generalPasteboard.string = [[SHPersistence shared] exportPlacesJSON];
    [self showMessage:SHText(@"exported")];
}

- (void)importPlaces {
    NSInteger count = [[SHPersistence shared] importPlacesJSON:UIPasteboard.generalPasteboard.string ?: @""];
    if (count < 0) [self showMessage:SHText(@"import_fail")];
    else [self showMessage:[NSString stringWithFormat:SHText(@"imported_fmt"), (long)count]];
}

// Places table sections: 0 bookmarks, 1 recents, 2 saved routes.
- (NSArray<NSDictionary *> *)placesInSection:(NSInteger)section {
    switch (section) {
        case 0: return [SHPersistence shared].bookmarks;
        case 1: return [SHPersistence shared].recents;
        default: return [SHPersistence shared].savedRoutes;
    }
}

/// Puts a saved route's stops on the map and opens the Route tab.
- (void)loadRoute:(NSDictionary *)route {
    [self clearWaypoints];
    for (NSArray *pair in route[@"points"]) {
        if (![pair isKindOfClass:NSArray.class] || pair.count < 2) continue;
        [self addWaypoint:CLLocationCoordinate2DMake([pair[0] doubleValue], [pair[1] doubleValue])];
    }
    if (self.waypointAnnotations.count) {
        [self.mapView showAnnotations:self.waypointAnnotations animated:YES];
    }
    [self selectTab:SHTabRoute openSheet:YES];
}

- (void)saveRouteTapped {
    if (self.waypoints.count == 0) { [self showMessage:SHText(@"need_stops")]; return; }
    NSArray<NSValue *> *points = [self.waypoints copy];
    [self askForNameWithTitle:SHText(@"route_name") initial:nil completion:^(NSString *name) {
        [[SHPersistence shared] saveRouteNamed:name points:points];
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    }];
}

- (void)copyCoordinatesTapped {
    SHPersistence *store = [SHPersistence shared];
    CLLocationCoordinate2D c;
    if (store.isSpoofing) c = store.coordinate;
    else if (self.hasSelection) c = self.selection;
    else { [self showMessage:SHText(@"need_pin")]; return; }
    UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%.6f, %.6f", c.latitude, c.longitude];
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    [self showMessage:SHText(@"coords_copied")];
}

- (void)openSchedule {
    [self.view endEditing:YES];
    [self.navigationController pushViewController:[[SHScheduleViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
}

- (void)shareExportFile {
    NSString *json = [[SHPersistence shared] exportPlacesJSON];
    NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"Shabah-places.json"];
    if (![json writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
        [self showMessage:SHText(@"export_fail")];
        return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    share.popoverPresentationController.sourceView = self.placesEditButton;
    [self presentViewController:share animated:YES completion:nil];
}

- (void)pickImportFile {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON, UTTypePlainText]];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSString *text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    if (scoped) [url stopAccessingSecurityScopedResource];
    NSInteger count = [[SHPersistence shared] importPlacesJSON:text ?: @""];
    if (count < 0) [self showMessage:SHText(@"import_fail")];
    else [self showMessage:[NSString stringWithFormat:SHText(@"imported_fmt"), (long)count]];
}

- (void)refreshRealLocationPin {
    SHPersistence *store = [SHPersistence shared];
    CLLocation *real = store.lastRealLocation;
    BOOL show = store.showRealLocation && store.isSpoofing && real != nil;
    if (!show) {
        if (self.realPin) [self.mapView removeAnnotation:self.realPin];
        self.realPin = nil;
        return;
    }
    if (!self.realPin) {
        self.realPin = [SHRealLocationAnnotation new];
        self.realPin.title = SHText(@"real_location_pin");
        self.realPin.coordinate = real.coordinate;
        [self.mapView addAnnotation:self.realPin];
    } else {
        self.realPin.coordinate = real.coordinate;
    }
}

- (void)openPlace:(NSDictionary *)place {
    CLLocationCoordinate2D c = CLLocationCoordinate2DMake([place[@"lat"] doubleValue], [place[@"lon"] doubleValue]);
    [self selectCoordinate:c name:place[@"name"] recenter:YES];
    [self.sheet setDetent:SHSheetDetentCollapsed animated:YES];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return tableView == self.placesTable ? 3 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (tableView != self.placesTable) return nil;
    switch (section) {
        case 0: return SHText(@"bookmarks");
        case 1: return SHText(@"recents");
        default: return SHText(@"saved_routes");
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (tableView == self.suggestionsTable) return self.completions.count;
    return MAX(1, (NSInteger)[self placesInSection:section].count);   // one placeholder row when empty
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.imageView.tintColor = [SHTheme accent];

    if (tableView == self.suggestionsTable) {
        MKLocalSearchCompletion *completion = self.completions[indexPath.row];
        cell.textLabel.text = completion.title;
        cell.detailTextLabel.text = completion.subtitle;
        cell.imageView.image = [UIImage systemImageNamed:@"mappin.circle.fill"];
    } else {
        NSArray *places = [self placesInSection:indexPath.section];
        if (places.count == 0) {
            NSArray *empty = @[@"no_bookmarks", @"no_recents", @"no_routes"];
            cell.textLabel.text = SHText(empty[MIN(2, indexPath.section)]);
            cell.textLabel.textColor = UIColor.secondaryLabelColor;
            cell.textLabel.font = [UIFont systemFontOfSize:14];
            cell.textLabel.numberOfLines = 0;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.section == 2) {
            NSDictionary *route = places[indexPath.row];
            cell.textLabel.text = route[@"name"];
            cell.detailTextLabel.text = [NSString stringWithFormat:SHText(@"stops_fmt"), (unsigned long)[route[@"points"] count]];
            cell.imageView.image = [UIImage systemImageNamed:@"point.topleft.down.curvedto.point.bottomright.up"];
        } else {
            NSDictionary *place = places[indexPath.row];
            cell.textLabel.text = place[@"name"];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.5f, %.5f", [place[@"lat"] doubleValue], [place[@"lon"] doubleValue]];
            cell.imageView.image = [UIImage systemImageNamed:indexPath.section == 0 ? @"star.fill" : @"clock.arrow.circlepath"];
        }
    }
    [SHTheme applyDirectionToView:cell];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (tableView == self.suggestionsTable) {
        MKLocalSearchCompletion *completion = self.completions[indexPath.row];
        self.searchField.text = completion.title;
        [self.searchField resignFirstResponder];
        [self hideSuggestions];
        [self runSearch:[[MKLocalSearchRequest alloc] initWithCompletion:completion]];
        return;
    }
    NSArray *places = [self placesInSection:indexPath.section];
    if (indexPath.row >= (NSInteger)places.count) return;
    if (indexPath.section == 2) [self loadRoute:places[indexPath.row]];
    else [self openPlace:places[indexPath.row]];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return tableView == self.placesTable && [self placesInSection:indexPath.section].count > 0;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0 ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style == UITableViewCellEditingStyleDelete && indexPath.section == 0) {
        [[SHPersistence shared] removeBookmarkAtIndex:indexPath.row];
    }
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return tableView == self.placesTable && indexPath.section == 0 && [SHPersistence shared].bookmarks.count > 1;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source toProposedIndexPath:(NSIndexPath *)proposed {
    if (proposed.section != 0) {
        return [NSIndexPath indexPathForRow:(NSInteger)[SHPersistence shared].bookmarks.count - 1 inSection:0];
    }
    return proposed;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    [[SHPersistence shared] moveBookmarkFromIndex:source.row toIndex:destination.row];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView != self.placesTable) return nil;
    NSArray *places = [self placesInSection:indexPath.section];
    if (indexPath.row >= (NSInteger)places.count) return nil;
    NSDictionary *place = places[indexPath.row];
    NSInteger row = indexPath.row;

    if (indexPath.section == 2) {
        UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:SHText(@"delete")
            handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
                [[SHPersistence shared] removeRouteAtIndex:row];
                done(YES);
            }];
        return [UISwipeActionsConfiguration configurationWithActions:@[delete]];
    }

    if (indexPath.section == 0) {
        UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:SHText(@"delete")
            handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
                [[SHPersistence shared] removeBookmarkAtIndex:row];
                done(YES);
            }];
        UIContextualAction *rename = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:SHText(@"rename")
            handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
                [self askForNameWithTitle:SHText(@"rename") initial:place[@"name"] completion:^(NSString *name) {
                    [[SHPersistence shared] renameBookmarkAtIndex:row to:name];
                }];
                done(YES);
            }];
        rename.backgroundColor = [SHTheme accent];
        return [UISwipeActionsConfiguration configurationWithActions:@[delete, rename]];
    }

    UIContextualAction *save = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:SHText(@"save")
        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            CLLocationCoordinate2D c = CLLocationCoordinate2DMake([place[@"lat"] doubleValue], [place[@"lon"] doubleValue]);
            [[SHPersistence shared] addBookmarkNamed:place[@"name"] coordinate:c];
            done(YES);
        }];
    save.backgroundColor = [SHTheme accent];
    save.image = [UIImage systemImageNamed:@"star"];
    return [UISwipeActionsConfiguration configurationWithActions:@[save]];
}

#pragma mark - MKMapViewDelegate

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay {
    if ([overlay isKindOfClass:MKPolyline.class]) {
        MKPolylineRenderer *r = [[MKPolylineRenderer alloc] initWithPolyline:(MKPolyline *)overlay];
        r.strokeColor = [SHTheme accent];
        r.lineWidth = 6;
        r.lineCap = kCGLineCapRound;
        r.lineJoin = kCGLineJoinRound;
        return r;
    }
    return [[MKOverlayRenderer alloc] initWithOverlay:overlay];
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    if ([annotation isKindOfClass:MKUserLocation.class]) return nil;
    if ([annotation isKindOfClass:SHRealLocationAnnotation.class]) {
        MKMarkerAnnotationView *real = (MKMarkerAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:@"real"];
        if (!real) real = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"real"];
        real.annotation = annotation;
        real.markerTintColor = UIColor.systemGrayColor;
        real.glyphImage = [UIImage systemImageNamed:@"location.fill"];
        real.displayPriority = MKFeatureDisplayPriorityRequired;
        real.alpha = 0.75;
        return real;
    }
    BOOL isStop =[annotation isKindOfClass:SHWaypointAnnotation.class];
    NSString *reuse = isStop ? @"stop" : @"pin";
    MKMarkerAnnotationView *view = (MKMarkerAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:reuse];
    if (!view) view = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:reuse];
    view.annotation = annotation;
    if (isStop) {
        view.markerTintColor = [SHTheme accent];
        view.glyphImage = nil;
        view.glyphText = [NSString stringWithFormat:@"%lu", (unsigned long)((SHWaypointAnnotation *)annotation).number];
        view.draggable = NO;
    } else {
        view.markerTintColor = UIColor.systemRedColor;
        view.glyphText = nil;
        view.glyphImage = [SHTheme ghostImageWithSize:20 color:UIColor.whiteColor];
        view.draggable = YES;
    }
    return view;
}

- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view didChangeDragState:(MKAnnotationViewDragState)newState fromOldState:(MKAnnotationViewDragState)oldState {
    if (newState == MKAnnotationViewDragStateEnding && view.annotation == self.pin) {
        [self selectCoordinate:self.pin.coordinate name:nil recenter:NO];
    }
}

#pragma mark - Keyboard

- (void)keyboardChanged:(NSNotification *)note {
    CGRect frame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect local = [self.view convertRect:frame fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(local));
    for (UIView *v in self.tabViews) {
        if (![v isKindOfClass:UIScrollView.class]) continue;
        UIScrollView *scroll = (UIScrollView *)v;
        scroll.contentInset = UIEdgeInsetsMake(0, 0, overlap, 0);
        scroll.verticalScrollIndicatorInsets = scroll.contentInset;
    }
    BOOL sheetFieldActive = self.latField.isFirstResponder || self.lonField.isFirstResponder || self.altitudeField.isFirstResponder;
    if (overlap > 0 && sheetFieldActive) [self.sheet setDetent:SHSheetDetentFull animated:YES];
}

#pragma mark - Alerts

- (void)showMessage:(NSString *)message {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:SHText(@"ok") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)askForNameWithTitle:(NSString *)title initial:(NSString *)initial completion:(void (^)(NSString *name))completion {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = initial;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:SHText(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert = ac;
    [ac addAction:[UIAlertAction actionWithTitle:SHText(@"save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        completion(weakAlert.textFields.firstObject.text ?: @"");
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
