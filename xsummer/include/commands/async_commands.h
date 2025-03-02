/**
 * @file async_commands.h
 * @brief Asynchronous command execution
 */
#ifndef ASYNC_COMMANDS_H
#define ASYNC_COMMANDS_H

#include <pthread.h>
#include <stdbool.h>
#include "../../src/commands/command_registry.h"
#include "../client.h"
#include "../command_queue.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Thread context for command execution
 */
typedef struct {
  INSTANCE* darwin;
  command_handler_t handler;
  command_handler_with_args_t handler_with_args;
  char command_id[64];
  char command_name[64];
  char* args;
  CommandQueue* queue;
} CommandThreadContext;

/**
 * @brief Initialize asynchronous command system
 * @return true if successful, false otherwise
 */
bool initialize_async_commands(void);

/**
 * @brief Execute a command asynchronously
 * @param ctx Client context
 * @param command_id Command ID
 * @param command Command name
 * @return true if the command was started, false otherwise
 */
bool execute_command_async(ClientContext* ctx, const char* command_id,
                           const char* command);

/**
 * @brief Process completed commands and send results
 * @param ctx Client context
 * @return true if successful, false otherwise
 */
bool process_completed_commands(ClientContext* ctx);

/**
 * @brief Stop all running commands
 * @param ctx Client context
 */
void stop_all_commands(ClientContext* ctx);

#ifdef __cplusplus
}
#endif

#endif /* ASYNC_COMMANDS_H */
