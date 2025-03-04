#import <Foundation/Foundation.h>
#import "ZCommandPoller.h"
#import "ZCommandReporter.h"
#import "ZCommandExecutor.h"
@class ZCommandModel;

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
- (void)commandService:(id)service didReceiveCommand:(ZCommandModel *)command;

/**
 * Called when a command is successfully executed
 *
 * @param service The command service
 * @param command The executed command
 * @param result The result of the command execution
 */
- (void)commandService:(id)service didExecuteCommand:(ZCommandModel *)command withResult:(NSDictionary *)result;

/**
 * Called when a command execution fails
 *
 * @param service The command service
 * @param command The command that failed to execute
 * @param error The error that occurred
 */
- (void)commandService:(id)service didFailToExecuteCommand:(ZCommandModel *)command withError:(NSError *)error;

/**
 * Called when a command is successfully reported to the server
 *
 * @param service The command service
 * @param command The command that was reported
 * @param response The server response
 */
- (void)commandService:(id)service didReportCommand:(ZCommandModel *)command withResponse:(NSDictionary *)response;

/**
 * Called when a command report fails
 *
 * @param service The command service
 * @param command The command that failed to report
 * @param error The error that occurred
 */
- (void)commandService:(id)service didFailToReportCommand:(ZCommandModel *)command withError:(NSError *)error;

@end

/**
 * @interface ZCommandService
 * @brief High-level service that coordinates command polling, execution, and reporting
 */
@interface ZCommandService : NSObject <ZCommandPollerDelegate, ZCommandReporterDelegate, ZCommandExecutorDelegate>

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
 * Indicates whether the command service is running
 */
@property(nonatomic, readonly) BOOL isRunning;

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
 * Start the command service
 *
 * @return YES if started successfully, NO otherwise
 */
- (BOOL)start;

/**
 * Stop the command service
 */
- (void)stop;

/**
 * Poll for commands immediately
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