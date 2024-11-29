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
