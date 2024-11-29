#ifndef RUNTIME_KIT_MESSAGING_H
#define RUNTIME_KIT_MESSAGING_H

#include "core.h"

RTKInstance rtk_msg_send_str(RTKContext* ctx, RTKInstance target, const char* selector_name, const char* arg);
RTKInstance rtk_msg_send_obj(RTKContext* ctx, RTKInstance target, const char* selector_name, RTKInstance arg);
RTKInstance rtk_msg_send_class(RTKContext* ctx, RTKClass cls, const char* selector_name);
RTKInstance rtk_msg_send_class_str(RTKContext* ctx, RTKClass cls, const char* selector_name, const char* arg);
RTKInstance rtk_msg_send_empty(RTKContext* ctx, RTKInstance target, const char* selector_name);
bool rtk_msg_send_data(RTKContext* ctx, RTKInstance target, const char* selector_name, RTKInstance data);

#endif
