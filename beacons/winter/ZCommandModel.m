#import "ZCommandModel.h"

@interface ZCommandModel ()

// Make properties readwrite in private interface
@property (nonatomic, copy, readwrite) NSString *commandId;
@property (nonatomic, copy, readwrite) NSString *type;
@property (nonatomic, strong, readwrite) NSDictionary *payload;
@property (nonatomic, assign, readwrite) ZCommandStatus status;
@property (nonatomic, copy, readwrite) NSString *createdAt;

@end

@implementation ZCommandModel

- (instancetype)initWithDictionary:(NSDictionary *)commandData {
    self = [super init];
    if (self) {
        // Required fields - server might use 'id' or 'command_id' for the command ID
        _commandId = [[commandData objectForKey:@"id"] copy];
        if (!_commandId) {
            _commandId = [[commandData objectForKey:@"command_id"] copy];
        }
        
        // Server might use 'type' or 'command' for the command type
        _type = [[commandData objectForKey:@"type"] copy];
        if (!_type) {
            _type = [[commandData objectForKey:@"command"] copy];
        }
        
        // Optional fields with defaults
        _payload = [commandData objectForKey:@"payload"] ?: [NSDictionary dictionary];
        [_payload retain];
        
        // Parse status if present, otherwise default to pending
        if ([commandData objectForKey:@"status"]) {
            NSString *statusString = [commandData objectForKey:@"status"];
            if ([statusString isEqualToString:@"pending"]) {
                _status = ZCommandStatusPending;
            } else if ([statusString isEqualToString:@"in_progress"]) {
                _status = ZCommandStatusInProgress;
            } else if ([statusString isEqualToString:@"completed"]) {
                _status = ZCommandStatusCompleted;
            } else if ([statusString isEqualToString:@"failed"]) {
                _status = ZCommandStatusFailed;
            } else if ([statusString isEqualToString:@"timeout"]) {
                _status = ZCommandStatusTimedOut;
            } else {
                _status = ZCommandStatusPending;
            }
        } else {
            _status = ZCommandStatusPending;
        }
        
        _createdAt = [[commandData objectForKey:@"created_at"] copy] ?: [[self currentTimestampString] copy];
        
        // Validate required fields
        if (!_commandId || !_type) {
            [self release];
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    [_commandId release];
    [_type release];
    [_payload release];
    [_createdAt release];
    [super dealloc];
}

- (NSDictionary *)asDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    // Add required fields
    [dict setValue:self.commandId forKey:@"id"];
    [dict setValue:self.type forKey:@"type"];
    
    // Add payload if not empty
    if (self.payload && [self.payload count] > 0) {
        [dict setValue:self.payload forKey:@"payload"];
    }
    
    // Convert status enum to string
    NSString *statusString;
    switch (self.status) {
        case ZCommandStatusPending:
            statusString = @"pending";
            break;
        case ZCommandStatusInProgress:
            statusString = @"in_progress";
            break;
        case ZCommandStatusCompleted:
            statusString = @"completed";
            break;
        case ZCommandStatusFailed:
            statusString = @"failed";
            break;
        case ZCommandStatusTimedOut:
            statusString = @"timeout";
            break;
        default:
            statusString = @"pending";
            break;
    }
    [dict setValue:statusString forKey:@"status"];
    
    // Add timestamp
    [dict setValue:self.createdAt forKey:@"created_at"];
    
    return dict;
}

- (NSString *)currentTimestampString {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
    [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    [formatter release];
    return timestamp;
}

- (void)setStatus:(ZCommandStatus)newStatus {
    _status = newStatus;
}

@end 