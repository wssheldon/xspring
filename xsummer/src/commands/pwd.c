/**
 * @file pwd.c
 * @brief Implementation of the pwd command
 */
#include "command_registry.h"
#include "common.h"

/**
 * @brief Get the current working directory
 * @param instance The runtime instance
 * @return Current working directory as string (caller must free)
 */
static char* cmd_pwd(INSTANCE* instance) {
  char cwd[PATH_MAX];
  if (!getcwd(cwd, sizeof(cwd))) {
    return create_error("Unable to get current directory");
  }

  return strdup(cwd);
}

/**
 * @brief Register the pwd command
 * @return true if registration succeeded, false otherwise
 */
bool register_pwd_command(void) {
  return register_command("pwd", cmd_pwd);
}