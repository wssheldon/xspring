#import "ZAPIClient.h"
#import "ZSSLBypass.h"

// Route definitions
static NSString * const kInitEndpoint = @"/beacon/init";
static NSString * const kPingEndpoint = @"/";

// Protocol byte constants (based on the server's expectations)
static const uint8_t kProtocolVersion = 0x01;
static const uint8_t kCommandInit = 0x02;
static const uint8_t kCommandPing = 0x01;

@interface ZAPIClient () <NSURLSessionDelegate>

@property (nonatomic, strong, readwrite) NSURL *serverURL;
@property (nonatomic, strong) NSURLSession *session;

@end

@implementation ZAPIClient

- (instancetype)initWithServerURL:(NSURL *)serverURL {
    self = [super init];
    if (self) {
        if (!serverURL) {
            NSLog(@"Error: Cannot initialize ZAPIClient with nil serverURL");
            return nil;
        }
        
        _serverURL = serverURL;
        _sslBypassEnabled = YES; // Enable SSL bypass by default
        
        NSLog(@"Initializing ZAPIClient with server URL: %@", serverURL);
        
        // Create URL session with custom configuration
        [self configureURLSession];
    }
    return self;
}

#pragma mark - Public Methods

- (void)sendInitRequestWithData:(NSDictionary *)data
                     completion:(void (^)(NSDictionary *response, NSError *error))completion {
    NSLog(@"Sending init request with data: %@", data);
    
    @try {
        // Convert to binary protocol format
        NSData *protocolData = [self createProtocolDataWithCommand:kCommandInit jsonData:data];
        
        if (!protocolData) {
            NSError *error = [NSError errorWithDomain:@"ZAPIClientErrorDomain"
                                                 code:-1
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to create protocol data for init request"}];
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        
        [self sendRequestToEndpoint:kInitEndpoint
                          withData:protocolData
                        httpMethod:@"POST"
                        completion:completion];
    }
    @catch (NSException *exception) {
        NSLog(@"Exception while creating init request: %@", exception);
        NSError *error = [NSError errorWithDomain:@"ZAPIClientErrorDomain"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: [exception reason]}];
        if (completion) {
            completion(nil, error);
        }
    }
}

- (void)sendPingRequestWithData:(NSDictionary *)data
                     completion:(void (^)(NSDictionary *response, NSError *error))completion {
    NSLog(@"Sending ping request with data: %@", data);
    
    @try {
        // Convert to binary protocol format
        NSData *protocolData = [self createProtocolDataWithCommand:kCommandPing jsonData:data];
        
        if (!protocolData) {
            NSError *error = [NSError errorWithDomain:@"ZAPIClientErrorDomain"
                                                 code:-1
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to create protocol data for ping request"}];
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        
        [self sendRequestToEndpoint:kPingEndpoint
                          withData:protocolData
                        httpMethod:@"POST"
                        completion:completion];
    }
    @catch (NSException *exception) {
        NSLog(@"Exception while creating ping request: %@", exception);
        NSError *error = [NSError errorWithDomain:@"ZAPIClientErrorDomain"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: [exception reason]}];
        if (completion) {
            completion(nil, error);
        }
    }
}

#pragma mark - Private Methods

- (NSData *)createProtocolDataWithCommand:(uint8_t)command jsonData:(NSDictionary *)jsonData {
    @try {
        if (!jsonData) {
            NSLog(@"Error: jsonData is nil");
            return nil;
        }
        
        // Build a text-based protocol message instead of binary
        NSMutableString *protocolMessage = [NSMutableString new];
        
        // Add version line
        [protocolMessage appendFormat:@"Version: %d\n", kProtocolVersion];
        
        // Add command/message type line
        [protocolMessage appendFormat:@"Type: %d\n", command];
        
        // Now add each field from the JSON data
        for (NSString *key in jsonData) {
            id value = jsonData[key];
            // Convert any non-string values to string
            NSString *stringValue;
            if ([value isKindOfClass:[NSString class]]) {
                stringValue = value;
            } else if ([value isKindOfClass:[NSNull class]]) {
                stringValue = @"";
            } else {
                stringValue = [NSString stringWithFormat:@"%@", value];
            }
            
            [protocolMessage appendFormat:@"%@: %@\n", key, stringValue];
        }
        
        NSLog(@"Created protocol message:\n%@", protocolMessage);
        
        // Convert the string to NSData using UTF8 encoding
        NSData *protocolData = [protocolMessage dataUsingEncoding:NSUTF8StringEncoding];
        if (!protocolData) {
            NSLog(@"Failed to convert protocol message to data");
            return nil;
        }
        
        return protocolData;
    }
    @catch (NSException *exception) {
        NSLog(@"Exception in createProtocolDataWithCommand: %@", exception);
        return nil;
    }
}

- (void)configureURLSession {
    // Create a session configuration
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.timeoutIntervalForRequest = 30.0;
    configuration.timeoutIntervalForResource = 60.0;
    
    NSLog(@"Configuring URL session for server: %@", self.serverURL);
    
    // Create a session with the configuration and self as delegate for SSL handling
    self.session = [NSURLSession sessionWithConfiguration:configuration
                                                delegate:self
                                           delegateQueue:nil];
}

- (void)sendRequestToEndpoint:(NSString *)endpoint
                     withData:(NSData *)data
                   httpMethod:(NSString *)httpMethod
                   completion:(void (^)(NSDictionary *response, NSError *error))completion {
    @try {
        // Create URL for the request
        NSURL *url = [NSURL URLWithString:endpoint relativeToURL:self.serverURL];
        
        if (!url) {
            NSError *error = [NSError errorWithDomain:@"ZAPIClientErrorDomain"
                                                 code:-1
                                             userInfo:@{
                                                 NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to create URL with endpoint: %@", endpoint]
                                             }];
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        
        NSLog(@"Sending %@ request to: %@", httpMethod, url);
        
        // Create request
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = httpMethod;
        // Change content type to text/plain since we're now sending text format
        [request setValue:@"text/plain" forHTTPHeaderField:@"Content-Type"];
        
        if (!data) {
            NSError *error = [NSError errorWithDomain:@"ZAPIClientErrorDomain"
                                                 code:-1
                                             userInfo:@{
                                                 NSLocalizedDescriptionKey: @"Failed to create protocol data"
                                             }];
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        
        request.HTTPBody = data;
        
        // Create and start data task
        NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                     completionHandler:^(NSData *responseData, NSURLResponse *response, NSError *error) {
            if (error) {
                NSLog(@"Network error: %@", error);
                if (completion) {
                    completion(nil, error);
                }
                return;
            }
            
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSLog(@"Response status code: %ld", (long)httpResponse.statusCode);
            
            if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
                NSString *responseBody = responseData ? [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] : @"No response body";
                NSLog(@"HTTP error with body: %@", responseBody);
                
                NSError *httpError = [NSError errorWithDomain:@"ZAPIClientErrorDomain"
                                                        code:httpResponse.statusCode
                                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP Error: %ld", (long)httpResponse.statusCode]}];
                if (completion) {
                    completion(nil, httpError);
                }
                return;
            }
            
            // Parse response data
            if (responseData && responseData.length > 0) {
                // Log response data as string for text-based protocol
                NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
                NSLog(@"Raw response data (%lu bytes):\n%@", 
                      (unsigned long)responseData.length,
                      responseString ?: @"[Non-UTF8 data]");
                
                // First try to parse as our protocol format
                NSDictionary *parsedResponse = [self parseProtocolResponse:responseData];
                if (parsedResponse) {
                    NSLog(@"Successfully parsed protocol response");
                    if (completion) {
                        completion(parsedResponse, nil);
                    }
                    return;
                }
                
                // If protocol parsing fails, try JSON
                NSError *parseError;
                id jsonObject = nil;
                @try {
                    jsonObject = [NSJSONSerialization JSONObjectWithData:responseData
                                                               options:0
                                                                 error:&parseError];
                }
                @catch (NSException *exception) {
                    NSLog(@"Exception parsing JSON: %@", exception);
                    parseError = [NSError errorWithDomain:@"ZAPIClientErrorDomain"
                                                   code:-1
                                               userInfo:@{NSLocalizedDescriptionKey: [exception reason]}];
                }
                
                if (!parseError && jsonObject && [jsonObject isKindOfClass:[NSDictionary class]]) {
                    NSLog(@"Parsed JSON response: %@", jsonObject);
                    if (completion) {
                        completion(jsonObject, nil);
                    }
                    return;
                }
                
                // If all parsing fails, return a simple success with the response string
                NSLog(@"Could not parse response data as protocol or JSON, returning raw response");
                if (completion) {
                    completion(@{
                        @"status": @"success",
                        @"response": responseString ?: @"[binary data]"
                    }, nil);
                }
            } else {
                // No data in response
                NSLog(@"No data in response, returning empty success");
                if (completion) {
                    completion(@{@"status": @"success"}, nil);
                }
            }
        }];
        
        [task resume];
    }
    @catch (NSException *exception) {
        NSLog(@"Exception in sendRequestToEndpoint: %@", exception);
        NSError *error = [NSError errorWithDomain:@"ZAPIClientErrorDomain"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: [exception reason]}];
        if (completion) {
            completion(nil, error);
        }
    }
}

#pragma mark - NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    NSLog(@"Received authentication challenge for host: %@", challenge.protectionSpace.host);
    
    if (self.sslBypassEnabled) {
        // Use SSL bypass for server certificate validation
        [ZSSLBypass handleAuthenticationChallenge:challenge completionHandler:completionHandler];
    } else {
        // Use default handling
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

- (NSDictionary *)parseProtocolResponse:(NSData *)responseData {
    @try {
        if (!responseData) {
            return nil;
        }
        
        // Convert data to string
        NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
        if (!responseString) {
            NSLog(@"Could not convert response data to string");
            return nil;
        }
        
        // Parse the text protocol format
        NSMutableDictionary *resultDict = [NSMutableDictionary dictionary];
        NSScanner *scanner = [NSScanner scannerWithString:responseString];
        
        NSString *line;
        while ([scanner scanUpToCharactersFromSet:[NSCharacterSet newlineCharacterSet] intoString:&line]) {
            // Skip the newline character
            [scanner scanCharactersFromSet:[NSCharacterSet newlineCharacterSet] intoString:NULL];
            
            // Skip empty lines
            if (line.length == 0) {
                continue;
            }
            
            // Look for key-value format (Key: Value)
            NSRange colonRange = [line rangeOfString:@":"];
            if (colonRange.location != NSNotFound) {
                NSString *key = [line substringToIndex:colonRange.location];
                NSString *value = @"";
                
                // If there's content after the colon
                if (colonRange.location + 1 < line.length) {
                    value = [[line substringFromIndex:colonRange.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                }
                
                // Special handling for version and message type
                if ([key isEqualToString:@"Version"]) {
                    resultDict[@"version"] = @([value intValue]);
                } else if ([key isEqualToString:@"Type"]) {
                    resultDict[@"msg_type"] = @([value intValue]);
                } else {
                    resultDict[key] = value;
                }
            }
        }
        
        NSLog(@"Parsed protocol response: %@", resultDict);
        return resultDict;
    }
    @catch (NSException *exception) {
        NSLog(@"Exception parsing protocol response: %@", exception);
        return nil;
    }
}

@end 