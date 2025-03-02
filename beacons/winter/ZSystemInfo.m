#import "ZSystemInfo.h"
#include <sys/utsname.h>

@implementation ZSystemInfo

+ (NSString *)hostname {
    char hostname[1024];
    hostname[1023] = '\0';
    
    if (gethostname(hostname, sizeof(hostname) - 1) == 0) {
        return [NSString stringWithCString:hostname encoding:NSUTF8StringEncoding];
    } else {
        return nil;
    }
}

+ (NSString *)username {
    return NSUserName();
}

+ (NSString *)osVersion {
    struct utsname systemInfo;
    if (uname(&systemInfo) == 0) {
        NSString *sysname = [NSString stringWithCString:systemInfo.sysname encoding:NSUTF8StringEncoding];
        NSString *release = [NSString stringWithCString:systemInfo.release encoding:NSUTF8StringEncoding];
        NSString *machine = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
        
        // Get more detailed OS X info
        NSOperatingSystemVersion osVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
        NSString *osxVersion = [NSString stringWithFormat:@"%ld.%ld.%ld",
                                (long)osVersion.majorVersion,
                                (long)osVersion.minorVersion,
                                (long)osVersion.patchVersion];
        
        return [NSString stringWithFormat:@"%@ %@ (%@) - %@", sysname, release, machine, osxVersion];
    } else {
        // Fallback if uname fails
        NSString *osVersion = [[NSProcessInfo processInfo] operatingSystemVersionString];
        return osVersion;
    }
}

@end 