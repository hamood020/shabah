#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>
#import <math.h>

#define SH_VERSION @"1.1.0"
#define SH_REPO @"hamood020/shabah"
#define SH_LOG(fmt, ...) SHLog(fmt, ##__VA_ARGS__)

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main thread when spoofing starts/stops or a setting that affects the overlay changes.
FOUNDATION_EXPORT NSString *const SHStateChangedNotification;
/// Posted on the main thread when bookmarks or recents change.
FOUNDATION_EXPORT NSString *const SHPlacesChangedNotification;
/// Posted on the main thread on every movement-engine tick. userInfo[@"finished"] is @YES at the end of a route.
FOUNDATION_EXPORT NSString *const SHEngineUpdateNotification;

/// UI string for `key` in the current language (Arabic or English).
FOUNDATION_EXPORT NSString *SHText(NSString *key);

/// Logs to NSLog and to an in-memory buffer the user can copy from Settings.
FOUNDATION_EXPORT void SHLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
FOUNDATION_EXPORT NSString *SHLogDump(void);

#pragma mark - Geo helpers

static inline NSValue *SHBox(CLLocationCoordinate2D c) {
    return [NSValue valueWithBytes:&c objCType:@encode(CLLocationCoordinate2D)];
}

static inline CLLocationCoordinate2D SHUnbox(NSValue *v) {
    CLLocationCoordinate2D c;
    [v getValue:&c];
    return c;
}

/// Great-circle distance in meters.
static inline double SHDistance(CLLocationCoordinate2D a, CLLocationCoordinate2D b) {
    double r = 6371000.0;
    double dLat = (b.latitude - a.latitude) * M_PI / 180.0;
    double dLon = (b.longitude - a.longitude) * M_PI / 180.0;
    double la1 = a.latitude * M_PI / 180.0, la2 = b.latitude * M_PI / 180.0;
    double h = sin(dLat / 2) * sin(dLat / 2) + cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2);
    return 2 * r * asin(MIN(1.0, sqrt(h)));
}

/// Initial bearing from a to b in degrees (0 = north, clockwise).
static inline double SHBearing(CLLocationCoordinate2D a, CLLocationCoordinate2D b) {
    double la1 = a.latitude * M_PI / 180.0, la2 = b.latitude * M_PI / 180.0;
    double dLon = (b.longitude - a.longitude) * M_PI / 180.0;
    double y = sin(dLon) * cos(la2);
    double x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dLon);
    return fmod(atan2(y, x) * 180.0 / M_PI + 360.0, 360.0);
}

/// Point reached from `c` after `meters` along `bearing` degrees.
static inline CLLocationCoordinate2D SHDestination(CLLocationCoordinate2D c, double bearing, double meters) {
    double r = 6371000.0, d = meters / r, br = bearing * M_PI / 180.0;
    double la1 = c.latitude * M_PI / 180.0, lo1 = c.longitude * M_PI / 180.0;
    double la2 = asin(sin(la1) * cos(d) + cos(la1) * sin(d) * cos(br));
    double lo2 = lo1 + atan2(sin(br) * sin(d) * cos(la1), cos(d) - sin(la1) * sin(la2));
    double lon = fmod(lo2 * 180.0 / M_PI + 540.0, 360.0) - 180.0;
    return CLLocationCoordinate2DMake(la2 * 180.0 / M_PI, lon);
}

static inline double SHRandomUnit(void) {
    return (double)arc4random() / (double)UINT32_MAX;
}

NS_ASSUME_NONNULL_END
