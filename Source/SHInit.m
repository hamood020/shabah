#import "SHPrefix.h"
#import "SHPersistence.h"
#import "SHLocationHooks.h"
#import "SHOverlay.h"
#import "SHScheduler.h"

/// Runs when dyld loads the dylib, before the host app's main().
__attribute__((constructor))
static void SHInitialize(void) {
    @autoreleasepool {
        SH_LOG(@"loaded %@ into %@", SH_VERSION, NSBundle.mainBundle.bundleIdentifier);
        [SHPersistence shared];
        SHInstallLocationHooks();
        [SHOverlay install];
        [[SHScheduler shared] start];
    }
}
