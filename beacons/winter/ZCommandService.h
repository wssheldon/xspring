#import <Foundation/Foundation.h>
#import "ZCommandModel.h"
@class ZCommandService;
@class ZAPIClient;

/**
 * @protocol ZCommandServiceDelegate
 * @brief Delegate protocol for the command service
 *
 * This protocol defines the delegate methods for the command service.
 */
@protocol ZCommandServiceDelegate <NSObject>

@optional

/**
 * Called when a new command is received
 *
 * @param service The command service
 * @param command The received command
 */
- (void)commandService:(ZCommandService *)service didReceiveCommand:(ZCommandModel *)command;

/**
 * Called when a command is successfully reported to the server
 *
 * @param service The command service
 * @param command The command that was reported
 * @param response The server response
 */
- (void)commandService:(ZCommandService *)service didReportCommand:(ZCommandModel *)command withResponse:(NSDictionary *)response;

/**
 * Called when a command report fails
 *
 * @param service The command service
 * @param command The command that failed to report
 * @param error The error that occurred
 */
- (void)commandService:(ZCommandService *)service didFailToReportCommand:(ZCommandModel *)command withError:(NSError *)error;

@end

/**
 * @interface ZCommandService
 * @brief Service for communicating with the command server
 *
 * This class handles communication with the command server, including polling for commands,
 * reporting command execution results, and managing timeouts.
 */
@interface ZCommandService : NSObject

/**
 * The service delegate
 */
@property(nonatomic, assign) id<ZCommandServiceDelegate> delegate;

/**
 * The poll interval in seconds (default: 60 seconds)
 */
@property(nonatomic, assign) NSTimeInterval pollInterval;

/**
 * The command timeout in seconds (default: 300 seconds)
 */
@property(nonatomic, assign) NSTimeInterval commandTimeout;

/**
 * The API client
 */
@property(nonatomic, strong, readonly) ZAPIClient *apiClient;

/**
 * Initialize with a server URL
 *
 * @param serverURL The URL of the command server
 * @return A new command service instance
 */
- (instancetype)initWithServerURL:(NSURL *)serverURL;

/**
 * Initialize with a server URL and beacon ID
 *
 * @param serverURL The URL of the command server
 * @param beaconId The unique identifier for the beacon
 * @return A new command service instance
 */
- (instancetype)initWithServerURL:(NSURL *)serverURL beaconId:(NSString *)beaconId;

/**
 * Start the command polling service
 *
 * @return YES if the service was started successfully, NO otherwise
 */
- (BOOL)start;

/**
 * Stop the command polling service
 */
- (void)stop;

/**
 * Force a poll for commands immediately
 */
- (void)pollNow;

/**
 * Report command execution results to the server
 *
 * @param command The command to report
 * @param result The result of the command execution
 * @param error The error that occurred during execution, if any
 */
- (void)reportCommand:(ZCommandModel *)command
               result:(NSDictionary *)result
                error:(NSError *)error;

@end