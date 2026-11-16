#import "SHPersistence.h"

NSString *const SHStateChangedNotification = @"SHStateChangedNotification";
NSString *const SHPlacesChangedNotification = @"SHPlacesChangedNotification";

static NSString *const kEnabled   = @"SHEnabled";
static NSString *const kLat       = @"SHLat";
static NSString *const kLon       = @"SHLon";
static NSString *const kAlt       = @"SHAltitude";
static NSString *const kJitter    = @"SHJitter";
static NSString *const kRadius    = @"SHJitterRadius";
static NSString *const kAutoStop  = @"SHAutoStopMinutes";
static NSString *const kExpiry    = @"SHExpiryDate";
static NSString *const kGlide     = @"SHGlide";
static NSString *const kArabic    = @"SHArabic";
static NSString *const kMapStyle  = @"SHMapStyle";
static NSString *const kUpdates   = @"SHCheckUpdates";
static NSString *const kTransport = @"SHTransport";
static NSString *const kSpeed     = @"SHSpeedKmh";
static NSString *const kLoop      = @"SHLoopRoute";
static NSString *const kRealistic = @"SHRealistic";
static NSString *const kJoystick  = @"SHJoystick";
static NSString *const kBookmarks = @"SHBookmarks";
static NSString *const kRecents   = @"SHRecents";
static NSString *const kRoutes    = @"SHSavedRoutes";
static NSString *const kTheme     = @"SHTheme";
static NSString *const kBtnSize   = @"SHButtonSize";
static NSString *const kBtnAlpha  = @"SHButtonOpacity";
static NSString *const kPill      = @"SHStatusPill";
static NSString *const kVolume    = @"SHVolumeGesture";
static NSString *const kRealPin   = @"SHShowRealLocation";
static NSString *const kNotify    = @"SHExpiryNotifications";
static NSString *const kSchedOn   = @"SHScheduleEnabled";
static NSString *const kSchedDays = @"SHScheduleDays";
static NSString *const kSchedFrom = @"SHScheduleStart";
static NSString *const kSchedTo   = @"SHScheduleEnd";
static NSString *const kSchedLoc  = @"SHScheduleLocation";

static const double kPresetSpeeds[] = { 5.0, 15.0, 60.0 };
static const NSUInteger kMaxRecents = 15;

static void SHPostOnMain(NSString *name) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:name object:nil];
    });
}

@implementation SHPersistence {
    NSUserDefaults *_d;
    BOOL _isSpoofing;
    BOOL _hasCoord;
    CLLocationCoordinate2D _coord;
    double _course, _speed;
    CFAbsoluteTime _lastWrite;
    // Smart jitter: a slow random walk inside the radius instead of independent jumps.
    double _jitterX, _jitterY, _accuracy;
    CFAbsoluteTime _lastJitterStep;
}

+ (instancetype)shared {
    static SHPersistence *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] initPrivate]; });
    return instance;
}

- (instancetype)initPrivate {
    if ((self = [super init])) {
        _d = [NSUserDefaults standardUserDefaults];
        _hasCoord = [_d objectForKey:kLat] && [_d objectForKey:kLon];
        _coord = CLLocationCoordinate2DMake([_d doubleForKey:kLat], [_d doubleForKey:kLon]);
        if (!CLLocationCoordinate2DIsValid(_coord)) _hasCoord = NO;
        _isSpoofing = _hasCoord && [_d boolForKey:kEnabled];

        _altitude = [_d doubleForKey:kAlt];
        _jitterEnabled = [_d boolForKey:kJitter];
        _jitterRadius = [_d objectForKey:kRadius] ? [_d doubleForKey:kRadius] : 15.0;
        _autoStopMinutes = [_d integerForKey:kAutoStop];
        _expiryDate = [_d objectForKey:kExpiry];
        _glideEnabled = [_d boolForKey:kGlide];
        _arabic = [_d objectForKey:kArabic] ? [_d boolForKey:kArabic]
                                            : [[NSLocale preferredLanguages].firstObject hasPrefix:@"ar"];
        _mapStyle = [_d integerForKey:kMapStyle];
        _checkUpdates = [_d objectForKey:kUpdates] ? [_d boolForKey:kUpdates] : YES;
        _transportMode = [_d integerForKey:kTransport];
        _speedKmh = [_d objectForKey:kSpeed] ? [_d doubleForKey:kSpeed] : kPresetSpeeds[0];
        _loopRoute = [_d boolForKey:kLoop];
        _realisticMotion = [_d objectForKey:kRealistic] ? [_d boolForKey:kRealistic] : YES;
        _joystickEnabled = [_d boolForKey:kJoystick];

        _themeIndex = [_d integerForKey:kTheme];
        _buttonSize = [_d objectForKey:kBtnSize] ? [_d doubleForKey:kBtnSize] : 56;
        _buttonOpacity = [_d objectForKey:kBtnAlpha] ? [_d doubleForKey:kBtnAlpha] : 1.0;
        _statusPillEnabled = [_d objectForKey:kPill] ? [_d boolForKey:kPill] : YES;
        _volumeGestureEnabled = [_d boolForKey:kVolume];
        _showRealLocation = [_d objectForKey:kRealPin] ? [_d boolForKey:kRealPin] : YES;
        _expiryNotifications = [_d boolForKey:kNotify];

        _scheduleEnabled = [_d boolForKey:kSchedOn];
        _scheduleDays = [_d arrayForKey:kSchedDays] ?: @[@1, @2, @3, @4, @5];   // Sunday to Thursday
        _scheduleStartMinutes = [_d objectForKey:kSchedFrom] ? [_d integerForKey:kSchedFrom] : 7 * 60;
        _scheduleEndMinutes = [_d objectForKey:kSchedTo] ? [_d integerForKey:kSchedTo] : 15 * 60;
        _scheduleLocation = [_d dictionaryForKey:kSchedLoc];

        _course = -1;
        _speed = -1;
        _accuracy = 5;
    }
    return self;
}

#pragma mark - State

- (BOOL)isSpoofing {
    BOOL expired = NO;
    @synchronized (self) {
        if (_isSpoofing && _expiryDate && _expiryDate.timeIntervalSinceNow <= 0) expired = YES;
    }
    if (expired) {
        SH_LOG(@"auto-stop time reached");
        [self stopSpoofing];
    }
    @synchronized (self) { return _isSpoofing; }
}

- (BOOL)hasCoordinate {
    @synchronized (self) { return _hasCoord; }
}

- (CLLocationCoordinate2D)coordinate {
    @synchronized (self) { return _coord; }
}

- (void)writeCoordinate:(CLLocationCoordinate2D)c {
    [_d setDouble:c.latitude forKey:kLat];
    [_d setDouble:c.longitude forKey:kLon];
    [_d setBool:YES forKey:kEnabled];
    _lastWrite = CFAbsoluteTimeGetCurrent();
}

- (void)startSpoofingAt:(CLLocationCoordinate2D)c {
    if (!CLLocationCoordinate2DIsValid(c)) return;
    @synchronized (self) {
        _coord = c;
        _hasCoord = YES;
        _course = -1;
        _speed = -1;
        _isSpoofing = YES;
        _jitterX = _jitterY = 0;
    }
    [self writeCoordinate:c];
    [self restartExpiryTimer];
    SH_LOG(@"spoofing at %.6f, %.6f", c.latitude, c.longitude);
    SHPostOnMain(SHStateChangedNotification);
}

- (void)moveTo:(CLLocationCoordinate2D)c course:(double)course speed:(double)speed {
    if (!CLLocationCoordinate2DIsValid(c)) return;
    BOOL wasOff;
    @synchronized (self) {
        wasOff = !_isSpoofing;
        _coord = c;
        _hasCoord = YES;
        _course = course;
        _speed = speed;
        _isSpoofing = YES;
    }
    // Writing defaults on every tick is wasteful; every 2 seconds is enough to survive a relaunch.
    if (wasOff || CFAbsoluteTimeGetCurrent() - _lastWrite > 2.0) [self writeCoordinate:c];
    if (wasOff) SHPostOnMain(SHStateChangedNotification);
}

- (void)restartExpiryTimer {
    NSDate *expiry = self.autoStopMinutes > 0 ? [NSDate dateWithTimeIntervalSinceNow:self.autoStopMinutes * 60.0] : nil;
    @synchronized (self) { _expiryDate = expiry; }
    if (expiry) [_d setObject:expiry forKey:kExpiry];
    else [_d removeObjectForKey:kExpiry];
}

- (void)stopSpoofing {
    @synchronized (self) {
        if (!_isSpoofing) return;
        _isSpoofing = NO;
        _expiryDate = nil;
    }
    [_d setBool:NO forKey:kEnabled];
    [_d removeObjectForKey:kExpiry];
    SH_LOG(@"spoofing stopped");
    SHPostOnMain(SHStateChangedNotification);
}

- (void)resumeLast {
    if (self.hasCoordinate) [self startSpoofingAt:self.coordinate];
}

- (CLLocation *)currentSpoofedLocation {
    if (![self isSpoofing]) return nil;

    CLLocationCoordinate2D c;
    double course, speed, accuracy;
    @synchronized (self) {
        c = _coord;
        course = _course;
        speed = _speed;

        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        double radius = self.jitterEnabled ? MAX(1.0, self.jitterRadius) : 0;
        if (now - _lastJitterStep > 0.8) {
            _lastJitterStep = now;
            if (radius > 0) {
                double step = radius * 0.25;
                _jitterX += (SHRandomUnit() * 2 - 1) * step;
                _jitterY += (SHRandomUnit() * 2 - 1) * step;
                double len = hypot(_jitterX, _jitterY);
                if (len > radius) { _jitterX *= radius / len; _jitterY *= radius / len; }
                _accuracy += (SHRandomUnit() * 2 - 1) * 2.0;
                _accuracy = MAX(5.0, MIN(MAX(8.0, radius), _accuracy));
            } else {
                _jitterX = _jitterY = 0;
                _accuracy = 4.5 + SHRandomUnit();
            }
        }
        accuracy = _accuracy;
        if (radius > 0) {
            c.latitude += _jitterY / 111320.0;
            double metersPerDegLon = 111320.0 * cos(c.latitude * M_PI / 180.0);
            if (metersPerDegLon > 1) c.longitude += _jitterX / metersPerDegLon;
        }
    }

    return [[CLLocation alloc] initWithCoordinate:c
                                         altitude:self.altitude
                               horizontalAccuracy:accuracy
                                 verticalAccuracy:accuracy * 1.5
                                           course:course
                                            speed:speed
                                        timestamp:[NSDate date]];
}

#pragma mark - Settings

- (void)setAltitude:(double)v       { _altitude = v;       [_d setDouble:v forKey:kAlt]; }
- (void)setJitterEnabled:(BOOL)v    { _jitterEnabled = v;  [_d setBool:v forKey:kJitter]; }
- (void)setJitterRadius:(double)v   { _jitterRadius = MAX(1, MIN(500, v)); [_d setDouble:_jitterRadius forKey:kRadius]; }
- (void)setGlideEnabled:(BOOL)v     { _glideEnabled = v;   [_d setBool:v forKey:kGlide]; }
- (void)setCheckUpdates:(BOOL)v     { _checkUpdates = v;   [_d setBool:v forKey:kUpdates]; }
- (void)setSpeedKmh:(double)v       { _speedKmh = MAX(1, MIN(300, v)); [_d setDouble:_speedKmh forKey:kSpeed]; }
- (void)setLoopRoute:(BOOL)v        { _loopRoute = v;      [_d setBool:v forKey:kLoop]; }
- (void)setRealisticMotion:(BOOL)v  { _realisticMotion = v; [_d setBool:v forKey:kRealistic]; }
- (void)setMapStyle:(NSInteger)v    { _mapStyle = v;       [_d setInteger:v forKey:kMapStyle]; }

- (void)setAutoStopMinutes:(NSInteger)v {
    _autoStopMinutes = MAX(0, v);
    [_d setInteger:_autoStopMinutes forKey:kAutoStop];
    if (self.isSpoofing) [self restartExpiryTimer];
}

- (void)setArabic:(BOOL)v {
    _arabic = v;
    [_d setBool:v forKey:kArabic];
    SHPostOnMain(SHStateChangedNotification);
}

- (void)setTransportMode:(NSInteger)v {
    _transportMode = MAX(0, MIN(2, v));
    [_d setInteger:_transportMode forKey:kTransport];
    self.speedKmh = kPresetSpeeds[_transportMode];
}

- (void)setJoystickEnabled:(BOOL)v {
    _joystickEnabled = v;
    [_d setBool:v forKey:kJoystick];
    SHPostOnMain(SHStateChangedNotification);
}

// Settings that change what the overlay shows post a state change so it redraws.
- (void)setThemeIndex:(NSInteger)v        { _themeIndex = MAX(0, v); [_d setInteger:_themeIndex forKey:kTheme]; SHPostOnMain(SHStateChangedNotification); }
- (void)setButtonSize:(double)v           { _buttonSize = MAX(44, MIN(76, v)); [_d setDouble:_buttonSize forKey:kBtnSize]; SHPostOnMain(SHStateChangedNotification); }
- (void)setButtonOpacity:(double)v        { _buttonOpacity = MAX(0.35, MIN(1, v)); [_d setDouble:_buttonOpacity forKey:kBtnAlpha]; SHPostOnMain(SHStateChangedNotification); }
- (void)setStatusPillEnabled:(BOOL)v      { _statusPillEnabled = v; [_d setBool:v forKey:kPill]; SHPostOnMain(SHStateChangedNotification); }
- (void)setVolumeGestureEnabled:(BOOL)v   { _volumeGestureEnabled = v; [_d setBool:v forKey:kVolume]; SHPostOnMain(SHStateChangedNotification); }
- (void)setShowRealLocation:(BOOL)v       { _showRealLocation = v; [_d setBool:v forKey:kRealPin]; }
- (void)setExpiryNotifications:(BOOL)v    { _expiryNotifications = v; [_d setBool:v forKey:kNotify]; SHPostOnMain(SHStateChangedNotification); }

- (void)setScheduleEnabled:(BOOL)v        { _scheduleEnabled = v; [_d setBool:v forKey:kSchedOn]; SHPostOnMain(SHStateChangedNotification); }
- (void)setScheduleDays:(NSArray<NSNumber *> *)v { _scheduleDays = [v copy] ?: @[]; [_d setObject:_scheduleDays forKey:kSchedDays]; SHPostOnMain(SHStateChangedNotification); }
- (void)setScheduleStartMinutes:(NSInteger)v { _scheduleStartMinutes = MAX(0, MIN(1439, v)); [_d setInteger:_scheduleStartMinutes forKey:kSchedFrom]; SHPostOnMain(SHStateChangedNotification); }
- (void)setScheduleEndMinutes:(NSInteger)v   { _scheduleEndMinutes = MAX(0, MIN(1439, v)); [_d setInteger:_scheduleEndMinutes forKey:kSchedTo]; SHPostOnMain(SHStateChangedNotification); }
- (void)setScheduleLocation:(NSDictionary *)v {
    _scheduleLocation = [v copy];
    if (v) [_d setObject:@{ @"name": v[@"name"] ?: @"", @"lat": v[@"lat"] ?: @0, @"lon": v[@"lon"] ?: @0 } forKey:kSchedLoc];
    else [_d removeObjectForKey:kSchedLoc];
    SHPostOnMain(SHStateChangedNotification);
}

#pragma mark - Places

static NSDictionary *SHPlace(NSString *name, CLLocationCoordinate2D c) {
    return @{ @"name": name, @"lat": @(c.latitude), @"lon": @(c.longitude), @"date": [NSDate date] };
}

static NSString *SHPlaceName(NSString *name, CLLocationCoordinate2D c) {
    NSString *t = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return t.length ? t : [NSString stringWithFormat:@"%.5f, %.5f", c.latitude, c.longitude];
}

- (NSArray<NSDictionary *> *)bookmarks {
    return [_d arrayForKey:kBookmarks] ?: @[];
}

- (void)saveBookmarks:(NSArray *)list {
    [_d setObject:list forKey:kBookmarks];
    SHPostOnMain(SHPlacesChangedNotification);
}

- (void)addBookmarkNamed:(NSString *)name coordinate:(CLLocationCoordinate2D)c {
    if (!CLLocationCoordinate2DIsValid(c)) return;
    NSMutableArray *list = [[self bookmarks] mutableCopy];
    [list addObject:SHPlace(SHPlaceName(name ?: @"", c), c)];
    [self saveBookmarks:list];
}

- (void)renameBookmarkAtIndex:(NSUInteger)index to:(NSString *)name {
    NSMutableArray *list = [[self bookmarks] mutableCopy];
    if (index >= list.count) return;
    NSMutableDictionary *item = [list[index] mutableCopy];
    CLLocationCoordinate2D c = CLLocationCoordinate2DMake([item[@"lat"] doubleValue], [item[@"lon"] doubleValue]);
    item[@"name"] = SHPlaceName(name, c);
    list[index] = item;
    [self saveBookmarks:list];
}

- (void)moveBookmarkFromIndex:(NSUInteger)from toIndex:(NSUInteger)to {
    NSMutableArray *list = [[self bookmarks] mutableCopy];
    if (from >= list.count || to >= list.count || from == to) return;
    id item = list[from];
    [list removeObjectAtIndex:from];
    [list insertObject:item atIndex:to];
    [self saveBookmarks:list];
}

- (void)removeBookmarkAtIndex:(NSUInteger)index {
    NSMutableArray *list = [[self bookmarks] mutableCopy];
    if (index >= list.count) return;
    [list removeObjectAtIndex:index];
    [self saveBookmarks:list];
}

- (NSArray<NSDictionary *> *)recents {
    return [_d arrayForKey:kRecents] ?: @[];
}

- (void)recordRecent:(CLLocationCoordinate2D)c name:(NSString *)name {
    if (!CLLocationCoordinate2DIsValid(c)) return;
    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *item in [self recents]) {
        CLLocationCoordinate2D o = CLLocationCoordinate2DMake([item[@"lat"] doubleValue], [item[@"lon"] doubleValue]);
        if (SHDistance(o, c) > 25) [list addObject:item];   // drop near-duplicates
    }
    [list insertObject:SHPlace(SHPlaceName(name ?: @"", c), c) atIndex:0];
    while (list.count > kMaxRecents) [list removeLastObject];
    [_d setObject:list forKey:kRecents];
    SHPostOnMain(SHPlacesChangedNotification);
}

- (NSArray<NSDictionary *> *)savedRoutes {
    return [_d arrayForKey:kRoutes] ?: @[];
}

- (void)saveRouteNamed:(NSString *)name points:(NSArray<NSValue *> *)points {
    if (points.count == 0) return;
    NSMutableArray *pairs = [NSMutableArray arrayWithCapacity:points.count];
    for (NSValue *v in points) {
        CLLocationCoordinate2D c = SHUnbox(v);
        [pairs addObject:@[@(c.latitude), @(c.longitude)]];
    }
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) trimmed = [NSString stringWithFormat:@"Route %lu", (unsigned long)[self savedRoutes].count + 1];
    NSMutableArray *list = [[self savedRoutes] mutableCopy];
    [list insertObject:@{ @"name": trimmed, @"points": pairs, @"date": [NSDate date] } atIndex:0];
    [_d setObject:list forKey:kRoutes];
    SHPostOnMain(SHPlacesChangedNotification);
}

- (void)removeRouteAtIndex:(NSUInteger)index {
    NSMutableArray *list = [[self savedRoutes] mutableCopy];
    if (index >= list.count) return;
    [list removeObjectAtIndex:index];
    [_d setObject:list forKey:kRoutes];
    SHPostOnMain(SHPlacesChangedNotification);
}

- (NSString *)exportPlacesJSON {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *item in [self bookmarks]) {
        [out addObject:@{ @"name": item[@"name"] ?: @"", @"lat": item[@"lat"] ?: @0, @"lon": item[@"lon"] ?: @0 }];
    }
    NSMutableArray *routes = [NSMutableArray array];
    for (NSDictionary *route in [self savedRoutes]) {
        [routes addObject:@{ @"name": route[@"name"] ?: @"", @"points": route[@"points"] ?: @[] }];
    }
    NSDictionary *root = @{ @"app": @"shabah", @"version": SH_VERSION, @"bookmarks": out, @"routes": routes };
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
}

- (NSInteger)importPlacesJSON:(NSString *)json {
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return -1;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *items = [root isKindOfClass:NSDictionary.class] ? root[@"bookmarks"] : root;
    if (![items isKindOfClass:NSArray.class]) items = @[];

    NSInteger added = 0;
    NSArray *routes = [root isKindOfClass:NSDictionary.class] ? root[@"routes"] : nil;
    if ([routes isKindOfClass:NSArray.class]) {
        for (id route in [[routes reverseObjectEnumerator] allObjects]) {
            if (![route isKindOfClass:NSDictionary.class] || ![route[@"points"] isKindOfClass:NSArray.class]) continue;
            NSMutableArray<NSValue *> *points = [NSMutableArray array];
            for (id pair in route[@"points"]) {
                if (![pair isKindOfClass:NSArray.class] || [pair count] < 2) continue;
                CLLocationCoordinate2D c = CLLocationCoordinate2DMake([pair[0] doubleValue], [pair[1] doubleValue]);
                if (CLLocationCoordinate2DIsValid(c)) [points addObject:SHBox(c)];
            }
            if (points.count) {
                [self saveRouteNamed:[route[@"name"] isKindOfClass:NSString.class] ? route[@"name"] : nil points:points];
                added++;
            }
        }
    }

    NSMutableArray *list = [[self bookmarks] mutableCopy];
    for (id item in items) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        id lat = item[@"lat"], lon = item[@"lon"];
        if (![lat respondsToSelector:@selector(doubleValue)] || ![lon respondsToSelector:@selector(doubleValue)]) continue;
        CLLocationCoordinate2D c = CLLocationCoordinate2DMake([lat doubleValue], [lon doubleValue]);
        if (!CLLocationCoordinate2DIsValid(c)) continue;
        NSString *name = [item[@"name"] isKindOfClass:NSString.class] ? item[@"name"] : @"";
        [list addObject:SHPlace(SHPlaceName(name, c), c)];
        added++;
    }
    if (added == 0) return -1;
    [self saveBookmarks:list];
    return added;
}

@end
