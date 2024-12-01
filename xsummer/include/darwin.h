#ifndef DARWIN_API_H
#define DARWIN_API_H

#include <stdbool.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <objc/runtime.h>
#include <objc/message.h>

typedef id (*objc_msgSend_t)(id, SEL, ...);
typedef Class (*objc_getClass_t)(const char*);
typedef SEL (*sel_registerName_t)(const char*);

typedef struct {
    // Core runtime functions
    objc_msgSend_t objc_msgSend;
    objc_getClass_t objc_getClass;
    sel_registerName_t sel_registerName;

    // System information
    Class processInfoClass;
    id processInfo;
    SEL processInfoSel;
    SEL hostNameSel;
    SEL userNameSel;
    SEL osVersionSel;

    // Network classes
    Class NSURLClass;
    Class NSURLSessionClass;
    Class NSMutableURLRequestClass;

    // Network selectors
    SEL URLWithStringSel;
    SEL requestWithURLSel;
    SEL setHTTPMethodSel;
    SEL setHTTPBodySel;
    SEL sharedSessionSel;
    SEL dataTaskWithRequestSel;
    SEL resumeSel;
    SEL cancelSel;
} DarwinContext;

// Public API
bool darwin_initialize(DarwinContext* context);
void darwin_cleanup(DarwinContext* context);

// System information getters
const char* darwin_get_hostname(const DarwinContext* context);
const char* darwin_get_username(const DarwinContext* context);
const char* darwin_get_os_version(const DarwinContext* context);

#endif
