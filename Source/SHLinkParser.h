#import "SHPrefix.h"

NS_ASSUME_NONNULL_BEGIN

/// Reads coordinates from typed text and from Google / Apple Maps links.
@interface SHLinkParser : NSObject

/// "23.58, 58.38", "23.58 58.38", google.com/maps/@23.58,58.38,15z, ...!3d23.58!4d58.38, ?q=23.58,58.38, maps.apple.com/?ll=...
+ (BOOL)coordinateFromText:(NSString *)text coordinate:(CLLocationCoordinate2D *)coordinate;

/// maps.app.goo.gl/..., goo.gl/maps/..., g.co/kgs/...
+ (BOOL)isShortLink:(NSString *)text;

/// Follows the short link's redirects. On success `found` is YES; otherwise `query`
/// may hold a place name taken from the final URL, to use as a search.
+ (void)resolveShortLink:(NSString *)text
              completion:(void (^)(BOOL found, CLLocationCoordinate2D coordinate, NSString *_Nullable query))completion;

@end

NS_ASSUME_NONNULL_END
