#ifndef RUNTIME_KIT_CORE_H
#define RUNTIME_KIT_CORE_H

#include <objc/runtime.h>
#include <objc/message.h>
#include <stdbool.h>

typedef id RTKInstance;
typedef Class RTKClass;
typedef SEL RTKSelector;

typedef enum {
    RTK_SUCCESS = 0,
    RTK_ERROR_CLASS_NOT_FOUND,
    RTK_ERROR_SELECTOR_NOT_FOUND,
    RTK_ERROR_INSTANCE_CREATION_FAILED,
    RTK_ERROR_METHOD_CALL_FAILED,
    RTK_ERROR_INVALID_ARGUMENT
} RTKError;

typedef struct RTKContext RTKContext;

// Context management
RTKContext* rtk_context_create(void);
void rtk_context_destroy(RTKContext* ctx);
const char* rtk_get_error(const RTKContext* ctx);
void rtk_set_error(RTKContext* ctx, RTKError error, const char* format, ...);

// Class and instance management
RTKClass rtk_get_class(RTKContext* ctx, const char* class_name);
RTKInstance rtk_create_instance(RTKContext* ctx, const char* class_name);
void rtk_release(RTKContext* ctx, RTKInstance instance);

#endif
