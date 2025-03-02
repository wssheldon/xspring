/**
 * @file applescript.c
 * @brief Implementation of the applescript command
 */
#include <objc/objc.h>
#include "command_registry.h"
#include "common.h"

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
 * @brief Create an NSString from a C string
 * @param instance The runtime instance
 * @param cString C string to convert
 * @return NSString object or NULL on error
 */
static id create_ns_string(INSTANCE* instance, const char* cString) {
  if (!cString) {
    DEBUG_LOG("Error: Null C string");
    return NULL;
  }

  Class NSStringClass = instance->Darwin.objc_getClass("NSString");
  if (!NSStringClass) {
    DEBUG_LOG("Error: Failed to get NSString class");
    return NULL;
  }

  SEL stringWithUTF8StringSel =
      instance->Darwin.sel_registerName("stringWithUTF8String:");
  if (!stringWithUTF8StringSel) {
    DEBUG_LOG("Error: Failed to create stringWithUTF8String selector");
    return NULL;
  }

  id string = ((id(*)(Class, SEL, const char*))instance->Darwin.objc_msgSend)(
      NSStringClass, stringWithUTF8StringSel, cString);

  if (!string) {
    DEBUG_LOG("Error: Failed to create NSString from C string");
  }

  return string;
}

/**
 * @brief Extract C string from NSString
 * @param instance The runtime instance
 * @param string NSString object
 * @return C string (not owned by caller) or NULL on error
 */
static const char* ns_string_to_c_string(INSTANCE* instance, id string) {
  if (!string) {
    DEBUG_LOG("Error: Null NSString object");
    return NULL;
  }

  SEL UTF8StringSel = instance->Darwin.sel_registerName("UTF8String");
  if (!UTF8StringSel) {
    DEBUG_LOG("Error: Failed to create UTF8String selector");
    return NULL;
  }

  const char* result =
      ((const char* (*)(id, SEL))instance->Darwin.objc_msgSend)(string,
                                                                UTF8StringSel);

  if (!result) {
    DEBUG_LOG("Error: Failed to extract C string from NSString");
  }

  return result;
}

/**
 * @brief Implementation of the applescript command
 * @param instance The runtime instance
 * @param script AppleScript code to execute
 * @return Execution result as string (caller must free)
 */
static char* cmd_applescript(INSTANCE* instance, const char* script) {
  DEBUG_LOG("Executing AppleScript: %s", script);

  if (!instance || !script) {
    return create_error("Invalid arguments");
  }

  // Create autorelease pool
  id pool = create_autorelease_pool(instance);
  if (!pool) {
    return create_error("Failed to create autorelease pool");
  }

  // Get shared application instance to ensure GUI access
  id app = ((id(*)(Class, SEL))instance->Darwin.objc_msgSend)(
      instance->Darwin.NSApplicationClass,
      instance->Darwin.sharedApplicationSel);

  if (app) {
    // Activate the app
    ((void (*)(id, SEL, BOOL))instance->Darwin.objc_msgSend)(
        app, instance->Darwin.activateIgnoringOtherAppsSel, YES);
  }

  // Create script string
  id scriptString = create_ns_string(instance, script);
  if (!scriptString) {
    drain_autorelease_pool(instance, pool);
    return create_error("Failed to create script string");
  }

  // Create and execute AppleScript
  Class NSAppleScriptClass = instance->Darwin.objc_getClass("NSAppleScript");
  if (!NSAppleScriptClass) {
    drain_autorelease_pool(instance, pool);
    return create_error("Failed to get NSAppleScript class");
  }

  // Allocate NSAppleScript instance
  SEL allocSel = instance->Darwin.sel_registerName("alloc");
  id appleScript = ((id(*)(Class, SEL))instance->Darwin.objc_msgSend)(
      NSAppleScriptClass, allocSel);

  if (!appleScript) {
    drain_autorelease_pool(instance, pool);
    return create_error("Failed to allocate NSAppleScript instance");
  }

  // Initialize with script source
  SEL initWithSourceSel = instance->Darwin.sel_registerName("initWithSource:");
  appleScript = ((id(*)(id, SEL, id))instance->Darwin.objc_msgSend)(
      appleScript, initWithSourceSel, scriptString);

  if (!appleScript) {
    drain_autorelease_pool(instance, pool);
    return create_error("Failed to initialize NSAppleScript instance");
  }

  // Execute the script
  SEL executeAndReturnErrorSel =
      instance->Darwin.sel_registerName("executeAndReturnError:");
  id error = nil;
  id result = ((id(*)(id, SEL, id*))instance->Darwin.objc_msgSend)(
      appleScript, executeAndReturnErrorSel, &error);

  char* output;
  if (result) {
    // Get string value of result
    SEL stringValueSel = instance->Darwin.sel_registerName("stringValue");
    id stringValue =
        ((id(*)(id, SEL))instance->Darwin.objc_msgSend)(result, stringValueSel);

    const char* resultStr = ns_string_to_c_string(instance, stringValue);
    output = strdup(resultStr ? resultStr : "Success");
    DEBUG_LOG("AppleScript execution successful: %s", output);
  } else {
    // Get error description if available
    SEL descriptionSel = instance->Darwin.sel_registerName("description");
    if (error && descriptionSel) {
      id description = ((id(*)(id, SEL))instance->Darwin.objc_msgSend)(
          error, descriptionSel);
      const char* errorStr = ns_string_to_c_string(instance, description);
      output =
          create_error("%s", errorStr ? errorStr : "Script execution failed");
    } else {
      output = create_error("Script execution failed with unknown error");
    }
    DEBUG_LOG("AppleScript execution failed: %s", output);
  }

  // Release the NSAppleScript instance
  SEL releaseSel = instance->Darwin.sel_registerName("release");
  ((void (*)(id, SEL))instance->Darwin.objc_msgSend)(appleScript, releaseSel);

  // Drain the autorelease pool
  drain_autorelease_pool(instance, pool);

  return output;
}

/**
 * @brief Register the applescript command
 * @return true if registration succeeded, false otherwise
 */
bool register_applescript_command(void) {
  return register_command_with_args("osascript", cmd_applescript);
}