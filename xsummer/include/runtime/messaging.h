#ifndef RUNTIME_KIT_MESSAGING_H
#define RUNTIME_KIT_MESSAGING_H

#include "core.h"

RTKInstance rtk_msg_send_str(RTKContext* ctx, RTKInstance target, const char* selector_name, const char* arg);
RTKInstance rtk_msg_send_obj(RTKContext* ctx, RTKInstance target, const char* selector_name, RTKInstance arg);
RTKInstance rtk_msg_send_class(RTKContext* ctx, RTKClass cls, const char* selector_name);
RTKInstance rtk_msg_send_class_str(RTKContext* ctx, RTKClass cls, const char* selector_name, const char* arg);
RTKInstance rtk_msg_send_empty(RTKContext* ctx, RTKInstance target, const char* selector_name);
bool rtk_msg_send_data(RTKContext* ctx, RTKInstance target, const char* selector_name, RTKInstance data);
bool rtk_msg_send_stream(RTKContext* ctx, RTKClass cls, const char* selector_name,
                        RTKInstance host, RTKInstance port,
                        RTKInstance* inputStream, RTKInstance* outputStream);

bool rtk_msg_send_buf(RTKContext* ctx, RTKInstance target, const char* selector_name,
                     void* buffer, size_t length);
RTKInstance rtk_msg_send_buf_length(RTKContext* ctx, RTKInstance target,
                                   const char* selector_name, void* buffer, size_t length);
bool rtk_msg_send_data_length(RTKContext* ctx, RTKInstance target,
                             const char* selector_name, RTKInstance data, size_t length);

RTKInstance rtk_msg_send_class_int(RTKContext* ctx, RTKClass cls,
    const char* selector_name, int value);

RTKInstance rtk_msg_send_2obj(RTKContext* ctx, RTKInstance target,
    const char* selector_name, RTKInstance arg1, RTKInstance arg2);

bool rtk_msg_send_stream_create(RTKContext* ctx, RTKClass cls,
    const char* selector_name, RTKInstance host, RTKInstance port,
    RTKInstance* input, RTKInstance* output);

RTKInstance rtk_msg_send_obj_int(RTKContext* ctx, RTKInstance target,
    const char* selector_name, RTKInstance arg, size_t intarg);

#endif
