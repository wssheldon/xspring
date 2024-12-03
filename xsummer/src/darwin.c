
#include "runtime/darwin.h"
#include <limits.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach/mach.h>
#include <mach/task.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "runtime/obf.h"

#ifdef DEBUG
#define DEBUG_LOG(...)            \
  do {                            \
    fprintf(stderr, "[DEBUG] ");  \
    fprintf(stderr, __VA_ARGS__); \
    fprintf(stderr, "\n");        \
  } while (0)
#else
#define DEBUG_LOG(...) ((void)0)
#endif

unsigned int HashStringJenkinsOneAtATime32BitA(const char* key) {
  size_t len = strlen(key);
  unsigned int hash = 0;
  for (size_t i = 0; i < len; ++i) {
    hash += key[i];
    hash += (hash << 10);
    hash ^= (hash >> 6);
  }
  hash += (hash << 3);
  hash ^= (hash >> 11);
  hash += (hash << 15);
  return hash;
}

#define HASHA(API) (HashStringJenkinsOneAtATime32BitA((char*)API))

FARPROC GetSymbolAddressH(void* handle, unsigned int symbolNameHash) {
  if (!handle)
    return NULL;

  const struct mach_header_64* header = (const struct mach_header_64*)handle;
  const struct load_command* cmd =
      (struct load_command*)((char*)header + sizeof(struct mach_header_64));

  const struct segment_command_64* linkedit = NULL;
  const struct segment_command_64* text = NULL;
  struct symtab_command* symtab = NULL;

  for (int i = 0; i < header->ncmds; i++) {
    if (cmd->cmd == LC_SEGMENT_64) {
      const struct segment_command_64* seg = (struct segment_command_64*)cmd;
      if (strcmp(seg->segname, "__LINKEDIT") == 0)
        linkedit = seg;
      if (strcmp(seg->segname, "__TEXT") == 0)
        text = seg;
    } else if (cmd->cmd == LC_SYMTAB)
      symtab = (struct symtab_command*)cmd;
    cmd = (const struct load_command*)((char*)cmd + cmd->cmdsize);
  }

  intptr_t slide = (intptr_t)header - text->vmaddr;
  const uintptr_t linkedit_base =
      (uintptr_t)slide + linkedit->vmaddr - linkedit->fileoff;

  const struct nlist_64* symtab_addr =
      (struct nlist_64*)(linkedit_base + symtab->symoff);
  const char* strtab = (char*)(linkedit_base + symtab->stroff);

  for (uint32_t i = 0; i < symtab->nsyms; i++) {
    if (symtab_addr[i].n_type & N_STAB)
      continue;
    const char* sym_name = strtab + symtab_addr[i].n_un.n_strx;
    if (sym_name && sym_name[0] != '\0') {
      if (HASHA(sym_name) == symbolNameHash) {
        return (FARPROC)(symtab_addr[i].n_value + slide);
      }
    }
  }
  return NULL;
}

static struct {
  const struct dyld_all_image_infos* infos;
  bool initialized;
} dyld_cache = {0};

static bool init_dyld_cache(void) {
  if (dyld_cache.initialized)
    return true;

  struct task_dyld_info info = {0};
  mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;

  if (task_info(mach_task_self(), TASK_DYLD_INFO, (task_info_t)&info, &count) ==
      KERN_SUCCESS) {
    dyld_cache.infos =
        (const struct dyld_all_image_infos*)info.all_image_info_addr;
    dyld_cache.initialized = true;
    return true;
  }
  return false;
}

void* GetLibraryHandleH(unsigned int libraryNameHash) {
  if (!init_dyld_cache() || !dyld_cache.infos)
    return NULL;

  _Alignas(16) char name_buf[PATH_MAX];
  const struct dyld_image_info* curr_info = dyld_cache.infos->infoArray;
  const uint32_t count = dyld_cache.infos->infoArrayCount;

  for (uint32_t i = 0; i < count; i++, curr_info++) {
    if (!curr_info || !curr_info->imageFilePath)
      continue;

    const char* base = strrchr(curr_info->imageFilePath, '/');
    if (!base++)
      continue;

    size_t len = strlen(base);
    if (len >= PATH_MAX)
      continue;

    for (size_t j = 0; j < len; j++) {
      name_buf[j] = (base[j] >= 'a' && base[j] <= 'z') ? base[j] - 32 : base[j];
    }
    name_buf[len] = '\0';

    if (HASHA(name_buf) == libraryNameHash) {
      return (void*)curr_info->imageLoadAddress;
    }
  }
  return NULL;
}

bool InitializeDarwinApi(INSTANCE* instance) {
  DEBUG_LOG("Starting API initialization");

  void* objc = GetLibraryHandleH(getLibHash());
  if (!objc) {
    DEBUG_LOG("Failed to get libobjc handle");
    return false;
  }
  DEBUG_LOG("Library handle obtained successfully: %p", objc);

  // Initialize Objective-C runtime functions
  instance->Darwin.objc_msgSend =
      (objc_msgSend_t)GetSymbolAddressH(objc, getObjcMsgSendHash());
  instance->Darwin.objc_getClass =
      (objc_getClass_t)GetSymbolAddressH(objc, getObjcGetClassHash());
  instance->Darwin.sel_registerName =
      (sel_registerName_t)GetSymbolAddressH(objc, getSelRegisterNameHash());

  if (!instance->Darwin.objc_msgSend || !instance->Darwin.objc_getClass ||
      !instance->Darwin.sel_registerName) {
    DEBUG_LOG("Failed to resolve basic Objective-C functions");
    return false;
  }

  // Initialize ProcessInfo
  instance->Darwin.processInfoClass =
      instance->Darwin.objc_getClass("NSProcessInfo");
  instance->Darwin.processInfoSel =
      instance->Darwin.sel_registerName("processInfo");
  instance->Darwin.hostNameSel = instance->Darwin.sel_registerName("hostName");
  instance->Darwin.userNameSel = instance->Darwin.sel_registerName("userName");
  instance->Darwin.osVersionSel =
      instance->Darwin.sel_registerName("operatingSystemVersionString");

  // Initialize FileManager
  DEBUG_LOG("Initializing FileManager");
  const char* fileManagerClassName = "NSFileManager";
  instance->Darwin.NSFileManagerClass =
      instance->Darwin.objc_getClass(fileManagerClassName);
  if (!instance->Darwin.NSFileManagerClass) {
    DEBUG_LOG("Failed to get NSFileManager class using direct name");
    return false;
  }
  DEBUG_LOG("Successfully got NSFileManager class");

  instance->Darwin.defaultManagerSel =
      instance->Darwin.sel_registerName("defaultManager");
  if (!instance->Darwin.defaultManagerSel) {
    DEBUG_LOG("Failed to create defaultManager selector");
    return false;
  }
  DEBUG_LOG("Successfully created defaultManager selector");

  instance->Darwin.contentsOfDirectoryAtPathSel =
      instance->Darwin.sel_registerName("contentsOfDirectoryAtPath:error:");
  if (!instance->Darwin.contentsOfDirectoryAtPathSel) {
    DEBUG_LOG("Failed to create contentsOfDirectoryAtPath selector");
    return false;
  }
  DEBUG_LOG("Successfully created contentsOfDirectoryAtPath selector");

  instance->Darwin.fileExistsAtPathSel =
      instance->Darwin.sel_registerName("fileExistsAtPath:");
  if (!instance->Darwin.fileExistsAtPathSel) {
    DEBUG_LOG("Failed to create fileExistsAtPath selector");
    return false;
  }

  instance->Darwin.attributesOfItemAtPathSel =
      instance->Darwin.sel_registerName("attributesOfItemAtPath:error:");
  if (!instance->Darwin.attributesOfItemAtPathSel) {
    DEBUG_LOG("Failed to create attributesOfItemAtPath selector");
    return false;
  }

  // Cache process info instance
  instance->Darwin.processInfo = instance->Darwin.objc_msgSend(
      (id)instance->Darwin.processInfoClass, instance->Darwin.processInfoSel);

  if (!instance->Darwin.processInfo) {
    DEBUG_LOG("Failed to get processInfo instance");
    return false;
  }

  DEBUG_LOG("Initializing AppKit framework");

  // Load AppKit framework
  instance->Darwin.appKitHandle =
      dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", RTLD_LAZY);
  if (!instance->Darwin.appKitHandle) {
    DEBUG_LOG("Failed to load AppKit framework: %s", dlerror());
    return false;
  }

  // Initialize NSApplication class and selectors
  instance->Darwin.NSApplicationClass =
      instance->Darwin.objc_getClass("NSApplication");
  if (!instance->Darwin.NSApplicationClass) {
    DEBUG_LOG("Failed to get NSApplication class");
    return false;
  }

  instance->Darwin.sharedApplicationSel =
      instance->Darwin.sel_registerName("sharedApplication");
  instance->Darwin.setActivationPolicySel =
      instance->Darwin.sel_registerName("setActivationPolicy:");
  instance->Darwin.activateIgnoringOtherAppsSel =
      instance->Darwin.sel_registerName("activateIgnoringOtherApps:");

  // Initialize NSAlert class
  instance->Darwin.NSAlertClass = instance->Darwin.objc_getClass("NSAlert");
  if (!instance->Darwin.NSAlertClass) {
    DEBUG_LOG("Failed to get NSAlert class");
    return false;
  }

  instance->Darwin.NSRunLoopClass = instance->Darwin.objc_getClass("NSRunLoop");
  if (!instance->Darwin.NSRunLoopClass) {
    DEBUG_LOG("Failed to get NSRunLoop class");
    return false;
  }

  instance->Darwin.beginModalSessionSel =
      instance->Darwin.sel_registerName("beginModalSessionForWindow:");
  instance->Darwin.runModalSessionSel =
      instance->Darwin.sel_registerName("runModalSession:");
  instance->Darwin.endModalSessionSel =
      instance->Darwin.sel_registerName("endModalSession:");
  instance->Darwin.mainRunLoopSel =
      instance->Darwin.sel_registerName("mainRunLoop");

  // Initialize NSAutoreleasePool class
  instance->Darwin.NSAutoreleasePoolClass =
      instance->Darwin.objc_getClass("NSAutoreleasePool");
  if (!instance->Darwin.NSAutoreleasePoolClass) {
    DEBUG_LOG("Failed to get NSAutoreleasePool class");
    return false;
  }

  DEBUG_LOG("Successfully initialized AppKit");

  DEBUG_LOG("Successfully initialized all Darwin APIs");
  return true;
}
