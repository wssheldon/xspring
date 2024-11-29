#ifndef RUNTIME_OBFUSCATE_H
#define RUNTIME_OBFUSCATE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Declarations
char* obfuscate_string(const char* str, size_t len);
const char* get_encrypted_string(size_t* out_len);

// Macro for string obfuscation
#define OBF(str) ({ \
    size_t len; \
    const char* encrypted = get_encrypted_string(&len); \
    obfuscate_string(encrypted, len); \
})

#ifdef __cplusplus
}
#endif

#endif
