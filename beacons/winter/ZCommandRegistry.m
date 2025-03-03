#import "ZCommandRegistry.h"

@interface ZCommandRegistry ()
@property (nonatomic, retain) NSMutableDictionary *handlers;
@property (nonatomic, retain) NSMutableDictionary *activeCommands;
@property (nonatomic, retain) dispatch_queue_t commandQueue;
@end

@implementation ZCommandRegistry

+ (instancetype)sharedRegistry {
    static ZCommandRegistry *sharedInstance = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedInstance = [[ZCommandRegistry alloc] init];
    });
    
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.handlers = [[NSMutableDictionary alloc] init];
        self.activeCommands = [[NSMutableDictionary alloc] init];
        self.commandQueue = dispatch_queue_create("com.zapit.beacon.commands", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)dealloc {
    [_handlers release];
    [_activeCommands release];
    dispatch_release(_commandQueue);
    [super dealloc];
}

- (BOOL)registerCommandHandler:(id<ZCommandHandler>)handler {
    if (!handler) {
        NSLog(@"Cannot register nil handler");
        return NO;
    }
    
    NSString *commandType = [handler commandType];
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
                                            userInfo:[NSDictionary dictionaryWithObject:@"Nil command" 
                                                                                 forKey:NSLocalizedDescriptionKey]];
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
                                            userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"No handler for command type: %@", commandType] 
                                                                                 forKey:NSLocalizedDescriptionKey]];
            completion(NO, nil, error);
        }
        return NO;
    }
    
    // Check if we can handle multiple commands of this type
    BOOL supportsMultiple = [handler respondsToSelector:@selector(supportsMultipleCommands)] && 
                          [handler supportsMultipleCommands];
    
    // Check if we already have an active command of this type
    NSString * __unused commandId = [command commandId];
    NSMutableArray *activeCommandsOfType = [self.activeCommands objectForKey:commandType];
    
    if (!supportsMultiple && activeCommandsOfType && [activeCommandsOfType count] > 0) {
        NSLog(@"Handler for command type '%@' already has an active command and doesn't support multiple commands", commandType);
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"ZCommandRegistry" 
                                                code:203 
                                            userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Handler for command type '%@' already has an active command", commandType] 
                                                                                 forKey:NSLocalizedDescriptionKey]];
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