#import "ZCommandHandler.h"

/**
 * @interface ZEchoCommandHandler
 * @brief A simple echo command handler
 *
 * This command handler simply echoes back the command payload.
 * Used for testing the command system.
 */
@interface ZEchoCommandHandler : ZBaseCommandHandler

/**
 * Initialize the echo command handler
 *
 * @return A new echo command handler instance
 */
- (instancetype)init;

@end