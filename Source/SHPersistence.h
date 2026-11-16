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

#pragma mark Overlay and appearance (1.1)
@property (nonatomic) NSInteger themeIndex;       // accent color, see SHTheme
@property (nonatomic) double buttonSize;          // floating button diameter, 44...76
@property (nonatomic) double buttonOpacity;       // 0.35...1
@property (nonatomic) BOOL statusPillEnabled;     // small status label over the app
@property (nonatomic) BOOL volumeGestureEnabled;  // 3 quick volume presses show the hidden button
@property (nonatomic) BOOL showRealLocation;      // grey pin for the real GPS position on the map
@property (nonatomic) BOOL expiryNotifications;   // local notification before / at auto stop

#pragma mark Weekly schedule (1.1)
@property (nonatomic) BOOL scheduleEnabled;
@property (nonatomic, copy) NSArray<NSNumber *> *scheduleDays;   // NSCalendar weekdays, 1 = Sunday
@property (nonatomic) NSInteger scheduleStartMinutes;             // minutes after midnight
@property (nonatomic) NSInteger scheduleEndMinutes;
@property (nonatomic, copy, nullable) NSDictionary *scheduleLocation;   // @{ name, lat, lon }

#pragma mark Real GPS (in memory only)
@property (atomic, strong, nullable) CLLocation *lastRealLocation;

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
/// Each route is @{ name, points: @[ @[lat, lon], ... ], date }.
- (NSArray<NSDictionary *> *)savedRoutes;
- (void)saveRouteNamed:(nullable NSString *)name points:(NSArray<NSValue *> *)points;
- (void)removeRouteAtIndex:(NSUInteger)index;
- (NSString *)exportPlacesJSON;
/// Returns the number of bookmarks imported, or -1 if the text is not valid.
- (NSInteger)importPlacesJSON:(NSString *)json;

@end

NS_ASSUME_NONNULL_END
