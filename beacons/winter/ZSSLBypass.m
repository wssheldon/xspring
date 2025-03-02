#import "ZSSLBypass.h"

@implementation ZSSLBypass

+ (void)handleAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
                    completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    
    // Only bypass SSL for server trust challenges
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSLog(@"SSL Bypass: Accepting certificate for %@", challenge.protectionSpace.host);
        
        // Create a credential with the server trust
        NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        
        // Accept the certificate
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
    } else {
        // For other challenge types, use default handling
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

@end 