#include "network.h"
#include <dispatch/dispatch.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <runtime/core.h>
#include <string.h>
#include <unistd.h>
#include "client.h"
#include "protocol.h"

typedef struct {
  http_response_t* resp;
  dispatch_semaphore_t semaphore;
} RequestContext;

#ifdef DEBUG
#include <stdio.h>
#define DEBUG_LOG(...)          \
  fprintf(stderr, "[DEBUG] ");  \
  fprintf(stderr, __VA_ARGS__); \
  fprintf(stderr, "\n")
#else
#define DEBUG_LOG(...) ((void)0)
#endif

typedef long NSInteger;
typedef unsigned long NSUInteger;

typedef void (*CompletionHandler)(RTKInstance data, RTKInstance response,
                                  RTKInstance error, void* context);

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

static void completion_invoke(void* block, id data, id response, id error) {
  struct Block_literal* literal = block;
  RequestContext* reqContext = literal->context;

  if (!reqContext || !reqContext->resp)
    return;

  http_response_t* resp = reqContext->resp;

  if (error) {
    DEBUG_LOG("Request error occurred");
    resp->status_code = 0;
  } else if (response) {
    resp->status_code = (int)((NSInteger(*)(id, SEL))objc_msgSend)(
        response, sel_registerName("statusCode"));

    if (data) {
      NSUInteger length = ((NSUInteger(*)(id, SEL))objc_msgSend)(
          data, sel_registerName("length"));

      if (length > 0) {
        resp->data = malloc(length + 1);
        if (resp->data) {
          const void* bytes = ((const void* (*)(id, SEL))objc_msgSend)(
              data, sel_registerName("bytes"));
          memcpy(resp->data, bytes, length);
          resp->data[length] = '\0';
          resp->length = length;
          DEBUG_LOG("Response data received: %s", resp->data);
        }
      }
    }
  }

  dispatch_semaphore_signal(reqContext->semaphore);
}

static RTKInstance create_completion_handler(RequestContext* reqContext) {
  static struct BlockDescriptor descriptor = {0, sizeof(struct Block_literal),
                                              NULL, NULL};

  struct Block_literal* block = malloc(sizeof(struct Block_literal));
  block->isa = objc_getClass("NSBlock");  // Or _NSConcreteGlobalBlock
  block->flags = (1 << 25);               // BLOCK_HAS_DESCRIPTOR
  block->reserved = 0;
  block->invoke = completion_invoke;
  block->descriptor = &descriptor;
  block->context = reqContext;

  return (RTKInstance)block;
}

bool send_http_request(ClientContext* ctx, const http_request_t* req,
                       http_response_t* resp) {
  DEBUG_LOG("Starting HTTP request to %s", req->url_path);

  // Create full URL string
  char url_str[512];
  snprintf(url_str, sizeof(url_str), "http://%s:%d%s", ctx->config.server_host,
           ctx->config.server_port, req->url_path);

  DEBUG_LOG("URL string: %s", url_str);

  // Initialize response if provided
  if (resp) {
    resp->data = NULL;
    resp->length = 0;
    resp->status_code = 0;
  }

  // Create URL
  RTKInstance urlString = rtk_string_create(ctx->rtk, url_str);
  if (!urlString) {
    DEBUG_LOG("Failed to create URL string");
    return false;
  }

  RTKInstance url = rtk_msg_send_obj(ctx->rtk, rtk_get_class(ctx->rtk, "NSURL"),
                                     "URLWithString:", urlString);
  if (!url) {
    DEBUG_LOG("Failed to create NSURL");
    rtk_release(ctx->rtk, urlString);
    return false;
  }

  // Create request
  RTKInstance request =
      rtk_msg_send_obj(ctx->rtk, rtk_get_class(ctx->rtk, "NSMutableURLRequest"),
                       "requestWithURL:", url);
  if (!request) {
    DEBUG_LOG("Failed to create request");
    rtk_release(ctx->rtk, urlString);
    rtk_release(ctx->rtk, url);
    return false;
  }

  // Set HTTP method and body if provided
  if (req->body) {
    RTKInstance postMethod = rtk_string_create(ctx->rtk, "POST");
    rtk_msg_send_obj(ctx->rtk, request, "setHTTPMethod:", postMethod);

    RTKInstance bodyData =
        rtk_data_create(ctx->rtk, (const uint8_t*)req->body, req->body_length);
    if (bodyData) {
      rtk_msg_send_obj(ctx->rtk, request, "setHTTPBody:", bodyData);
      rtk_release(ctx->rtk, bodyData);
    }
    rtk_release(ctx->rtk, postMethod);
  }

  // Set headers
  RTKInstance contentTypeKey = rtk_string_create(ctx->rtk, "Content-Type");
  RTKInstance contentTypeValue = rtk_string_create(ctx->rtk, "text/plain");
  rtk_msg_send_2obj(ctx->rtk, request,
                    "setValue:forHTTPHeaderField:", contentTypeValue,
                    contentTypeKey);

  // Get shared session
  RTKInstance session = rtk_msg_send_class(
      ctx->rtk, rtk_get_class(ctx->rtk, "NSURLSession"), "sharedSession");
  if (!session) {
    DEBUG_LOG("Failed to get shared session");
    return false;
  }

  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
  if (!semaphore) {
    DEBUG_LOG("Failed to create semaphore");
    return false;
  }

  RequestContext* reqContext = malloc(sizeof(RequestContext));
  if (!reqContext) {
    DEBUG_LOG("Failed to allocate request context");
    dispatch_release(semaphore);
    return false;
  }

  reqContext->resp = resp;
  reqContext->semaphore = semaphore;

  RTKInstance completionHandler = create_completion_handler(reqContext);
  if (!completionHandler) {
    DEBUG_LOG("Failed to create completion handler");
    free(reqContext);
    dispatch_release(semaphore);
    return false;
  }

  RTKInstance dataTask = ((id(*)(id, SEL, id, id))objc_msgSend)(
      session, sel_registerName("dataTaskWithRequest:completionHandler:"),
      request, completionHandler);

  if (!dataTask) {
    DEBUG_LOG("Failed to create data task");
    free(completionHandler);
    free(reqContext);
    dispatch_release(semaphore);
    return false;
  }

  rtk_msg_send_empty(ctx->rtk, dataTask, "resume");

  long result = dispatch_semaphore_wait(
      semaphore, dispatch_time(DISPATCH_TIME_NOW, 5LL * NSEC_PER_SEC));
  bool requestSuccess = (result == 0);

  if (!requestSuccess) {
    DEBUG_LOG("Request timed out");
  }

  rtk_release(ctx->rtk, urlString);
  rtk_release(ctx->rtk, url);
  rtk_release(ctx->rtk, contentTypeKey);
  rtk_release(ctx->rtk, contentTypeValue);
  rtk_release(ctx->rtk, request);
  rtk_release(ctx->rtk, dataTask);
  rtk_release(ctx->rtk, completionHandler);
  dispatch_release(semaphore);
  free(reqContext);

  if (resp && resp->status_code == 0) {
    DEBUG_LOG("Request failed or timed out");
    return false;
  }

  DEBUG_LOG("Request completed successfully");
  return requestSuccess;
}

void free_http_response(http_response_t* resp) {
  if (!resp)
    return;
  if (resp->data) {
    free(resp->data);
    resp->data = NULL;
  }
  resp->length = 0;
}

char* get_command_from_response(ClientContext* ctx, const http_request_t* req) {
  http_response_t response = {0};

  if (!send_http_request(ctx, req, &response)) {
    DEBUG_LOG("Failed to send command poll request");
    return NULL;
  }

  if (response.status_code == 204) {  // No Content
    DEBUG_LOG("No pending commands (status 204)");
    free_http_response(&response);
    return NULL;
  }

  if (response.status_code != 200 || !response.data) {
    DEBUG_LOG("Invalid response: status=%d", response.status_code);
    free_http_response(&response);
    return NULL;
  }

  DEBUG_LOG("Parsing response: %s", response.data);

  // Parse our protocol format response
  char* command = NULL;
  char* lines = strdup(response.data);
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
