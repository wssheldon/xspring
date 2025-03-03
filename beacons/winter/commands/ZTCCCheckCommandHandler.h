#import <Foundation/Foundation.h>
#import "ZCommandHandler.h"

/**
 * Command handler for checking TCC permissions.
 * This handler allows checking what TCC permissions the beacon process currently has.
 */
@interface ZTCCCheckCommandHandler : ZBaseCommandHandler

/**
 * Initializes the command handler.
 * @return The initialized handler.
 */
- (instancetype)init;

/**
 * Checks various TCC permissions like Full Disk Access, Desktop access, etc.
 * @param username The username to check permissions for, or nil for current user.
 * @return A string with the results of the TCC checks.
 */
- (NSString *)checkTCCPermissions:(NSString *)username;

@end