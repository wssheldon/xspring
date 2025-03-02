/**
 * @file commands.h
 * @brief Command system interface for xsummer
 */
#ifndef COMMANDS_H
#define COMMANDS_H

#include <stdbool.h>
#include "runtime/xspring.h"

/**
 * @brief Function type for command handlers without arguments
 * @param instance The runtime instance
 * @return Result string that will be freed by the caller
 */
typedef char* (*command_handler_t)(INSTANCE* instance);

/**
 * @brief Function type for command handlers with arguments
 * @param instance The runtime instance
 * @param args Command arguments string
 * @return Result string that will be freed by the caller
 */
typedef char* (*command_handler_with_args_t)(INSTANCE* instance,
                                             const char* args);

/**
 * @brief Get a handler for a command without arguments
 * @param command Command name
 * @return Handler function pointer or NULL if not found
 */
command_handler_t get_command_handler(const char* command);

/**
 * @brief Get a handler for a command with arguments
 * @param command Command name
 * @return Handler function pointer or NULL if not found
 */
command_handler_with_args_t get_command_handler_with_args(const char* command);

/**
 * @brief Initialize the command system
 * @return true if initialization succeeded, false otherwise
 */
bool initialize_command_system(void);

#endif /* COMMANDS_H */
