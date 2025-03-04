#import "ZLSCommandHandler.h"

@implementation ZLSCommandHandler

- (instancetype)init {
    return [super initWithType:@"ls"];
}

- (void)executeCommand:(ZCommandModel *)command 
           completion:(void (^)(BOOL success, NSDictionary *result, NSError *error))completion {
    NSLog(@"Executing ls command: %@", [command commandId]);
    
    // Get the payload from the command
    NSDictionary *payload = [command payload];
    
    // Extract path from payload or use current directory
    NSString *path = [payload objectForKey:@"path"];
    if (!path) {
        path = @".";
    }
    
    // Extract options from payload
    BOOL showHidden = [[payload objectForKey:@"showHidden"] boolValue];
    BOOL longFormat = [[payload objectForKey:@"longFormat"] boolValue];
    
    // Create file manager instance
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // Resolve path to absolute path
    NSString *absolutePath = [path stringByStandardizingPath];
    if ([path isEqualToString:@"."]) {
        absolutePath = [fileManager currentDirectoryPath];
    } else if (![path isAbsolutePath]) {
        absolutePath = [[fileManager currentDirectoryPath] stringByAppendingPathComponent:path];
    }
    
    // Check if path exists
    BOOL isDirectory;
    if (![fileManager fileExistsAtPath:absolutePath isDirectory:&isDirectory]) {
        NSError *error = [NSError errorWithDomain:@"ZLSCommandHandler" 
                                           code:404 
                                       userInfo:@{NSLocalizedDescriptionKey: 
                                                 [NSString stringWithFormat:@"Path does not exist: %@", path]}];
        if (completion) {
            completion(NO, nil, error);
        }
        return;
    }
    
    NSError *error = nil;
    NSArray *contents;
    
    // Get directory contents
    if (isDirectory) {
        contents = [fileManager contentsOfDirectoryAtPath:absolutePath error:&error];
        if (error) {
            if (completion) {
                completion(NO, nil, error);
            }
            return;
        }
    } else {
        // If path is a file, just list that file
        contents = @[[path lastPathComponent]];
    }
    
    // Filter hidden files if needed
    if (!showHidden) {
        contents = [contents filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id obj, NSDictionary * __unused bindings) {
            return ![(NSString *)obj hasPrefix:@"."];
        }]];
    }
    
    // Create result array
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:[contents count]];
    
    // Process each item
    for (NSString *itemName in contents) {
        NSString *itemPath = [absolutePath stringByAppendingPathComponent:itemName];
        NSMutableDictionary *itemInfo = [NSMutableDictionary dictionary];
        
        // Get file attributes
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:itemPath error:&error];
        if (error) {
            NSLog(@"Error getting attributes for %@: %@", itemPath, error);
            continue;
        }
        
        // Basic info always included
        [itemInfo setObject:itemName forKey:@"name"];
        [itemInfo setObject:[attributes fileType] forKey:@"type"];
        
        if (longFormat) {
            // Add detailed attributes for long format
            [itemInfo setObject:[NSNumber numberWithUnsignedLongLong:[attributes fileSize]] 
                       forKey:@"size"];
            [itemInfo setObject:[attributes fileModificationDate] forKey:@"modificationDate"];
            [itemInfo setObject:[attributes fileCreationDate] forKey:@"creationDate"];
            [itemInfo setObject:[NSNumber numberWithUnsignedLong:[attributes filePosixPermissions]] 
                       forKey:@"permissions"];
            
            // Convert NSNumber to unsigned long for owner and group IDs
            NSNumber *ownerID = [attributes fileOwnerAccountID];
            NSNumber *groupID = [attributes fileGroupOwnerAccountID];
            if (ownerID) [itemInfo setObject:[NSNumber numberWithUnsignedLong:[ownerID unsignedLongValue]] forKey:@"ownerID"];
            if (groupID) [itemInfo setObject:[NSNumber numberWithUnsignedLong:[groupID unsignedLongValue]] forKey:@"groupID"];
            
            // Get owner and group names
            NSString *ownerName = [attributes fileOwnerAccountName];
            NSString *groupName = [attributes fileGroupOwnerAccountName];
            if (ownerName) [itemInfo setObject:ownerName forKey:@"owner"];
            if (groupName) [itemInfo setObject:groupName forKey:@"group"];
            
            // Check if item is symlink
            if ([[attributes fileType] isEqualToString:NSFileTypeSymbolicLink]) {
                NSString *destPath = [fileManager destinationOfSymbolicLinkAtPath:itemPath error:&error];
                if (!error && destPath) {
                    [itemInfo setObject:destPath forKey:@"linkDestination"];
                }
            }
        }
        
        [items addObject:itemInfo];
    }
    
    // Sort items (directories first, then alphabetically)
    [items sortUsingComparator:^NSComparisonResult(NSDictionary *item1, NSDictionary *item2) {
        BOOL isDir1 = [[item1 objectForKey:@"type"] isEqualToString:NSFileTypeDirectory];
        BOOL isDir2 = [[item2 objectForKey:@"type"] isEqualToString:NSFileTypeDirectory];
        
        if (isDir1 != isDir2) {
            return isDir1 ? NSOrderedAscending : NSOrderedDescending;
        }
        
        return [[item1 objectForKey:@"name"] compare:[item2 objectForKey:@"name"]];
    }];
    
    // Create final result dictionary
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [result setObject:@"ls_response" forKey:@"type"];
    [result setObject:absolutePath forKey:@"path"];
    [result setObject:items forKey:@"items"];
    [result setObject:[NSNumber numberWithBool:isDirectory] forKey:@"isDirectory"];
    
    // Complete with success
    if (completion) {
        completion(YES, result, nil);
    }
}

- (BOOL)supportsMultipleCommands {
    // LS commands can run multiple instances simultaneously
    return YES;
}

@end 