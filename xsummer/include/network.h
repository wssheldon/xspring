#ifndef NETWORK_H
#define NETWORK_H

#include <runtime/kit.h>
#include <stdbool.h>
#include <dispatch/dispatch.h>

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

bool send_http_request(ClientContext* ctx, const http_request_t* req, http_response_t* resp);
void free_http_response(http_response_t* resp);
char* get_command_from_response(ClientContext* ctx, const http_request_t* req);

#endif
