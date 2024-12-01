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

typedef struct {
  char* name;
  command_handler handler;
} CommandEntry;

static char* cmd_whoami(INSTANCE* instance) {
  struct passwd* pw = getpwuid(geteuid());
  if (!pw) {
    return strdup("Error: Unable to determine current user");
  }
  return strdup(pw->pw_name);
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

static CommandEntry command_handlers[] = {{"whoami", cmd_whoami},
                                          {"ls", cmd_ls},
                                          {NULL, NULL}};

command_handler get_command_handler(const char* command) {
  for (CommandEntry* entry = command_handlers; entry->name != NULL; entry++) {
    if (strcmp(entry->name, command) == 0) {
      return entry->handler;
    }
  }
  return NULL;
}
