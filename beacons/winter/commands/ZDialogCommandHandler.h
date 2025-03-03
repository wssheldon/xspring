#import "ZCommandHandler.h"

/**
 * @interface ZDialogCommandHandler
 * @brief A command handler for displaying dialogs to the user
 *
 * This command handler displays dialog boxes to the user
 * and reports back their response.
 */
@interface ZDialogCommandHandler : ZBaseCommandHandler

/**
 * Initialize the dialog command handler
 *
 * @return A new dialog command handler instance
 */
- (instancetype)init;

@end