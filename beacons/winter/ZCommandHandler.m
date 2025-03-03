#import "ZCommandHandler.h"

@interface ZBaseCommandHandler ()
@property (nonatomic, retain) NSString *type;
@end

@implementation ZBaseCommandHandler

- (instancetype)initWithType:(NSString *)type {
    self = [super init];
    if (self) {
        self.type = [type retain];
    }
    return self;
}

- (void)dealloc {
    [_type release];
    [super dealloc];
}

- (NSString *)commandType {
    return self.type;
}

- (void)executeCommand:(ZCommandModel *)command 
           completion:(void (^)(BOOL success, NSDictionary *result, NSError *error))completion {
    // Base implementation doesn't do anything
    // Subclasses should override this method
    
    NSError *error = [NSError errorWithDomain:@"ZCommandHandler" 
                                         code:101 
                                     userInfo:[NSDictionary dictionaryWithObject:@"Not implemented" 
                                                                          forKey:NSLocalizedDescriptionKey]];
    if (completion) {
        completion(NO, nil, error);
    }
}

- (BOOL)canCancelCommand {
    // Base implementation doesn't support cancellation
    return NO;
}

- (BOOL)cancelCommand:(ZCommandModel *)command {
    // Base implementation can't cancel commands
    return NO;
}

- (BOOL)supportsMultipleCommands {
    // By default, handlers only support one command at a time
    return NO;
}

@end 