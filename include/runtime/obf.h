#ifndef RUNTIME_OBFUSCATE_H
#define RUNTIME_OBFUSCATE_H

#include <stdint.h>
#include <stddef.h>
#include <string.h>  // for strlen
#include <stdlib.h>  // for free

#ifdef __cplusplus
extern "C" {
#endif

// Declarations
char* obfuscate_string(const char* str, size_t len);
const char* get_encrypted_string(size_t* out_len);

// Helper macro to make static analyzer's job harder
#define OBFUSCATE_CONCAT(x, y) x ## y
#define CONCAT(x, y) OBFUSCATE_CONCAT(x, y)

// Create unique identifier for each usage
#define UNIQUE_ID(prefix) CONCAT(prefix, __LINE__)

// Macro to create stack cleanup
#define CLEANUP_STACK __attribute__((cleanup(cleanup_buffer)))

// Macro for string obfuscation with automatic cleanup
#define OBF(str) ({ \
    CLEANUP_STACK char* UNIQUE_ID(result) = NULL; \
    size_t UNIQUE_ID(len); \
    const char* UNIQUE_ID(encrypted) = get_encrypted_string(&UNIQUE_ID(len)); \
    UNIQUE_ID(result) = obfuscate_string(UNIQUE_ID(encrypted), UNIQUE_ID(len)); \
    UNIQUE_ID(result); \
})

// Macro for inline string obfuscation with size
#define OBF_WITH_SIZE(str, size_ptr) ({ \
    CLEANUP_STACK char* UNIQUE_ID(result) = NULL; \
    const char* UNIQUE_ID(encrypted) = get_encrypted_string(size_ptr); \
    UNIQUE_ID(result) = obfuscate_string(UNIQUE_ID(encrypted), *size_ptr); \
    UNIQUE_ID(result); \
})

// Helper function for cleanup attribute
static inline void cleanup_buffer(char** buf) {
    if (*buf) {
        volatile char* ptr = *buf;
        size_t len = strlen(ptr);
        while (len--) {
            ((volatile char*)*buf)[len] = 0;
        }
        free(*buf);
        *buf = NULL;
    }
}

#ifdef __cplusplus
}
#endif

#endif
