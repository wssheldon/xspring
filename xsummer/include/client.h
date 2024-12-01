#ifndef CLIENT_H
#define CLIENT_H

#include <runtime/kit.h>
#include <runtime/xspring.h>
#include "darwin.h"

typedef struct {
    char server_host[256];
    int server_port;
    int ping_interval;
    char client_id[64];
} client_config_t;

typedef struct ClientContext {
    INSTANCE darwin;
    DarwinContext darwinapi;
    RTKContext* rtk;
    client_config_t config;
} ClientContext;

#endif // CLIENT_H
