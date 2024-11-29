#ifndef XSPRING_H
#define XSPRING_H

#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <dlfcn.h>
#include <objc/runtime.h>
#include <objc/message.h>
#include <sys/types.h>
#include <sys/sysctl.h>
#include <sys/stat.h>
#include <libproc.h>
#include <libgen.h>
#include <unistd.h>

#define MAX_PATH 1024
typedef void* FARPROC;

typedef struct _BUFFER {
    void* Buffer;
    uint64_t Length;
} BUFFER, *PBUFFER;

#define PTR_OF_TYPE(x) x##_t x

// Common function pointer types used by Darwin APIs
typedef id (*objc_msgSend_t)(id, SEL, ...);
typedef Class (*objc_getClass_t)(const char*);
typedef SEL (*sel_registerName_t)(const char*);

// File operations
typedef int (*open_t)(const char*, int, ...);
typedef ssize_t (*read_t)(int, void*, size_t);
typedef ssize_t (*write_t)(int, const void*, size_t);
typedef int (*close_t)(int);

// Process operations
typedef pid_t (*fork_t)(void);
typedef int (*execve_t)(const char*, char *const[], char *const[]);
typedef pid_t (*waitpid_t)(pid_t, int*, int);

// Memory operations
typedef void* (*mmap_t)(void*, size_t, int, int, int, off_t);
typedef int (*munmap_t)(void*, size_t);
typedef int (*mprotect_t)(void*, size_t, int);

typedef struct {
    BUFFER Base;

    struct {
        // libobjc.dylib
        PTR_OF_TYPE(objc_msgSend);

    } Darwin;

} INSTANCE;

unsigned int HashStringJenkinsOneAtATime32BitA(const char* key);
FARPROC GetSymbolAddressH(void* handle, unsigned int symbolNameHash);
void* GetLibraryHandleH(unsigned int libraryNameHash);

#endif