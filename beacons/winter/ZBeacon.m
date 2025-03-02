#import "ZBeacon.h"
#import "ZAPIClient.h"
#import "ZSystemInfo.h"

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

// Private properties
@property (nonatomic, strong) NSTimer *pingTimer;
@property (nonatomic, strong) dispatch_queue_t eventQueue;
@property (nonatomic, assign) int retryCount;
@property (nonatomic, assign) NSTimeInterval retryDelay;

@end

@implementation ZBeacon

#pragma mark - Lifecycle

- (instancetype)initWithServerURL:(NSURL *)serverURL {
    @try {
        self = [super init];
        if (self) {
            if (!serverURL) {
                NSLog(@"Error: Cannot initialize ZBeacon with nil serverURL");
                return nil;
            }
            
            // Create API client
            _apiClient = [[ZAPIClient alloc] initWithServerURL:serverURL];
            if (!_apiClient) {
                NSLog(@"Error: Failed to create API client");
                return nil;
            }
            
            // Generate a unique ID
            _beaconId = [[NSUUID UUID] UUIDString];
            _status = @"initializing";
            _lastSeen = [self currentTimestampString];
            _eventQueue = dispatch_queue_create("com.zbeacon.eventQueue", DISPATCH_QUEUE_SERIAL);
            _retryCount = 0;
            _retryDelay = kInitialRetryDelay;
            
            // Get system information safely
            _hostname = [self safeGetHostname];
            _username = [self safeGetUsername];
            _osVersion = [self safeGetOSVersion];
            
            NSLog(@"Beacon initialized with ID: %@", _beaconId);
            NSLog(@"System info: hostname=%@, username=%@, os=%@", 
                  _hostname ?: @"(unknown)", 
                  _username ?: @"(unknown)", 
                  _osVersion ?: @"(unknown)");
        }
        return self;
    }
    @catch (NSException *exception) {
        NSLog(@"Exception during beacon initialization: %@", exception);
        return nil;
    }
}

- (NSString *)safeGetHostname {
    @try {
        return [ZSystemInfo hostname];
    }
    @catch (NSException *exception) {
        NSLog(@"Failed to get hostname: %@", exception);
        return nil;
    }
}

- (NSString *)safeGetUsername {
    @try {
        return [ZSystemInfo username];
    }
    @catch (NSException *exception) {
        NSLog(@"Failed to get username: %@", exception);
        return nil;
    }
}

- (NSString *)safeGetOSVersion {
    @try {
        return [ZSystemInfo osVersion];
    }
    @catch (NSException *exception) {
        NSLog(@"Failed to get OS version: %@", exception);
        return nil;
    }
}

- (void)dealloc {
    [self stop];
}

#pragma mark - Public Methods

- (void)start {
    @try {
        dispatch_async(self.eventQueue, ^{
            if (self.isRunning) {
                NSLog(@"Beacon is already running.");
                return;
            }
            
            NSLog(@"Starting beacon with ID: %@", self.beaconId);
            self.running = YES;
            self.retryCount = 0;
            self.retryDelay = kInitialRetryDelay;
            
            // Register with server
            [self registerWithServer];
        });
    }
    @catch (NSException *exception) {
        NSLog(@"Exception during beacon start: %@", exception);
    }
}

- (void)stop {
    @try {
        dispatch_async(self.eventQueue, ^{
            if (!self.isRunning) {
                return;
            }
            
            NSLog(@"Stopping beacon: %@", self.beaconId);
            
            // Invalidate and release timer on main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.pingTimer) {
                    [self.pingTimer invalidate];
                    self.pingTimer = nil;
                }
            });
            
            self.status = @"offline";
            self.running = NO;
        });
    }
    @catch (NSException *exception) {
        NSLog(@"Exception during beacon stop: %@", exception);
    }
}

#pragma mark - Private Methods

- (void)registerWithServer {
    @try {
        NSLog(@"Registering beacon with server...");
        
        // Prepare registration data
        NSDictionary *registrationData = @{
            @"client_id": self.beaconId,
            @"hostname": self.hostname ?: [NSNull null],
            @"username": self.username ?: [NSNull null],
            @"os_version": self.osVersion ?: [NSNull null]
        };
        
        // Log registration data
        NSLog(@"Registration data: %@", registrationData);
        
        // Send init request to server
        [self.apiClient sendInitRequestWithData:registrationData completion:^(NSDictionary *response, NSError *error) {
            if (error) {
                NSLog(@"Error registering beacon: %@", error.localizedDescription);
                self.status = @"error";
                
                // Retry logic if we haven't exceeded the maximum retry attempts
                if (self.retryCount < kMaxRetryAttempts) {
                    self.retryCount++;
                    NSLog(@"Retrying registration in %.1f seconds (attempt %d of %d)...", 
                         self.retryDelay, self.retryCount, kMaxRetryAttempts);
                    
                    dispatch_time_t retryTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.retryDelay * NSEC_PER_SEC));
                    dispatch_after(retryTime, self.eventQueue, ^{
                        [self registerWithServer];
                    });
                    
                    // Increase retry delay with exponential backoff (up to max delay)
                    self.retryDelay = MIN(self.retryDelay * 2, kMaxRetryDelay);
                } else {
                    NSLog(@"Failed to register after %d attempts. Giving up.", kMaxRetryAttempts);
                }
                
                return;
            }
            
            // Registration successful, reset retry counters
            self.retryCount = 0;
            self.retryDelay = kInitialRetryDelay;
            
            NSLog(@"Beacon registered successfully: %@", response);
            self.status = @"online";
            self.lastSeen = [self currentTimestampString];
            
            // Start ping timer on main thread (every 60 seconds)
            dispatch_async(dispatch_get_main_queue(), ^{
                @try {
                    // Cancel any existing timer first
                    if (self.pingTimer) {
                        [self.pingTimer invalidate];
                        self.pingTimer = nil;
                    }
                    
                    // Create new timer
                    self.pingTimer = [NSTimer timerWithTimeInterval:60.0
                                                             target:self
                                                           selector:@selector(pingServer)
                                                           userInfo:nil
                                                            repeats:YES];
                    
                    // Add to run loop
                    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
                    [runLoop addTimer:self.pingTimer forMode:NSRunLoopCommonModes];
                    
                    // Send initial ping immediately
                    [self performSelector:@selector(pingServer) withObject:nil afterDelay:0.1];
                }
                @catch (NSException *exception) {
                    NSLog(@"Exception setting up ping timer: %@", exception);
                }
            });
        }];
    }
    @catch (NSException *exception) {
        NSLog(@"Exception during registration: %@", exception);
    }
}

- (void)pingServer {
    @try {
        if (!self.isRunning) {
            NSLog(@"Beacon is not running. Skipping ping.");
            return;
        }
        
        NSLog(@"Pinging server with beacon ID: %@", self.beaconId);
        
        // Prepare ping data
        NSDictionary *pingData = @{
            @"client_id": self.beaconId,
            @"status": self.status,
            @"timestamp": [self currentTimestampString]
        };
        
        // Send ping request to server
        [self.apiClient sendPingRequestWithData:pingData completion:^(NSDictionary *response, NSError *error) {
            if (error) {
                NSLog(@"Error pinging server: %@", error.localizedDescription);
                return;
            }
            
            NSLog(@"Ping successful: %@", response);
            self.lastSeen = [self currentTimestampString];
        }];
    }
    @catch (NSException *exception) {
        NSLog(@"Exception during ping: %@", exception);
    }
}

- (NSString *)currentTimestampString {
    @try {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
        [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
        return [formatter stringFromDate:[NSDate date]];
    }
    @catch (NSException *exception) {
        NSLog(@"Exception generating timestamp: %@", exception);
        return @"1970-01-01T00:00:00Z"; // Return a default timestamp if there's an error
    }
}

@end 