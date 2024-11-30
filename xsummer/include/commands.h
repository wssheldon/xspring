#ifndef COMMANDS_H
#define COMMANDS_H

typedef char* (*command_handler)(void);

command_handler get_command_handler(const char* command);

#endif
