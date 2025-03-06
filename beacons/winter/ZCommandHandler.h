#import <Foundation/Foundation.h>
#import "ZCommandModel.h"

/**
 * @protocol ZCommandHandler
 * @brief Protocol for command handlers
 *
 * This protocol defines the interface for command handlers.
 * Each command type should have its own handler implementation.
 */
@protocol ZCommandHandler <NSObject>

/**
 * Get the command type this handler can process
 *
 * @return The command type string
 */
- (NSString *)command;

/**
 * Execute a command
 *
 * @param command The command to execute
 * @param completion Block to be executed when the command completes
 */
- (void)executeCommand:(ZCommandModel *)command
            completion:(void (^)(BOOL success, NSDictionary *result, NSError *error))completion;

/**
 * Check if this handler can cancel a command
 *
 * @return YES if commands can be cancelled, NO otherwise
 */
- (BOOL)canCancelCommand;

/**
 * Cancel a command in progress
 *
 * @param command The command to cancel
 * @return YES if the command was cancelled, NO otherwise
 */
- (BOOL)cancelCommand:(ZCommandModel *)command;

@optional

/**
 * Check if this handler supports running multiple commands at once
 *
 * @return YES if multiple commands are supported, NO otherwise
 */
- (BOOL)supportsMultipleCommands;

/**
 * Get the command description
 *
 * @return The command description string
 */
- (NSString *)description;

/**
 * Handle a command
 *
 * @param command The command to handle
 * @return YES if the command was handled, NO otherwise
 */
- (BOOL)handleCommand:(ZCommandModel *)command;

@end

/**
 * @interface ZBaseCommandHandler
 * @brief Base class for command handlers
 *
 * This class provides a base implementation for command handlers.
 */
@interface ZBaseCommandHandler : NSObject <ZCommandHandler>

/**
 * Initialize with a command type
 *
 * @param type The command type
 * @return A new command handler instance
 */
- (instancetype)initWithType:(NSString *)type;

@end