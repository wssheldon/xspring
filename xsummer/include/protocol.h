#ifndef PROTOCOL_H
#define PROTOCOL_H

#include <stddef.h>
#include <stdbool.h>
#include "client.h"
#include "sysinfo.h"

#define PROTOCOL_VERSION 1

typedef uint8_t protocol_msg_type_t;
enum {
    PROTOCOL_MSG_PING = 1,
    PROTOCOL_MSG_INIT,
    PROTOCOL_MSG_INFO,
    PROTOCOL_MSG_ERROR
};

typedef struct ProtocolBuilder ProtocolBuilder;

#if defined(__clang__) || defined(__GNUC__)
#define NODISCARD __attribute__((warn_unused_result))
#else
#define NODISCARD
#endif


NODISCARD ProtocolBuilder* protocol_builder_create(protocol_msg_type_t type);
void protocol_builder_destroy(ProtocolBuilder* builder);

NODISCARD bool protocol_add_string(ProtocolBuilder* builder,
                                 const char* key,
                                 const char* value);

NODISCARD bool protocol_add_int(ProtocolBuilder* builder,
                               const char* key,
                               int value);

bool protocol_add_uint(ProtocolBuilder* builder, const char* key, unsigned int value);
bool protocol_add_bool(ProtocolBuilder* builder, const char* key, bool value);
bool protocol_add_binary(ProtocolBuilder* builder, const char* key, const void* data, size_t length);
bool protocol_add_bytes(ProtocolBuilder* builder, const char* key, const unsigned char* data, size_t length);
bool protocol_add_hex(ProtocolBuilder* builder, const char* key, const unsigned char* data, size_t length);

const char* protocol_get_message(const ProtocolBuilder* builder);
size_t protocol_get_length(const ProtocolBuilder* builder);
bool protocol_has_error(const ProtocolBuilder* builder);

ProtocolBuilder* protocol_create_ping(const char* client_id);
ProtocolBuilder* protocol_create_init(const char* client_id, const SystemInfo* info);
ProtocolBuilder* protocol_create_error(int error_code, const char* error_message);

#endif
