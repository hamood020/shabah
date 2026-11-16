#import "SHPersistence.h"

NSString *const SHStateChangedNotification = @"SHStateChangedNotification";

static NSString *const kEnabled   = @"SHEnabled";
static NSString *const kLat       = @"SHLat";
static NSString *const kLon       = @"SHLon";
static NSString *const kAlt       = @"SHAltitude";
static NSString *const kFluct     = @"SHFluctuation";
static NSString *const kRadius    = @"SHFluctuationRadius";
static NSString *const kExpiry    = @"SHExpiryDate";
static NSString *const kArabic    = @"SHArabic";
static NSString *const kBookmarks = @"SHBookmarks";

static void SHPostStateChanged(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SHStateChangedNotification object:nil];
    });
}

@implementation SHPersistence {
    NSUserDefaults *_defaults;
    BOOL _isSpoofing;
    CLLocationCoordinate2D _coord;
    double _course;
    double _speed;
}

+ (instancetype)shared {
    static SHPersistence *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] initPrivate]; });
    return instance;
}

- (instancetype)initPrivate {
    if ((self = [super init])) {
        _defaults = [NSUserDefaults standardUserDefaults];
        BOOL hasCoord = [_defaults objectForKey:kLat] && [_defaults objectForKey:kLon];
        _coord = CLLocationCoordinate2DMake([_defaults doubleForKey:kLat], [_defaults doubleForKey:kLon]);
        _isSpoofing = [_defaults boolForKey:kEnabled] && hasCoord && CLLocationCoordinate2DIsValid(_coord);
        _altitude = [_defaults doubleForKey:kAlt];
        _fluctuationEnabled = [_defaults boolForKey:kFluct];
        _fluctuationRadius = [_defaults objectForKey:kRadius] ? [_defaults doubleForKey:kRadius] : 15.0;
        _expiryDate = [_defaults objectForKey:kExpiry];
        if ([_defaults objectForKey:kArabic]) {
            _arabic = [_defaults boolForKey:kArabic];
        } else {
            _arabic = [[NSLocale preferredLanguages].firstObject hasPrefix:@"ar"];
        }
        _course = -1;
        _speed = -1;
    }
    return self;
}

#pragma mark - State

- (BOOL)isSpoofing {
    @synchronized (self) {
        if (_isSpoofing && _expiryDate && _expiryDate.timeIntervalSinceNow <= 0) {
            SH_LOG(@"spoof expired, stopping");
            [self stopSpoofing];
        }
        return _isSpoofing;
    }
}

- (CLLocationCoordinate2D)coordinate {
    @synchronized (self) { return _coord; }
}

- (void)startSpoofingAt:(CLLocationCoordinate2D)coordinate {
    if (!CLLocationCoordinate2DIsValid(coordinate)) return;
    @synchronized (self) {
        _coord = coordinate;
        _course = -1;
        _speed = -1;
        _isSpoofing = YES;
    }
    [_defaults setDouble:coordinate.latitude forKey:kLat];
    [_defaults setDouble:coordinate.longitude forKey:kLon];
    [_defaults setBool:YES forKey:kEnabled];
    SHPostStateChanged();
}

- (void)moveTo:(CLLocationCoordinate2D)coordinate course:(double)course speed:(double)speed {
    if (!CLLocationCoordinate2DIsValid(coordinate)) return;
    @synchronized (self) {
        _coord = coordinate;
        _course = course;
        _speed = speed;
        _isSpoofing = YES;
    }
    [_defaults setDouble:coordinate.latitude forKey:kLat];
    [_defaults setDouble:coordinate.longitude forKey:kLon];
    [_defaults setBool:YES forKey:kEnabled];
}

- (void)stopSpoofing {
    @synchronized (self) { _isSpoofing = NO; }
    [_defaults setBool:NO forKey:kEnabled];
    SHPostStateChanged();
}

- (CLLocation *)currentSpoofedLocation {
    if (![self isSpoofing]) return nil;
    CLLocationCoordinate2D c;
    double course, speed;
    @synchronized (self) { c = _coord; course = _course; speed = _speed; }

    double accuracy = 5.0;
    if (self.fluctuationEnabled && self.fluctuationRadius > 0) {
        // Uniform random point inside a circle of the given radius.
        double r = self.fluctuationRadius * sqrt((double)arc4random() / UINT32_MAX);
        double theta = 2.0 * M_PI * ((double)arc4random() / UINT32_MAX);
        double metersPerDegLat = 111320.0;
        double metersPerDegLon = 111320.0 * cos(c.latitude * M_PI / 180.0);
        c.latitude += (r * cos(theta)) / metersPerDegLat;
        if (metersPerDegLon > 1) c.longitude += (r * sin(theta)) / metersPerDegLon;
        accuracy = MAX(5.0, self.fluctuationRadius);
    }

    return [[CLLocation alloc] initWithCoordinate:c
                                         altitude:self.altitude
                               horizontalAccuracy:accuracy
                                 verticalAccuracy:10.0
                                           course:course
                                            speed:speed
                                        timestamp:[NSDate date]];
}

#pragma mark - Settings

- (void)setAltitude:(double)altitude {
    _altitude = altitude;
    [_defaults setDouble:altitude forKey:kAlt];
}

- (void)setFluctuationEnabled:(BOOL)enabled {
    _fluctuationEnabled = enabled;
    [_defaults setBool:enabled forKey:kFluct];
}

- (void)setFluctuationRadius:(double)radius {
    _fluctuationRadius = MAX(0, radius);
    [_defaults setDouble:_fluctuationRadius forKey:kRadius];
}

- (void)setExpiryDate:(NSDate *)date {
    _expiryDate = date;
    if (date) [_defaults setObject:date forKey:kExpiry];
    else [_defaults removeObjectForKey:kExpiry];
}

- (void)setArabic:(BOOL)arabic {
    _arabic = arabic;
    [_defaults setBool:arabic forKey:kArabic];
}

#pragma mark - Bookmarks

- (NSArray<NSDictionary *> *)bookmarks {
    NSArray *stored = [_defaults arrayForKey:kBookmarks];
    return stored ?: @[];
}

- (void)addBookmarkNamed:(NSString *)name coordinate:(CLLocationCoordinate2D)coordinate {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) trimmed = [NSString stringWithFormat:@"%.5f, %.5f", coordinate.latitude, coordinate.longitude];
    NSMutableArray *list = [[self bookmarks] mutableCopy];
    [list addObject:@{ @"name": trimmed, @"lat": @(coordinate.latitude), @"lon": @(coordinate.longitude) }];
    [_defaults setObject:list forKey:kBookmarks];
}

- (void)removeBookmarkAtIndex:(NSUInteger)index {
    NSMutableArray *list = [[self bookmarks] mutableCopy];
    if (index >= list.count) return;
    [list removeObjectAtIndex:index];
    [_defaults setObject:list forKey:kBookmarks];
}

@end
