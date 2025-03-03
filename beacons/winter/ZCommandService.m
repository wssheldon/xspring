#import "ZCommandService.h"
#import "ZCommandRegistry.h"
#import "ZAPIClient.h"

// Error domains and codes
static NSString *const ZCommandServiceErrorDomain = @"ZCommandServiceErrorDomain";
static const NSInteger __unused ZCommandServiceErrorInvalidURL = 301;
static const NSInteger __unused ZCommandServiceErrorInvalidResponse = 302;
static const NSInteger ZCommandServiceErrorNetworkError = 303;
static const NSInteger __unused ZCommandServiceErrorBeaconNotRegistered = 304;

// API paths
static NSString *const kCommandPollPath = @"/beacon/poll";
static NSString *const kCommandResponsePath = @"/beacon/response";

@interface ZCommandService ()
@property (nonatomic, retain) NSURL *serverURL;
@property (nonatomic, retain) NSString *beaconId;
@property (nonatomic, retain) NSMutableDictionary *pendingCommands;
@property (nonatomic, retain) NSMutableDictionary *commandTimers;
@property (nonatomic, retain) dispatch_source_t pollTimer;
@property (nonatomic, retain) dispatch_queue_t serviceQueue;
@property (nonatomic, assign) BOOL isPolling;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, strong, readwrite) ZAPIClient *apiClient;
@end

@implementation ZCommandService

#pragma mark - Initialization

- (instancetype)initWithServerURL:(NSURL *)serverURL {
    return [self initWithServerURL:serverURL beaconId:nil];
}

- (instancetype)initWithServerURL:(NSURL *)serverURL beaconId:(NSString *)beaconId {
    self = [super init];
    if (self) {
        self.serverURL = [serverURL retain];
        self.beaconId = [beaconId retain];
        self.pendingCommands = [[NSMutableDictionary alloc] init];
        self.commandTimers = [[NSMutableDictionary alloc] init];
        self.serviceQueue = dispatch_queue_create("com.zapit.beacon.commandservice", 0);
        self.isPolling = NO;
        self.isRunning = NO;
        
        // Create API client with SSL bypass
        self.apiClient = [[ZAPIClient alloc] initWithServerURL:serverURL];
        self.apiClient.sslBypassEnabled = YES;
        
        // Default intervals - decrease polling interval for better responsiveness
        self.pollInterval = 5.0; // 5 seconds instead of 60 seconds
        self.commandTimeout = 300.0; // 5 minutes
    }
    return self;
}

- (void)dealloc {
    [self stop];
    
    [_serverURL release];
    [_beaconId release];
    [_pendingCommands release];
    [_commandTimers release];
    [_apiClient release];
    
    if (_serviceQueue) {
        dispatch_release(_serviceQueue);
    }
    
    [super dealloc];
}

#pragma mark - Public methods

- (BOOL)start {
    if (self.isRunning) {
        NSLog(@"Command service is already running");
        return YES;
    }
    
    if (!self.serverURL) {
        NSLog(@"Cannot start command service: server URL is nil");
        return NO;
    }
    
    if (!self.beaconId || [self.beaconId length] == 0) {
        NSLog(@"Cannot start command service: beacon ID is nil or empty");
        return NO;
    }
    
    self.isRunning = YES;
    
    // Start polling
    [self startPollingTimer];
    
    // Poll immediately
    [self pollNow];
    
    return YES;
}

- (void)stop {
    if (!self.isRunning) {
        return;
    }
    
    [self stopPollingTimer];
    
    // Cancel all command timers
    for (NSString *commandId in [self.commandTimers allKeys]) {
        dispatch_source_t timer = [self.commandTimers objectForKey:commandId];
        dispatch_source_cancel(timer);
    }
    [self.commandTimers removeAllObjects];
    
    self.isRunning = NO;
}

- (void)pollNow {
    if (!self.isRunning) {
        NSLog(@"Cannot poll: command service is not running");
        return;
    }
    
    if (self.isPolling) {
        NSLog(@"Already polling for commands, skipping");
        return;
    }
    
    self.isPolling = YES;
    
    dispatch_async(self.serviceQueue, ^{
        [self pollForCommandsInternal];
    });
}

- (void)reportCommand:(ZCommandModel *)command 
               result:(NSDictionary *)result 
                error:(NSError *)error {
    if (!command) {
        NSLog(@"Cannot report nil command");
        return;
    }
    
    if (!self.isRunning) {
        NSLog(@"Cannot report command: command service is not running");
        return;
    }
    
    dispatch_async(self.serviceQueue, ^{
        [self reportCommandInternal:command result:result error:error];
    });
}

#pragma mark - Private methods

- (void)startPollingTimer {
    if (self.pollTimer) {
        dispatch_source_cancel(self.pollTimer);
        dispatch_release(self.pollTimer);
        self.pollTimer = nil;
    }
    
    self.pollTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.serviceQueue);
    
    uint64_t interval = (uint64_t)(self.pollInterval * NSEC_PER_SEC);
    dispatch_source_set_timer(self.pollTimer, dispatch_time(DISPATCH_TIME_NOW, interval), interval, 1 * NSEC_PER_SEC);
    
    __block ZCommandService *blockSelf = self;
    dispatch_source_set_event_handler(self.pollTimer, ^{
        [blockSelf pollForCommandsInternal];
    });
    
    dispatch_resume(self.pollTimer);
}

- (void)stopPollingTimer {
    if (self.pollTimer) {
        dispatch_source_cancel(self.pollTimer);
        dispatch_release(self.pollTimer);
        self.pollTimer = nil;
    }
}

- (void)pollForCommandsInternal {
    if (!self.beaconId || [self.beaconId length] == 0) {
        NSLog(@"Cannot poll for commands: beacon ID is nil or empty");
        self.isPolling = NO;
        return;
    }
    
    // Create the poll URL
    NSString *pollURLString = [NSString stringWithFormat:@"%@%@/%@", 
                               [self.serverURL absoluteString], 
                               kCommandPollPath,
                               self.beaconId];
    NSURL *pollURL = [NSURL URLWithString:pollURLString];
    
    if (!pollURL) {
        NSLog(@"Failed to create poll URL from string: %@", pollURLString);
        self.isPolling = NO;
        return;
    }
    
    NSLog(@"Polling for commands at: %@", pollURLString);
    
    // Create the request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:pollURL];
    [request setHTTPMethod:@"GET"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    
    // Create a semaphore to make this synchronous
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    __block NSData *responseData = nil;
    __block NSHTTPURLResponse *httpResponse = nil;
    __block NSError *connectionError = nil;
    
    // Use NSURLSessionDataTask with delegate for SSL handling
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config 
                                                         delegate:(id<NSURLSessionDelegate>)self.apiClient
                                                    delegateQueue:nil];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request 
                                          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        responseData = [data retain];
        httpResponse = [(NSHTTPURLResponse *)response retain];
        connectionError = [error retain];
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];
    
    // Wait for the request to complete
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    dispatch_release(semaphore);
    
    if (connectionError) {
        NSLog(@"Error polling for commands: %@", [connectionError localizedDescription]);
        self.isPolling = NO;
        [responseData release];
        [httpResponse release];
        [connectionError release];
        return;
    }
    
    if (httpResponse.statusCode != 200) {
        NSLog(@"Error polling for commands: HTTP status code %ld", (long)httpResponse.statusCode);
        self.isPolling = NO;
        [responseData release];
        [httpResponse release];
        [connectionError release];
        return;
    }
    
    if (httpResponse.statusCode == 204) {
        // No commands available
        self.isPolling = NO;
        [responseData release];
        [httpResponse release];
        [connectionError release];
        return;
    }
    
    // Convert data to string
    NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
    [responseData release];
    [httpResponse release];
    [connectionError release];
    
    if (!responseString) {
        NSLog(@"Error parsing command poll response: could not convert to string");
        self.isPolling = NO;
        [responseString release];
        return;
    }
    
    NSLog(@"Received command poll response: %@", responseString);
    
    // Parse the protocol message
    NSMutableDictionary *commandDict = [NSMutableDictionary dictionary];
    NSArray *lines = [responseString componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSArray *parts = [line componentsSeparatedByString:@": "];
        if ([parts count] >= 2) {
            NSString *key = [parts objectAtIndex:0];
            NSString *value = [[parts subarrayWithRange:NSMakeRange(1, [parts count] - 1)] componentsJoinedByString:@": "];
            
            // Skip Type and Version headers
            if (![key isEqualToString:@"Version"] && ![key isEqualToString:@"Type"]) {
                [commandDict setObject:value forKey:key];
            }
        }
    }
    
    [responseString release];
    
    // Check if we have a valid command
    if ([commandDict count] > 0 && [commandDict objectForKey:@"id"] && [commandDict objectForKey:@"command"]) {
        ZCommandModel *command = [[[ZCommandModel alloc] initWithDictionary:commandDict] autorelease];
        if (command) {
            // Add to pending commands
            [self.pendingCommands setObject:command forKey:[command commandId]];
            
            // Start a timeout timer for the command
            [self startTimeoutTimerForCommand:command];
            
            // Notify delegate
            if (self.delegate && [self.delegate respondsToSelector:@selector(commandService:didReceiveCommand:)]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate commandService:self didReceiveCommand:command];
                });
            }
            
            // Execute the command
            ZCommandRegistry *registry = [ZCommandRegistry sharedRegistry];
            [registry executeCommand:command completion:^(BOOL __unused success, NSDictionary *cmdResult, NSError *cmdError) {
                [self reportCommand:command result:cmdResult error:cmdError];
            }];
        }
    } else {
        NSLog(@"Received invalid command format");
    }
    
    self.isPolling = NO;
}

- (void)startTimeoutTimerForCommand:(ZCommandModel *)command {
    NSString *commandId = [command commandId];
    
    // Cancel existing timer if any
    dispatch_source_t existingTimer = [self.commandTimers objectForKey:commandId];
    if (existingTimer) {
        dispatch_source_cancel(existingTimer);
        [self.commandTimers removeObjectForKey:commandId];
    }
    
    // Create a new timer
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.serviceQueue);
    
    uint64_t timeout = (uint64_t)(self.commandTimeout * NSEC_PER_SEC);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, timeout), DISPATCH_TIME_FOREVER, 1 * NSEC_PER_SEC);
    
    __block ZCommandService *blockSelf = self;
    __block NSString *blockCommandId = [[commandId retain] autorelease];
    
    dispatch_source_set_event_handler(timer, ^{
        // Handle command timeout
        ZCommandModel *cmd = [blockSelf.pendingCommands objectForKey:blockCommandId];
        if (cmd) {
            [cmd setStatus:ZCommandStatusTimedOut];
            
            // Report timeout to server
            NSDictionary *result = [NSDictionary dictionaryWithObject:@"Command timed out" forKey:@"message"];
            NSError *timeoutError = [NSError errorWithDomain:ZCommandServiceErrorDomain
                                                        code:305
                                                    userInfo:[NSDictionary dictionaryWithObject:@"Command timed out" 
                                                                                         forKey:NSLocalizedDescriptionKey]];
            [blockSelf reportCommandInternal:cmd result:result error:timeoutError];
            
            // Remove from pending commands
            [blockSelf.pendingCommands removeObjectForKey:blockCommandId];
        }
        
        // Cancel and remove the timer
        dispatch_source_t cmdTimer = [blockSelf.commandTimers objectForKey:blockCommandId];
        if (cmdTimer) {
            dispatch_source_cancel(cmdTimer);
            [blockSelf.commandTimers removeObjectForKey:blockCommandId];
        }
    });
    
    // Store the timer
    [self.commandTimers setObject:timer forKey:commandId];
    
    // Start the timer
    dispatch_resume(timer);
}

- (void)reportCommandInternal:(ZCommandModel *)command 
                       result:(NSDictionary *)result 
                        error:(NSError *)error {
    if (!command) {
        return;
    }
    
    NSString *commandId = [command commandId];
    
    // Update command status if not already set
    if ([command status] == ZCommandStatusPending || [command status] == ZCommandStatusInProgress) {
        [command setStatus:error ? ZCommandStatusFailed : ZCommandStatusCompleted];
    }
    
    // Create the response URL
    // Try to convert command ID to integer if possible (server might expect numeric ID)
    NSInteger numericCommandId = [commandId integerValue];
    NSString *commandIdStr = numericCommandId > 0 ? [NSString stringWithFormat:@"%ld", (long)numericCommandId] : commandId;
    
    NSString *responseURLString = [NSString stringWithFormat:@"%@%@/%@/%@", 
                                  [self.serverURL absoluteString], 
                                  kCommandResponsePath,
                                  self.beaconId,
                                  commandIdStr];
    NSURL *responseURL = [NSURL URLWithString:responseURLString];
    
    if (!responseURL) {
        NSLog(@"Failed to create response URL from string: %@", responseURLString);
        return;
    }

    NSLog(@"Reporting command response to: %@", responseURLString);

    // Create the request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:responseURL];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"text/plain" forHTTPHeaderField:@"Content-Type"];
    
    // Set the status
    NSString *statusString = @"completed";
    switch ([command status]) {
        case ZCommandStatusPending:
            statusString = @"pending";
            break;
        case ZCommandStatusInProgress:
            statusString = @"in_progress";
            break;
        case ZCommandStatusCompleted:
            statusString = @"completed";
            break;
        case ZCommandStatusFailed:
            statusString = @"failed";
            break;
        case ZCommandStatusTimedOut:
            statusString = @"timed_out";
            break;
    }
    
    // Create the protocol message
    NSMutableString *protocolMessage = [NSMutableString string];
    [protocolMessage appendString:@"Version: 1\n"];
    [protocolMessage appendString:@"Type: 5\n"];
    [protocolMessage appendFormat:@"id: %@\n", commandId];
    [protocolMessage appendFormat:@"status: %@\n", statusString];
    
    // Add result data if available
    if (result) {
        NSError *jsonError = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result options:0 error:&jsonError];
        if (!jsonError && jsonData) {
            NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            // Set the result directly without any transformation
            [protocolMessage appendFormat:@"result: %@\n", jsonString];
            [jsonString release];
        } else {
            // If JSON serialization fails, try to provide a simple string result
            NSString *fallbackResult = @"Command executed successfully";
            [protocolMessage appendFormat:@"result: \"%@\"\n", fallbackResult];
            NSLog(@"Warning: Could not serialize result to JSON: %@", [jsonError localizedDescription]);
        }
    } else {
        // Always provide a result field to satisfy the server's requirement
        [protocolMessage appendString:@"result: \"{}\"\n"];
    }
    
    // Add error information if available
    if (error) {
        [protocolMessage appendFormat:@"error: %@\n", [error localizedDescription]];
    }
    
    NSLog(@"Sending command response: %@", protocolMessage);
    
    // Set the request body
    NSData *bodyData = [protocolMessage dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody:bodyData];
    
    // Debug log the full request details
    NSLog(@"Command response details - URL: %@, Method: %@, Headers: %@, Body length: %lu", 
          [request URL], 
          [request HTTPMethod],
          [request allHTTPHeaderFields],
          (unsigned long)[bodyData length]);
    
    // Create a semaphore to make this synchronous
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    __block NSHTTPURLResponse *httpResponse = nil;
    __block NSError *connectionError = nil;
    
    // Use NSURLSessionDataTask with delegate for SSL handling
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config 
                                                         delegate:(id<NSURLSessionDelegate>)self.apiClient
                                                    delegateQueue:nil];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request 
                                           completionHandler:^(NSData * __unused data, NSURLResponse *response, NSError *error) {
        httpResponse = [(NSHTTPURLResponse *)response retain];
        connectionError = [error retain];
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];
    
    // Wait for the request to complete
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    dispatch_release(semaphore);
    
    if (connectionError) {
        NSLog(@"Error reporting command: %@", [connectionError localizedDescription]);
        
        // Notify delegate
        if (self.delegate && [self.delegate respondsToSelector:@selector(commandService:didFailToReportCommand:withError:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate commandService:self didFailToReportCommand:command withError:connectionError];
            });
        }
        
        [httpResponse release];
        [connectionError release];
        return;
    }
    
    if (httpResponse.statusCode != 200) {
        NSLog(@"Error reporting command: HTTP status code %ld", (long)httpResponse.statusCode);
        
        NSError *httpError = [NSError errorWithDomain:ZCommandServiceErrorDomain
                                                code:ZCommandServiceErrorNetworkError
                                            userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"HTTP Error: %ld", (long)httpResponse.statusCode]
                                                                               forKey:NSLocalizedDescriptionKey]];
        
        // Notify delegate
        if (self.delegate && [self.delegate respondsToSelector:@selector(commandService:didFailToReportCommand:withError:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate commandService:self didFailToReportCommand:command withError:httpError];
            });
        }
        
        [httpResponse release];
        [connectionError release];
        return;
    }
    
    [httpResponse release];
    [connectionError release];
    
    // Command reported successfully
    NSLog(@"Command %@ reported successfully with status: %@", commandId, statusString);
    
    // Remove the command from pending commands if it's completed or failed
    if ([command status] == ZCommandStatusCompleted || 
        [command status] == ZCommandStatusFailed || 
        [command status] == ZCommandStatusTimedOut) {
        [self.pendingCommands removeObjectForKey:commandId];
        
        // Cancel and remove the timer
        dispatch_source_t cmdTimer = [self.commandTimers objectForKey:commandId];
        if (cmdTimer) {
            dispatch_source_cancel(cmdTimer);
            [self.commandTimers removeObjectForKey:commandId];
        }
    }
    
    // Notify delegate
    if (self.delegate && [self.delegate respondsToSelector:@selector(commandService:didReportCommand:withResponse:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate commandService:self didReportCommand:command withResponse:result];
        });
    }
}

@end 