#ifndef RUNTIME_KIT_FOUNDATION_H
#define RUNTIME_KIT_FOUNDATION_H

#include "core.h"

// Define NSUInteger if Foundation isn't available
#if !defined(FOUNDATION_EXPORT)
typedef unsigned long NSUInteger;
#endif

RTKInstance rtk_string_create(RTKContext* ctx, const char* str);
RTKInstance rtk_data_create(RTKContext* ctx, const void* bytes, size_t length);
bool rtk_data_get_bytes(RTKContext* ctx, RTKInstance data, void* buffer, size_t buffer_size, size_t* out_length);

#endif
