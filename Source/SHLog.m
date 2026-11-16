#import "SHPrefix.h"

static NSMutableArray<NSString *> *gLines;
static dispatch_queue_t gLogQueue;

static void SHLogSetup(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gLines = [NSMutableArray array];
        gLogQueue = dispatch_queue_create("shabah.log", DISPATCH_QUEUE_SERIAL);
    });
}

void SHLog(NSString *format, ...) {
    SHLogSetup();
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[Shabah] %@", message);

    NSDate *now = [NSDate date];
    dispatch_async(gLogQueue, ^{
        static NSDateFormatter *formatter;
        if (!formatter) {
            formatter = [NSDateFormatter new];
            formatter.dateFormat = @"HH:mm:ss";
            formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        }
        [gLines addObject:[NSString stringWithFormat:@"%@ %@", [formatter stringFromDate:now], message]];
        if (gLines.count > 400) [gLines removeObjectsInRange:NSMakeRange(0, 100)];
    });
}

NSString *SHLogDump(void) {
    SHLogSetup();
    __block NSString *body;
    dispatch_sync(gLogQueue, ^{ body = [gLines componentsJoinedByString:@"\n"]; });
    NSString *header = [NSString stringWithFormat:@"Shabah %@\nApp: %@\niOS: %@\n----\n",
                        SH_VERSION,
                        NSBundle.mainBundle.bundleIdentifier ?: @"?",
                        UIDevice.currentDevice.systemVersion];
    return [header stringByAppendingString:body ?: @""];
}
