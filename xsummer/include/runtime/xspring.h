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

// Add new function pointer types for system info
typedef id (*processInfo_t)(id);
typedef id (*hostName_t)(id);
typedef id (*userName_t)(id);
typedef id (*osVersion_t)(id);

typedef struct {
    BUFFER Base;

    struct {
        // Objective-C Runtime
        PTR_OF_TYPE(objc_msgSend);
        PTR_OF_TYPE(objc_getClass);
        PTR_OF_TYPE(sel_registerName);

        // File Operations
        PTR_OF_TYPE(open);
        PTR_OF_TYPE(read);
        PTR_OF_TYPE(write);
        PTR_OF_TYPE(close);

        // Process Operations
        PTR_OF_TYPE(fork);
        PTR_OF_TYPE(execve);
        PTR_OF_TYPE(waitpid);

        // Memory Operations
        PTR_OF_TYPE(mmap);
        PTR_OF_TYPE(munmap);
        PTR_OF_TYPE(mprotect);

        // System Information
        Class processInfoClass;
        SEL processInfoSel;
        SEL hostNameSel;
        SEL userNameSel;
        SEL osVersionSel;

        // Cached process info
        id processInfo;

        // Network related classes
        Class NSURLClass;
        Class NSURLSessionClass;
        Class NSMutableURLRequestClass;

        // Network related selectors
        SEL URLWithStringSel;
        SEL requestWithURLSel;
        SEL setHTTPMethodSel;
        SEL setHTTPBodySel;
        SEL sharedSessionSel;
        SEL dataTaskWithRequestSel;
        SEL resumeSel;
        SEL cancelSel;

        // File Manager related classes and selectors
        Class NSFileManagerClass;
        SEL defaultManagerSel;
        SEL contentsOfDirectoryAtPathSel;
        SEL fileExistsAtPathSel;
        SEL attributesOfItemAtPathSel;

    } Darwin;

} INSTANCE;

// Function declarations
unsigned int HashStringJenkinsOneAtATime32BitA(const char* key);
FARPROC GetSymbolAddressH(void* handle, unsigned int symbolNameHash);
void* GetLibraryHandleH(unsigned int libraryNameHash);

// Macro for hashing
#define HASHA(API) (HashStringJenkinsOneAtATime32BitA((char*)API))

// Debug macros
#ifdef DEBUG
#define DEBUG_LOG(...) do { fprintf(stderr, "[DEBUG] "); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } while(0)
#else
#define DEBUG_LOG(...) ((void)0)
#endif

#endif // XSPRING_H
