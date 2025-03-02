#import <Foundation/Foundation.h>
#import "ZBeacon.h"
#import <signal.h>

// Global variable for the beacon
static ZBeacon *gBeacon = nil;

void printUsage(const char *programName) {
    printf("Usage: %s [OPTIONS]\n\n", programName);
    printf("Options:\n");
    printf("  --url=URL           Server URL (default: https://localhost:4444)\n");
    printf("  --debug             Enable verbose debug logging\n");
    printf("  --help              Display this help message\n");
    printf("\nExample:\n");
    printf("  %s --url=https://example.com:4444 --debug\n", programName);
}

void signalHandler(int signal) {
    NSLog(@"Received signal %d, shutting down...", signal);
    if (gBeacon) {
        [gBeacon stop];
    }
    exit(0);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        @try {
            NSLog(@"Winter Beacon starting up...");
            
            // Default configuration
            NSString *serverURLString = @"https://localhost:4444";
            BOOL debugMode = NO;
            
            // Parse command line arguments
            for (int i = 1; i < argc; i++) {
                NSString *arg = [NSString stringWithUTF8String:argv[i]];
                
                if ([arg hasPrefix:@"--url="]) {
                    serverURLString = [arg substringFromIndex:6]; // Skip "--url="
                } else if ([arg isEqualToString:@"--debug"]) {
                    debugMode = YES;
                } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
                    printUsage(argv[0]);
                    return 0;
                } else if (![arg hasPrefix:@"--"]) {
                    // For backward compatibility, treat positional arg as URL
                    serverURLString = arg;
                }
            }
            
            // Setup basic signal handling for graceful exit
            signal(SIGINT, signalHandler);
            signal(SIGTERM, signalHandler);
            
            NSLog(@"Using server URL: %@", serverURLString);
            if (debugMode) {
                NSLog(@"Debug mode enabled");
            }
            
            // Create and configure beacon
            NSURL *serverURL = [NSURL URLWithString:serverURLString];
            if (!serverURL) {
                NSLog(@"Error: Invalid server URL format: %@", serverURLString);
                return 1;
            }
            
            NSLog(@"Creating beacon with server URL: %@", serverURL);
            gBeacon = [[ZBeacon alloc] initWithServerURL:serverURL];
            
            if (!gBeacon) {
                NSLog(@"Error: Failed to create beacon");
                return 1;
            }
            
            // Set up more advanced signal handling via GCD
            dispatch_source_t signalSource = dispatch_source_create(
                DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, dispatch_get_main_queue());
            
            if (signalSource) {
                dispatch_source_set_event_handler(signalSource, ^{
                    NSLog(@"Received interrupt signal via GCD. Shutting down gracefully...");
                    if (gBeacon) {
                        [gBeacon stop];
                    }
                    exit(0);
                });
                
                dispatch_resume(signalSource);
            }
            
            // Start beacon
            NSLog(@"Starting beacon...");
            [gBeacon start];
            
            // Keep the application running until user interrupts
            NSLog(@"Beacon running. Press Ctrl+C to exit.");
            [[NSRunLoop currentRunLoop] run];
        }
        @catch (NSException *exception) {
            NSLog(@"Uncaught exception: %@", exception);
            NSLog(@"Reason: %@", [exception reason]);
            
            // Get the call stack
            NSArray *callStack = [exception callStackSymbols];
            if (callStack) {
                NSLog(@"Stack trace:");
                for (NSString *frame in callStack) {
                    NSLog(@"  %@", frame);
                }
            }
            
            return 1;
        }
    }
    return 0;
} 