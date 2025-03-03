#import <Foundation/Foundation.h>
#import "ZCommandHandler.h"
#import "ZCommandModel.h"

/**
 * @interface ZCommandRegistry
 * @brief Registry for command handlers
 *
 * This class manages command handlers and dispatches commands to the appropriate handler.
 */
@interface ZCommandRegistry : NSObject

/**
 * Get the shared command registry instance
 *
 * @return The shared instance
 */
+ (instancetype)sharedRegistry;

/**
 * Register a command handler
 *
 * @param handler The command handler to register
 * @return YES if registration was successful, NO otherwise
 */
- (BOOL)registerCommandHandler:(id<ZCommandHandler>)handler;

/**
 * Unregister a command handler
 *
 * @param commandType The command type to unregister
 * @return YES if unregistration was successful, NO otherwise
 */
- (BOOL)unregisterCommandHandlerForType:(NSString *)commandType;

/**
 * Get a command handler for a specific command type
 *
 * @param commandType The command type
 * @return The command handler, or nil if no handler is registered for the type
 */
- (id<ZCommandHandler>)handlerForCommandType:(NSString *)commandType;

/**
 * Check if a handler exists for a command type
 *
 * @param commandType The command type
 * @return YES if a handler exists, NO otherwise
 */
- (BOOL)canHandleCommandType:(NSString *)commandType;

/**
 * Execute a command with the appropriate handler
 *
 * @param command The command to execute
 * @param completion Block to be executed when the command completes
 * @return YES if the command was dispatched, NO otherwise
 */
- (BOOL)executeCommand:(ZCommandModel *)command
            completion:(void (^)(BOOL success, NSDictionary *result, NSError *error))completion;

/**
 * Cancel a command
 *
 * @param command The command to cancel
 * @return YES if the command was cancelled, NO otherwise
 */
- (BOOL)cancelCommand:(ZCommandModel *)command;

@end