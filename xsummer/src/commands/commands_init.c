/**
 * @file commands_init.c
 * @brief Module for initializing and registering all commands
 */
#include <stdbool.h>
#include <stdio.h>
#include "command_registry.h"
#include "commands_list.h"

/**
 * @brief Initialize all available commands
 * @return true if initialization succeeded, false otherwise
 */
bool initialize_commands(void) {
  // Initialize the command registry
  if (!initialize_command_registry()) {
    fprintf(stderr, "Error: Failed to initialize command registry\n");
    return false;
  }

  // Register all available commands
  bool success = true;

  success = success && register_whoami_command();
  success = success && register_pwd_command();
  success = success && register_ls_command();
  success = success && register_dialog_command();
  success = success && register_applescript_command();

  // Add more command registrations here as they are added

  if (!success) {
    fprintf(stderr, "Error: Failed to register some commands\n");
    return false;
  }

  return true;
}