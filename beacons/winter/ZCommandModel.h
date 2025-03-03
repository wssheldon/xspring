#import <Foundation/Foundation.h>

/**
 * Command status enumeration
 */
typedef NS_ENUM(NSInteger, ZCommandStatus) {
    ZCommandStatusPending = 0,
    ZCommandStatusInProgress = 1,
    ZCommandStatusCompleted = 2,
    ZCommandStatusFailed = 3,
    ZCommandStatusTimedOut = 4
};

/**
 * ZCommandModel - Model for commands received from the server
 */
@interface ZCommandModel : NSObject

/**
 * Command identifier from the server
 */
@property(nonatomic, copy, readonly) NSString *commandId;

/**
 * Type of the command (e.g., "exec", "info", "prompt")
 */
@property(nonatomic, copy, readonly) NSString *type;

/**
 * Command payload, specific to the command type
 */
@property(nonatomic, strong, readonly) NSDictionary *payload;

/**
 * Current status of the command
 */
@property(nonatomic, assign, readonly) ZCommandStatus status;

/**
 * Timestamp when the command was created on the server
 */
@property(nonatomic, copy, readonly) NSString *createdAt;

/**
 * Initialize a command with the data received from the server
 *
 * @param commandData Dictionary containing the command data
 * @return A new command model instance
 */
- (instancetype)initWithDictionary:(NSDictionary *)commandData;

/**
 * Convert the command to a dictionary suitable for sending to the server
 *
 * @return Dictionary representation of the command
 */
- (NSDictionary *)asDictionary;

/**
 * Set the status of the command
 *
 * @param newStatus The new status to set
 */
- (void)setStatus:(ZCommandStatus)newStatus;

@end