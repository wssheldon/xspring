#import <Foundation/Foundation.h>

// Forward declarations
@class ZAPIClient;
@protocol ZBeaconDelegate;

/**
 * ZBeacon - Main class for the beacon implementation
 * Handles registration with the server and maintains a communication loop
 */
@interface ZBeacon : NSObject

/**
 * Configuration struct for beacon settings
 */
typedef struct
{
    NSTimeInterval pingInterval;      // Time between pings in seconds (default: 60)
    NSTimeInterval initialRetryDelay; // Initial delay before retry (default: 5)
    NSTimeInterval maxRetryDelay;     // Maximum delay between retries (default: 60)
    NSUInteger maxRetryAttempts;      // Maximum number of retry attempts (default: 5)
} ZBeaconConfiguration;

/**
 * Default configuration for the beacon
 * @return A configuration struct with default values
 */
+ (ZBeaconConfiguration)defaultConfiguration;

#pragma mark - Properties

/// Unique identifier for this beacon
@property(nonatomic, copy, readonly) NSString *beaconId;

/// Last time the beacon communicated with the server
@property(nonatomic, copy, readonly) NSString *lastSeen;

/// Current status of the beacon
@property(nonatomic, copy, readonly) NSString *status;

/// Hostname of the machine running the beacon
@property(nonatomic, copy, readonly) NSString *hostname;

/// Username of the user running the beacon
@property(nonatomic, copy, readonly) NSString *username;

/// OS version of the machine running the beacon
@property(nonatomic, copy, readonly) NSString *osVersion;

/// API client for communicating with the server
@property(nonatomic, strong, readonly) ZAPIClient *apiClient;

/// Flag indicating whether the beacon is running
@property(nonatomic, assign, readonly, getter=isRunning) BOOL running;

/// Delegate for beacon events - NOTE: NOT retained by the beacon
@property(nonatomic, assign) id<ZBeaconDelegate> delegate;

/// Configuration options
@property(nonatomic, assign, readonly) ZBeaconConfiguration configuration;

#pragma mark - Lifecycle

/**
 * Initialize a new beacon with the given server URL and default configuration
 * @param serverURL The URL of the server to connect to
 * @return A new beacon instance
 */
- (instancetype)initWithServerURL:(NSURL *)serverURL;

/**
 * Initialize a new beacon with the given server URL and custom configuration
 * @param serverURL The URL of the server to connect to
 * @param configuration Custom configuration options
 * @return A new beacon instance
 */
- (instancetype)initWithServerURL:(NSURL *)serverURL
                    configuration:(ZBeaconConfiguration)configuration;

/**
 * Unavailable initializer
 */
- (instancetype)init;

#pragma mark - Control Methods

/**
 * Start the beacon's operation
 * This will register with the server and begin the event loop
 * @return YES if the beacon started successfully, NO otherwise
 */
- (BOOL)start;

/**
 * Stop the beacon's operation
 */
- (void)stop;

/**
 * Force an immediate ping to the server
 * @return YES if the ping was sent, NO if the beacon is not running
 */
- (BOOL)forcePing;

@end

/**
 * Delegate protocol for beacon events
 */
@protocol ZBeaconDelegate <NSObject>
@optional

/**
 * Called when the beacon successfully registers with the server
 * @param beacon The beacon that registered
 * @param response The server response
 */
- (void)beacon:(ZBeacon *)beacon didRegisterWithResponse:(NSDictionary *)response;

/**
 * Called when the beacon fails to register with the server
 * @param beacon The beacon that failed
 * @param error The error that occurred
 * @param willRetry Whether the beacon will retry registration
 */
- (void)beacon:(ZBeacon *)beacon didFailToRegisterWithError:(NSError *)error willRetry:(BOOL)willRetry;

/**
 * Called when the beacon successfully pings the server
 * @param beacon The beacon that pinged
 * @param response The server response
 */
- (void)beacon:(ZBeacon *)beacon didPingWithResponse:(NSDictionary *)response;

/**
 * Called when the beacon fails to ping the server
 * @param beacon The beacon that failed
 * @param error The error that occurred
 */
- (void)beacon:(ZBeacon *)beacon didFailToPingWithError:(NSError *)error;

/**
 * Called when the beacon's status changes
 * @param beacon The beacon whose status changed
 * @param status The new status
 */
- (void)beacon:(ZBeacon *)beacon didChangeStatus:(NSString *)status;

@end
