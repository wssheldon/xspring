#include "commands.h"
#include <pwd.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define COMMAND_BUFFER_SIZE 1024

typedef struct {
  char* name;
  command_handler handler;
} CommandEntry;

static char* cmd_whoami(void) {
  struct passwd* pw = getpwuid(geteuid());
  if (!pw) {
    return strdup("Error: Unable to determine current user");
  }
  return strdup(pw->pw_name);
}

static CommandEntry command_handlers[] = {{"whoami", cmd_whoami}, {NULL, NULL}};

command_handler get_command_handler(const char* command) {
  for (CommandEntry* entry = command_handlers; entry->name != NULL; entry++) {
    if (strcmp(entry->name, command) == 0) {
      return entry->handler;
    }
  }
  return NULL;
}
