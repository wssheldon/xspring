#import <Foundation/Foundation.h>

/**
 * ZAPIClient - Handles API communication with the server
 * Implements SSL bypass and necessary API endpoints
 */
@interface ZAPIClient : NSObject

/// The server URL
@property(nonatomic, strong, readonly) NSURL *serverURL;

/// Whether to use SSL bypass
@property(nonatomic, assign) BOOL sslBypassEnabled;

/**
 * Initialize a new API client with the given server URL
 * @param serverURL The URL of the server to connect to
 * @return A new API client instance
 */
- (instancetype)initWithServerURL:(NSURL *)serverURL;

/**
 * Send an initialization request to the server
 * @param data The data to send in the request
 * @param completion Block to be executed when the request completes
 */
- (void)sendInitRequestWithData:(NSDictionary *)data
                     completion:(void (^)(NSDictionary *response, NSError *error))completion;

/**
 * Send a ping request to the server
 * @param data The data to send in the request
 * @param completion Block to be executed when the request completes
 */
- (void)sendPingRequestWithData:(NSDictionary *)data
                     completion:(void (^)(NSDictionary *response, NSError *error))completion;

@end