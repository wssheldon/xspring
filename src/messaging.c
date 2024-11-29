#include "runtime/messaging.h"
#include "runtime/foundation.h"
#include "runtime/core.h"
#include <string.h>

RTKInstance rtk_msg_send_str(RTKContext* ctx, RTKInstance target, const char* selector_name, const char* arg) {
    if (!ctx || !target || !selector_name || !arg) {
        if (ctx) {
            rtk_set_error(ctx, RTK_ERROR_INVALID_ARGUMENT, "Invalid arguments to rtk_msg_send_str");
        }
        return NULL;
    }

    RTKInstance str = rtk_string_create(ctx, arg);
    if (!str) return NULL;

    SEL selector = sel_registerName(selector_name);
    if (!selector) {
        rtk_set_error(ctx, RTK_ERROR_SELECTOR_NOT_FOUND, "Selector not found: %s", selector_name);
        return NULL;
    }

    RTKInstance result = ((id (*)(id, SEL, id))objc_msgSend)(target, selector, str);
    if (!result) {
        rtk_set_error(ctx, RTK_ERROR_METHOD_CALL_FAILED, "Method call failed: %s", selector_name);
    }

    return result;
}

RTKInstance rtk_msg_send_obj(RTKContext* ctx, RTKInstance target, const char* selector_name, RTKInstance arg) {
    if (!ctx || !target || !selector_name) {
        if (ctx) {
            rtk_set_error(ctx, RTK_ERROR_INVALID_ARGUMENT, "Invalid arguments to rtk_msg_send_obj");
        }
        return NULL;
    }

    SEL selector = sel_registerName(selector_name);
    if (!selector) {
        rtk_set_error(ctx, RTK_ERROR_SELECTOR_NOT_FOUND, "Selector not found: %s", selector_name);
        return NULL;
    }

    RTKInstance result = ((id (*)(id, SEL, id))objc_msgSend)(target, selector, arg);
    if (!result) {
        rtk_set_error(ctx, RTK_ERROR_METHOD_CALL_FAILED, "Method call failed: %s", selector_name);
    }

    return result;
}

RTKInstance rtk_msg_send_class(RTKContext* ctx, RTKClass cls, const char* selector_name) {
    if (!ctx || !cls || !selector_name) {
        if (ctx) {
            rtk_set_error(ctx, RTK_ERROR_INVALID_ARGUMENT, "Invalid arguments to rtk_msg_send_class");
        }
        return NULL;
    }

    SEL selector = sel_registerName(selector_name);
    if (!selector) {
        rtk_set_error(ctx, RTK_ERROR_SELECTOR_NOT_FOUND, "Selector not found: %s", selector_name);
        return NULL;
    }

    RTKInstance result = ((id (*)(id, SEL))objc_msgSend)((id)cls, selector);
    if (!result) {
        rtk_set_error(ctx, RTK_ERROR_METHOD_CALL_FAILED, "Class method call failed: %s", selector_name);
    }

    return result;
}

RTKInstance rtk_msg_send_class_str(RTKContext* ctx, RTKClass cls, const char* selector_name, const char* arg) {
    if (!ctx || !cls || !selector_name || !arg) {
        if (ctx) {
            rtk_set_error(ctx, RTK_ERROR_INVALID_ARGUMENT, "Invalid arguments to rtk_msg_send_class_str");
        }
        return NULL;
    }

    RTKInstance str = rtk_string_create(ctx, arg);
    if (!str) return NULL;

    SEL selector = sel_registerName(selector_name);
    if (!selector) {
        rtk_set_error(ctx, RTK_ERROR_SELECTOR_NOT_FOUND, "Selector not found: %s", selector_name);
        return NULL;
    }

    RTKInstance result = ((id (*)(id, SEL, id))objc_msgSend)((id)cls, selector, str);
    if (!result) {
        rtk_set_error(ctx, RTK_ERROR_METHOD_CALL_FAILED, "Class method call failed: %s", selector_name);
    }

    return result;
}

RTKInstance rtk_msg_send_empty(RTKContext* ctx, RTKInstance target, const char* selector_name) {
    if (!ctx || !target || !selector_name) {
        if (ctx) {
            rtk_set_error(ctx, RTK_ERROR_INVALID_ARGUMENT, "Invalid arguments to rtk_msg_send_empty");
        }
        return NULL;
    }

    SEL selector = sel_registerName(selector_name);
    if (!selector) {
        rtk_set_error(ctx, RTK_ERROR_SELECTOR_NOT_FOUND, "Selector not found: %s", selector_name);
        return NULL;
    }

    RTKInstance result = ((id (*)(id, SEL))objc_msgSend)(target, selector);
    if (!result) {
        rtk_set_error(ctx, RTK_ERROR_METHOD_CALL_FAILED, "Method call failed: %s", selector_name);
    }

    return result;
}

bool rtk_msg_send_data(RTKContext* ctx, RTKInstance target, const char* selector_name, RTKInstance data) {
    if (!ctx || !target || !selector_name || !data) {
        if (ctx) {
            rtk_set_error(ctx, RTK_ERROR_INVALID_ARGUMENT, "Invalid arguments to rtk_msg_send_data");
        }
        return false;
    }

    SEL selector = sel_registerName(selector_name);
    if (!selector) {
        rtk_set_error(ctx, RTK_ERROR_SELECTOR_NOT_FOUND, "Selector not found: %s", selector_name);
        return false;
    }

    ((void (*)(id, SEL, id))objc_msgSend)(target, selector, data);
    return true;
}

bool rtk_msg_send_stream(RTKContext* ctx, RTKClass cls, const char* selector_name,
                        RTKInstance host, RTKInstance port,
                        RTKInstance* inputStream, RTKInstance* outputStream) {
    if (!ctx || !cls || !selector_name || !host || !port || !inputStream || !outputStream) {
        if (ctx) {
            rtk_set_error(ctx, RTK_ERROR_INVALID_ARGUMENT, "Invalid arguments to rtk_msg_send_stream");
        }
        return false;
    }

    SEL selector = sel_registerName(selector_name);
    if (!selector) {
        rtk_set_error(ctx, RTK_ERROR_SELECTOR_NOT_FOUND, "Selector not found: %s", selector_name);
        return false;
    }

    ((void (*)(id, SEL, id, id, id*, id*))objc_msgSend)
        ((id)cls, selector, host, port, inputStream, outputStream);

    return (*inputStream != NULL && *outputStream != NULL);
}

bool rtk_msg_send_buf(RTKContext* ctx, RTKInstance target, const char* selector_name,
                     void* buffer, size_t length) {
    if (!ctx || !target || !selector_name || !buffer) {
        if (ctx) {
            rtk_set_error(ctx, RTK_ERROR_INVALID_ARGUMENT, "Invalid arguments to rtk_msg_send_buf");
        }
        return false;
    }

    SEL selector = sel_registerName(selector_name);
    if (!selector) {
        rtk_set_error(ctx, RTK_ERROR_SELECTOR_NOT_FOUND, "Selector not found: %s", selector_name);
        return false;
    }

    ((void (*)(id, SEL, void*, NSUInteger))objc_msgSend)(target, selector, buffer, length);
    return true;
}

bool rtk_msg_send_data_length(RTKContext* ctx, RTKInstance target,
                             const char* selector_name, RTKInstance data, size_t length) {
    if (!ctx || !target || !selector_name || !data) {
        if (ctx) {
            rtk_set_error(ctx, RTK_ERROR_INVALID_ARGUMENT,
                         "Invalid arguments to rtk_msg_send_data_length");
        }
        return false;
    }

    SEL selector = sel_registerName(selector_name);
    if (!selector) {
        rtk_set_error(ctx, RTK_ERROR_SELECTOR_NOT_FOUND,
                     "Selector not found: %s", selector_name);
        return false;
    }

    ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(target, selector, data, length);
    return true;
}

RTKInstance rtk_msg_send_buf_length(RTKContext* ctx, RTKInstance target,
                                   const char* selector_name, void* buffer, size_t length) {
    if (!ctx || !target || !selector_name || !buffer) {
        if (ctx) {
            rtk_set_error(ctx, RTK_ERROR_INVALID_ARGUMENT,
                         "Invalid arguments to rtk_msg_send_buf_length");
        }
        return NULL;
    }

    SEL selector = sel_registerName(selector_name);
    if (!selector) {
        rtk_set_error(ctx, RTK_ERROR_SELECTOR_NOT_FOUND,
                     "Selector not found: %s", selector_name);
        return NULL;
    }

    return ((id (*)(id, SEL, void*, NSUInteger))objc_msgSend)(target, selector, buffer, length);
}
