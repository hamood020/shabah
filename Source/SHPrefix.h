#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>

#define SH_VERSION @"1.0.0-dev"
#define SH_LOG(fmt, ...) NSLog(@"[Shabah] " fmt, ##__VA_ARGS__)

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main thread whenever spoofing starts, stops or moves.
FOUNDATION_EXPORT NSString *const SHStateChangedNotification;

/// Returns the UI string for `key` in the current language (Arabic or English).
FOUNDATION_EXPORT NSString *SHText(NSString *key);

NS_ASSUME_NONNULL_END
