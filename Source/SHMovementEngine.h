#import "SHPrefix.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SHEngineMode) {
    SHEngineModeIdle,
    SHEngineModeRoute,     // following a multi-stop route
    SHEngineModeJoystick,  // driven by the on-screen joystick
    SHEngineModeGlide,     // gradual move to a newly chosen point
};

/// Moves the spoofed location over time. Speed comes from SHPersistence.speedKmh,
/// so changing it applies immediately, even in the middle of a route.
@interface SHMovementEngine : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) SHEngineMode mode;
@property (nonatomic, readonly, getter=isPaused) BOOL paused;
@property (nonatomic, readonly) double progress;          // 0...1 along the route
@property (nonatomic, readonly) double remainingMeters;

/// `coordinates` is a dense polyline (boxed CLLocationCoordinate2D) starting at the current point.
- (void)startRouteWithCoordinates:(NSArray<NSValue *> *)coordinates;
- (void)glideTo:(CLLocationCoordinate2D)target;
- (void)pause;
- (void)resume;
- (void)stop;

/// dx/dy in -1...1, screen orientation (dy < 0 means north).
- (void)setJoystickVector:(CGVector)vector;

@end

NS_ASSUME_NONNULL_END
