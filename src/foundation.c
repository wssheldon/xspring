#include "runtime/foundation.h"
#include "runtime/core.h"
#include <string.h>

RTKInstance rtk_string_create(RTKContext* ctx, const char* str) {
    if (!ctx || !str) {
        if (ctx) {
            rtk_set_error(ctx, RTK_ERROR_INVALID_ARGUMENT, "Invalid arguments to rtk_string_create");
        }
        return NULL;
    }

    RTKClass stringClass = rtk_get_class(ctx, "NSString");
    if (!stringClass) return NULL;

    SEL selector = sel_registerName("stringWithUTF8String:");
    RTKInstance result = ((id (*)(id, SEL, const char*))objc_msgSend)(
        (id)stringClass,
        selector,
        str
    );

    if (!result) {
        rtk_set_error(ctx, RTK_ERROR_INSTANCE_CREATION_FAILED, "Failed to create NSString");
    }

    return result;
}

RTKInstance rtk_data_create(RTKContext* ctx, const void* bytes, size_t length) {
    if (!ctx || !bytes || length == 0) {
        if (ctx) {
            rtk_set_error(ctx, RTK_ERROR_INVALID_ARGUMENT, "Invalid arguments to rtk_data_create");
        }
        return NULL;
    }

    RTKClass dataClass = rtk_get_class(ctx, "NSData");
    if (!dataClass) return NULL;

    SEL selector = sel_registerName("dataWithBytes:length:");
    RTKInstance result = ((id (*)(id, SEL, const void*, size_t))objc_msgSend)(
        (id)dataClass,
        selector,
        bytes,
        length
    );

    if (!result) {
        rtk_set_error(ctx, RTK_ERROR_INSTANCE_CREATION_FAILED, "Failed to create NSData");
    }

    return result;
}

bool rtk_data_get_bytes(RTKContext* ctx, RTKInstance data, void* buffer, size_t buffer_size, size_t* out_length) {
    if (!ctx || !data || !buffer || !out_length) {
        if (ctx) {
            rtk_set_error(ctx, RTK_ERROR_INVALID_ARGUMENT, "Invalid arguments to rtk_data_get_bytes");
        }
        return false;
    }

    SEL lengthSel = sel_registerName("length");
    SEL bytesSel = sel_registerName("bytes");

    size_t length = (size_t)((NSUInteger (*)(id, SEL))objc_msgSend)(data, lengthSel);
    if (length > buffer_size) {
        rtk_set_error(ctx, RTK_ERROR_INVALID_ARGUMENT, "Buffer too small for data");
        return false;
    }

    const void* bytes = ((const void* (*)(id, SEL))objc_msgSend)(data, bytesSel);
    if (!bytes) {
        rtk_set_error(ctx, RTK_ERROR_METHOD_CALL_FAILED, "Failed to get bytes from NSData");
        return false;
    }

    memcpy(buffer, bytes, length);
    *out_length = length;

    return true;
}
