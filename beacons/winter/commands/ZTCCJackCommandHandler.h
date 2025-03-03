#import <Foundation/Foundation.h>
#import "ZCommandHandler.h"
#import <AppKit/AppKit.h>

/**
 * @interface ZTCCJackCommandHandler
 * @brief Command handler for demonstrating TCC clickjacking
 *
 * This command handler creates a fake system crash dialog window that overlays
 * the macOS TCC permission dialog to demonstrate clickjacking.
 */
@interface ZTCCJackCommandHandler : ZBaseCommandHandler

/**
 * Initialize the TCCJack command handler
 *
 * @return A new TCCJack command handler instance
 */
- (instancetype)init;

/**
 * Creates an AppleScript to trigger Full Disk Access TCC prompt
 *
 * @return Path to the created AppleScript file
 */
- (NSString *)createAppleScript;

/**
 * Reset TCC permissions for AppleEvents to ensure prompt appears
 */
- (void)resetTCCPermissions;

/**
 * Run the AppleScript to trigger Full Disk Access TCC prompt
 */
- (void)runAppleScript;

/**
 * Create a fake system crash dialog window
 */
- (void)createFakeSystemCrashDialog;

/**
 * Ensure the application is properly set up for UI display
 */
- (void)ensureApplicationSetup;

@end