#import "ZPWDCommandHandler.h"

@implementation ZPWDCommandHandler

- (instancetype)init {
    return [super initWithType:@"pwd"];
}

- (NSString *)command {
    return @"pwd";
}

- (void)executeCommand:(ZCommandModel *)command 
           completion:(void (^)(BOOL success, NSDictionary *result, NSError *error))completion {
    NSLog(@"Executing pwd command: %@", [command commandId]);
    
    // Get the current working directory using NSFileManager
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *currentPath = [fileManager currentDirectoryPath];
    
    if (!currentPath) {
        NSError *error = [NSError errorWithDomain:@"ZPWDCommandHandler" 
                                           code:500 
                                       userInfo:@{NSLocalizedDescriptionKey: 
                                                 @"Failed to get current working directory"}];
        if (completion) {
            completion(NO, nil, error);
        }
        return;
    }
    
    // Create date formatter for ISO 8601 dates
    NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
    [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
    [dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    
    // Get additional path information
    NSDictionary *attributes = [fileManager attributesOfItemAtPath:currentPath error:nil];
    
    // Create result dictionary
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [result setObject:@"pwd_response" forKey:@"type"];
    [result setObject:currentPath forKey:@"path"];
    
    // Add additional path information if available
    if (attributes) {
        // Add creation and modification dates as formatted strings
        NSDate *creationDate = [attributes fileCreationDate];
        NSDate *modificationDate = [attributes fileModificationDate];
        
        if (creationDate) {
            [result setObject:[dateFormatter stringFromDate:creationDate] forKey:@"creationDate"];
        }
        if (modificationDate) {
            [result setObject:[dateFormatter stringFromDate:modificationDate] forKey:@"modificationDate"];
        }
        
        // Add permissions
        NSNumber *permissions = [NSNumber numberWithUnsignedLong:[attributes filePosixPermissions]];
        if (permissions) {
            [result setObject:permissions forKey:@"permissions"];
        }
        
        // Add owner information
        NSString *owner = [attributes fileOwnerAccountName];
        if (owner) {
            [result setObject:owner forKey:@"owner"];
        }
        
        // Add group information
        NSString *group = [attributes fileGroupOwnerAccountName];
        if (group) {
            [result setObject:group forKey:@"group"];
        }
    }
    
    // Add path components for easier parsing
    NSArray *pathComponents = [currentPath pathComponents];
    if (pathComponents) {
        [result setObject:pathComponents forKey:@"components"];
    }
    
    // Add symbolic link information if the current directory is a symlink
    if ([[attributes fileType] isEqualToString:NSFileTypeSymbolicLink]) {
        NSError *linkError = nil;
        NSString *destPath = [fileManager destinationOfSymbolicLinkAtPath:currentPath error:&linkError];
        if (!linkError && destPath) {
            [result setObject:destPath forKey:@"linkDestination"];
        }
    }
    
    // Add volume information
    NSDictionary *volumeInfo = [[NSFileManager defaultManager] attributesOfFileSystemForPath:currentPath error:nil];
    if (volumeInfo) {
        NSMutableDictionary *volume = [NSMutableDictionary dictionary];
        
        // Get volume size information
        NSNumber *totalSize = [volumeInfo objectForKey:NSFileSystemSize];
        NSNumber *freeSize = [volumeInfo objectForKey:NSFileSystemFreeSize];
        NSNumber *nodes = [volumeInfo objectForKey:NSFileSystemNodes];
        NSNumber *freeNodes = [volumeInfo objectForKey:NSFileSystemFreeNodes];
        
        if (totalSize) [volume setObject:totalSize forKey:@"totalSize"];
        if (freeSize) [volume setObject:freeSize forKey:@"freeSize"];
        if (nodes) [volume setObject:nodes forKey:@"totalNodes"];
        if (freeNodes) [volume setObject:freeNodes forKey:@"freeNodes"];
        
        [result setObject:volume forKey:@"volume"];
    }
    
    // Complete with success
    if (completion) {
        completion(YES, result, nil);
    }
}

- (BOOL)supportsMultipleCommands {
    // PWD commands can run multiple instances simultaneously
    return YES;
}

@end 