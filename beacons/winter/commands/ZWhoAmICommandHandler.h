#import "ZCommandHandler.h"

/**
 * @interface ZWhoAmICommandHandler
 * @brief A command handler that returns current user information
 *
 * This command handler returns information about the currently logged in user,
 * including username, hostname, and other relevant system information.
 */
@interface ZWhoAmICommandHandler : ZBaseCommandHandler

/**
 * Initialize the whoami command handler
 *
 * @return A new whoami command handler instance
 */
- (instancetype)init;

@end