#import "ZDialogCommandHandler.h"
#import <AppKit/AppKit.h>

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
    void (^safeCompletion)(BOOL, NSDictionary*, NSError*) = [completion copy];
    
    // Ensure proper application setup for UI operations
    dispatch_async(dispatch_get_main_queue(), ^{
        [self ensureApplicationSetup];
        
        // Show the dialog based on type without creating a temporary window first
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        
        if ([dialogType isEqualToString:@"alert"]) {
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            [alert setMessageText:title];
            [alert setInformativeText:message];
            [alert addButtonWithTitle:@"OK"];
            
            [alert runModal];
            
            [result setObject:@"alert_response" forKey:@"type"];
            [result setObject:@"ok" forKey:@"button"];
            
        } else if ([dialogType isEqualToString:@"confirm"]) {
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            [alert setMessageText:title];
            [alert setInformativeText:message];
            [alert addButtonWithTitle:@"Yes"];
            [alert addButtonWithTitle:@"No"];
            
            NSModalResponse returnCode = [alert runModal];
            
            BOOL confirmed = (returnCode == NSAlertFirstButtonReturn);
            [result setObject:@"confirm_response" forKey:@"type"];
            [result setObject:(confirmed ? @"yes" : @"no") forKey:@"button"];
            [result setObject:[NSNumber numberWithBool:confirmed] forKey:@"confirmed"];
            
        } else if ([dialogType isEqualToString:@"prompt"]) {
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            [alert setMessageText:title];
            [alert setInformativeText:message];
            
            NSTextField *input = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)] autorelease];
            [input setStringValue:@""];
            [alert setAccessoryView:input];
            
            [alert addButtonWithTitle:@"OK"];
            [alert addButtonWithTitle:@"Cancel"];
            
            // Make the text field the first responder
            [[alert window] makeFirstResponder:input];
            
            NSModalResponse returnCode = [alert runModal];
            
            BOOL confirmed = (returnCode == NSAlertFirstButtonReturn);
            [result setObject:@"prompt_response" forKey:@"type"];
            [result setObject:(confirmed ? @"ok" : @"cancel") forKey:@"button"];
            
            if (confirmed) {
                NSString *value = [input stringValue];
                [result setObject:(value ? value : @"") forKey:@"value"];
                
                // If this was a password prompt, clarify in the result
                if ([title isEqualToString:@"Authentication Required"]) {
                    [result setObject:@"password" forKey:@"input_type"];
                }
            }
        } else {
            // Unknown dialog type, default to alert
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            [alert setMessageText:title];
            [alert setInformativeText:message];
            [alert addButtonWithTitle:@"OK"];
            
            [alert runModal];
            
            [result setObject:@"alert_response" forKey:@"type"];
            [result setObject:@"ok" forKey:@"button"];
        }
        
        // Save the result and call completion handler
        if (safeCompletion) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                safeCompletion(YES, result, nil);
                [safeCompletion release]; // Release the copied block
            });
        }
    });
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
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
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

// Delete or comment out all other methods as they are no longer used
// We've simplified the approach significantly to avoid the duplicate window issue

@end 