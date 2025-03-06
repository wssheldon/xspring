#import "ZAppleScriptCommandHandler.h"

@implementation ZAppleScriptCommandHandler

- (instancetype)init {
    return [super initWithType:@"applescript"];
}

- (NSString *)command {
    return @"applescript";
}

- (void)executeCommand:(ZCommandModel *)command 
           completion:(void (^)(BOOL success, NSDictionary *result, NSError *error))completion {
    NSLog(@"Executing applescript command: %@", [command commandId]);
    
    // Get the payload from the command
    NSDictionary *payload = [command payload];
    
    // Extract script from payload
    NSString *script = [payload objectForKey:@"script"];
    if (!script) {
        NSError *error = [NSError errorWithDomain:@"ZAppleScriptCommandHandler" 
                                           code:400 
                                       userInfo:@{NSLocalizedDescriptionKey: 
                                                 @"No script provided in payload"}];
        if (completion) {
            completion(NO, nil, error);
        }
        return;
    }
    
    // Remove any surrounding quotes if present
    if ([script hasPrefix:@"\""] && [script hasSuffix:@"\""]) {
        script = [script substringWithRange:NSMakeRange(1, [script length] - 2)];
    }
    
    // Replace escaped quotes with regular quotes
    script = [script stringByReplacingOccurrencesOfString:@"\\\"" withString:@"\""];
    
    NSLog(@"Executing AppleScript: %@", script);
    
    // Create and compile the AppleScript
    NSDictionary *errorInfo = nil;
    NSAppleScript *appleScript = [[[NSAppleScript alloc] initWithSource:script] autorelease];
    
    if (!appleScript) {
        NSError *error = [NSError errorWithDomain:@"ZAppleScriptCommandHandler" 
                                           code:500 
                                       userInfo:@{NSLocalizedDescriptionKey: 
                                                 @"Failed to create AppleScript instance"}];
        if (completion) {
            completion(NO, nil, error);
        }
        return;
    }
    
    // Execute the script
    NSAppleEventDescriptor *result = [appleScript executeAndReturnError:&errorInfo];
    
    // Create result dictionary
    NSMutableDictionary *response = [NSMutableDictionary dictionary];
    [response setObject:@"applescript_response" forKey:@"type"];
    
    if (errorInfo) {
        // Script execution failed
        [response setObject:@NO forKey:@"success"];
        [response setObject:[errorInfo objectForKey:NSAppleScriptErrorMessage] ?: @"Unknown error" 
                   forKey:@"error"];
        [response setObject:[errorInfo objectForKey:NSAppleScriptErrorNumber] ?: @(-1) 
                   forKey:@"errorCode"];
        [response setObject:[errorInfo objectForKey:NSAppleScriptErrorBriefMessage] ?: @"" 
                   forKey:@"briefError"];
        
        // Add error range if available
        NSRange errorRange;
        errorRange.location = [[errorInfo objectForKey:NSAppleScriptErrorRange] rangeValue].location;
        errorRange.length = [[errorInfo objectForKey:NSAppleScriptErrorRange] rangeValue].length;
        if (errorRange.location != 0 || errorRange.length != 0) {
            [response setObject:@{
                @"location": [NSNumber numberWithUnsignedInteger:errorRange.location],
                @"length": [NSNumber numberWithUnsignedInteger:errorRange.length]
            } forKey:@"errorRange"];
        }
        
        if (completion) {
            completion(NO, response, nil);
        }
        return;
    }
    
    // Script executed successfully
    [response setObject:@YES forKey:@"success"];
    
    // Process the result if we have one
    if (result) {
        // Add the result type
        [response setObject:[NSNumber numberWithInteger:[result descriptorType]] 
                   forKey:@"resultType"];
        
        // If it's a list, process all items
        if ([result descriptorType] == typeAEList) {
            NSMutableArray *items = [NSMutableArray array];
            NSInteger count = [result numberOfItems];
            
            for (NSInteger i = 1; i <= count; i++) {
                NSAppleEventDescriptor *item = [result descriptorAtIndex:i];
                if (item) {
                    NSString *itemString = [item stringValue];
                    if (itemString) {
                        [items addObject:itemString];
                    }
                }
            }
            
            if ([items count] > 0) {
                [response setObject:items forKey:@"items"];
            }
            [response setObject:[items componentsJoinedByString:@", "] forKey:@"output"];
        } else {
            // For non-list results, just get the string value
            NSString *stringResult = [result stringValue];
            if (stringResult) {
                [response setObject:stringResult forKey:@"output"];
            }
        }
    }
    
    // Complete with success
    if (completion) {
        completion(YES, response, nil);
    }
}

- (BOOL)supportsMultipleCommands {
    // AppleScript commands can run multiple instances simultaneously
    return YES;
}

@end 