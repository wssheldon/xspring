#include "network.h"
#include "client.h"
#include <unistd.h>

#ifdef DEBUG
#include <stdio.h>
#define DEBUG_LOG(...) fprintf(stderr, "[DEBUG] "); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n")
#else
#define DEBUG_LOG(...) ((void)0)
#endif

bool send_http_request(ClientContext* ctx, const http_request_t* req) {
    DEBUG_LOG("Starting HTTP request to %s", req->url_path);

    // Create full URL string
    char url_str[512];
    snprintf(url_str, sizeof(url_str), "http://%s:%d%s",
        ctx->config.server_host, ctx->config.server_port, req->url_path);

    DEBUG_LOG("URL string: %s", url_str);

    RTKInstance urlString = rtk_string_create(ctx->rtk, url_str);
    if (!urlString) {
        DEBUG_LOG("Failed to create URL string");
        return false;
    }

    RTKInstance url = rtk_msg_send_obj(ctx->rtk,
        rtk_get_class(ctx->rtk, "NSURL"),
        "URLWithString:",
        urlString);
    if (!url) {
        DEBUG_LOG("Failed to create NSURL");
        rtk_release(ctx->rtk, urlString);
        return false;
    }

    RTKInstance request = rtk_msg_send_obj(ctx->rtk,
        rtk_get_class(ctx->rtk, "NSMutableURLRequest"),
        "requestWithURL:",
        url);
    if (!request) {
        DEBUG_LOG("Failed to create request");
        rtk_release(ctx->rtk, urlString);
        rtk_release(ctx->rtk, url);
        return false;
    }

    RTKInstance postMethod = rtk_string_create(ctx->rtk, "POST");
    rtk_msg_send_obj(ctx->rtk, request, "setHTTPMethod:", postMethod);

    RTKInstance bodyData = rtk_data_create(ctx->rtk, (const uint8_t*)req->body, req->body_length);
    if (!bodyData) {
        DEBUG_LOG("Failed to create body data");
        return false;
    }
    rtk_msg_send_obj(ctx->rtk, request, "setHTTPBody:", bodyData);

    RTKInstance contentTypeKey = rtk_string_create(ctx->rtk, "Content-Type");
    RTKInstance contentTypeValue = rtk_string_create(ctx->rtk, "text/plain");
    rtk_msg_send_2obj(ctx->rtk, request, "setValue:forHTTPHeaderField:",
        contentTypeValue, contentTypeKey);

    RTKInstance session = rtk_msg_send_class(ctx->rtk,
        rtk_get_class(ctx->rtk, "NSURLSession"),
        "sharedSession");
    if (!session) {
        DEBUG_LOG("Failed to get shared session");
        return false;
    }

    RTKInstance dataTask = rtk_msg_send_obj(ctx->rtk, session,
        "dataTaskWithRequest:",
        request);
    if (!dataTask) {
        DEBUG_LOG("Failed to create data task");
        return false;
    }

    rtk_msg_send_empty(ctx->rtk, dataTask, "resume");

    // Wait for completion
    usleep(1000000);  // Wait 1 second for response

    // Cleanup
    rtk_release(ctx->rtk, urlString);
    rtk_release(ctx->rtk, url);
    rtk_release(ctx->rtk, postMethod);
    rtk_release(ctx->rtk, bodyData);
    rtk_release(ctx->rtk, contentTypeKey);
    rtk_release(ctx->rtk, contentTypeValue);
    rtk_release(ctx->rtk, request);
    rtk_release(ctx->rtk, dataTask);
    rtk_release(ctx->rtk, session);

    return true;
}
