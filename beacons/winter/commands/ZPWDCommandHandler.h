#import "ZCommandHandler.h"

/**
 * @interface ZPWDCommandHandler
 * @brief A command handler that returns the current working directory
 *
 * This command handler returns the absolute path of the current working directory
 * using native macOS APIs.
 */
@interface ZPWDCommandHandler : ZBaseCommandHandler

/**
 * Initialize the pwd command handler
 *
 * @return A new pwd command handler instance
 */
- (instancetype)init;

@end