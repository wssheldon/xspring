#import <Foundation/Foundation.h>
@class ZCommandModel;

@protocol ZCommandExecutorDelegate <NSObject>
- (void)commandExecutor:(id)executor didCompleteCommand:(ZCommandModel *)command withResult:(NSDictionary *)result;
- (void)commandExecutor:(id)executor didFailCommand:(ZCommandModel *)command withError:(NSError *)error;
- (void)commandExecutor:(id)executor didTimeoutCommand:(ZCommandModel *)command;
@end

/**
 * @interface ZCommandExecutor
 * @brief Handles command execution and timeout management
 */
@interface ZCommandExecutor : NSObject

@property(nonatomic, assign) id<ZCommandExecutorDelegate> delegate;
@property(nonatomic, assign) NSTimeInterval commandTimeout;

/**
 * Initialize a new command executor
 *
 * @return A new command executor instance
 */
- (instancetype)init;

/**
 * Execute a command with timeout
 *
 * @param command The command to execute
 */
- (void)executeCommand:(ZCommandModel *)command;

/**
 * Cancel a command execution
 *
 * @param command The command to cancel
 * @return YES if command was cancelled, NO otherwise
 */
- (BOOL)cancelCommand:(ZCommandModel *)command;

@end