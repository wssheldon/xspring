#ifndef COMMANDS_H
#define COMMANDS_H

#include "runtime/xspring.h"

typedef char* (*command_handler)(INSTANCE* instance);
command_handler get_command_handler(const char* command);

#endif
