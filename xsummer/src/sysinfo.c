#include <sysinfo.h>
#include <string.h>
#include <stdio.h>

#ifdef DEBUG
#include <stdarg.h>
static inline void debug_log(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    fprintf(stderr, "[DEBUG] ");
    vfprintf(stderr, fmt, args);
    fprintf(stderr, "\n");
    va_end(args);
}
#define DEBUG_LOG(...) debug_log(__VA_ARGS__)
#else
#define DEBUG_LOG(...) ((void)0)
#endif

typedef enum {
    SYSTEM_INFO_HOSTNAME,
    SYSTEM_INFO_USERNAME,
    SYSTEM_INFO_OSVERSION,
    SYSTEM_INFO_COUNT
} SystemInfoType;

// Structure to hold selector information
typedef struct {
    const char* selector_name;
    const char* utf8_selector_name;
} SelectorInfo;

// Structure to define system information retrieval
typedef struct {
    const char* name;          // Human readable name for debugging
    SelectorInfo selector;     // Selector information
    bool required;             // Whether this info is required for initialization
} SystemInfoDef;

// Table defining all system information types
static const SystemInfoDef SYSTEM_INFO_DEFS[SYSTEM_INFO_COUNT] = {
    [SYSTEM_INFO_HOSTNAME] = {
        .name = "hostname",
        .selector = {
            .selector_name = "hostName",
            .utf8_selector_name = "UTF8String"
        },
        .required = true
    },
    [SYSTEM_INFO_USERNAME] = {
        .name = "username",
        .selector = {
            .selector_name = "userName",
            .utf8_selector_name = "UTF8String"
        },
        .required = true
    },
    [SYSTEM_INFO_OSVERSION] = {
        .name = "os_version",
        .selector = {
            .selector_name = "operatingSystemVersionString",
            .utf8_selector_name = "UTF8String"
        },
        .required = true
    }
};

static struct {
    SEL selectors[SYSTEM_INFO_COUNT];
    SEL utf8_selector;
    bool initialized;
} SelectorCache = {0};

static bool ensure_selectors(INSTANCE* instance) {
    if (SelectorCache.initialized) return true;

    // Initialize UTF8String selector
    SelectorCache.utf8_selector = instance->Darwin.sel_registerName("UTF8String");
    if (!SelectorCache.utf8_selector) return false;

    // Initialize other selectors
    for (size_t i = 0; i < SYSTEM_INFO_COUNT; i++) {
        SelectorCache.selectors[i] = instance->Darwin.sel_registerName(
            SYSTEM_INFO_DEFS[i].selector.selector_name
        );
        if (!SelectorCache.selectors[i]) return false;
    }

    SelectorCache.initialized = true;
    return true;
}

// Safe string copy helper
static bool safe_strcpy(char* dst, size_t dst_size, const char* src) {
    if (!dst || !src || dst_size == 0) return false;
    size_t len = strlen(src);
    if (len >= dst_size) return false;
    memcpy(dst, src, len + 1);
    return true;
}

// Generic system information getter
static bool internal_get_system_info(INSTANCE* instance, SystemInfoType type,
                                   char* buffer, size_t buflen) {
    if (!instance || !buffer || buflen == 0 || type >= SYSTEM_INFO_COUNT) {
        DEBUG_LOG("Invalid parameters for GetSystemInfo");
        return false;
    }

    const SystemInfoDef* def = &SYSTEM_INFO_DEFS[type];
    DEBUG_LOG("Getting %s...", def->name);

    if (!ensure_selectors(instance)) {
        DEBUG_LOG("Failed to initialize selectors");
        return false;
    }

    // Get the information using the cached selector
    id info = instance->Darwin.objc_msgSend(
        instance->Darwin.processInfo,
        SelectorCache.selectors[type]
    );

    if (!info) {
        DEBUG_LOG("Failed to get %s", def->name);
        return false;
    }

    const char* str = ((const char* (*)(id, SEL))instance->Darwin.objc_msgSend)(
        info, SelectorCache.utf8_selector);

    if (!str) {
        DEBUG_LOG("Failed to get string value for %s", def->name);
        return false;
    }

    if (!safe_strcpy(buffer, buflen, str)) {
        DEBUG_LOG("Buffer too small for %s", def->name);
        return false;
    }

    DEBUG_LOG("Got %s: %s", def->name, buffer);
    return true;
}

bool GetSystemHostName(INSTANCE* instance, char* buffer, size_t buflen) {
    return internal_get_system_info(instance, SYSTEM_INFO_HOSTNAME, buffer, buflen);
}

bool GetSystemUserName(INSTANCE* instance, char* buffer, size_t buflen) {
    return internal_get_system_info(instance, SYSTEM_INFO_USERNAME, buffer, buflen);
}

bool GetSystemOSVersion(INSTANCE* instance, char* buffer, size_t buflen) {
    return internal_get_system_info(instance, SYSTEM_INFO_OSVERSION, buffer, buflen);
}

bool GetAllSystemInfo(INSTANCE* instance, SystemInfo* info) {
    if (!instance || !info) return false;

    bool success = true;
    success &= GetSystemHostName(instance, info->hostname, sizeof(info->hostname));
    success &= GetSystemUserName(instance, info->username, sizeof(info->username));
    success &= GetSystemOSVersion(instance, info->os_version, sizeof(info->os_version));
    return success;
}
