#import "ZCommandExecutor.h"
#import "ZCommandModel.h"
#import "ZCommandRegistry.h"

@interface ZCommandExecutor ()

@property(nonatomic, retain) NSMutableDictionary *commandTimers;
@property(nonatomic, assign) dispatch_queue_t executorQueue;

@end

@implementation ZCommandExecutor

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _commandTimeout = 300.0; // Default to 5 minutes
        _commandTimers = [[NSMutableDictionary dictionary] retain];
        _executorQueue = dispatch_queue_create("com.zapit.beacon.commandexecutor", 0);
    }
    return self;
}

- (void)dealloc {
    [_commandTimers release];
    
    if (_executorQueue) {
        dispatch_release(_executorQueue);
    }
    
    [super dealloc];
}

#pragma mark - Public Methods

- (void)executeCommand:(ZCommandModel *)command {
    if (!command) {
        return;
    }
    
    // Retain command for use in block
    ZCommandModel *blockCommand = [command retain];
    
    dispatch_async(self.executorQueue, ^{
        [self executeCommandInternal:blockCommand];
        [blockCommand release];
    });
}

- (BOOL)cancelCommand:(ZCommandModel *)command {
    if (!command) {
        return NO;
    }
    
    NSString *commandId = [command commandId];
    dispatch_source_t timer = self.commandTimers[commandId];
    if (timer) {
        dispatch_source_cancel(timer);
        dispatch_release(timer);
        [self.commandTimers removeObjectForKey:commandId];
        return YES;
    }
    
    return NO;
}

#pragma mark - Private Methods

- (void)executeCommandInternal:(ZCommandModel *)command {
    // Start timeout timer
    [self startTimeoutTimerForCommand:command];
    
    // Get command registry
    ZCommandRegistry *registry = [ZCommandRegistry sharedRegistry];
    
    // Execute command
    ZCommandExecutor *blockSelf = self;
    [registry executeCommand:command completion:^(BOOL success, NSDictionary *result, NSError *error) {
        // Cancel timeout timer
        [blockSelf cancelCommand:command];
        
        // Notify delegate
        if (success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [blockSelf.delegate commandExecutor:blockSelf 
                              didCompleteCommand:command 
                                    withResult:result];
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [blockSelf.delegate commandExecutor:blockSelf 
                                   didFailCommand:command 
                                      withError:error];
            });
        }
    }];
}

- (void)startTimeoutTimerForCommand:(ZCommandModel *)command {
    NSString *commandId = [command commandId];
    
    // Cancel existing timer if any
    dispatch_source_t existingTimer = self.commandTimers[commandId];
    if (existingTimer) {
        dispatch_source_cancel(existingTimer);
        dispatch_release(existingTimer);
        [self.commandTimers removeObjectForKey:commandId];
    }
    
    // Create new timer
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.executorQueue);
    
    uint64_t timeout = (uint64_t)(self.commandTimeout * NSEC_PER_SEC);
    dispatch_source_set_timer(timer,
                            dispatch_time(DISPATCH_TIME_NOW, timeout),
                            DISPATCH_TIME_FOREVER,
                            1 * NSEC_PER_SEC);
    
    ZCommandExecutor *blockSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        // Handle timeout
        dispatch_async(dispatch_get_main_queue(), ^{
            [blockSelf.delegate commandExecutor:blockSelf didTimeoutCommand:command];
        });
        
        // Cancel and remove timer
        dispatch_source_t timeoutTimer = blockSelf.commandTimers[commandId];
        if (timeoutTimer) {
            dispatch_source_cancel(timeoutTimer);
            dispatch_release(timeoutTimer);
            [blockSelf.commandTimers removeObjectForKey:commandId];
        }
    });
    
    // Store and start timer
    self.commandTimers[commandId] = timer;
    dispatch_resume(timer);
}

@end 