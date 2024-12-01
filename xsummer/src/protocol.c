#include "protocol.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define INITIAL_BUFFER_SIZE ((size_t)1024)
#define MAX_KEY_LENGTH ((size_t)64)

struct ProtocolBuilder {
  char* buffer;
  size_t capacity;
  size_t length;
  bool error;
  protocol_msg_type_t type;
} __attribute__((aligned(sizeof(void*))));

static const char base64_chars[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static char* base64_encode(const unsigned char* data, size_t input_length,
                           size_t* output_length) {
  *output_length = 4 * ((input_length + 2) / 3);

  char* encoded_data = malloc(*output_length + 1);
  if (!encoded_data)
    return NULL;

  size_t i, j;
  for (i = 0, j = 0; i < input_length;) {
    uint32_t octet_a = i < input_length ? data[i++] : 0;
    uint32_t octet_b = i < input_length ? data[i++] : 0;
    uint32_t octet_c = i < input_length ? data[i++] : 0;

    uint32_t triple = (octet_a << 16) + (octet_b << 8) + octet_c;

    encoded_data[j++] = base64_chars[(triple >> 18) & 0x3F];
    encoded_data[j++] = base64_chars[(triple >> 12) & 0x3F];
    encoded_data[j++] = base64_chars[(triple >> 6) & 0x3F];
    encoded_data[j++] = base64_chars[triple & 0x3F];
  }

  // Add padding if necessary
  if (input_length % 3 > 0) {
    for (i = 0; i < 3 - (input_length % 3); i++) {
      encoded_data[*output_length - 1 - i] = '=';
    }
  }

  encoded_data[*output_length] = '\0';
  return encoded_data;
}

static char* escape_string(const char* input, size_t* output_length) {
  if (!input || !output_length)
    return NULL;

  size_t input_len = strlen(input);
  // allocate worst-case scenario (every character needs escaping)
  char* output = malloc(input_len * 2 + 1);
  if (!output)
    return NULL;

  size_t i, j;
  for (i = 0, j = 0; i < input_len; i++) {
    switch (input[i]) {
      case '\n':
        output[j++] = '\\';
        output[j++] = 'n';
        break;
      case '\r':
        output[j++] = '\\';
        output[j++] = 'r';
        break;
      case '\t':
        output[j++] = '\\';
        output[j++] = 't';
        break;
      case '\\':
        output[j++] = '\\';
        output[j++] = '\\';
        break;
      case ':':
        output[j++] = '\\';
        output[j++] = ':';
        break;
      default:
        // only include printable characters
        if (input[i] >= 32 && input[i] <= 126) {
          output[j++] = input[i];
        }
        break;
    }
  }

  output[j] = '\0';
  *output_length = j;

  // reallocate to actual size needed
  char* final = realloc(output, j + 1);
  return final ? final : output;
}

static inline bool ensure_capacity(ProtocolBuilder* builder,
                                   size_t additional) {
  if (!builder || builder->error)
    return false;

  size_t required = builder->length + additional;
  if (required <= builder->capacity)
    return true;

  size_t new_capacity = builder->capacity * 2;
  while (new_capacity < required) {
    new_capacity *= 2;
  }

  char* new_buffer = realloc(builder->buffer, new_capacity);
  if (!new_buffer) {
    builder->error = true;
    return false;
  }

  builder->buffer = new_buffer;
  builder->capacity = new_capacity;
  return true;
}

static bool append_data(ProtocolBuilder* builder, const char* data,
                        size_t length) {
  if (!ensure_capacity(builder, length + 1))
    return false;

  memcpy(builder->buffer + builder->length, data, length);
  builder->length += length;
  builder->buffer[builder->length] = '\0';

  return true;
}

NODISCARD ProtocolBuilder* protocol_builder_create(protocol_msg_type_t type) {
  ProtocolBuilder* builder = calloc(1, sizeof(*builder));
  if (!builder)
    return NULL;

  builder->buffer = malloc(INITIAL_BUFFER_SIZE);
  if (!builder->buffer) {
    free(builder);
    return NULL;
  }

  *builder = (ProtocolBuilder){.buffer = builder->buffer,
                               .capacity = INITIAL_BUFFER_SIZE,
                               .length = 0,
                               .error = false,
                               .type = type};

  // Add message type header
  char header[64];
  int written = snprintf(header, sizeof(header), "Version: %d\nType: %d\n",
                         PROTOCOL_VERSION, type);

  if (written < 0 || !append_data(builder, header, written)) {
    protocol_builder_destroy(builder);
    return NULL;
  }

  return builder;
}

void protocol_builder_destroy(ProtocolBuilder* builder) {
  if (!builder)
    return;
  if (builder->buffer) {
    // Secure cleanup
    memset(builder->buffer, 0, builder->capacity);
    free(builder->buffer);
  }
  memset(builder, 0, sizeof(ProtocolBuilder));
  free(builder);
}

bool protocol_add_string(ProtocolBuilder* builder, const char* key,
                         const char* value) {
  if (!builder || !key || !value || builder->error)
    return false;

  size_t escaped_len = 0;
  char* escaped_value = escape_string(value, &escaped_len);
  if (!escaped_value)
    return false;

  // Ensure the field buffer is large enough
  size_t key_len = strlen(key);
  size_t total_len =
      key_len + escaped_len + 3;  // key + ": " + escaped_value + "\n"
  char* field = malloc(total_len + 1);

  if (!field) {
    free(escaped_value);
    return false;
  }

  int written = snprintf(field, total_len + 1, "%s: %s\n", key, escaped_value);
  free(escaped_value);

  if (written < 0) {
    free(field);
    return false;
  }

  bool result = append_data(builder, field, written);
  free(field);

  return result;
}

bool protocol_add_int(ProtocolBuilder* builder, const char* key, int value) {
  char value_str[32];
  snprintf(value_str, sizeof(value_str), "%d", value);
  return protocol_add_string(builder, key, value_str);
}

bool protocol_add_uint(ProtocolBuilder* builder, const char* key,
                       unsigned int value) {
  char value_str[32];
  snprintf(value_str, sizeof(value_str), "%u", value);
  return protocol_add_string(builder, key, value_str);
}

bool protocol_add_bool(ProtocolBuilder* builder, const char* key, bool value) {
  return protocol_add_string(builder, key, value ? "true" : "false");
}

bool protocol_add_binary(ProtocolBuilder* builder, const char* key,
                         const void* data, size_t length) {
  if (!builder || !key || !data || builder->error)
    return false;

  // Base64 encode the binary data
  char* encoded = NULL;
  size_t encoded_len = 0;

  encoded = base64_encode(data, length, &encoded_len);
  if (!encoded)
    return false;

  bool result = protocol_add_string(builder, key, encoded);
  free(encoded);

  return result;
}

static char* bytes_to_hex(const unsigned char* data, size_t length,
                          size_t* out_len) {
  char* hex = malloc(length * 2 + 1);
  if (!hex)
    return NULL;

  for (size_t i = 0; i < length; i++) {
    sprintf(hex + (i * 2), "%02x", data[i]);
  }

  hex[length * 2] = '\0';
  *out_len = length * 2;

  return hex;
}

bool protocol_add_bytes(ProtocolBuilder* builder, const char* key,
                        const unsigned char* data, size_t length) {
  if (!builder || !key || !data || builder->error)
    return false;

  size_t encoded_len = 0;
  char* encoded = base64_encode(data, length, &encoded_len);
  if (!encoded)
    return false;

  bool result = protocol_add_string(builder, key, encoded);
  free(encoded);

  return result;
}

bool protocol_add_hex(ProtocolBuilder* builder, const char* key,
                      const unsigned char* data, size_t length) {
  if (!builder || !key || !data || builder->error)
    return false;

  size_t hex_len = 0;
  char* hex = bytes_to_hex(data, length, &hex_len);
  if (!hex)
    return false;

  bool result = protocol_add_string(builder, key, hex);
  free(hex);

  return result;
}

const char* protocol_get_message(const ProtocolBuilder* builder) {
  return builder && !builder->error ? builder->buffer : NULL;
}

size_t protocol_get_length(const ProtocolBuilder* builder) {
  return builder && !builder->error ? builder->length : 0;
}

bool protocol_has_error(const ProtocolBuilder* builder) {
  return builder ? builder->error : true;
}

// Helper functions
ProtocolBuilder* protocol_create_ping(const char* client_id) {
  ProtocolBuilder* builder = protocol_builder_create(PROTOCOL_MSG_PING);
  if (!builder)
    return NULL;

  if (!protocol_add_string(builder, "client_id", client_id)) {
    protocol_builder_destroy(builder);
    return NULL;
  }

  return builder;
}

ProtocolBuilder* protocol_create_init(const char* client_id,
                                      const SystemInfo* info) {
  if (!client_id || !info)
    return NULL;

  ProtocolBuilder* builder = protocol_builder_create(PROTOCOL_MSG_INIT);
  if (!builder)
    return NULL;

  bool success = protocol_add_string(builder, "client_id", client_id) &&
                 protocol_add_string(builder, "hostname", info->hostname) &&
                 protocol_add_string(builder, "username", info->username) &&
                 protocol_add_string(builder, "os_version", info->os_version);

  if (!success) {
    protocol_builder_destroy(builder);
    return NULL;
  }

  return builder;
}

ProtocolBuilder* protocol_create_error(int error_code,
                                       const char* error_message) {
  ProtocolBuilder* builder = protocol_builder_create(PROTOCOL_MSG_ERROR);
  if (!builder)
    return NULL;

  bool success = protocol_add_int(builder, "code", error_code) &&
                 protocol_add_string(builder, "message", error_message);

  if (!success) {
    protocol_builder_destroy(builder);
    return NULL;
  }

  return builder;
}

ProtocolBuilder* protocol_create_command_response(const char* command_id,
                                                  const char* result) {
  if (!command_id || !result)
    return NULL;

  ProtocolBuilder* builder =
      protocol_builder_create(PROTOCOL_MSG_COMMAND_RESPONSE);
  if (!builder)
    return NULL;

  bool success = protocol_add_string(builder, "command_id", command_id) &&
                 protocol_add_string(builder, "result", result);

  if (!success) {
    protocol_builder_destroy(builder);
    return NULL;
  }

  return builder;
}
