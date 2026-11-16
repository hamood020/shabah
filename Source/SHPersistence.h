#import "SHPrefix.h"

NS_ASSUME_NONNULL_BEGIN

/// Thread-safe store for the spoofing state. Settings persist in NSUserDefaults
/// of the host app, so the spoof survives app restarts.
@interface SHPersistence : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly, getter=isSpoofing) BOOL spoofing;
@property (nonatomic, readonly) CLLocationCoordinate2D coordinate;

@property (nonatomic) double altitude;              // meters
@property (nonatomic) BOOL fluctuationEnabled;      // random jitter around the point
@property (nonatomic) double fluctuationRadius;     // meters
@property (nonatomic, strong, nullable) NSDate *expiryDate; // auto-stop time
@property (nonatomic) BOOL arabic;                  // UI language

- (void)startSpoofingAt:(CLLocationCoordinate2D)coordinate;
/// Used by the route simulator on every tick (course in degrees, speed in m/s).
- (void)moveTo:(CLLocationCoordinate2D)coordinate course:(double)course speed:(double)speed;
- (void)stopSpoofing;

/// The location to hand to the app, or nil when spoofing is off.
- (nullable CLLocation *)currentSpoofedLocation;

/// Each bookmark is @{ @"name": NSString, @"lat": NSNumber, @"lon": NSNumber }.
- (NSArray<NSDictionary *> *)bookmarks;
- (void)addBookmarkNamed:(NSString *)name coordinate:(CLLocationCoordinate2D)coordinate;
- (void)removeBookmarkAtIndex:(NSUInteger)index;

@end

NS_ASSUME_NONNULL_END
