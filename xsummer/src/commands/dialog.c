/**
 * @file dialog.c
 * @brief Implementation of the dialog command
 */
#include <objc/objc.h>
#include "command_registry.h"
#include "common.h"

#ifdef __LP64__
typedef unsigned long NSUInteger;
typedef long NSInteger;
#else
typedef unsigned int NSUInteger;
typedef int NSInteger;
#endif

/**
 * @brief Helper function to create an autorelease pool
 * @param instance The runtime instance
 * @return Autorelease pool object or NULL on error
 */
static id create_autorelease_pool(INSTANCE* instance) {
  if (!instance->Darwin.NSAutoreleasePoolClass) {
    DEBUG_LOG("Error: NSAutoreleasePoolClass is null");
    return NULL;
  }

  SEL newSel = instance->Darwin.sel_registerName("new");
  if (!newSel) {
    DEBUG_LOG("Error: Failed to create 'new' selector");
    return NULL;
  }

  id pool = ((id(*)(Class, SEL))instance->Darwin.objc_msgSend)(
      instance->Darwin.NSAutoreleasePoolClass, newSel);

  if (!pool) {
    DEBUG_LOG("Error: Failed to create autorelease pool");
  }

  return pool;
}

/**
 * @brief Drain an autorelease pool
 * @param instance The runtime instance
 * @param pool Autorelease pool to drain
 */
static void drain_autorelease_pool(INSTANCE* instance, id pool) {
  if (!pool) {
    return;
  }

  SEL drainSel = instance->Darwin.sel_registerName("drain");
  if (!drainSel) {
    DEBUG_LOG("Error: Failed to create 'drain' selector");
    return;
  }

  ((void (*)(id, SEL))instance->Darwin.objc_msgSend)(pool, drainSel);
}

/**
 * @brief Initialize application for UI operations
 * @param instance The runtime instance
 * @return Application object or NULL on error
 */
static id initialize_application(INSTANCE* instance) {
  if (!instance->Darwin.NSApplicationClass) {
    DEBUG_LOG("Error: NSApplicationClass is null");
    return NULL;
  }

  if (!instance->Darwin.sharedApplicationSel) {
    DEBUG_LOG("Error: sharedApplicationSel is null");
    return NULL;
  }

  id app = ((id(*)(Class, SEL))instance->Darwin.objc_msgSend)(
      instance->Darwin.NSApplicationClass,
      instance->Darwin.sharedApplicationSel);

  if (!app) {
    DEBUG_LOG("Error: Failed to get shared application");
    return NULL;
  }

  // Set activation policy to Accessory (important!)
  ((void (*)(id, SEL, NSInteger))instance->Darwin.objc_msgSend)(
      app, instance->Darwin.setActivationPolicySel,
      1  // NSApplicationActivationPolicyAccessory
  );

  // Activate the app
  ((void (*)(id, SEL, BOOL))instance->Darwin.objc_msgSend)(
      app, instance->Darwin.activateIgnoringOtherAppsSel, YES);

  return app;
}

/**
 * @brief Implementation of the dialog command
 * @param instance The runtime instance
 * @return Dialog result as string (caller must free)
 */
static char* cmd_dialog(INSTANCE* instance) {
  DEBUG_LOG("Starting dialog command");

  if (!instance) {
    DEBUG_LOG("Error: Null instance pointer");
    return create_error("Internal error - null instance");
  }

  // Create autorelease pool
  id pool = create_autorelease_pool(instance);
  if (!pool) {
    return create_error("Failed to create autorelease pool");
  }

  // Initialize shared application
  id app = initialize_application(instance);
  if (!app) {
    drain_autorelease_pool(instance, pool);
    return create_error("Failed to initialize application");
  }

  // Get main run loop
  Class NSRunLoopClass = instance->Darwin.objc_getClass("NSRunLoop");
  SEL mainRunLoopSel = instance->Darwin.sel_registerName("mainRunLoop");
  id runLoop = ((id(*)(Class, SEL))instance->Darwin.objc_msgSend)(
      NSRunLoopClass, mainRunLoopSel);

  // Create alert
  id alert = ((id(*)(Class, SEL))instance->Darwin.objc_msgSend)(
      instance->Darwin.NSAlertClass, instance->Darwin.sel_registerName("new"));

  if (!alert) {
    DEBUG_LOG("Error: Failed to create alert");
    drain_autorelease_pool(instance, pool);
    return create_error("Failed to create alert");
  }

  // Configure alert
  Class NSStringClass = instance->Darwin.objc_getClass("NSString");
  SEL stringWithUTF8StringSel =
      instance->Darwin.sel_registerName("stringWithUTF8String:");

  // Set message text
  id messageString =
      ((id(*)(Class, SEL, const char*))instance->Darwin.objc_msgSend)(
          NSStringClass, stringWithUTF8StringSel,
          "This is a message from xsummer");

  ((void (*)(id, SEL, id))instance->Darwin.objc_msgSend)(
      alert, instance->Darwin.sel_registerName("setMessageText:"),
      messageString);

  // Add OK button
  id okButtonTitle =
      ((id(*)(Class, SEL, const char*))instance->Darwin.objc_msgSend)(
          NSStringClass, stringWithUTF8StringSel, "OK");

  ((void (*)(id, SEL, id))instance->Darwin.objc_msgSend)(
      alert, instance->Darwin.sel_registerName("addButtonWithTitle:"),
      okButtonTitle);

  // Get window and set level
  SEL windowSel = instance->Darwin.sel_registerName("window");
  id alertWindow =
      ((id(*)(id, SEL))instance->Darwin.objc_msgSend)(alert, windowSel);

  // Set window level
  ((void (*)(id, SEL, NSInteger))instance->Darwin.objc_msgSend)(
      alertWindow, instance->Darwin.sel_registerName("setLevel:"),
      8  // NSModalPanelWindowLevel = 8
  );

  // Run the alert
  SEL runModalSel = instance->Darwin.sel_registerName("runModal");
  NSInteger result = ((NSInteger(*)(id, SEL))instance->Darwin.objc_msgSend)(
      alert, runModalSel);

  DEBUG_LOG("Dialog closed with result: %ld", (long)result);

  // Run the run loop briefly to process events
  id date = ((id(*)(Class, SEL, double))instance->Darwin.objc_msgSend)(
      instance->Darwin.objc_getClass("NSDate"),
      instance->Darwin.sel_registerName("dateWithTimeIntervalSinceNow:"), 0.1);

  ((void (*)(id, SEL, id))instance->Darwin.objc_msgSend)(
      runLoop, instance->Darwin.sel_registerName("runUntilDate:"), date);

  // Format return string
  char* resultStr = NULL;
  if (result == 1000) {  // NSAlertFirstButtonReturn
    resultStr = strdup("OK clicked");
  } else {
    resultStr = strdup("Dialog closed");
  }

  // Clean up
  drain_autorelease_pool(instance, pool);

  return resultStr;
}

/**
 * @brief Register the dialog command
 * @return true if registration succeeded, false otherwise
 */
bool register_dialog_command(void) {
  return register_command("dialog", cmd_dialog);
}