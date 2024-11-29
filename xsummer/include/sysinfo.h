#ifndef XSUMMER_SYSINFO_H
#define XSUMMER_SYSINFO_H

#include <runtime/xspring.h>
#include <stdbool.h>
#include <stddef.h>

// Structure to hold all system information
typedef struct SystemInfo {
    char hostname[256];
    char username[256];
    char os_version[256];
} SystemInfo;

// Public API
bool GetSystemHostName(INSTANCE* instance, char* buffer, size_t buflen);
bool GetSystemUserName(INSTANCE* instance, char* buffer, size_t buflen);
bool GetSystemOSVersion(INSTANCE* instance, char* buffer, size_t buflen);
bool GetAllSystemInfo(INSTANCE* instance, SystemInfo* info);

#endif // XSUMMER_SYSINFO_H
