#import "SHRouteSimulator.h"
#import "SHPersistence.h"

static const NSTimeInterval kTickInterval = 1.0;

static double SHBearing(CLLocationCoordinate2D from, CLLocationCoordinate2D to) {
    double lat1 = from.latitude * M_PI / 180.0, lat2 = to.latitude * M_PI / 180.0;
    double dLon = (to.longitude - from.longitude) * M_PI / 180.0;
    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    double deg = atan2(y, x) * 180.0 / M_PI;
    return fmod(deg + 360.0, 360.0);
}

@implementation SHRouteSimulator {
    NSArray<NSValue *> *_points;        // boxed CLLocationCoordinate2D
    NSArray<NSNumber *> *_cumulative;   // distance from the start to each point, meters
    double _covered;
    NSTimer *_timer;
}

+ (instancetype)shared {
    static SHRouteSimulator *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _speedMetersPerSecond = 5.0 / 3.6;
    }
    return self;
}

- (BOOL)isRunning {
    return _timer != nil;
}

- (void)startWithPolyline:(MKPolyline *)polyline {
    [self stop];
    NSUInteger count = polyline.pointCount;
    if (count < 2) return;

    CLLocationCoordinate2D *coords = malloc(sizeof(CLLocationCoordinate2D) * count);
    [polyline getCoordinates:coords range:NSMakeRange(0, count)];

    NSMutableArray<NSValue *> *points = [NSMutableArray arrayWithCapacity:count];
    NSMutableArray<NSNumber *> *cumulative = [NSMutableArray arrayWithCapacity:count];
    double total = 0;
    for (NSUInteger i = 0; i < count; i++) {
        if (i > 0) {
            CLLocation *a = [[CLLocation alloc] initWithLatitude:coords[i - 1].latitude longitude:coords[i - 1].longitude];
            CLLocation *b = [[CLLocation alloc] initWithLatitude:coords[i].latitude longitude:coords[i].longitude];
            total += [b distanceFromLocation:a];
        }
        [points addObject:[NSValue valueWithBytes:&coords[i] objCType:@encode(CLLocationCoordinate2D)]];
        [cumulative addObject:@(total)];
    }
    free(coords);

    _points = points;
    _cumulative = cumulative;
    _covered = 0;

    [[SHPersistence shared] startSpoofingAt:[self coordinateAt:0]];
    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:kTickInterval repeats:YES block:^(NSTimer *t) {
        [weakSelf tick];
    }];
    SH_LOG(@"route started: %lu points, %.0f m", (unsigned long)count, total);
}

- (void)stop {
    [_timer invalidate];
    _timer = nil;
}

- (CLLocationCoordinate2D)coordinateAt:(NSUInteger)index {
    CLLocationCoordinate2D c;
    [_points[index] getValue:&c];
    return c;
}

- (void)tick {
    double total = _cumulative.lastObject.doubleValue;
    _covered = MIN(total, _covered + self.speedMetersPerSecond * kTickInterval);

    // Find the segment that contains the covered distance.
    NSUInteger seg = 0;
    while (seg + 1 < _cumulative.count - 1 && _cumulative[seg + 1].doubleValue < _covered) seg++;

    CLLocationCoordinate2D a = [self coordinateAt:seg];
    CLLocationCoordinate2D b = [self coordinateAt:seg + 1];
    double segStart = _cumulative[seg].doubleValue;
    double segLength = _cumulative[seg + 1].doubleValue - segStart;
    double f = segLength > 0 ? (_covered - segStart) / segLength : 1.0;
    f = MAX(0, MIN(1, f));

    CLLocationCoordinate2D current = CLLocationCoordinate2DMake(a.latitude + (b.latitude - a.latitude) * f,
                                                                a.longitude + (b.longitude - a.longitude) * f);
    BOOL finished = _covered >= total;
    [[SHPersistence shared] moveTo:current course:SHBearing(a, b) speed:finished ? 0 : self.speedMetersPerSecond];

    if (finished) {
        [self stop];
        SH_LOG(@"route finished");
    }
    if (self.onUpdate) self.onUpdate(current, finished);
}

@end
