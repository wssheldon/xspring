#import "ZBeacon.h"
#import "ZAPIClient.h"
#import "ZSystemInfo.h"

// Domain for beacon errors
NSString *const ZBeaconErrorDomain = @"com.zbeacon.error";

// Status constants
NSString *const ZBeaconStatusInitializing = @"initializing";
NSString *const ZBeaconStatusOnline = @"online";
NSString *const ZBeaconStatusOffline = @"offline";
NSString *const ZBeaconStatusError = @"error";

// Constants
static const NSTimeInterval kInitialRetryDelay = 5.0;  // 5 seconds
static const NSTimeInterval kMaxRetryDelay = 60.0;     // 1 minute
static const int kMaxRetryAttempts = 5;                // Maximum number of retry attempts

// Private interface extensions
@interface ZBeacon ()

// Make properties readwrite in private interface
@property (nonatomic, copy, readwrite) NSString *beaconId;
@property (nonatomic, copy, readwrite) NSString *lastSeen;
@property (nonatomic, copy, readwrite) NSString *status;
@property (nonatomic, copy, readwrite) NSString *hostname;
@property (nonatomic, copy, readwrite) NSString *username;
@property (nonatomic, copy, readwrite) NSString *osVersion;
@property (nonatomic, strong, readwrite) ZAPIClient *apiClient;
@property (nonatomic, assign, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, assign, readwrite) ZBeaconConfiguration configuration;

// Private properties
@property (nonatomic, strong) NSTimer *pingTimer;
@property (nonatomic, strong) dispatch_queue_t beaconQueue;
@property (nonatomic, strong) dispatch_queue_t networkQueue;
@property (nonatomic, assign) NSUInteger retryCount;
@property (nonatomic, assign) NSTimeInterval currentRetryDelay;
@property (nonatomic, strong) NSDateFormatter *timestampFormatter;
@property (nonatomic, strong) dispatch_source_t registrationTimer;

// Private methods
- (void)setupTimestampFormatter;
- (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description;
- (void)notifyDelegateOfStatusChange;
- (BOOL)registerWithServerWithCompletion:(void(^)(BOOL success, NSError *error))completion;
- (void)pingServerInternal:(void(^)(BOOL success, NSError *error, NSDictionary *response))completion;
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

- (instancetype)initWithServerURL:(NSURL *)serverURL {
    return [self initWithServerURL:serverURL configuration:[ZBeacon defaultConfiguration]];
}

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithServerURL:(NSURL *)serverURL configuration:(ZBeaconConfiguration)configuration {
    @try {
        self = [super init];
        if (self) {
            if (!serverURL) {
                [self logMessage:@"Error: Cannot initialize ZBeacon with nil serverURL"];
                [self release];
                return nil;
            }
            
            // Store configuration
            _configuration = configuration;
            
            // Create API client
            _apiClient = [[ZAPIClient alloc] initWithServerURL:serverURL];
            if (!_apiClient) {
                [self logMessage:@"Error: Failed to create API client"];
                [self release];
                return nil;
            }
            
            // Initialize properties
            _beaconId = [[NSUUID UUID] UUIDString];
            [_beaconId retain];
            
            _status = [ZBeaconStatusInitializing retain];
            _lastSeen = [[self currentTimestampString] retain];
            _retryCount = 0;
            _currentRetryDelay = configuration.initialRetryDelay;
            
            // Create dispatch queues
            NSString *queueNamePrefix = [NSString stringWithFormat:@"com.zbeacon.%@", _beaconId];
            _beaconQueue = dispatch_queue_create([[queueNamePrefix stringByAppendingString:@".beaconQueue"] UTF8String], DISPATCH_QUEUE_SERIAL);
            _networkQueue = dispatch_queue_create([[queueNamePrefix stringByAppendingString:@".networkQueue"] UTF8String], DISPATCH_QUEUE_CONCURRENT);
            
            // Setup timestamp formatter
            [self setupTimestampFormatter];
            
            // Get system information synchronously during initialization
            [self collectSystemInformationSync];
            
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
        [self release];
        return nil;
    }
}

- (void)collectSystemInformationSync {
    @try {
        // Get system information synchronously
        self.hostname = [[ZSystemInfo hostname] retain];
        self.username = [[ZSystemInfo username] retain];
        self.osVersion = [[ZSystemInfo osVersion] retain];
    }
    @catch (NSException *exception) {
        [self logMessage:@"Error collecting system information: %@", exception];
    }
}

- (void)updateSystemInformationAsync {
    // We still provide an async method to update system info after initialization
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @try {
            NSString *newHostname = [ZSystemInfo hostname];
            NSString *newUsername = [ZSystemInfo username];
            NSString *newOSVersion = [ZSystemInfo osVersion];
            
            dispatch_async(self.beaconQueue, ^{
                [self.hostname release];
                self.hostname = [newHostname retain];
                
                [self.username release];
                self.username = [newUsername retain];
                
                [self.osVersion release];
                self.osVersion = [newOSVersion retain];
                
                [self logMessage:@"System info updated: hostname=%@, username=%@, os=%@", 
                    self.hostname ?: @"(unknown)", 
                    self.username ?: @"(unknown)", 
                    self.osVersion ?: @"(unknown)"];
            });
        }
        @catch (NSException *exception) {
            [self logMessage:@"Error updating system information: %@", exception];
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
            [self registerWithServerWithCompletion:^(BOOL success, NSError *error) {
                if (!success) {
                    // If initial registration fails, still return success but schedule retry
                    [self scheduleRetry];
                }
                
                // Schedule periodic system info updates
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_SEC)), self.beaconQueue, ^{
                    [self updateSystemInformationAsync];
                });
                
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
    
    [self pingServerInternal:^(BOOL success, NSError *error, NSDictionary *response) {
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
        [self.status release];
        self.status = [newStatus retain];
        [self notifyDelegateOfStatusChange];
    }
}

- (void)notifyDelegateOfStatusChange {
    id<ZBeaconDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(beacon:didChangeStatus:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate beacon:self didChangeStatus:self.status];
        });
    }
}

- (BOOL)registerWithServerWithCompletion:(void(^)(BOOL success, NSError *error))completion {
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
        
        // Create a block to retain 'self' for the operation
        ZBeacon *blockSelf = self;
        [blockSelf retain]; // Retain for the async operation
        
        // Send init request to server
        dispatch_async(self.networkQueue, ^{
            [blockSelf.apiClient sendInitRequestWithData:registrationData completion:^(NSDictionary *response, NSError *error) {
                dispatch_async(blockSelf.beaconQueue, ^{
                    if (!blockSelf.isRunning) {
                        // Beacon was stopped during the network request
                        [blockSelf release]; // Balance the retain
                        return;
                    }
                    
                    if (error) {
                        [blockSelf logMessage:@"Error registering beacon: %@", error.localizedDescription];
                        [blockSelf setStatusSafely:ZBeaconStatusError];
                        
                        // Notify delegate
                        id<ZBeaconDelegate> delegate = blockSelf.delegate;
                        if ([delegate respondsToSelector:@selector(beacon:didFailToRegisterWithError:willRetry:)]) {
                            BOOL willRetry = blockSelf.retryCount < blockSelf.configuration.maxRetryAttempts;
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [delegate beacon:blockSelf didFailToRegisterWithError:error willRetry:willRetry];
                            });
                        }
                        
                        if (completion) completion(NO, error);
                        [blockSelf release]; // Balance the retain
                        return;
                    }
                    
                    // Registration successful, reset retry counters
                    blockSelf.retryCount = 0;
                    blockSelf.currentRetryDelay = blockSelf.configuration.initialRetryDelay;
                    
                    [blockSelf logMessage:@"Beacon registered successfully: %@", response];
                    [blockSelf setStatusSafely:ZBeaconStatusOnline];
                    
                    [blockSelf.lastSeen release];
                    blockSelf.lastSeen = [[blockSelf currentTimestampString] retain];
                    
                    // Notify delegate
                    id<ZBeaconDelegate> delegate = blockSelf.delegate;
                    if ([delegate respondsToSelector:@selector(beacon:didRegisterWithResponse:)]) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [delegate beacon:blockSelf didRegisterWithResponse:response];
                        });
                    }
                    
                    // Start ping timer on main thread
                    dispatch_async(dispatch_get_main_queue(), ^{
                        @try {
                            // Cancel any existing timer first
                            if (blockSelf.pingTimer) {
                                [blockSelf.pingTimer invalidate];
                                blockSelf.pingTimer = nil;
                            }
                            
                            // Create new timer
                            blockSelf.pingTimer = [NSTimer timerWithTimeInterval:blockSelf.configuration.pingInterval
                                                                     target:blockSelf
                                                                   selector:@selector(pingTimerFired)
                                                                   userInfo:nil
                                                                    repeats:YES];
                            
                            // Add to run loop
                            NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
                            [runLoop addTimer:blockSelf.pingTimer forMode:NSRunLoopCommonModes];
                            
                            // Send initial ping immediately
                            [blockSelf performSelector:@selector(pingTimerFired) withObject:nil afterDelay:0.1];
                        }
                        @catch (NSException *exception) {
                            [blockSelf logMessage:@"Exception setting up ping timer: %@", exception];
                        }
                    });
                    
                    if (completion) completion(YES, nil);
                    [blockSelf release]; // Balance the retain
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

- (void)pingServerInternal:(void(^)(BOOL success, NSError *error, NSDictionary *response))completion {
    if (!self.isRunning) {
        [self logMessage:@"Beacon is not running. Skipping ping."];
        NSError *error = [self errorWithCode:102 description:@"Beacon is not running"];
        if (completion) completion(NO, error, nil);
        return;
    }
    
    dispatch_async(self.beaconQueue, ^{
        @try {
            [self logMessage:@"Pinging server with beacon ID: %@", self.beaconId];
            
            // Prepare ping data
            NSDictionary *pingData = @{
                @"client_id": self.beaconId,
                @"status": self.status,
                @"timestamp": [self currentTimestampString]
            };
            
            // Retain self for the async operation
            ZBeacon *blockSelf = self;
            [blockSelf retain];
            
            // Send ping request to server
            dispatch_async(self.networkQueue, ^{
                [blockSelf.apiClient sendPingRequestWithData:pingData completion:^(NSDictionary *response, NSError *error) {
                    dispatch_async(blockSelf.beaconQueue, ^{
                        if (error) {
                            [blockSelf logMessage:@"Error pinging server: %@", error.localizedDescription];
                            
                            // Notify delegate
                            id<ZBeaconDelegate> delegate = blockSelf.delegate;
                            if ([delegate respondsToSelector:@selector(beacon:didFailToPingWithError:)]) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [delegate beacon:blockSelf didFailToPingWithError:error];
                                });
                            }
                            
                            if (completion) completion(NO, error, nil);
                            [blockSelf release]; // Balance the retain
                            return;
                        }
                        
                        [blockSelf logMessage:@"Ping successful: %@", response];
                        
                        [blockSelf.lastSeen release];
                        blockSelf.lastSeen = [[blockSelf currentTimestampString] retain];
                        
                        // Notify delegate
                        id<ZBeaconDelegate> delegate = blockSelf.delegate;
                        if ([delegate respondsToSelector:@selector(beacon:didPingWithResponse:)]) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [delegate beacon:blockSelf didPingWithResponse:response];
                            });
                        }
                        
                        if (completion) completion(YES, nil, response);
                        [blockSelf release]; // Balance the retain
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
            dispatch_retain(self.registrationTimer); // Retain the timer
            
            uint64_t nanoseconds = (uint64_t)(self.currentRetryDelay * NSEC_PER_SEC);
            dispatch_source_set_timer(self.registrationTimer, 
                                     dispatch_time(DISPATCH_TIME_NOW, nanoseconds), 
                                     DISPATCH_TIME_FOREVER, 
                                     (1ull * NSEC_PER_SEC) / 10);
            
            // Retain self for the async operation
            ZBeacon *blockSelf = self;
            [blockSelf retain];
            
            dispatch_source_set_event_handler(self.registrationTimer, ^{
                @try {
                    [blockSelf cancelRetryTimer];
                    
                    if (!blockSelf.isRunning) {
                        [blockSelf logMessage:@"Beacon is no longer running. Cancelling retry."];
                        [blockSelf release]; // Balance the retain
                        return;
                    }
                    
                    [blockSelf logMessage:@"Retrying registration..."];
                    [blockSelf registerWithServerWithCompletion:^(BOOL success, NSError *regError) {
                        if (!success) {
                            // Increase retry delay with exponential backoff (up to max delay)
                            blockSelf.currentRetryDelay = MIN(blockSelf.currentRetryDelay * 2, blockSelf.configuration.maxRetryDelay);
                            [blockSelf scheduleRetry];
                        }
                        [blockSelf release]; // Balance the initial retain
                    }];
                }
                @catch (NSException *exception) {
                    [blockSelf logMessage:@"Exception during retry: %@", exception];
                    [blockSelf release]; // Balance the retain
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
            dispatch_release(self.registrationTimer);
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
                           userInfo:[NSDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey]];
}

- (void)logMessage:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSLog(@"[ZBeacon %@] %@", [self.beaconId substringToIndex:8], message);
    [message release];
}

@end 