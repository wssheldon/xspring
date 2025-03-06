#import "ZEchoCommandHandler.h"

@implementation ZEchoCommandHandler

- (instancetype)init {
    return [super initWithType:@"echo"];
}

- (NSString *)command {
    return @"echo";
}

- (void)executeCommand:(ZCommandModel *)command 
           completion:(void (^)(BOOL success, NSDictionary *result, NSError *error))completion {
    NSLog(@"Executing echo command: %@", [command commandId]);
    
    // Get the payload from the command
    NSDictionary *payload = [command payload];
    
    // Create a result dictionary that includes the original payload
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [result setObject:@"echo_response" forKey:@"type"];
    
    if (payload) {
        [result setObject:payload forKey:@"original_payload"];
    }
    
    // Add a timestamp
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
    [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    [result setObject:timestamp forKey:@"timestamp"];
    
    // Always succeed for echo commands
    if (completion) {
        completion(YES, result, nil);
    }
}

- (BOOL)supportsMultipleCommands {
    // Echo commands can run multiple instances simultaneously
    return YES;
}

@end 