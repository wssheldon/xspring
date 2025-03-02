/**
 * @file command_registry.h
 * @brief Command registry interface for managing available commands
 */
#ifndef COMMAND_REGISTRY_H
#define COMMAND_REGISTRY_H

#include <stdbool.h>
#include "../../include/commands.h"

/**
 * @brief Register a command without arguments
 * @param name Command name
 * @param handler Function pointer to command handler
 * @return true if registration succeeded, false otherwise
 */
bool register_command(const char* name, command_handler_t handler);

/**
 * @brief Register a command with arguments
 * @param name Command name
 * @param handler Function pointer to command handler with arguments
 * @return true if registration succeeded, false otherwise
 */
bool register_command_with_args(const char* name,
                                command_handler_with_args_t handler);

/**
 * @brief Initialize the command registry
 * @return true if initialization succeeded, false otherwise
 */
bool initialize_command_registry(void);

/**
 * @brief Get a handler for a command without arguments
 * @param command Command name
 * @return Handler function pointer or NULL if not found
 */
command_handler_t lookup_command_handler(const char* command);

/**
 * @brief Get a handler for a command with arguments
 * @param command Command name
 * @return Handler function pointer or NULL if not found
 */
command_handler_with_args_t lookup_command_handler_with_args(
    const char* command);

#endif /* COMMAND_REGISTRY_H */
