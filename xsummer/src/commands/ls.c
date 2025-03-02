/**
 * @file ls.c
 * @brief Implementation of the ls command
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
 * @brief Helper function to get current working directory
 * @param buffer Buffer to write path to
 * @param buffer_size Size of buffer
 * @return true if successful, false on error
 */
static bool get_current_working_directory(char* buffer, size_t buffer_size) {
  if (!getcwd(buffer, buffer_size)) {
    return false;
  }
  return true;
}

/**
 * @brief Helper function to create an NSString from a C string
 * @param instance The runtime instance
 * @param cString C string to convert
 * @return NSString object or NULL on error
 */
static id create_ns_string(INSTANCE* instance, const char* cString) {
  Class NSStringClass = instance->Darwin.objc_getClass("NSString");
  if (!NSStringClass) {
    return NULL;
  }

  SEL stringWithUTF8StringSel =
      instance->Darwin.sel_registerName("stringWithUTF8String:");
  if (!stringWithUTF8StringSel) {
    return NULL;
  }

  return ((id(*)(Class, SEL, const char*))instance->Darwin.objc_msgSend)(
      NSStringClass, stringWithUTF8StringSel, cString);
}

/**
 * @brief Helper function to convert NSString to C string
 * @param instance The runtime instance
 * @param string NSString object
 * @return C string or NULL on error (not owned by caller)
 */
static const char* ns_string_to_c_string(INSTANCE* instance, id string) {
  if (!string) {
    return NULL;
  }

  SEL UTF8StringSel = instance->Darwin.sel_registerName("UTF8String");
  if (!UTF8StringSel) {
    return NULL;
  }

  return ((const char* (*)(id, SEL))instance->Darwin.objc_msgSend)(
      string, UTF8StringSel);
}

/**
 * @brief Implementation of the ls command
 * @param instance The runtime instance
 * @return Directory listing as string (caller must free)
 */
static char* cmd_ls(INSTANCE* instance) {
  DEBUG_LOG("Starting ls command");

  if (!instance) {
    DEBUG_LOG("Error: Null instance pointer");
    return create_error("Internal error - null instance");
  }

  char* result = malloc(COMMAND_BUFFER_SIZE);
  if (!result) {
    DEBUG_LOG("Error: Failed to allocate result buffer");
    return create_error("Memory allocation failed");
  }

  size_t offset = 0;

  // Get current working directory
  char cwd[PATH_MAX];
  if (!get_current_working_directory(cwd, sizeof(cwd))) {
    DEBUG_LOG("Error: Failed to get current working directory");
    free(result);
    return create_error("Unable to get current directory");
  }
  DEBUG_LOG("Current working directory: %s", cwd);

  // Create path string
  id pathString = create_ns_string(instance, cwd);
  if (!pathString) {
    DEBUG_LOG("Error: Failed to create path string");
    free(result);
    return create_error("Failed to create path string");
  }

  DEBUG_LOG("Successfully created path string");

  // Get file manager
  DEBUG_LOG("Getting file manager");
  if (!instance->Darwin.NSFileManagerClass) {
    DEBUG_LOG("Error: NSFileManagerClass is null");
    free(result);
    return create_error("FileManager class not initialized");
  }

  if (!instance->Darwin.defaultManagerSel) {
    DEBUG_LOG("Error: defaultManagerSel is null");
    free(result);
    return create_error("FileManager selector not initialized");
  }

  DEBUG_LOG("Calling defaultManager on NSFileManager");
  id fileManager = ((id(*)(id, SEL))instance->Darwin.objc_msgSend)(
      (id)instance->Darwin.NSFileManagerClass,
      instance->Darwin.defaultManagerSel);

  if (!fileManager) {
    DEBUG_LOG("Error: Failed to get file manager instance");
    free(result);
    return create_error("Failed to create file manager");
  }

  DEBUG_LOG("Successfully got file manager instance");

  // Get directory contents
  DEBUG_LOG("Getting directory contents");
  if (!instance->Darwin.contentsOfDirectoryAtPathSel) {
    DEBUG_LOG("Error: contentsOfDirectoryAtPathSel is null");
    free(result);
    return create_error("Directory contents selector not initialized");
  }

  id error = nil;
  DEBUG_LOG("Calling contentsOfDirectoryAtPath:error:");

  // Get directory contents
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
          const char* errorStr = ns_string_to_c_string(instance, description);
          DEBUG_LOG("Error details: %s", errorStr ? errorStr : "Unknown error");
        }
      }
    }
    free(result);
    return create_error("Unable to list directory contents");
  }

  DEBUG_LOG("Successfully got directory contents");

  // Get array count
  DEBUG_LOG("Getting array count");
  SEL countSel = instance->Darwin.sel_registerName("count");
  if (!countSel) {
    DEBUG_LOG("Error: Failed to create count selector");
    free(result);
    return create_error("Failed to create count selector");
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
  SEL stringByAppendingPathComponentSel =
      instance->Darwin.sel_registerName("stringByAppendingPathComponent:");
  SEL fileSizeSel = instance->Darwin.sel_registerName("fileSize");
  SEL fileTypeSel = instance->Darwin.sel_registerName("fileType");
  SEL modificationDateSel =
      instance->Darwin.sel_registerName("fileModificationDate");
  SEL descriptionSel = instance->Darwin.sel_registerName("description");

  // Verify all selectors
  if (!objectAtIndexSel || !stringByAppendingPathComponentSel || !fileSizeSel ||
      !fileTypeSel || !modificationDateSel || !descriptionSel) {
    DEBUG_LOG("Error: Failed to create one or more required selectors");
    free(result);
    return create_error("Failed to create required selectors");
  }

  // Iterate through contents
  DEBUG_LOG("Starting directory iteration");
  for (NSUInteger i = 0; i < itemCount && offset < COMMAND_BUFFER_SIZE - 256;
       i++) {
    DEBUG_LOG("Processing item %lu of %lu", (unsigned long)i,
              (unsigned long)itemCount);

    // Get filename
    id fileName = ((id(*)(id, SEL, NSUInteger))instance->Darwin.objc_msgSend)(
        contents, objectAtIndexSel, i);

    if (!fileName) {
      DEBUG_LOG("Error: Failed to get filename for index %lu",
                (unsigned long)i);
      continue;
    }

    // Get the filename as a C string
    const char* name = ns_string_to_c_string(instance, fileName);
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
    const char* typeStr = ns_string_to_c_string(instance, fileType);

    // Get modification date
    id modDate = ((id(*)(id, SEL))instance->Darwin.objc_msgSend)(
        attributes, modificationDateSel);
    id dateStr = ((id(*)(id, SEL))instance->Darwin.objc_msgSend)(
        modDate, descriptionSel);
    const char* dateChars = ns_string_to_c_string(instance, dateStr);

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

/**
 * @brief Register the ls command
 * @return true if registration succeeded, false otherwise
 */
bool register_ls_command(void) {
  return register_command("ls", cmd_ls);
}