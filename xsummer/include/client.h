#ifndef CLIENT_H
#define CLIENT_H

#include <stdbool.h>
#include <stdint.h>
#include <time.h>
#include "network.h"  // Include network.h for HTTP types
#include "runtime/xspring.h"

// Forward declaration
typedef struct CommandQueue CommandQueue;

// Client configuration
typedef struct {
  char server_host[256];
  int server_port;
  int ping_interval;
  char client_id[64];
} client_config_t;

// Client context
typedef struct ClientContext {
  client_config_t config;
  INSTANCE darwin;  // The runtime instance
  struct RTKContext* rtk;
  CommandQueue* command_queue;
} ClientContext;

#endif /* CLIENT_H */
