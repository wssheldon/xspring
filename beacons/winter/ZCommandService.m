#import "ZCommandService.h"
#import "ZCommandModel.h"

// Default values
static const NSTimeInterval kDefaultPollInterval = 60.0;  // 1 minute
static const NSTimeInterval kDefaultCommandTimeout = 300.0;  // 5 minutes

@interface ZCommandService ()

@property(nonatomic, strong) ZCommandPoller *poller;
@property(nonatomic, strong) ZCommandReporter *reporter;
@property(nonatomic, strong) ZCommandExecutor *executor;
@property(nonatomic, strong) NSURL *serverURL;
@property(nonatomic, copy) NSString *beaconId;
@property(nonatomic, assign, readwrite) BOOL isRunning;

@end

@implementation ZCommandService

#pragma mark - Initialization

- (instancetype)initWithServerURL:(NSURL *)serverURL {
    return [self initWithServerURL:serverURL beaconId:nil];
}

- (instancetype)initWithServerURL:(NSURL *)serverURL beaconId:(NSString *)beaconId {
    self = [super init];
    if (self) {
        _serverURL = serverURL;
        _beaconId = [beaconId copy];
        _pollInterval = kDefaultPollInterval;
        _commandTimeout = kDefaultCommandTimeout;
        
        // Initialize components
        _poller = [[ZCommandPoller alloc] initWithServerURL:serverURL beaconId:beaconId];
        _poller.delegate = self;
        _poller.pollInterval = _pollInterval;
        
        _reporter = [[ZCommandReporter alloc] initWithServerURL:serverURL beaconId:beaconId];
        _reporter.delegate = self;
        
        _executor = [[ZCommandExecutor alloc] init];
        _executor.delegate = self;
        _executor.commandTimeout = _commandTimeout;
    }
    return self;
}

#pragma mark - Public Methods

- (BOOL)start {
    if (self.isRunning) {
        return NO;
    }
    
    [self.poller startPolling];
    self.isRunning = YES;
    return YES;
}

- (void)stop {
    if (!self.isRunning) {
        return;
    }
    
    [self.poller stopPolling];
    self.isRunning = NO;
}

- (void)pollNow {
    [self.poller pollNow];
}

- (void)reportCommand:(ZCommandModel *)command result:(NSDictionary *)result error:(NSError *)error {
    [self.reporter reportCommand:command result:result error:error];
}

#pragma mark - Property Setters

- (void)setPollInterval:(NSTimeInterval)pollInterval {
    _pollInterval = pollInterval;
    self.poller.pollInterval = pollInterval;
}

- (void)setCommandTimeout:(NSTimeInterval)commandTimeout {
    _commandTimeout = commandTimeout;
    self.executor.commandTimeout = commandTimeout;
}

#pragma mark - ZCommandPollerDelegate

- (void)commandPoller:(id)poller didReceiveCommand:(ZCommandModel *)command {
    // Notify delegate of received command
    if ([self.delegate respondsToSelector:@selector(commandService:didReceiveCommand:)]) {
        [self.delegate commandService:self didReceiveCommand:command];
    }
    
    // Execute the command
    [self.executor executeCommand:command];
}

- (void)commandPoller:(id)poller didFailWithError:(NSError *)error {
    NSLog(@"Command polling failed: %@", error);
}

#pragma mark - ZCommandExecutorDelegate

- (void)commandExecutor:(id)executor didCompleteCommand:(ZCommandModel *)command withResult:(NSDictionary *)result {
    // Notify delegate of successful execution
    if ([self.delegate respondsToSelector:@selector(commandService:didExecuteCommand:withResult:)]) {
        [self.delegate commandService:self didExecuteCommand:command withResult:result];
    }
    
    // Report result to server
    [self.reporter reportCommand:command result:result error:nil];
}

- (void)commandExecutor:(id)executor didFailCommand:(ZCommandModel *)command withError:(NSError *)error {
    // Notify delegate of execution failure
    if ([self.delegate respondsToSelector:@selector(commandService:didFailToExecuteCommand:withError:)]) {
        [self.delegate commandService:self didFailToExecuteCommand:command withError:error];
    }
    
    // Report error to server
    [self.reporter reportCommand:command result:nil error:error];
}

- (void)commandExecutor:(id)executor didTimeoutCommand:(ZCommandModel *)command {
    NSError *timeoutError = [NSError errorWithDomain:@"ZCommandServiceErrorDomain"
                                               code:-1
                                           userInfo:@{NSLocalizedDescriptionKey: @"Command execution timed out"}];
    
    // Notify delegate of timeout
    if ([self.delegate respondsToSelector:@selector(commandService:didFailToExecuteCommand:withError:)]) {
        [self.delegate commandService:self didFailToExecuteCommand:command withError:timeoutError];
    }
    
    // Report timeout to server
    [self.reporter reportCommand:command result:nil error:timeoutError];
}

#pragma mark - ZCommandReporterDelegate

- (void)commandReporter:(id)reporter didReportCommand:(ZCommandModel *)command withResponse:(NSDictionary *)response {
    // Notify delegate of successful report
    if ([self.delegate respondsToSelector:@selector(commandService:didReportCommand:withResponse:)]) {
        [self.delegate commandService:self didReportCommand:command withResponse:response];
    }
}

- (void)commandReporter:(id)reporter didFailToReportCommand:(ZCommandModel *)command withError:(NSError *)error {
    // Notify delegate of report failure
    if ([self.delegate respondsToSelector:@selector(commandService:didFailToReportCommand:withError:)]) {
        [self.delegate commandService:self didFailToReportCommand:command withError:error];
    }
}

@end 