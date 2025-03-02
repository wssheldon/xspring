#import <Foundation/Foundation.h>

/**
 * ZSSLBypass - Handles SSL certificate validation bypass
 * Used to allow connections to servers with self-signed or invalid certificates
 */
@interface ZSSLBypass : NSObject

/**
 * Handle an authentication challenge by bypassing SSL certificate validation
 * @param challenge The authentication challenge
 * @param completionHandler The completion handler to call when the challenge has been handled
 */
+ (void)handleAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
                    completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler;

@end