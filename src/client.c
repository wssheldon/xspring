#include "runtime/kit.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdbool.h>

// Configuration structure
typedef struct {
    char server_host[256];
    int server_port;
    int ping_interval;  // in seconds
    char client_id[64]; // unique identifier for this client
} client_config_t;

// Global state
static bool should_run = true;
static client_config_t config;

// Forward declarations
static bool load_config(const char* config_path);
static bool send_ping(RTKContext* ctx);
static void handle_command(const char* command);

// Load configuration from file
static bool load_config(const char* config_path) {
    FILE* fp = fopen(config_path, "r");
    if (!fp) {
        // If config doesn't exist, use defaults
        strncpy(config.server_host, "127.0.0.1", sizeof(config.server_host) - 1);
        config.server_port = 4444;
        config.ping_interval = 60;
        snprintf(config.client_id, sizeof(config.client_id), "client_%d", getpid());
        return false;
    }

    char line[512];
    while (fgets(line, sizeof(line), fp)) {
        char key[64], value[256];
        if (sscanf(line, "%63[^=]=%255s", key, value) == 2) {
            if (strcmp(key, "server_host") == 0) {
                strncpy(config.server_host, value, sizeof(config.server_host) - 1);
            } else if (strcmp(key, "server_port") == 0) {
                config.server_port = atoi(value);
            } else if (strcmp(key, "ping_interval") == 0) {
                config.ping_interval = atoi(value);
            } else if (strcmp(key, "client_id") == 0) {
                strncpy(config.client_id, value, sizeof(config.client_id) - 1);
            }
        }
    }
    fclose(fp);
    return true;
}

static void handle_command(const char* command) {
    if (!command) return;

    if (strncmp(command, "STOP", 4) == 0) {
        should_run = false;
    }
    printf("Received command: %s\n", command);
}

static bool send_ping(RTKContext* ctx) {
    // Create socket
    RTKInstance socket = rtk_create_instance(ctx, "NSSocket");
    if (!socket) {
        fprintf(stderr, "Failed to create socket: %s\n", rtk_get_error(ctx));
        return false;
    }

    // Create host
    RTKClass hostClass = rtk_get_class(ctx, "NSHost");
    if (!hostClass) {
        fprintf(stderr, "Failed to get NSHost class: %s\n", rtk_get_error(ctx));
        rtk_release(ctx, socket);
        return false;
    }

    RTKInstance host = rtk_msg_send_class_str(ctx, hostClass, "hostWithName:", config.server_host);
    if (!host) {
        fprintf(stderr, "Failed to create host: %s\n", rtk_get_error(ctx));
        rtk_release(ctx, socket);
        return false;
    }

    // Connect
    if (!rtk_msg_send_obj(ctx, socket, "connectToHost:port:", host)) {
        fprintf(stderr, "Failed to connect: %s\n", rtk_get_error(ctx));
        rtk_release(ctx, socket);
        return false;
    }

    // Send ping
    char ping_msg[512];
    snprintf(ping_msg, sizeof(ping_msg), "PING %s\n", config.client_id);

    RTKInstance data = rtk_data_create(ctx, ping_msg, strlen(ping_msg));
    if (!data) {
        fprintf(stderr, "Failed to create data: %s\n", rtk_get_error(ctx));
        rtk_release(ctx, socket);
        return false;
    }

    if (!rtk_msg_send_data(ctx, socket, "writeData:", data)) {
        fprintf(stderr, "Failed to send data: %s\n", rtk_get_error(ctx));
        rtk_release(ctx, socket);
        return false;
    }

    // Read response
    RTKInstance response = rtk_msg_send_empty(ctx, socket, "readDataToEndOfFile");
    if (response) {
        size_t length;
        char buffer[4096];
        if (rtk_data_get_bytes(ctx, response, buffer, sizeof(buffer), &length)) {
            buffer[length] = '\0';
            handle_command(buffer);
        }
    }

    rtk_release(ctx, socket);
    return true;
}

int main(int argc, char* argv[]) {
    const char* config_path = (argc > 1) ? argv[1] : "client.conf";
    load_config(config_path);

    RTKContext* ctx = rtk_context_create();
    if (!ctx) {
        fprintf(stderr, "Failed to create runtime context\n");
        return 1;
    }

    printf("Client started (ID: %s)\n", config.client_id);
    printf("Connecting to %s:%d\n", config.server_host, config.server_port);

    while (should_run) {
        if (!send_ping(ctx)) {
            printf("Failed to connect to server, retrying in %d seconds\n", config.ping_interval);
        }
        sleep(config.ping_interval);
    }

    rtk_context_destroy(ctx);
    return 0;
}