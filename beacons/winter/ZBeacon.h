#import <Foundation/Foundation.h>

// Forward declarations
@class ZAPIClient;
@class ZBeacon;
@protocol ZBeaconDelegate;
@class ZCommandService;
@class ZCommandModel;

/**
 * ZBeacon Configuration
 * Structure to hold beacon configuration options
 */
typedef struct
{
    NSTimeInterval pingInterval;        // Interval between pings (in seconds)
    NSTimeInterval initialRetryDelay;   // Initial delay before retrying a failed operation (in seconds)
    NSTimeInterval maxRetryDelay;       // Maximum delay for retries (in seconds)
    NSUInteger maxRetryAttempts;        // Maximum number of retry attempts
    NSTimeInterval commandPollInterval; // Interval between command polls (in seconds)
} ZBeaconConfiguration;

/**
 * Default configuration values
 */
extern const ZBeaconConfiguration ZBeaconDefaultConfiguration;

/**
 * ZBeaconDelegate protocol
 * Implement this protocol to receive beacon events
 */
@protocol ZBeaconDelegate
@optional
/**
 * Called when the beacon's status changes
 * @param beacon The beacon instance
 * @param status The new status
 */
- (void)beacon:(ZBeacon *)beacon didChangeStatus:(NSString *)status;

/**
 * Called when the beacon successfully registers with the server
 * @param beacon The beacon instance
 * @param response The server response
 */
- (void)beacon:(ZBeacon *)beacon didRegisterWithResponse:(NSDictionary *)response;

/**
 * Called when the beacon fails to register with the server
 * @param beacon The beacon instance
 * @param error The error that occurred
 * @param willRetry Whether the beacon will retry registration
 */
- (void)beacon:(ZBeacon *)beacon didFailToRegisterWithError:(NSError *)error willRetry:(BOOL)willRetry;

/**
 * Called when the beacon successfully pings the server
 * @param beacon The beacon instance
 * @param response The server response
 */
- (void)beacon:(ZBeacon *)beacon didPingWithResponse:(NSDictionary *)response;

/**
 * Called when the beacon fails to ping the server
 * @param beacon The beacon instance
 * @param error The error that occurred
 */
- (void)beacon:(ZBeacon *)beacon didFailToPingWithError:(NSError *)error;

/**
 * Called when the beacon receives a command from the server
 * @param beacon The beacon instance
 * @param command The received command
 */
- (void)beacon:(ZBeacon *)beacon didReceiveCommand:(ZCommandModel *)command;

/**
 * Called when the beacon completes a command execution
 * @param beacon The beacon instance
 * @param command The executed command
 * @param result The command execution result
 */
- (void)beacon:(ZBeacon *)beacon didExecuteCommand:(ZCommandModel *)command withResult:(id)result;

/**
 * Called when the beacon fails to execute a command
 * @param beacon The beacon instance
 * @param command The command that failed
 * @param error The error that occurred
 */
- (void)beacon:(ZBeacon *)beacon didFailToExecuteCommand:(ZCommandModel *)command withError:(NSError *)error;

@end

/**
 * ZBeacon - Main class for the beacon implementation
 * Handles registration with the server and maintains a communication loop
 */
@interface ZBeacon : NSObject

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

/// The server URL
@property(nonatomic, retain) NSURL *serverURL;

/// The command service used by the beacon
@property(nonatomic, readonly) ZCommandService *commandService;

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

/**
 * Register a command handler
 * @param commandType The type of command to handle
 * @param handlerClass The class of the handler to register
 * @return YES if registration was successful, NO otherwise
 */
- (BOOL)registerCommandHandler:(NSString *)commandType handlerClass:(Class)handlerClass;

/**
 * Force a poll for commands
 */
- (void)pollForCommands;

@end
