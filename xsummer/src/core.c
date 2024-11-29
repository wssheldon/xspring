#include <runtime/core.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>

struct RTKContext {
    RTKError last_error;
    char error_message[256];
    RTKInstance autorelease_pool;
} __attribute__((aligned(16)));

void rtk_set_error(RTKContext* ctx, RTKError error, const char* format, ...) {
    if (!ctx) return;

    ctx->last_error = error;
    va_list args;
    va_start(args, format);
    vsnprintf(ctx->error_message, sizeof(ctx->error_message), format, args);
    va_end(args);
}

RTKContext* rtk_context_create(void) {
    RTKContext* ctx = calloc(1, sizeof(RTKContext));
    if (!ctx) return NULL;

    RTKClass poolClass = objc_getClass("NSAutoreleasePool");
    if (!poolClass) {
        free(ctx);
        return NULL;
    }

    ctx->autorelease_pool = ((id (*)(id, SEL))objc_msgSend)((id)poolClass, sel_registerName("alloc"));
    ctx->autorelease_pool = ((id (*)(id, SEL))objc_msgSend)(ctx->autorelease_pool, sel_registerName("init"));

    return ctx;
}

void rtk_context_destroy(RTKContext* ctx) {
    if (!ctx) return;

    if (ctx->autorelease_pool) {
        ((void (*)(id, SEL))objc_msgSend)(ctx->autorelease_pool, sel_registerName("drain"));
    }

    free(ctx);
}

const char* rtk_get_error(const RTKContext* ctx) {
    return ctx ? ctx->error_message : "No context";
}

RTKClass rtk_get_class(RTKContext* ctx, const char* class_name) {
    if (!ctx || !class_name) {
        if (ctx) {
            rtk_set_error(ctx, RTK_ERROR_INVALID_ARGUMENT, "Invalid arguments to rtk_get_class");
        }
        return NULL;
    }

    fprintf(stderr, "[DEBUG] Looking up class: %s\n", class_name);
    RTKClass cls = objc_getClass(class_name);
    if (!cls) {
        rtk_set_error(ctx, RTK_ERROR_CLASS_NOT_FOUND, "Class not found: %s", class_name);
        fprintf(stderr, "[DEBUG] Class lookup failed: %s\n", class_name);
    } else {
        fprintf(stderr, "[DEBUG] Found class: %s at %p\n", class_name, (void*)cls);
    }

    return cls;
}

RTKInstance rtk_create_instance(RTKContext* ctx, const char* class_name) {
    RTKClass cls = rtk_get_class(ctx, class_name);
    if (!cls) return NULL;

    RTKInstance instance = ((id (*)(id, SEL))objc_msgSend)((id)cls, sel_registerName("alloc"));
    if (!instance) {
        rtk_set_error(ctx, RTK_ERROR_INSTANCE_CREATION_FAILED, "Failed to allocate instance of %s", class_name);
        return NULL;
    }

    instance = ((id (*)(id, SEL))objc_msgSend)(instance, sel_registerName("init"));
    if (!instance) {
        rtk_set_error(ctx, RTK_ERROR_INSTANCE_CREATION_FAILED, "Failed to initialize instance of %s", class_name);
        return NULL;
    }

    return instance;
}

void rtk_release(RTKContext* ctx, RTKInstance instance) {
    if (!ctx || !instance) return;
    ((void (*)(id, SEL))objc_msgSend)(instance, sel_registerName("release"));
}
