/**
 * @file command_queue.c
 * @brief Implementation of command queue for asynchronous command execution
 */
#include "../include/command_queue.h"
#include <stdlib.h>
#include <string.h>

#ifdef DEBUG
#include <stdio.h>
#define DEBUG_LOG(...)            \
  do {                            \
    fprintf(stderr, "[DEBUG] ");  \
    fprintf(stderr, __VA_ARGS__); \
    fprintf(stderr, "\n");        \
  } while (0)
#else
#define DEBUG_LOG(...) ((void)0)
#endif

/**
 * @brief Create a new command queue
 * @return Newly created command queue or NULL on failure
 */
CommandQueue* create_command_queue(void) {
  CommandQueue* queue = (CommandQueue*)malloc(sizeof(CommandQueue));
  if (!queue) {
    DEBUG_LOG("Failed to allocate memory for command queue");
    return NULL;
  }

  // Initialize with a reasonable capacity
  queue->capacity = 10;
  queue->entries =
      (CommandEntry*)malloc(sizeof(CommandEntry) * queue->capacity);
  if (!queue->entries) {
    DEBUG_LOG("Failed to allocate memory for command entries");
    free(queue);
    return NULL;
  }

  queue->count = 0;

  // Initialize mutex
  if (pthread_mutex_init(&queue->lock, NULL) != 0) {
    DEBUG_LOG("Failed to initialize command queue mutex");
    free(queue->entries);
    free(queue);
    return NULL;
  }

  return queue;
}

/**
 * @brief Destroy a command queue and free all resources
 * @param queue The queue to destroy
 */
void destroy_command_queue(CommandQueue* queue) {
  if (!queue)
    return;

  pthread_mutex_lock(&queue->lock);

  // Free all command results
  for (size_t i = 0; i < queue->count; i++) {
    if (queue->entries[i].result) {
      free(queue->entries[i].result);
    }
  }

  free(queue->entries);

  pthread_mutex_unlock(&queue->lock);
  pthread_mutex_destroy(&queue->lock);

  free(queue);
}

/**
 * @brief Add a command to the queue
 * @param queue The command queue
 * @param command_id The unique command ID
 * @param command_name The command name
 * @return true if successful, false otherwise
 */
bool add_command_to_queue(CommandQueue* queue, const char* command_id,
                          const char* command_name) {
  if (!queue || !command_id || !command_name)
    return false;

  pthread_mutex_lock(&queue->lock);

  // Resize if needed
  if (queue->count >= queue->capacity) {
    size_t new_capacity = queue->capacity * 2;
    CommandEntry* new_entries = (CommandEntry*)realloc(
        queue->entries, sizeof(CommandEntry) * new_capacity);
    if (!new_entries) {
      pthread_mutex_unlock(&queue->lock);
      DEBUG_LOG("Failed to resize command queue");
      return false;
    }

    queue->entries = new_entries;
    queue->capacity = new_capacity;
  }

  // Initialize new entry
  CommandEntry* entry = &queue->entries[queue->count];
  strncpy(entry->id, command_id, sizeof(entry->id) - 1);
  entry->id[sizeof(entry->id) - 1] = '\0';

  strncpy(entry->name, command_name, sizeof(entry->name) - 1);
  entry->name[sizeof(entry->name) - 1] = '\0';

  entry->state = COMMAND_PENDING;
  entry->result = NULL;
  entry->context = NULL;

  queue->count++;

  pthread_mutex_unlock(&queue->lock);
  return true;
}

/**
 * @brief Update the state of a command in the queue
 * @param queue The command queue
 * @param command_id The unique command ID
 * @param state The new state
 * @return true if successful, false otherwise
 */
bool update_command_state(CommandQueue* queue, const char* command_id,
                          CommandState state) {
  if (!queue || !command_id)
    return false;

  bool found = false;

  pthread_mutex_lock(&queue->lock);

  for (size_t i = 0; i < queue->count; i++) {
    if (strcmp(queue->entries[i].id, command_id) == 0) {
      queue->entries[i].state = state;
      found = true;
      break;
    }
  }

  pthread_mutex_unlock(&queue->lock);

  if (!found) {
    DEBUG_LOG("Command %s not found in queue", command_id);
  }

  return found;
}

/**
 * @brief Store the result of a command
 * @param queue The command queue
 * @param command_id The unique command ID
 * @param result The result string (will be copied)
 * @return true if successful, false otherwise
 */
bool store_command_result(CommandQueue* queue, const char* command_id,
                          const char* result) {
  if (!queue || !command_id)
    return false;

  bool found = false;

  pthread_mutex_lock(&queue->lock);

  for (size_t i = 0; i < queue->count; i++) {
    if (strcmp(queue->entries[i].id, command_id) == 0) {
      // Free any existing result
      if (queue->entries[i].result) {
        free(queue->entries[i].result);
      }

      // Copy new result if provided
      if (result) {
        queue->entries[i].result = strdup(result);
        if (!queue->entries[i].result) {
          DEBUG_LOG("Failed to allocate memory for command result");
        }
      } else {
        queue->entries[i].result = NULL;
      }

      // Update state to completed
      queue->entries[i].state = COMMAND_COMPLETED;
      found = true;
      break;
    }
  }

  pthread_mutex_unlock(&queue->lock);

  if (!found) {
    DEBUG_LOG("Command %s not found in queue", command_id);
  }

  return found;
}

/**
 * @brief Get completed commands
 * @param queue The command queue
 * @return Array of completed commands (NULL-terminated), caller must free
 */
CommandEntry* get_completed_commands(CommandQueue* queue) {
  if (!queue)
    return NULL;

  pthread_mutex_lock(&queue->lock);

  // Count completed commands
  size_t completed_count = 0;
  for (size_t i = 0; i < queue->count; i++) {
    if (queue->entries[i].state == COMMAND_COMPLETED ||
        queue->entries[i].state == COMMAND_FAILED) {
      completed_count++;
    }
  }

  if (completed_count == 0) {
    pthread_mutex_unlock(&queue->lock);
    return NULL;
  }

  // Allocate result array (plus one for NULL terminator)
  CommandEntry* result =
      (CommandEntry*)malloc(sizeof(CommandEntry) * (completed_count + 1));
  if (!result) {
    pthread_mutex_unlock(&queue->lock);
    DEBUG_LOG("Failed to allocate memory for completed commands");
    return NULL;
  }

  // Copy completed entries
  size_t result_index = 0;
  for (size_t i = 0; i < queue->count; i++) {
    if (queue->entries[i].state == COMMAND_COMPLETED ||
        queue->entries[i].state == COMMAND_FAILED) {

      // Copy entry
      memcpy(&result[result_index], &queue->entries[i], sizeof(CommandEntry));

      // Make a new copy of the result string
      if (queue->entries[i].result) {
        result[result_index].result = strdup(queue->entries[i].result);
      }

      result_index++;
    }
  }

  // Add NULL terminator entry
  memset(&result[result_index], 0, sizeof(CommandEntry));

  pthread_mutex_unlock(&queue->lock);
  return result;
}

/**
 * @brief Remove a command from the queue
 * @param queue The command queue
 * @param command_id The unique command ID
 * @return true if successful, false otherwise
 */
bool remove_command(CommandQueue* queue, const char* command_id) {
  if (!queue || !command_id)
    return false;

  bool found = false;

  pthread_mutex_lock(&queue->lock);

  for (size_t i = 0; i < queue->count; i++) {
    if (strcmp(queue->entries[i].id, command_id) == 0) {
      // Free result if exists
      if (queue->entries[i].result) {
        free(queue->entries[i].result);
      }

      // Move last entry to current position (if not already the last)
      if (i < queue->count - 1) {
        memcpy(&queue->entries[i], &queue->entries[queue->count - 1],
               sizeof(CommandEntry));
      }

      queue->count--;
      found = true;
      break;
    }
  }

  pthread_mutex_unlock(&queue->lock);

  if (!found) {
    DEBUG_LOG("Command %s not found for removal", command_id);
  }

  return found;
}

/**
 * @brief Check if a command is still running
 * @param queue The command queue
 * @param command_id The unique command ID
 * @return true if the command is running, false otherwise
 */
bool is_command_running(CommandQueue* queue, const char* command_id) {
  if (!queue || !command_id)
    return false;

  bool running = false;

  pthread_mutex_lock(&queue->lock);

  for (size_t i = 0; i < queue->count; i++) {
    if (strcmp(queue->entries[i].id, command_id) == 0) {
      running = (queue->entries[i].state == COMMAND_RUNNING);
      break;
    }
  }

  pthread_mutex_unlock(&queue->lock);
  return running;
}