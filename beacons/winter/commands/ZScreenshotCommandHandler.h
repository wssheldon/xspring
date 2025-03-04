#import <Foundation/Foundation.h>
#import "ZCommandHandler.h"
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>

// Error domain and codes
extern NSString *const ZScreenshotErrorDomain;
typedef NS_ENUM(NSInteger, ZScreenshotErrorCode) {
    ZScreenshotErrorCodeCaptureFailed = 1000, // Failed to capture screenshot
    ZScreenshotErrorCodeSaveFailed = 1001,    // Failed to save screenshot
    ZScreenshotErrorCodeInvalidScreen = 1002, // Invalid screen specified
    ZScreenshotErrorCodeInvalidWindow = 1003, // Invalid window specified
    ZScreenshotErrorCodeInvalidFormat = 1004  // Invalid image format
};

/**
 * @interface ZScreenshotCommandHandler
 * @brief A command handler for taking screenshots
 *
 * This command handler captures screenshots of displays or windows
 * using ScreenCaptureKit and returns them as base64 encoded PNG data.
 */
@interface ZScreenshotCommandHandler : ZBaseCommandHandler <SCStreamDelegate, SCStreamOutput>

/**
 * Initialize the screenshot command handler
 *
 * @return A new screenshot command handler instance
 */
- (instancetype)init;

@end