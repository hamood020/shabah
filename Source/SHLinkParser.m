#import "SHLinkParser.h"

@implementation SHLinkParser

+ (NSArray<NSRegularExpression *> *)patterns {
    static NSArray *patterns;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray<NSString *> *sources = @[
            // Place pin inside Google Maps data blob (most precise, check first).
            @"!3d(-?\\d{1,3}\\.\\d+)!4d(-?\\d{1,3}\\.\\d+)",
            // Map center: google.com/maps/@23.58,58.38,15z
            @"@(-?\\d{1,3}\\.\\d+),(-?\\d{1,3}\\.\\d+)",
            // Query parameters used by Google and Apple Maps.
            @"[?&](?:q|ll|sll|daddr|center|query|destination|coordinate)=(-?\\d{1,3}(?:\\.\\d+)?)\\s*,\\s*(-?\\d{1,3}(?:\\.\\d+)?)",
            // Plain "lat, lon", "lat lon" or with an Arabic comma.
            @"^\\s*(-?\\d{1,3}(?:\\.\\d+)?)\\s*[,،\\s]\\s*(-?\\d{1,3}(?:\\.\\d+)?)\\s*$",
        ];
        NSMutableArray *compiled = [NSMutableArray array];
        for (NSString *s in sources) {
            NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:s options:0 error:nil];
            if (re) [compiled addObject:re];
        }
        patterns = compiled;
    });
    return patterns;
}

+ (BOOL)coordinateFromText:(NSString *)text coordinate:(CLLocationCoordinate2D *)out {
    if (text.length == 0) return NO;
    NSString *s = [text stringByRemovingPercentEncoding] ?: text;
    s = [s stringByReplacingOccurrencesOfString:@"٫" withString:@"."];   // Arabic decimal separator
    for (NSRegularExpression *re in [self patterns]) {
        NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
        if (!m || m.numberOfRanges < 3) continue;
        double lat = [[s substringWithRange:[m rangeAtIndex:1]] doubleValue];
        double lon = [[s substringWithRange:[m rangeAtIndex:2]] doubleValue];
        CLLocationCoordinate2D c = CLLocationCoordinate2DMake(lat, lon);
        if (!CLLocationCoordinate2DIsValid(c) || (lat == 0 && lon == 0)) continue;
        if (out) *out = c;
        return YES;
    }
    return NO;
}

+ (BOOL)isShortLink:(NSString *)text {
    NSString *s = text.lowercaseString;
    return [s containsString:@"goo.gl/"] || [s containsString:@"g.co/"];
}

+ (nullable NSURL *)firstURLInText:(NSString *)text {
    NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
    NSTextCheckingResult *m = [detector firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    return m.URL;
}

+ (nullable NSString *)queryFromURL:(NSURL *)url {
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in components.queryItems) {
        if (([item.name isEqualToString:@"q"] || [item.name isEqualToString:@"query"]) && item.value.length) return item.value;
    }
    NSArray<NSString *> *parts = url.pathComponents;
    NSUInteger i = [parts indexOfObject:@"place"];
    if (i != NSNotFound && i + 1 < parts.count) {
        return [[parts[i + 1] stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding];
    }
    return nil;
}

+ (void)resolveShortLink:(NSString *)text
              completion:(void (^)(BOOL, CLLocationCoordinate2D, NSString *))completion {
    NSURL *url = [self firstURLInText:text];
    if (!url) {
        completion(NO, kCLLocationCoordinate2DInvalid, nil);
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 10;
    [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)" forHTTPHeaderField:@"User-Agent"];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        CLLocationCoordinate2D c = kCLLocationCoordinate2DInvalid;
        BOOL found = NO;
        NSString *query = nil;
        NSURL *finalURL = response.URL;
        if (finalURL) {
            found = [self coordinateFromText:finalURL.absoluteString coordinate:&c];
            if (!found) query = [self queryFromURL:finalURL];
        }
        if (!found && data.length && data.length < 2 * 1024 * 1024) {
            NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            // Only trust the precise pin pattern inside page bodies.
            NSRegularExpression *pin = [self patterns].firstObject;
            NSTextCheckingResult *m = body ? [pin firstMatchInString:body options:0 range:NSMakeRange(0, body.length)] : nil;
            if (m) found = [self coordinateFromText:[body substringWithRange:m.range] coordinate:&c];
        }
        SH_LOG(@"short link resolved: found=%d final=%@", found, finalURL.host ?: @"-");
        dispatch_async(dispatch_get_main_queue(), ^{ completion(found, c, query); });
    }] resume];
}

@end
