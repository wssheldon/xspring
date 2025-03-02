/**
 * @file whoami.c
 * @brief Implementation of the whoami command
 */
#include <pwd.h>
#include "command_registry.h"
#include "common.h"

/**
 * @brief Get the current user name
 * @param instance The runtime instance
 * @return Current user name as string (caller must free)
 */
static char* cmd_whoami(INSTANCE* instance) {
  struct passwd* pw = getpwuid(geteuid());
  if (!pw) {
    return create_error("Unable to determine current user");
  }

  return strdup(pw->pw_name);
}

/**
 * @brief Register the whoami command
 * @return true if registration succeeded, false otherwise
 */
bool register_whoami_command(void) {
  return register_command("whoami", cmd_whoami);
}