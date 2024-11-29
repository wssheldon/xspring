#include <runtime/kit.h>
#include <runtime/obf.h>
#include <runtime/xspring.h>
#include <runtime/symbol_resolv.h>
#include <runtime/kit.h>
#include <runtime/foundation.h>
#include <runtime/messaging.h>
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
        config.ping_interval = 3;
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
    DEBUG_LOG("Starting HTTP request");

    // Create NSURL
    DEBUG_LOG("Creating URL string for http://%s:%d", config.server_host, config.server_port);
    char url_str[512];
    snprintf(url_str, sizeof(url_str), "http://%s:%d", config.server_host, config.server_port);
    RTKInstance urlString = rtk_string_create(ctx, url_str);
    if (!urlString) {
        DEBUG_LOG("Failed to create URL string");
        return false;
    }
    DEBUG_LOG("Created URL string: %s", url_str);

    RTKInstance url = rtk_msg_send_obj(ctx,
        rtk_get_class(ctx, "NSURL"),
        "URLWithString:",
        urlString);
    if (!url) {
        DEBUG_LOG("Failed to create NSURL");
        rtk_release(ctx, urlString);
        return false;
    }
    DEBUG_LOG("Created NSURL successfully");

    // Create NSMutableURLRequest
    DEBUG_LOG("Creating NSMutableURLRequest");
    RTKInstance request = rtk_msg_send_obj(ctx,
        rtk_get_class(ctx, "NSMutableURLRequest"),
        "requestWithURL:",
        url);
    if (!request) {
        DEBUG_LOG("Failed to create request");
        rtk_release(ctx, urlString);
        rtk_release(ctx, url);
        return false;
    }

    // Set HTTP method to POST
    DEBUG_LOG("Setting HTTP method to POST");
    RTKInstance postMethod = rtk_string_create(ctx, "POST");
    rtk_msg_send_obj(ctx, request, "setHTTPMethod:", postMethod);

    // Create request body
    char ping_msg[512];
    snprintf(ping_msg, sizeof(ping_msg), "PING %s\n", config.client_id);
    DEBUG_LOG("Creating request body: %s", ping_msg);
    RTKInstance bodyData = rtk_data_create(ctx, (const uint8_t*)ping_msg, strlen(ping_msg));
    if (!bodyData) {
        DEBUG_LOG("Failed to create body data");
        return false;
    }
    rtk_msg_send_obj(ctx, request, "setHTTPBody:", bodyData);

    // Set content type header
    DEBUG_LOG("Setting Content-Type header");
    RTKInstance contentTypeKey = rtk_string_create(ctx, "Content-Type");
    RTKInstance contentTypeValue = rtk_string_create(ctx, "text/plain");
    rtk_msg_send_2obj(ctx, request, "setValue:forHTTPHeaderField:",
        contentTypeValue, contentTypeKey);

    // Get shared session
    DEBUG_LOG("Getting shared NSURLSession");
    RTKInstance session = rtk_msg_send_class(ctx,
        rtk_get_class(ctx, "NSURLSession"),
        "sharedSession");
    if (!session) {
        DEBUG_LOG("Failed to get shared session");
        return false;
    }

    // Create data task
    DEBUG_LOG("Creating data task");
    RTKInstance dataTask = rtk_msg_send_obj(ctx, session,
        "dataTaskWithRequest:",
        request);
    if (!dataTask) {
        DEBUG_LOG("Failed to create data task");
        return false;
    }

    // Resume the task
    DEBUG_LOG("Resuming data task");
    rtk_msg_send_empty(ctx, dataTask, "resume");

    // Wait for completion
    DEBUG_LOG("Waiting for response...");
    usleep(1000000);  // Wait 1 second for response
    DEBUG_LOG("Wait complete");

    // Cleanup
    DEBUG_LOG("Cleaning up resources");
    rtk_release(ctx, urlString);
    rtk_release(ctx, url);
    rtk_release(ctx, postMethod);
    rtk_release(ctx, bodyData);
    rtk_release(ctx, contentTypeKey);
    rtk_release(ctx, contentTypeValue);
    rtk_release(ctx, request);
    rtk_release(ctx, dataTask);
    rtk_release(ctx, session);

    DEBUG_LOG("Request cycle complete");
    return true;
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
    if (!instance->Darwin.objc_msgSend) {
        DEBUG_LOG("Failed to resolve objc_msgSend");
        return false;
    }

    instance->Darwin.objc_getClass = (objc_getClass_t)GetSymbolAddressH(objc, getObjcGetClassHash());
    if (!instance->Darwin.objc_getClass) {
        DEBUG_LOG("Failed to resolve objc_getClass");
        return false;
    }

    instance->Darwin.sel_registerName = (sel_registerName_t)GetSymbolAddressH(objc, getSelRegisterNameHash());
    if (!instance->Darwin.sel_registerName) {
        DEBUG_LOG("Failed to resolve sel_registerName");
        return false;
    }

    DEBUG_LOG("Successfully initialized all Objective-C runtime functions");

    // TODO: Initialize other Darwin APIs as needed
    // For now we'll just focus on the Objective-C runtime functions

    return true;
}

int main(int argc, char* argv[]) {
    printf("0x%X\n", HASHA("LIBOBJC.A.DYLIB"));

    DEBUG_LOG("Starting client application");

    // Print hashes for debugging
    printHashes();

    INSTANCE instance = {0};
    if (!InitializeDarwinApi(&instance)) {
        printf("Failed to initialize Darwin API\n");
        return 1;
    }

    // Get NSProcessInfo class and selectors
    Class processInfoClass = objc_getClass("NSProcessInfo");
    SEL processInfoSel = sel_registerName("processInfo");
    SEL hostNameSel = sel_registerName("hostName");

    // Call [NSProcessInfo processInfo] using our resolved msgSend
    id processInfo = instance.Darwin.objc_msgSend((id)processInfoClass, processInfoSel);

    // Call [processInfo hostName]
    id hostname = instance.Darwin.objc_msgSend(processInfo, hostNameSel);

    printf("Hostname: %s\n", (char*)hostname);

    const char* config_path = (argc > 1) ? argv[1] : "client.conf";
    DEBUG_LOG("Using config path: %s", config_path);

    if (load_config(config_path)) {
        DEBUG_LOG("Configuration loaded from file");
    } else {
        DEBUG_LOG("Using default configuration");
    }

    RTKContext* ctx = rtk_context_create();
    if (!ctx) {
        DEBUG_LOG("Failed to create runtime context");
        fprintf(stderr, "Failed to create runtime context\n");
        return 1;
    }
    DEBUG_LOG("Runtime context created successfully");

    printf("Client started (ID: %s)\n", config.client_id);
    printf("Connecting to %s:%d\n", config.server_host, config.server_port);
    DEBUG_LOG("Client initialized with ID: %s", config.client_id);
    DEBUG_LOG("Server target: %s:%d", config.server_host, config.server_port);

    while (should_run) {
        DEBUG_LOG("Starting ping cycle");
        if (!send_ping(ctx)) {
            DEBUG_LOG("Ping failed");
            printf("Failed to connect to server, retrying in %d seconds\n", config.ping_interval);
        } else {
            DEBUG_LOG("Ping successful");
        }
        DEBUG_LOG("Waiting %d seconds before next ping", config.ping_interval);
        sleep(config.ping_interval);
    }

    DEBUG_LOG("Shutting down client");
    rtk_context_destroy(ctx);
    DEBUG_LOG("Cleanup complete");
    return 0;
}
