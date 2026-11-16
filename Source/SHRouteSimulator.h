#import "SHPrefix.h"

NS_ASSUME_NONNULL_BEGIN

/// Moves the spoofed location along a polyline at a constant speed.
@interface SHRouteSimulator : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic) double speedMetersPerSecond;

/// Called on the main thread after every step; `finished` is YES at the end of the route.
@property (nonatomic, copy, nullable) void (^onUpdate)(CLLocationCoordinate2D coordinate, BOOL finished);

- (void)startWithPolyline:(MKPolyline *)polyline;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
