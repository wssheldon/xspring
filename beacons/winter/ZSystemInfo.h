#import <Foundation/Foundation.h>

/**
 * ZSystemInfo - Utility class to gather system information
 */
@interface ZSystemInfo : NSObject

/**
 * Get the hostname of the current machine
 * @return The hostname
 */
+ (NSString *)hostname;

/**
 * Get the username of the current user
 * @return The username
 */
+ (NSString *)username;

/**
 * Get the OS version of the current machine
 * @return The OS version
 */
+ (NSString *)osVersion;

@end