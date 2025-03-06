#import "ZScreenshotCommandHandler.h"
#import <CoreGraphics/CoreGraphics.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreImage/CoreImage.h>

// Define error domain
NSString *const ZScreenshotErrorDomain = @"com.zscreenshot.error";

// Supported image formats
typedef NS_ENUM(NSInteger, ZScreenshotImageFormat) {
    ZScreenshotImageFormatPNG,
    ZScreenshotImageFormatJPEG,
    ZScreenshotImageFormatTIFF
};

@interface ZScreenshotCommandHandler () <SCStreamDelegate, SCStreamOutput>
@property (nonatomic, retain) SCStreamConfiguration *config;
@property (nonatomic, retain) SCShareableContent *shareableContent;
@property (nonatomic, retain) SCStream *stream;
@property (nonatomic, copy) void (^pendingCompletion)(BOOL success, NSDictionary *result, NSError *error);
@end

@implementation ZScreenshotCommandHandler

- (instancetype)init {
    self = [super initWithType:@"screenshot"];
    if (self) {
        _config = [[SCStreamConfiguration alloc] init];
        [_config setWidth:3840]; // Support up to 4K
        [_config setHeight:2160];
        [_config setMinimumFrameInterval:CMTimeMake(1, 1)]; // 1 frame per second is enough for screenshots
        [_config setQueueDepth:1]; // Only need one frame
    }
    return self;
}

- (void)dealloc {
    [_config release];
    [_shareableContent release];
    [_stream release];
    [_pendingCompletion release];
    [super dealloc];
}

- (NSString *)command {
    return @"screenshot";
}

/**
 * Execute the screenshot command
 *
 * Command parameters:
 * - screen_index: (optional) Index of screen to capture, -1 for all screens
 * - window_id: (optional) Window ID to capture, 0 for all windows
 * - format: (optional) Image format: "png", "jpeg", or "tiff"
 * - quality: (optional) Image quality (0-100, JPEG only)
 * - save_path: (optional) Custom save path
 *
 * @param command Command model containing operation parameters
 * @param completion Block called with operation results
 */
- (void)executeCommand:(ZCommandModel *)command 
           completion:(void (^)(BOOL success, NSDictionary *result, NSError *error))completion {
    NSLog(@"Executing screenshot command: %@", [command commandId]);
    
    // Store completion handler
    self.pendingCompletion = completion;
    
    // Get the payload from the command
    NSDictionary *payload = [command payload];
    
    // Extract parameters from payload
    NSInteger screenIndex = -1; // Default to all screens
    if ([payload objectForKey:@"screen_index"]) {
        screenIndex = [[payload objectForKey:@"screen_index"] integerValue];
    }
    
    // Get available screens
    [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent *content, NSError *error) {
        if (error) {
            if (self.pendingCompletion) {
                self.pendingCompletion(NO, nil, error);
            }
            return;
        }
        
        self.shareableContent = content;
        NSArray<SCDisplay *> *displays = content.displays;
        
        // Validate screen index
        if (screenIndex >= 0 && screenIndex >= (NSInteger)[displays count]) {
            NSError *error = [NSError errorWithDomain:ZScreenshotErrorDomain
                                               code:ZScreenshotErrorCodeInvalidScreen
                                           userInfo:@{NSLocalizedDescriptionKey: @"Invalid screen index"}];
            if (self.pendingCompletion) {
                self.pendingCompletion(NO, nil, error);
            }
            return;
        }
        
        // Setup filter for display
        SCDisplay *targetDisplay = nil;
        if (screenIndex >= 0) {
            targetDisplay = [displays objectAtIndex:(NSUInteger)screenIndex];
        } else {
            targetDisplay = [displays firstObject]; // Default to main display
        }
        
        // Create content filter
        SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:targetDisplay excludingApplications:@[] exceptingWindows:@[]];
        
        // Create stream
        self.stream = [[SCStream alloc] initWithFilter:filter configuration:self.config delegate:self];
        [filter release];
        
        // Add stream output handler
        NSError *outputError = nil;
        if (![self.stream addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:dispatch_get_main_queue() error:&outputError]) {
            if (self.pendingCompletion) {
                self.pendingCompletion(NO, nil, outputError);
            }
            return;
        }
        
        // Start capture
        [self.stream startCaptureWithCompletionHandler:^(NSError *error) {
            if (error) {
                if (self.pendingCompletion) {
                    self.pendingCompletion(NO, nil, error);
                }
            }
        }];
    }];
}

#pragma mark - SCStreamDelegate Protocol

- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    if (error && self.pendingCompletion) {
        self.pendingCompletion(NO, nil, error);
    }
}

#pragma mark - SCStreamOutput Protocol

- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(SCStreamOutputType)type {
    // Only process one frame
    [stream stopCaptureWithCompletionHandler:^(NSError *error) {
        if (error) {
            if (self.pendingCompletion) {
                self.pendingCompletion(NO, nil, error);
            }
            return;
        }
    }];
    
    // Get image from sample buffer
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!imageBuffer) {
        NSError *error = [NSError errorWithDomain:ZScreenshotErrorDomain
                                           code:ZScreenshotErrorCodeCaptureFailed
                                       userInfo:@{NSLocalizedDescriptionKey: @"Failed to get image buffer"}];
        if (self.pendingCompletion) {
            self.pendingCompletion(NO, nil, error);
        }
        return;
    }
    
    // Create CGImage from buffer
    CIImage *ciImage = [[[CIImage alloc] initWithCVPixelBuffer:imageBuffer] autorelease];
    CGRect extent = [ciImage extent];
    CIContext *context = [[CIContext contextWithOptions:@{}] retain];
    CGImageRef cgImage = [context createCGImage:ciImage fromRect:extent];
    [context release];
    
    if (!cgImage) {
        NSError *error = [NSError errorWithDomain:ZScreenshotErrorDomain
                                           code:ZScreenshotErrorCodeCaptureFailed
                                       userInfo:@{NSLocalizedDescriptionKey: @"Failed to create CGImage"}];
        if (self.pendingCompletion) {
            self.pendingCompletion(NO, nil, error);
        }
        return;
    }
    
    // Convert to PNG data
    NSBitmapImageRep *bitmapRep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    NSData *pngData = [bitmapRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [bitmapRep release];
    CGImageRelease(cgImage);
    
    if (!pngData) {
        NSError *error = [NSError errorWithDomain:ZScreenshotErrorDomain
                                           code:ZScreenshotErrorCodeSaveFailed
                                       userInfo:@{NSLocalizedDescriptionKey: @"Failed to convert screenshot to PNG"}];
        if (self.pendingCompletion) {
            self.pendingCompletion(NO, nil, error);
        }
        return;
    }
    
    // Create result dictionary with base64 encoded image data
    NSString *base64Image = [pngData base64EncodedStringWithOptions:0];
    NSDictionary *result = @{
        @"type": @"screenshot_response",
        @"format": @"png",
        @"data": base64Image
    };
    
    // Complete with success
    if (self.pendingCompletion) {
        self.pendingCompletion(YES, result, nil);
    }
}

@end 