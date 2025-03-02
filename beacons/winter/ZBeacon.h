#import <Foundation/Foundation.h>

// Forward declarations
@class ZAPIClient;

/**
 * ZBeacon - Main class for the beacon implementation
 * Handles registration with the server and maintains a communication loop
 */
@interface ZBeacon : NSObject

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

/**
 * Initialize a new beacon with the given server URL
 * @param serverURL The URL of the server to connect to
 * @return A new beacon instance
 */
- (instancetype)initWithServerURL:(NSURL *)serverURL;

/**
 * Start the beacon's operation
 * This will register with the server and begin the event loop
 */
- (void)start;

/**
 * Stop the beacon's operation
 */
- (void)stop;

@end