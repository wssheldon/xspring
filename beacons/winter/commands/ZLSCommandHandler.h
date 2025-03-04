#import "ZCommandHandler.h"

/**
 * @interface ZLSCommandHandler
 * @brief A command handler that provides directory listing functionality
 *
 * This command handler provides detailed directory listing functionality
 * using native macOS APIs. It supports listing files, directories, and
 * their attributes similar to the Unix ls command.
 */
@interface ZLSCommandHandler : ZBaseCommandHandler

/**
 * Initialize the ls command handler
 *
 * @return A new ls command handler instance
 */
- (instancetype)init;

@end