#import "ZWhoAmICommandHandler.h"
#import "ZSystemInfo.h"

@implementation ZWhoAmICommandHandler

- (instancetype)init {
    return [super initWithType:@"whoami"];
}

- (void)executeCommand:(ZCommandModel *)command 
           completion:(void (^)(BOOL success, NSDictionary *result, NSError *error))completion {
    NSLog(@"Executing whoami command: %@", [command commandId]);
    
    // Create a result dictionary with user information
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [result setObject:@"whoami_response" forKey:@"type"];
    
    // Get system information
    NSString *username = [ZSystemInfo username];
    NSString *hostname = [ZSystemInfo hostname];
    NSString *osVersion = [ZSystemInfo osVersion];
    
    // Add user information to result
    if (username) {
        [result setObject:username forKey:@"username"];
    } else {
        [result setObject:@"unknown" forKey:@"username"];
    }
    
    if (hostname) {
        [result setObject:hostname forKey:@"hostname"];
    }
    
    if (osVersion) {
        [result setObject:osVersion forKey:@"os_version"];
    }
    
    // Add additional information if available
    NSDictionary *processInfo = [[NSProcessInfo processInfo] environment];
    NSString *home = [processInfo objectForKey:@"HOME"];
    NSString *shell = [processInfo objectForKey:@"SHELL"];
    
    if (home) {
        [result setObject:home forKey:@"home"];
    }
    
    if (shell) {
        [result setObject:shell forKey:@"shell"];
    }
    
    // Add process information
    [result setObject:[NSNumber numberWithInt:[[NSProcessInfo processInfo] processIdentifier]] forKey:@"pid"];
    
    // Add timestamp
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
    [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    [result setObject:timestamp forKey:@"timestamp"];
    
    // Complete with success
    if (completion) {
        completion(YES, result, nil);
    }
}

- (BOOL)supportsMultipleCommands {
    // WhoAmI commands can run multiple instances simultaneously
    return YES;
}

@end 