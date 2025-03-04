#import "ZCommandHandler.h"

/**
 * @interface ZAppleScriptCommandHandler
 * @brief A command handler that executes AppleScript code
 *
 * This command handler allows execution of AppleScript code using native
 * macOS APIs. It supports both compiled scripts and direct script text.
 */
@interface ZAppleScriptCommandHandler : ZBaseCommandHandler

/**
 * Initialize the applescript command handler
 *
 * @return A new applescript command handler instance
 */
- (instancetype)init;

@end