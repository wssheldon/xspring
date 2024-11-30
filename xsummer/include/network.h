#ifndef NETWORK_H
#define NETWORK_H

#include <runtime/kit.h>
#include <stdbool.h>
#include <dispatch/dispatch.h>
#include <objc/runtime.h>
#include <objc/message.h>

typedef struct {
    const char* url_path;
    const char* body;
    size_t body_length;
} http_request_t;

typedef struct {
    char* data;
    size_t length;
    int status_code;
} http_response_t;

typedef struct ClientContext ClientContext;

#define HTTP_STATUS_OK 200
#define HTTP_STATUS_NO_CONTENT 204

typedef enum {
    NETWORK_SUCCESS = 0,
    NETWORK_ERROR_INVALID_ARGS,
    NETWORK_ERROR_MEMORY,
    NETWORK_ERROR_URL_CREATE,
    NETWORK_ERROR_REQUEST_CREATE,
    NETWORK_ERROR_TIMEOUT,
    NETWORK_ERROR_SEND,
    NETWORK_ERROR_RESPONSE,
} NetworkError;

NetworkError send_http_request(ClientContext* ctx, const http_request_t* req, http_response_t* resp);
void free_http_response(http_response_t* resp);
char* get_command_from_response(ClientContext* ctx, const http_request_t* req);

#endif
