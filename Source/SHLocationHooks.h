#import "SHPrefix.h"

/// Swizzles CoreLocation / MapKit so the host app receives the spoofed location.
/// Safe to call more than once.
FOUNDATION_EXPORT void SHInstallLocationHooks(void);
