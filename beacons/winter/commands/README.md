# ZBeacon Command Handlers

This directory contains command handlers for the ZBeacon command system. Each command handler is responsible for handling a specific type of command sent from the server to the beacon.

## Command Handler Structure

A command handler consists of two files:

- `Z<CommandName>CommandHandler.h` - The header file defining the class
- `Z<CommandName>CommandHandler.m` - The implementation file

## Creating a New Command Handler

To create a new command handler:

1. Create a new header file (`Z<CommandName>CommandHandler.h`) that imports `ZCommandHandler.h` and declares a class that inherits from `ZBaseCommandHandler`.
2. Create a new implementation file (`Z<CommandName>CommandHandler.m`) that implements the methods required by the `ZCommandHandler` protocol.
3. Update `ZBeacon.m` to import your new handler and register it in the `registerDefaultCommandHandlers` method.
4. Update `Makefile` to include your new command handler in the `SOURCES` variable.

## Example Command Handler

A minimal command handler looks like this:

### Header File (ZExampleCommandHandler.h)

```objc
#import "ZCommandHandler.h"

@interface ZExampleCommandHandler : ZBaseCommandHandler

- (instancetype)init;

@end
```

### Implementation File (ZExampleCommandHandler.m)

```objc
#import "ZExampleCommandHandler.h"

@implementation ZExampleCommandHandler

- (instancetype)init {
    return [super initWithType:@"example"];
}

- (void)executeCommand:(ZCommandModel *)command
           completion:(void (^)(BOOL success, NSDictionary *result, NSError *error))completion {

    NSLog(@"Executing example command: %@", [command commandId]);

    // Get the payload from the command
    NSDictionary *payload = [command payload];

    // Create a result dictionary
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [result setObject:@"example_response" forKey:@"type"];

    // Add results to the dictionary
    // ...

    // Complete with success
    if (completion) {
        completion(YES, result, nil);
    }
}

@end
```

## Available Command Handlers

- **ZEchoCommandHandler**: Simple echo command that returns the input payload (command type: `echo`)
- **ZDialogCommandHandler**: Shows dialog boxes to the user and returns their response (command type: `dialog`)
- **ZWhoAmICommandHandler**: Returns information about the current user (command type: `whoami`)

## Command Flow

1. Server sends a command to the beacon
2. ZBeacon receives the command and looks up the appropriate handler
3. ZBeacon calls the handler's `executeCommand:completion:` method
4. Handler processes the command and calls the completion block with results
5. ZBeacon reports the results back to the server
