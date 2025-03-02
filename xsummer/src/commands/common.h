/**
 * @file common.h
 * @brief Common definitions and utilities for command implementations
 */
#ifndef COMMANDS_COMMON_H
#define COMMANDS_COMMON_H

#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "../../include/runtime/xspring.h"

/**
 * @brief Default size for command result buffers
 */
#define COMMAND_BUFFER_SIZE 4096

/**
 * @brief Create a duplicate string from the given input (caller must free)
 * @param format Format string for sprintf
 * @param ... Arguments for format string
 * @return Newly allocated string that caller must free, or NULL on error
 */
static inline char* create_result(const char* format, ...) {
  char* result = malloc(COMMAND_BUFFER_SIZE);
  if (!result) {
    return strdup("Error: Memory allocation failed");
  }

  va_list args;
  va_start(args, format);
  vsnprintf(result, COMMAND_BUFFER_SIZE, format, args);
  va_end(args);

  return result;
}

/**
 * @brief Create an error result string (caller must free)
 * @param format Format string for sprintf
 * @param ... Arguments for format string
 * @return Newly allocated error string that caller must free
 */
static inline char* create_error(const char* format, ...) {
  char buffer[COMMAND_BUFFER_SIZE];

  va_list args;
  va_start(args, format);
  vsnprintf(buffer, sizeof(buffer), format, args);
  va_end(args);

  char* result = malloc(COMMAND_BUFFER_SIZE);
  if (!result) {
    return strdup("Error: Memory allocation failed");
  }

  snprintf(result, COMMAND_BUFFER_SIZE, "Error: %s", buffer);
  return result;
}

#endif /* COMMANDS_COMMON_H */