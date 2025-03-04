#import "ZCommandReporter.h"
#import "ZCommandModel.h"
#import "ZAPIClient.h"

static NSString *const kCommandResponsePath = @"/beacon/response";

@interface ZCommandReporter ()

@property(nonatomic, retain) NSURL *serverURL;
@property(nonatomic, copy) NSString *beaconId;
@property(nonatomic, assign) dispatch_queue_t reporterQueue;
@property(nonatomic, retain) ZAPIClient *apiClient;

@end

@implementation ZCommandReporter

#pragma mark - Initialization

- (instancetype)initWithServerURL:(NSURL *)serverURL beaconId:(NSString *)beaconId {
    self = [super init];
    if (self) {
        self.serverURL = serverURL;
        self.beaconId = [beaconId copy];
        self.reporterQueue = dispatch_queue_create("com.zapit.beacon.commandreporter", 0);
        
        // Initialize API client with SSL bypass
        self.apiClient = [[ZAPIClient alloc] initWithServerURL:serverURL];
        self.apiClient.sslBypassEnabled = YES;
    }
    return self;
}

- (void)dealloc {
    [_serverURL release];
    [_beaconId release];
    [_apiClient release];
    
    if (_reporterQueue) {
        dispatch_release(_reporterQueue);
    }
    
    [super dealloc];
}

#pragma mark - Public Methods

- (void)reportCommand:(ZCommandModel *)command result:(NSDictionary *)result error:(NSError *)error {
    if (!command) {
        return;
    }
    
    // Retain objects that will be used in the block
    ZCommandModel *blockCommand = [command retain];
    NSDictionary *blockResult = [result retain];
    NSError *blockError = [error retain];
    
    dispatch_async(self.reporterQueue, ^{
        [self reportCommandInternal:blockCommand result:blockResult error:blockError];
        
        // Release retained objects
        [blockCommand release];
        [blockResult release];
        [blockError release];
    });
}

#pragma mark - Private Methods

- (void)reportCommandInternal:(ZCommandModel *)command result:(NSDictionary *)result error:(NSError *)error {
    // Create response URL
    NSString *commandId = [command commandId];
    NSInteger numericCommandId = [commandId integerValue];
    NSString *commandIdStr = numericCommandId > 0 ? 
        [NSString stringWithFormat:@"%ld", (long)numericCommandId] : commandId;
    
    NSString *responseURLString = [NSString stringWithFormat:@"%@%@/%@/%@",
                                 [self.serverURL absoluteString],
                                 kCommandResponsePath,
                                 self.beaconId,
                                 commandIdStr];
    NSURL *responseURL = [NSURL URLWithString:responseURLString];
    
    if (!responseURL) {
        NSError *urlError = [NSError errorWithDomain:@"ZCommandReporterErrorDomain"
                                              code:-1
                                          userInfo:@{NSLocalizedDescriptionKey: @"Invalid response URL"}];
        [self notifyDelegateOfError:urlError forCommand:command];
        return;
    }
    
    // Create request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:responseURL];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"text/plain" forHTTPHeaderField:@"Content-Type"];
    
    // Determine command status
    NSString *statusString = @"completed";
    if (error) {
        statusString = @"failed";
    }
    
    // Create protocol message
    NSMutableString *protocolMessage = [NSMutableString string];
    [protocolMessage appendString:@"Version: 1\n"];
    [protocolMessage appendString:@"Type: 5\n"];
    [protocolMessage appendFormat:@"id: %@\n", commandId];
    [protocolMessage appendFormat:@"status: %@\n", statusString];
    
    // Add result data
    if (result) {
        NSError *jsonError = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result options:0 error:&jsonError];
        if (!jsonError && jsonData) {
            NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            [protocolMessage appendFormat:@"result: %@\n", jsonString];
            [jsonString release];
        } else {
            [protocolMessage appendString:@"result: \"{}\"\n"];
            NSLog(@"Warning: Could not serialize result to JSON: %@", [jsonError localizedDescription]);
        }
    } else {
        [protocolMessage appendString:@"result: \"{}\"\n"];
    }
    
    // Add error information
    if (error) {
        [protocolMessage appendFormat:@"error: %@\n", [error localizedDescription]];
    }
    
    // Set request body
    NSData *bodyData = [protocolMessage dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody:bodyData];
    
    // Create semaphore for synchronous operation
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    __block NSHTTPURLResponse *httpResponse = nil;
    __block NSError *connectionError = nil;
    __block NSData *responseData = nil;
    
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
        [self notifyDelegateOfError:connectionError forCommand:command];
        [responseData release];
        [httpResponse release];
        [connectionError release];
        return;
    }
    
    if (httpResponse.statusCode != 200) {
        NSError *httpError = [NSError errorWithDomain:@"ZCommandReporterErrorDomain"
                                               code:-2
                                           userInfo:@{NSLocalizedDescriptionKey:
                                                        [NSString stringWithFormat:@"HTTP Error: %ld", (long)httpResponse.statusCode]}];
        [self notifyDelegateOfError:httpError forCommand:command];
        [responseData release];
        [httpResponse release];
        [connectionError release];
        return;
    }
    
    // Parse response if needed
    NSDictionary *response = nil;
    if (responseData) {
        NSError *jsonError = nil;
        response = [[NSJSONSerialization JSONObjectWithData:responseData
                                                  options:0
                                                    error:&jsonError] retain];
        if (jsonError) {
            NSLog(@"Warning: Could not parse response JSON: %@", [jsonError localizedDescription]);
        }
    }
    
    // Notify delegate of success
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate commandReporter:self didReportCommand:command withResponse:response];
        [response release];
    });
    
    [responseData release];
    [httpResponse release];
    [connectionError release];
}

- (void)notifyDelegateOfError:(NSError *)error forCommand:(ZCommandModel *)command {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate commandReporter:self didFailToReportCommand:command withError:error];
    });
}

@end 