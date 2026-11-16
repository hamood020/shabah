#import "SHUpdateChecker.h"
#import "SHPersistence.h"

static NSString *const kLastCheck = @"SHLastUpdateCheck";

@implementation SHUpdateChecker

+ (void)checkForce:(BOOL)force completion:(void (^)(NSString *, NSURL *, BOOL))completion {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (!force) {
        if (![SHPersistence shared].checkUpdates) return;
        NSDate *last = [d objectForKey:kLastCheck];
        if (last && -last.timeIntervalSinceNow < 24 * 3600) return;
    }
    [d setObject:[NSDate date] forKey:kLastCheck];

    NSURL *api = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.github.com/repos/%@/releases/latest", SH_REPO]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:api];
    request.timeoutInterval = 10;
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"Shabah" forHTTPHeaderField:@"User-Agent"];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *newer = nil;
        NSURL *page = nil;
        BOOL failed = YES;
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([json isKindOfClass:NSDictionary.class] && [json[@"tag_name"] isKindOfClass:NSString.class]) {
            failed = NO;
            NSString *tag = json[@"tag_name"];
            NSString *latest = [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag;
            if ([latest compare:SH_VERSION options:NSNumericSearch] == NSOrderedDescending) {
                newer = latest;
                if ([json[@"html_url"] isKindOfClass:NSString.class]) page = [NSURL URLWithString:json[@"html_url"]];
            }
        } else if ([response isKindOfClass:NSHTTPURLResponse.class] && ((NSHTTPURLResponse *)response).statusCode == 404) {
            failed = NO;   // no releases published yet
        }
        SH_LOG(@"update check: latest newer=%@ failed=%d", newer ?: @"none", failed);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(newer, page, failed); });
    }] resume];
}

@end
