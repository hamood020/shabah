#import "SHMovementEngine.h"
#import "SHPersistence.h"
#import <QuartzCore/QuartzCore.h>

NSString *const SHEngineUpdateNotification = @"SHEngineUpdateNotification";

static const NSTimeInterval kTick = 0.25;
static const double kJoystickDeadZone = 0.08;

@implementation SHMovementEngine {
    NSTimer *_timer;

    // Route
    NSArray<NSValue *> *_points;
    NSArray<NSNumber *> *_cumulative;
    double _covered;
    double _speedFactor;
    CFTimeInterval _stopUntil;
    double _lastCourse;

    // Joystick
    CGVector _joystick;

    // Glide
    CLLocationCoordinate2D _glideFrom, _glideTo;
    double _glideDuration, _glideElapsed;
}

+ (instancetype)shared {
    static SHMovementEngine *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _speedFactor = 1.0;
        _lastCourse = -1;
    }
    return self;
}

#pragma mark - Timer

- (void)ensureTimer {
    if (_timer) return;
    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer timerWithTimeInterval:kTick repeats:YES block:^(NSTimer *t) { [weakSelf tick]; }];
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)stopTimer {
    [_timer invalidate];
    _timer = nil;
}

- (void)post:(BOOL)finished {
    [[NSNotificationCenter defaultCenter] postNotificationName:SHEngineUpdateNotification
                                                        object:self
                                                      userInfo:@{ @"finished": @(finished) }];
}

- (double)speedMps {
    return [SHPersistence shared].speedKmh / 3.6;
}

- (void)tick {
    switch (_mode) {
        case SHEngineModeRoute:    if (!_paused) [self tickRoute]; break;
        case SHEngineModeJoystick: [self tickJoystick]; break;
        case SHEngineModeGlide:    [self tickGlide]; break;
        case SHEngineModeIdle:     [self stopTimer]; return;
    }
    if (_mode != SHEngineModeIdle) [self post:NO];
}

#pragma mark - Route

- (void)loadPoints:(NSArray<NSValue *> *)points {
    NSMutableArray<NSNumber *> *cumulative = [NSMutableArray arrayWithCapacity:points.count];
    double total = 0;
    for (NSUInteger i = 0; i < points.count; i++) {
        if (i > 0) total += SHDistance(SHUnbox(points[i - 1]), SHUnbox(points[i]));
        [cumulative addObject:@(total)];
    }
    _points = points;
    _cumulative = cumulative;
    _covered = 0;
}

- (double)totalLength {
    return _cumulative.lastObject.doubleValue;
}

- (void)startRouteWithCoordinates:(NSArray<NSValue *> *)coordinates {
    // Drop consecutive duplicates so every segment has a length.
    NSMutableArray<NSValue *> *clean = [NSMutableArray array];
    for (NSValue *v in coordinates) {
        if (clean.count && SHDistance(SHUnbox(clean.lastObject), SHUnbox(v)) < 0.5) continue;
        [clean addObject:v];
    }
    if (clean.count < 2) return;

    [self stop];
    [self loadPoints:clean];
    _mode = SHEngineModeRoute;
    _paused = NO;
    _speedFactor = 1.0;
    _stopUntil = 0;
    [[SHPersistence shared] startSpoofingAt:SHUnbox(clean.firstObject)];
    [self ensureTimer];
    SH_LOG(@"route started: %lu points, %.0f m", (unsigned long)clean.count, [self totalLength]);
    [self post:NO];
}

- (void)tickRoute {
    SHPersistence *store = [SHPersistence shared];
    CFTimeInterval now = CACurrentMediaTime();
    double total = [self totalLength];

    // Find the current segment.
    NSUInteger seg = 0, last = _cumulative.count - 1;
    while (seg + 1 < last && _cumulative[seg + 1].doubleValue < _covered) seg++;

    if (now < _stopUntil) {   // short realistic stop (traffic light, etc.)
        [store moveTo:store.coordinate course:_lastCourse speed:0];
        return;
    }

    double factor = 1.0;
    if (store.realisticMotion) {
        _speedFactor += (SHRandomUnit() - 0.5) * 0.06;
        _speedFactor = MAX(0.85, MIN(1.15, _speedFactor));
        factor = _speedFactor;

        // Slow down before sharp turns.
        if (seg + 2 <= last) {
            double toVertex = _cumulative[seg + 1].doubleValue - _covered;
            double inBearing = SHBearing(SHUnbox(_points[seg]), SHUnbox(_points[seg + 1]));
            double outBearing = SHBearing(SHUnbox(_points[seg + 1]), SHUnbox(_points[seg + 2]));
            double turn = fabs(fmod(outBearing - inBearing + 540.0, 360.0) - 180.0);
            if (toVertex < 25 && turn > 45) factor *= 0.5;
        }
        // Occasional short stop (~ every 1-2 minutes on average).
        if (arc4random_uniform(1000) < 3) _stopUntil = now + 3 + arc4random_uniform(6);
    }

    double speed = [self speedMps] * factor;
    _covered = MIN(total, _covered + speed * kTick);
    while (seg + 1 < last && _cumulative[seg + 1].doubleValue < _covered) seg++;

    CLLocationCoordinate2D a = SHUnbox(_points[seg]);
    CLLocationCoordinate2D b = SHUnbox(_points[seg + 1]);
    double segStart = _cumulative[seg].doubleValue;
    double segLength = _cumulative[seg + 1].doubleValue - segStart;
    double f = segLength > 0 ? MAX(0, MIN(1, (_covered - segStart) / segLength)) : 1.0;
    CLLocationCoordinate2D current = CLLocationCoordinate2DMake(a.latitude + (b.latitude - a.latitude) * f,
                                                                a.longitude + (b.longitude - a.longitude) * f);
    _lastCourse = SHBearing(a, b);
    [store moveTo:current course:_lastCourse speed:speed];

    if (_covered >= total) {
        if (store.loopRoute) {
            [self loadPoints:[[_points reverseObjectEnumerator] allObjects]];
            SH_LOG(@"route loop: reversing");
        } else {
            [store moveTo:current course:_lastCourse speed:0];
            _mode = SHEngineModeIdle;
            [self stopTimer];
            SH_LOG(@"route finished");
            [self post:YES];
        }
    }
}

- (double)progress {
    if (_mode != SHEngineModeRoute) return 0;
    double total = [self totalLength];
    return total > 0 ? _covered / total : 0;
}

- (double)remainingMeters {
    if (_mode != SHEngineModeRoute) return 0;
    return MAX(0, [self totalLength] - _covered);
}

- (void)pause {
    if (_mode != SHEngineModeRoute) return;
    _paused = YES;
    SHPersistence *store = [SHPersistence shared];
    [store moveTo:store.coordinate course:_lastCourse speed:0];
    [self post:NO];
}

- (void)resume {
    if (_mode != SHEngineModeRoute) return;
    _paused = NO;
    [self ensureTimer];
    [self post:NO];
}

- (void)stop {
    BOOL wasActive = _mode != SHEngineModeIdle;
    _mode = SHEngineModeIdle;
    _paused = NO;
    _joystick = CGVectorMake(0, 0);
    [self stopTimer];
    if (wasActive) {
        SHPersistence *store = [SHPersistence shared];
        if (store.isSpoofing) [store moveTo:store.coordinate course:_lastCourse speed:0];
        [self post:NO];
    }
}

#pragma mark - Joystick

- (void)setJoystickVector:(CGVector)vector {
    _joystick = vector;
    double magnitude = hypot(vector.dx, vector.dy);
    SHPersistence *store = [SHPersistence shared];

    if (magnitude < kJoystickDeadZone) {
        if (_mode == SHEngineModeJoystick) {
            [store moveTo:store.coordinate course:_lastCourse speed:0];
            _mode = SHEngineModeIdle;
            [self stopTimer];
            [self post:NO];
        }
        return;
    }

    if (_mode != SHEngineModeJoystick) {
        if (!store.hasCoordinate) return;
        if (_mode != SHEngineModeIdle) [self stop];
        if (!store.isSpoofing) [store startSpoofingAt:store.coordinate];
        _mode = SHEngineModeJoystick;
        [self ensureTimer];
    }
}

- (void)tickJoystick {
    SHPersistence *store = [SHPersistence shared];
    double magnitude = MIN(1.0, hypot(_joystick.dx, _joystick.dy));
    if (magnitude < kJoystickDeadZone) return;
    double bearing = fmod(atan2(_joystick.dx, -_joystick.dy) * 180.0 / M_PI + 360.0, 360.0);
    double speed = [self speedMps] * magnitude;
    CLLocationCoordinate2D next = SHDestination(store.coordinate, bearing, speed * kTick);
    _lastCourse = bearing;
    [store moveTo:next course:bearing speed:speed];
}

#pragma mark - Glide

- (void)glideTo:(CLLocationCoordinate2D)target {
    SHPersistence *store = [SHPersistence shared];
    if (!store.isSpoofing || !store.hasCoordinate) {
        [self stop];
        [store startSpoofingAt:target];
        return;
    }
    [self stop];
    _glideFrom = store.coordinate;
    _glideTo = target;
    double distance = SHDistance(_glideFrom, _glideTo);
    _glideDuration = MAX(3.0, MIN(60.0, distance / MAX(1.0, [self speedMps])));
    _glideElapsed = 0;
    _lastCourse = SHBearing(_glideFrom, _glideTo);
    _mode = SHEngineModeGlide;
    [store restartExpiryTimer];
    [self ensureTimer];
    SH_LOG(@"glide %.0f m over %.0f s", distance, _glideDuration);
}

- (void)tickGlide {
    SHPersistence *store = [SHPersistence shared];
    _glideElapsed += kTick;
    double f = MIN(1.0, _glideElapsed / _glideDuration);
    double eased = f < 0.5 ? 2 * f * f : 1 - pow(-2 * f + 2, 2) / 2;   // ease in-out
    CLLocationCoordinate2D c = CLLocationCoordinate2DMake(_glideFrom.latitude + (_glideTo.latitude - _glideFrom.latitude) * eased,
                                                          _glideFrom.longitude + (_glideTo.longitude - _glideFrom.longitude) * eased);
    double speed = f < 1.0 ? SHDistance(_glideFrom, _glideTo) / _glideDuration : 0;
    [store moveTo:c course:_lastCourse speed:speed];
    if (f >= 1.0) {
        _mode = SHEngineModeIdle;
        [self stopTimer];
        [self post:NO];
    }
}

@end
