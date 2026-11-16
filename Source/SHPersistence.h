#import "SHPrefix.h"

NS_ASSUME_NONNULL_BEGIN

/// Thread-safe store for the spoofing state and every user setting.
/// Values live in the host app's NSUserDefaults, so each injected app keeps its own settings.
@interface SHPersistence : NSObject

+ (instancetype)shared;

#pragma mark Live state
@property (nonatomic, readonly, getter=isSpoofing) BOOL spoofing;
@property (nonatomic, readonly) BOOL hasCoordinate;
@property (nonatomic, readonly) CLLocationCoordinate2D coordinate;  // base point, without jitter

#pragma mark Settings
@property (nonatomic) double altitude;            // meters
@property (nonatomic) BOOL jitterEnabled;
@property (nonatomic) double jitterRadius;        // meters, 5...100
@property (nonatomic) NSInteger autoStopMinutes;  // 0 = never
@property (nonatomic, readonly, nullable) NSDate *expiryDate;
@property (nonatomic) BOOL glideEnabled;          // move gradually to a new point
@property (nonatomic) BOOL arabic;
@property (nonatomic) NSInteger mapStyle;         // 0 standard, 1 satellite, 2 hybrid, 3 night
@property (nonatomic) BOOL checkUpdates;
@property (nonatomic) NSInteger transportMode;    // 0 walk, 1 bike, 2 car (also resets speedKmh)
@property (nonatomic) double speedKmh;
@property (nonatomic) BOOL loopRoute;
@property (nonatomic) BOOL realisticMotion;
@property (nonatomic) BOOL joystickEnabled;       // joystick shown over the host app

#pragma mark Spoofing
- (void)startSpoofingAt:(CLLocationCoordinate2D)coordinate;
/// Called by the movement engine on every tick (course in degrees, speed in m/s).
- (void)moveTo:(CLLocationCoordinate2D)coordinate course:(double)course speed:(double)speed;
- (void)restartExpiryTimer;
- (void)stopSpoofing;
- (void)resumeLast;
/// What the host app receives, or nil when spoofing is off.
- (nullable CLLocation *)currentSpoofedLocation;

#pragma mark Places
/// Each place is @{ name, lat, lon, date }.
- (NSArray<NSDictionary *> *)bookmarks;
- (void)addBookmarkNamed:(nullable NSString *)name coordinate:(CLLocationCoordinate2D)coordinate;
- (void)renameBookmarkAtIndex:(NSUInteger)index to:(NSString *)name;
- (void)moveBookmarkFromIndex:(NSUInteger)from toIndex:(NSUInteger)to;
- (void)removeBookmarkAtIndex:(NSUInteger)index;
- (NSArray<NSDictionary *> *)recents;
- (void)recordRecent:(CLLocationCoordinate2D)coordinate name:(nullable NSString *)name;
- (NSString *)exportPlacesJSON;
/// Returns the number of bookmarks imported, or -1 if the text is not valid.
- (NSInteger)importPlacesJSON:(NSString *)json;

@end

NS_ASSUME_NONNULL_END
