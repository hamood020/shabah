#import "SHMapPickerViewController.h"
#import "SHPersistence.h"
#import "SHRouteSimulator.h"
#import "SHOverlay.h"
#import "SHBookmarksViewController.h"

static const double kSpeedsKmh[] = { 5.0, 15.0, 60.0 }; // walk, bike, car

@interface SHMapPickerViewController () <MKMapViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIVisualEffectView *card;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *coordLabel;
@property (nonatomic, strong) UISwitch *fluctSwitch;
@property (nonatomic, strong) UISegmentedControl *modeSegment;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) MKPointAnnotation *pin;
@property (nonatomic, strong) MKPointAnnotation *mover;
@property (nonatomic, strong) MKPolyline *routeLine;
@property (nonatomic, strong) id stateObserver;
@property (nonatomic) BOOL hasSelection;
@property (nonatomic) CLLocationCoordinate2D selection;
@end

@implementation SHMapPickerViewController

- (void)dealloc {
    if (_stateObserver) [[NSNotificationCenter defaultCenter] removeObserver:_stateObserver];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.mapView = [[MKMapView alloc] init];
    self.mapView.delegate = self;
    self.mapView.showsUserLocation = YES;
    self.mapView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.mapView addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)]];
    [self.view addSubview:self.mapView];
    [NSLayoutConstraint activateConstraints:@[
        [self.mapView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.mapView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.mapView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.mapView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    [self buildChrome];

    SHPersistence *store = [SHPersistence shared];
    if (store.isSpoofing) {
        [self selectCoordinate:store.coordinate recenter:YES];
    }

    __weak typeof(self) weakSelf = self;
    self.stateObserver = [[NSNotificationCenter defaultCenter] addObserverForName:SHStateChangedNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [weakSelf refresh]; }];
    [self refresh];
}

#pragma mark - UI

/// Builds everything that depends on the language; called again when it changes.
- (void)buildChrome {
    BOOL arabic = [SHPersistence shared].arabic;
    UISemanticContentAttribute dir = arabic ? UISemanticContentAttributeForceRightToLeft : UISemanticContentAttributeForceLeftToRight;
    self.navigationController.view.semanticContentAttribute = dir;
    self.navigationController.navigationBar.semanticContentAttribute = dir;

    self.title = SHText(@"title");
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:SHText(@"close") style:UIBarButtonItemStyleDone target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:SHText(@"lang") style:UIBarButtonItemStylePlain target:self action:@selector(toggleLanguage)];

    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = SHText(@"search");
    self.searchBar.semanticContentAttribute = dir;
    self.navigationItem.titleView = self.searchBar;

    [self.card removeFromSuperview];
    self.card = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    self.card.translatesAutoresizingMaskIntoConstraints = NO;
    self.card.layer.cornerRadius = 18;
    self.card.clipsToBounds = YES;
    [self.view addSubview:self.card];

    self.statusLabel = [UILabel new];
    self.statusLabel.font = [UIFont boldSystemFontOfSize:17];

    self.coordLabel = [UILabel new];
    self.coordLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    self.coordLabel.textColor = UIColor.secondaryLabelColor;
    self.coordLabel.numberOfLines = 0;

    UILabel *fluctLabel = [UILabel new];
    fluctLabel.text = SHText(@"fluct");
    self.fluctSwitch = [UISwitch new];
    self.fluctSwitch.on = [SHPersistence shared].fluctuationEnabled;
    [self.fluctSwitch addTarget:self action:@selector(fluctChanged) forControlEvents:UIControlEventValueChanged];
    UIStackView *fluctRow = [[UIStackView alloc] initWithArrangedSubviews:@[fluctLabel, self.fluctSwitch]];
    fluctRow.alignment = UIStackViewAlignmentCenter;

    NSInteger previousMode = self.modeSegment ? self.modeSegment.selectedSegmentIndex : 0;
    self.modeSegment = [[UISegmentedControl alloc] initWithItems:@[SHText(@"walk"), SHText(@"bike"), SHText(@"car")]];
    self.modeSegment.selectedSegmentIndex = previousMode;
    [self.modeSegment addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];

    UIColor *brand = [UIColor colorWithRed:0.10 green:0.55 blue:0.55 alpha:1];
    UIStackView *row1 = [self rowWithButtons:@[
        [self buttonWithTitle:SHText(@"apply") color:brand action:@selector(applyTapped)],
        [self buttonWithTitle:SHText(@"route") color:UIColor.systemIndigoColor action:@selector(routeTapped)],
    ]];
    UIStackView *row2 = [self rowWithButtons:@[
        [self buttonWithTitle:SHText(@"save") color:UIColor.systemGrayColor action:@selector(saveTapped)],
        [self buttonWithTitle:SHText(@"bookmarks") color:UIColor.systemGrayColor action:@selector(bookmarksTapped)],
    ]];
    self.stopButton = [self buttonWithTitle:SHText(@"stop") color:UIColor.systemRedColor action:@selector(stopTapped)];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.statusLabel, self.coordLabel, fluctRow, self.modeSegment, row1, row2, self.stopButton]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card.contentView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [self.card.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12],
        [self.card.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [self.card.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [stack.topAnchor constraintEqualToAnchor:self.card.contentView.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:self.card.contentView.bottomAnchor constant:-14],
        [stack.leadingAnchor constraintEqualToAnchor:self.card.contentView.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:self.card.contentView.trailingAnchor constant:-14],
    ]];

    [self applyDirection:dir toView:self.card];
    self.mapView.layoutMargins = UIEdgeInsetsMake(0, 0, 330, 0); // keep the Apple logo / legal link visible
}

- (void)applyDirection:(UISemanticContentAttribute)dir toView:(UIView *)view {
    view.semanticContentAttribute = dir;
    if ([view isKindOfClass:UILabel.class]) ((UILabel *)view).textAlignment = NSTextAlignmentNatural;
    for (UIView *sub in view.subviews) [self applyDirection:dir toView:sub];
}

- (UIButton *)buttonWithTitle:(NSString *)title color:(UIColor *)color action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    b.backgroundColor = color;
    b.layer.cornerRadius = 10;
    [b.heightAnchor constraintEqualToConstant:44].active = YES;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UIStackView *)rowWithButtons:(NSArray<UIButton *> *)buttons {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 10;
    return row;
}

- (void)refresh {
    SHPersistence *store = [SHPersistence shared];
    BOOL on = store.isSpoofing;
    self.statusLabel.text = on ? SHText(@"status_on") : SHText(@"status_off");
    self.statusLabel.textColor = on ? UIColor.systemGreenColor : UIColor.secondaryLabelColor;
    self.stopButton.enabled = on;
    self.stopButton.alpha = on ? 1.0 : 0.4;
    if (self.hasSelection) {
        self.coordLabel.text = [NSString stringWithFormat:@"%.6f, %.6f", self.selection.latitude, self.selection.longitude];
    } else {
        self.coordLabel.text = SHText(@"hint");
    }
}

#pragma mark - Selection

- (void)selectCoordinate:(CLLocationCoordinate2D)c recenter:(BOOL)recenter {
    if (!CLLocationCoordinate2DIsValid(c)) return;
    self.selection = c;
    self.hasSelection = YES;
    if (!self.pin) {
        self.pin = [MKPointAnnotation new];
        self.pin.coordinate = c;
        [self.mapView addAnnotation:self.pin];
    } else {
        self.pin.coordinate = c;
    }
    if (recenter) {
        [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(c, 1500, 1500) animated:YES];
    }
    [self refresh];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    CGPoint p = [g locationInView:self.mapView];
    [self selectCoordinate:[self.mapView convertPoint:p toCoordinateFromView:self.mapView] recenter:NO];
    [[UISelectionFeedbackGenerator new] selectionChanged];
}

#pragma mark - Search

/// Accepts "lat, lon" or "lat lon" typed or pasted into the search bar.
- (BOOL)parseCoordinate:(NSString *)text into:(CLLocationCoordinate2D *)out {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^\\s*(-?\\d+(?:\\.\\d+)?)\\s*[, ]\\s*(-?\\d+(?:\\.\\d+)?)\\s*$" options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!m) return NO;
    double lat = [[text substringWithRange:[m rangeAtIndex:1]] doubleValue];
    double lon = [[text substringWithRange:[m rangeAtIndex:2]] doubleValue];
    CLLocationCoordinate2D c = CLLocationCoordinate2DMake(lat, lon);
    if (!CLLocationCoordinate2DIsValid(c)) return NO;
    *out = c;
    return YES;
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    NSString *query = searchBar.text ?: @"";
    if (query.length == 0) return;

    CLLocationCoordinate2D parsed;
    if ([self parseCoordinate:query into:&parsed]) {
        [self selectCoordinate:parsed recenter:YES];
        return;
    }

    MKLocalSearchRequest *request = [MKLocalSearchRequest new];
    request.naturalLanguageQuery = query;
    request.region = self.mapView.region;
    __weak typeof(self) weakSelf = self;
    [[[MKLocalSearch alloc] initWithRequest:request] startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
        MKMapItem *item = response.mapItems.firstObject;
        if (!item) { [weakSelf alert:SHText(@"search_fail")]; return; }
        [weakSelf selectCoordinate:item.placemark.coordinate recenter:YES];
        weakSelf.pin.title = item.name;
    }];
}

#pragma mark - Actions

- (void)close {
    [self.searchBar resignFirstResponder];
    [self.navigationController dismissViewControllerAnimated:YES completion:^{
        [SHOverlay pickerDidClose];
    }];
}

- (void)toggleLanguage {
    SHPersistence *store = [SHPersistence shared];
    store.arabic = !store.arabic;
    [self buildChrome];
    [self refresh];
}

- (void)fluctChanged {
    [SHPersistence shared].fluctuationEnabled = self.fluctSwitch.on;
}

- (void)modeChanged {
    [SHRouteSimulator shared].speedMetersPerSecond = kSpeedsKmh[self.modeSegment.selectedSegmentIndex] / 3.6;
}

- (void)applyTapped {
    if (!self.hasSelection) { [self alert:SHText(@"need_pin")]; return; }
    [[SHRouteSimulator shared] stop];
    [self clearRoute];
    [[SHPersistence shared] startSpoofingAt:self.selection];
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
}

- (void)routeTapped {
    SHPersistence *store = [SHPersistence shared];
    if (!store.isSpoofing) { [self alert:SHText(@"need_start")]; return; }
    if (!self.hasSelection) { [self alert:SHText(@"need_pin")]; return; }

    MKDirectionsRequest *request = [MKDirectionsRequest new];
    request.source = [[MKMapItem alloc] initWithPlacemark:[[MKPlacemark alloc] initWithCoordinate:store.coordinate]];
    request.destination = [[MKMapItem alloc] initWithPlacemark:[[MKPlacemark alloc] initWithCoordinate:self.selection]];
    request.transportType = self.modeSegment.selectedSegmentIndex == 2 ? MKDirectionsTransportTypeAutomobile : MKDirectionsTransportTypeWalking;

    __weak typeof(self) weakSelf = self;
    [[[MKDirections alloc] initWithRequest:request] calculateDirectionsWithCompletionHandler:^(MKDirectionsResponse *response, NSError *error) {
        MKRoute *route = response.routes.firstObject;
        if (!route) {
            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeError];
            [weakSelf alert:SHText(@"route_fail")];
            return;
        }
        [weakSelf startRoute:route.polyline];
    }];
}

- (void)startRoute:(MKPolyline *)line {
    [self clearRoute];
    self.routeLine = line;
    [self.mapView addOverlay:line];
    [self.mapView setVisibleMapRect:line.boundingMapRect edgePadding:UIEdgeInsetsMake(60, 40, 360, 40) animated:YES];

    self.mover = [MKPointAnnotation new];
    [self.mapView addAnnotation:self.mover];

    SHRouteSimulator *sim = [SHRouteSimulator shared];
    sim.speedMetersPerSecond = kSpeedsKmh[self.modeSegment.selectedSegmentIndex] / 3.6;
    __weak typeof(self) weakSelf = self;
    sim.onUpdate = ^(CLLocationCoordinate2D c, BOOL finished) {
        weakSelf.mover.coordinate = c;
        if (finished) {
            weakSelf.statusLabel.text = SHText(@"route_done");
            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
        }
    };
    [sim startWithPolyline:line];
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
}

- (void)clearRoute {
    if (self.routeLine) [self.mapView removeOverlay:self.routeLine];
    if (self.mover) [self.mapView removeAnnotation:self.mover];
    self.routeLine = nil;
    self.mover = nil;
}

- (void)stopTapped {
    [[SHRouteSimulator shared] stop];
    [self clearRoute];
    [[SHPersistence shared] stopSpoofing];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
}

- (void)saveTapped {
    if (!self.hasSelection) { [self alert:SHText(@"need_pin")]; return; }
    CLLocationCoordinate2D c = self.selection;
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:SHText(@"bookmark_name") message:nil preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = self.pin.title; }];
    [ac addAction:[UIAlertAction actionWithTitle:SHText(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert = ac;
    [ac addAction:[UIAlertAction actionWithTitle:SHText(@"save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [[SHPersistence shared] addBookmarkNamed:weakAlert.textFields.firstObject.text ?: @"" coordinate:c];
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)bookmarksTapped {
    SHBookmarksViewController *vc = [[SHBookmarksViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    __weak typeof(self) weakSelf = self;
    vc.onSelect = ^(CLLocationCoordinate2D c, NSString *name) {
        [weakSelf.navigationController popViewControllerAnimated:YES];
        [weakSelf selectCoordinate:c recenter:YES];
        weakSelf.pin.title = name;
    };
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)alert:(NSString *)message {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:SHText(@"ok") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - MKMapViewDelegate

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay {
    if ([overlay isKindOfClass:MKPolyline.class]) {
        MKPolylineRenderer *r = [[MKPolylineRenderer alloc] initWithPolyline:(MKPolyline *)overlay];
        r.strokeColor = UIColor.systemTealColor;
        r.lineWidth = 5;
        return r;
    }
    return [[MKOverlayRenderer alloc] initWithOverlay:overlay];
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    if ([annotation isKindOfClass:MKUserLocation.class]) return nil;
    BOOL isMover = annotation == self.mover;
    NSString *reuse = isMover ? @"mover" : @"pin";
    MKMarkerAnnotationView *view = (MKMarkerAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:reuse];
    if (!view) view = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:reuse];
    view.annotation = annotation;
    view.markerTintColor = isMover ? UIColor.systemBlueColor : UIColor.systemRedColor;
    view.glyphImage = [UIImage systemImageNamed:isMover ? @"figure.walk" : @"mappin"];
    view.draggable = !isMover;
    return view;
}

- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view didChangeDragState:(MKAnnotationViewDragState)newState fromOldState:(MKAnnotationViewDragState)oldState {
    if (newState == MKAnnotationViewDragStateEnding && view.annotation == self.pin) {
        [self selectCoordinate:self.pin.coordinate recenter:NO];
    }
}

@end
