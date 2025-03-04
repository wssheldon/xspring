#import <Foundation/Foundation.h>
@class ZCommandModel;

@protocol ZCommandPollerDelegate <NSObject>
- (void)commandPoller:(id)poller didReceiveCommand:(ZCommandModel *)command;
- (void)commandPoller:(id)poller didFailWithError:(NSError *)error;
@end

/**
 * @interface ZCommandPoller
 * @brief Handles polling for new commands from the server
 */
@interface ZCommandPoller : NSObject

@property(nonatomic, assign) id<ZCommandPollerDelegate> delegate;
@property(nonatomic, assign) NSTimeInterval pollInterval;

/**
 * Initialize with server URL and beacon ID
 *
 * @param serverURL The server URL
 * @param beaconId The beacon ID
 * @return A new command poller instance
 */
- (instancetype)initWithServerURL:(NSURL *)serverURL beaconId:(NSString *)beaconId;

/**
 * Start polling for commands
 */
- (void)startPolling;

/**
 * Stop polling for commands
 */
- (void)stopPolling;

/**
 * Poll immediately for commands
 */
- (void)pollNow;

@end