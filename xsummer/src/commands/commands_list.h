/**
 * @file commands_list.h
 * @brief Declarations for all available command registration functions
 */
#ifndef COMMANDS_LIST_H
#define COMMANDS_LIST_H

#include <stdbool.h>

/**
 * @brief Register the whoami command
 * @return true if registration succeeded, false otherwise
 */
bool register_whoami_command(void);

/**
 * @brief Register the pwd command
 * @return true if registration succeeded, false otherwise
 */
bool register_pwd_command(void);

/**
 * @brief Register the ls command
 * @return true if registration succeeded, false otherwise
 */
bool register_ls_command(void);

/**
 * @brief Register the dialog command
 * @return true if registration succeeded, false otherwise
 */
bool register_dialog_command(void);

/**
 * @brief Register the applescript command
 * @return true if registration succeeded, false otherwise
 */
bool register_applescript_command(void);

#endif /* COMMANDS_LIST_H */