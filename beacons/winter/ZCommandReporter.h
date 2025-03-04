#import <Foundation/Foundation.h>
@class ZCommandModel;

@protocol ZCommandReporterDelegate <NSObject>
- (void)commandReporter:(id)reporter didReportCommand:(ZCommandModel *)command withResponse:(NSDictionary *)response;
- (void)commandReporter:(id)reporter didFailToReportCommand:(ZCommandModel *)command withError:(NSError *)error;
@end

/**
 * @interface ZCommandReporter
 * @brief Handles reporting command results back to the server
 */
@interface ZCommandReporter : NSObject

@property(nonatomic, assign) id<ZCommandReporterDelegate> delegate;

/**
 * Initialize with server URL and beacon ID
 *
 * @param serverURL The server URL
 * @param beaconId The beacon ID
 * @return A new command reporter instance
 */
- (instancetype)initWithServerURL:(NSURL *)serverURL beaconId:(NSString *)beaconId;

/**
 * Report command result to server
 *
 * @param command The command to report
 * @param result The command result
 * @param error Any error that occurred
 */
- (void)reportCommand:(ZCommandModel *)command
               result:(NSDictionary *)result
                error:(NSError *)error;

@end