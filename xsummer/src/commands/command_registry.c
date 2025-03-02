/**
 * @file command_registry.c
 * @brief Command registry implementation for managing available commands
 */
#include "command_registry.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/**
 * @brief Entry in the command registry
 */
typedef struct {
  char* name; /**< Command name */
  union {
    command_handler_t handler; /**< Handler for commands without args */
    command_handler_with_args_t
        handler_with_args; /**< Handler for commands with args */
  };
  bool has_args; /**< Whether command takes arguments */
} command_entry_t;

/** Maximum number of commands that can be registered */
#define MAX_COMMANDS 64

/** Command registry storage */
static command_entry_t command_registry[MAX_COMMANDS];

/** Number of commands currently registered */
static size_t command_count = 0;

/**
 * @brief Initialize the command registry
 * @return true if initialization succeeded, false otherwise
 */
bool initialize_command_registry(void) {
  command_count = 0;
  memset(command_registry, 0, sizeof(command_registry));
  return true;
}

/**
 * @brief Register a command without arguments
 * @param name Command name
 * @param handler Function pointer to command handler
 * @return true if registration succeeded, false otherwise
 */
bool register_command(const char* name, command_handler_t handler) {
  if (name == NULL || handler == NULL) {
    return false;
  }

  if (command_count >= MAX_COMMANDS) {
    fprintf(stderr, "Error: Command registry full, cannot register '%s'\n",
            name);
    return false;
  }

  // Check for duplicate command
  for (size_t i = 0; i < command_count; i++) {
    if (strcmp(command_registry[i].name, name) == 0) {
      fprintf(stderr, "Error: Command '%s' already registered\n", name);
      return false;
    }
  }

  // Add the command to the registry
  command_registry[command_count].name = strdup(name);
  if (command_registry[command_count].name == NULL) {
    fprintf(stderr, "Error: Failed to allocate memory for command name\n");
    return false;
  }

  command_registry[command_count].handler = handler;
  command_registry[command_count].has_args = false;
  command_count++;

  return true;
}

/**
 * @brief Register a command with arguments
 * @param name Command name
 * @param handler Function pointer to command handler with arguments
 * @return true if registration succeeded, false otherwise
 */
bool register_command_with_args(const char* name,
                                command_handler_with_args_t handler) {
  if (name == NULL || handler == NULL) {
    return false;
  }

  if (command_count >= MAX_COMMANDS) {
    fprintf(stderr, "Error: Command registry full, cannot register '%s'\n",
            name);
    return false;
  }

  // Check for duplicate command
  for (size_t i = 0; i < command_count; i++) {
    if (strcmp(command_registry[i].name, name) == 0) {
      fprintf(stderr, "Error: Command '%s' already registered\n", name);
      return false;
    }
  }

  // Add the command to the registry
  command_registry[command_count].name = strdup(name);
  if (command_registry[command_count].name == NULL) {
    fprintf(stderr, "Error: Failed to allocate memory for command name\n");
    return false;
  }

  command_registry[command_count].handler_with_args = handler;
  command_registry[command_count].has_args = true;
  command_count++;

  return true;
}

/**
 * @brief Lookup a command in the registry by name
 * @param command Command name to look up
 * @param index Pointer to store index if found
 * @return true if command is found, false otherwise
 */
static bool lookup_command(const char* command, size_t* index) {
  if (command == NULL || index == NULL) {
    return false;
  }

  for (size_t i = 0; i < command_count; i++) {
    if (strcmp(command_registry[i].name, command) == 0) {
      *index = i;
      return true;
    }
  }

  return false;
}

/**
 * @brief Get a handler for a command without arguments
 * @param command Command name
 * @return Handler function pointer or NULL if not found
 */
command_handler_t lookup_command_handler(const char* command) {
  size_t index;

  if (lookup_command(command, &index) && !command_registry[index].has_args) {
    return command_registry[index].handler;
  }

  return NULL;
}

/**
 * @brief Get a handler for a command with arguments
 * @param command Command name
 * @return Handler function pointer or NULL if not found
 */
command_handler_with_args_t lookup_command_handler_with_args(
    const char* command) {
  size_t index;

  if (lookup_command(command, &index) && command_registry[index].has_args) {
    return command_registry[index].handler_with_args;
  }

  return NULL;
}

/**
 * @brief Clean up the command registry resources
 */
void cleanup_command_registry(void) {
  for (size_t i = 0; i < command_count; i++) {
    free(command_registry[i].name);
    command_registry[i].name = NULL;
  }

  command_count = 0;
}