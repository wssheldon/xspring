#ifndef NETWORK_H
#define NETWORK_H

#include <runtime/kit.h>
#include <stdbool.h>
#include <stddef.h>

typedef struct {
    const char* url_path;
    const char* body;
    size_t body_length;
} http_request_t;

typedef struct ClientContext ClientContext;

bool send_http_request(ClientContext* ctx, const http_request_t* req);

#endif // NETWORK_H
