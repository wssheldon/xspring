/**
 * @file command_queue.h
 * @brief Command queue for asynchronous command execution
 */
#ifndef COMMAND_QUEUE_H
#define COMMAND_QUEUE_H

#include <pthread.h>
#include <stdbool.h>
#include <stddef.h>
#include "runtime/xspring.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Command state enum
 */
typedef enum {
  COMMAND_PENDING,   /**< Command is pending execution */
  COMMAND_RUNNING,   /**< Command is currently running */
  COMMAND_COMPLETED, /**< Command has completed successfully */
  COMMAND_FAILED     /**< Command execution failed */
} CommandState;

/**
 * @brief Command entry structure
 */
typedef struct {
  char id[64];        /**< Unique command ID */
  char name[64];      /**< Command name */
  CommandState state; /**< Current command state */
  pthread_t thread;   /**< Thread handling this command */
  char* result;       /**< Command result (if completed) */
  void* context;      /**< Command-specific context */
} CommandEntry;

/**
 * @brief Command queue structure
 */
typedef struct CommandQueue {
  CommandEntry* entries; /**< Array of command entries */
  size_t count;          /**< Current number of entries */
  size_t capacity;       /**< Current capacity */
  pthread_mutex_t lock;  /**< Thread safety lock */
} CommandQueue;

/**
 * @brief Create a new command queue
 * @return Newly created command queue or NULL on failure
 */
CommandQueue* create_command_queue(void);

/**
 * @brief Destroy a command queue and free all resources
 * @param queue The queue to destroy
 */
void destroy_command_queue(CommandQueue* queue);

/**
 * @brief Add a command to the queue
 * @param queue The command queue
 * @param command_id The unique command ID
 * @param command_name The command name
 * @return true if successful, false otherwise
 */
bool add_command_to_queue(CommandQueue* queue, const char* command_id,
                          const char* command_name);

/**
 * @brief Update the state of a command in the queue
 * @param queue The command queue
 * @param command_id The unique command ID
 * @param state The new state
 * @return true if successful, false otherwise
 */
bool update_command_state(CommandQueue* queue, const char* command_id,
                          CommandState state);

/**
 * @brief Store the result of a command
 * @param queue The command queue
 * @param command_id The unique command ID
 * @param result The result string (will be copied)
 * @return true if successful, false otherwise
 */
bool store_command_result(CommandQueue* queue, const char* command_id,
                          const char* result);

/**
 * @brief Get completed commands
 * @param queue The command queue
 * @return Array of completed commands (NULL-terminated), caller must free
 */
CommandEntry* get_completed_commands(CommandQueue* queue);

/**
 * @brief Remove a command from the queue
 * @param queue The command queue
 * @param command_id The unique command ID
 * @return true if successful, false otherwise
 */
bool remove_command(CommandQueue* queue, const char* command_id);

/**
 * @brief Check if a command is still running
 * @param queue The command queue
 * @param command_id The unique command ID
 * @return true if the command is running, false otherwise
 */
bool is_command_running(CommandQueue* queue, const char* command_id);

#ifdef __cplusplus
}
#endif

#endif /* COMMAND_QUEUE_H */
