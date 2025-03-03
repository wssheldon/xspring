#import "ZTCCCheckCommandHandler.h"
#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreServices/CoreServices.h>

@implementation ZTCCCheckCommandHandler

- (instancetype)init {
    self = [super initWithType:@"tcccheck"];
    return self;
}

- (void)executeCommand:(ZCommandModel *)command completion:(void (^)(BOOL, NSDictionary *, NSError *))completion {
    NSString *username = nil;
    
    // Extract username from payload if provided
    if (command.payload && [command.payload isKindOfClass:[NSDictionary class]]) {
        username = command.payload[@"username"];
    }
    
    // Check TCC permissions
    NSString *results = [self checkTCCPermissions:username];
    
    // Return the results
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [result setObject:@"tcccheck_response" forKey:@"type"];
    [result setObject:@"success" forKey:@"status"];
    [result setObject:results forKey:@"results"];
    
    completion(YES, result, nil);
}

- (NSString *)checkTCCPermissions:(NSString *)suppliedUsername {
    bool fullDiskAccess = NO;
    bool desktopAccess = NO;
    bool documentsAccess = NO;
    bool downloadsAccess = NO;
    NSString *userTCCPath;
    NSString *username;
    NSString *fdaQueryString = @"kMDItemDisplayName = *TCC.db";
    NSMutableString *output = [NSMutableString stringWithString:@""];
    
    // Get execution context information
    [output appendString:@"Execution Context:\n"];
    NSDictionary *env = [NSProcessInfo processInfo].environment;
    NSString *bundleID = env[@"__CFBundleIdentifier"];
    [output appendFormat:@"__CFBundleIdentifier: %@\n", bundleID ? bundleID : @"(not set)"];
    NSString *xpcService = env[@"XPC_SERVICE_NAME"];
    [output appendFormat:@"XPC_SERVICE_NAME: %@\n", xpcService ? xpcService : @"(not set)"];
    NSString *packagePath = env[@"PACKAGE_PATH"];
    [output appendFormat:@"PACKAGE_PATH: %@\n", packagePath ? packagePath : @"(not set)"];
    
    [output appendString:@"\n\nTCC Accesses:\n"];
    
    // Determine which user to check
    if (suppliedUsername && ![suppliedUsername isEqualToString:@""]) {
        username = suppliedUsername;
    } else {
        username = NSUserName();
    }
    
    if ([username isEqualToString:@"root"]) {
        return [output stringByAppendingString:@"Currently the root user - must supply a username to check"];
    } else {
        userTCCPath = [NSString stringWithFormat:@"/Users/%@/Library/Application Support/com.apple.TCC/TCC.db", username];
    }
    
    // Check for full disk access
    MDQueryRef query = MDQueryCreate(kCFAllocatorDefault, (__bridge CFStringRef)fdaQueryString, NULL, NULL);
    if (query == NULL) {
        [output appendString:@"Full Disk Access: unknown - failed to query\n"];
    } else {
        MDQueryExecute(query, kMDQuerySynchronous);
        for (int i = 0; i < MDQueryGetResultCount(query); i++) {
            MDItemRef item = (MDItemRef)MDQueryGetResultAtIndex(query, i);
            NSString *path = CFBridgingRelease(MDItemCopyAttribute(item, kMDItemPath));
            if ([path hasSuffix:userTCCPath]) {
                fullDiskAccess = YES;
            }
        }
        
        [output appendFormat:@"Full Disk Access: %@\n", fullDiskAccess ? @"true" : @"false"];
        CFRelease(query);
    }
    
    // Check for folder access (Desktop, Documents, Downloads)
    NSString *queryFolderString = [NSString stringWithFormat:@"kMDItemKind = Folder -onlyin /Users/%@", username];
    query = MDQueryCreate(kCFAllocatorDefault, (__bridge CFStringRef)queryFolderString, NULL, NULL);
    if (query == NULL) {
        [output appendString:@"Desktop Access: unknown - failed to query\n"];
        [output appendString:@"Documents Access: unknown - failed to query\n"];
        [output appendString:@"Downloads Access: unknown - failed to query\n"];
    } else {
        MDQueryExecute(query, kMDQuerySynchronous);
        for (int i = 0; i < MDQueryGetResultCount(query); i++) {
            MDItemRef item = (MDItemRef)MDQueryGetResultAtIndex(query, i);
            NSString *path = CFBridgingRelease(MDItemCopyAttribute(item, kMDItemPath));
            
            if ([path isEqualToString:[NSString stringWithFormat:@"/Users/%@/Desktop", username]]) {
                desktopAccess = YES;
            }
            if ([path isEqualToString:[NSString stringWithFormat:@"/Users/%@/Documents", username]]) {
                documentsAccess = YES;
            }
            if ([path isEqualToString:[NSString stringWithFormat:@"/Users/%@/Downloads", username]]) {
                downloadsAccess = YES;
            }
        }
        
        [output appendFormat:@"Desktop Access: %@\n", desktopAccess ? @"true" : @"false"];
        [output appendFormat:@"Documents Access: %@\n", documentsAccess ? @"true" : @"false"];
        [output appendFormat:@"Downloads Access: %@\n", downloadsAccess ? @"true" : @"false"];
        CFRelease(query);
    }
    
    // Check for Accessibility permissions
    [output appendFormat:@"Accessibility Enabled: %@\n", AXIsProcessTrusted() ? @"true" : @"false"];
    
    return output;
}

@end 