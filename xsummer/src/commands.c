/**
 * @file commands.c
 * @brief Main command system implementation for xsummer
 */
#include "../include/commands.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Include command registry interface
#include "commands/command_registry.h"

// Function to initialize the command system
extern bool initialize_commands(void);

/**
 * @brief Initialize the command system
 * @return true if initialization succeeded, false otherwise
 */
bool initialize_command_system(void) {
  return initialize_commands();
}

/**
 * @brief Get a handler for a command without arguments
 * @param command Command name
 * @return Handler function pointer or NULL if not found
 */
command_handler_t get_command_handler(const char* command) {
  return lookup_command_handler(command);
}

/**
 * @brief Get a handler for a command with arguments
 * @param command Command name
 * @return Handler function pointer or NULL if not found
 */
command_handler_with_args_t get_command_handler_with_args(const char* command) {
  return lookup_command_handler_with_args(command);
}
