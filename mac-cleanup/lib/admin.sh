#!/bin/zsh
#
# lib/admin.sh - Admin/sudo operations for mac-cleanup
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Detect admin user
mc_detect_admin_user() {
  # Try to get current user's groups
  local current_user=$(whoami)
  
  # Check if current user is in admin group
  if groups | grep -q admin; then
    MC_ADMIN_USERNAME="$current_user"
    log_message "INFO" "Using current user ($current_user) as admin"
    return 0
  fi
  
  # Try to detect admin users from system
  local admin_users=$(dscl . -read /Groups/admin GroupMembership 2>/dev/null | cut -d' ' -f2-)
  
  if [[ -n "$admin_users" ]]; then
    # Use first admin user found (prefer current user if in list)
    for user in $admin_users; do
      if [[ "$user" == "$current_user" ]]; then
        MC_ADMIN_USERNAME="$user"
        log_message "INFO" "Detected admin user: $user"
        return 0
      fi
    done
    # If current user not in list, use first admin user
    # Use awk with fallback to full path
    local awk_cmd="awk"
    if ! command -v awk &> /dev/null; then
      awk_cmd="/usr/bin/awk"
    fi
    MC_ADMIN_USERNAME=$(echo $admin_users | $awk_cmd '{print $1}')
    log_message "INFO" "Detected admin user: $MC_ADMIN_USERNAME"
    return 0
  fi
  
  # Fallback: prompt user
  print_warning "Could not auto-detect admin user."
  print_info "Please enter your administrative account username:"
  read MC_ADMIN_USERNAME
  
  if [[ -z "$MC_ADMIN_USERNAME" ]]; then
    print_error "No admin username provided."
    return 1
  fi
  
  log_message "INFO" "Using manually entered admin user: $MC_ADMIN_USERNAME"
  return 0
}

# SEC-2/SEC-3: Safe sudo execution without shell interpretation
# This function accepts a command array and executes it with sudo
# without any shell interpretation, preventing command injection
safe_sudo_exec() {
  local cmd="$1"
  shift

  # Execute with sudo, passing all arguments safely
  # The -- ensures no further option processing
  # All arguments are passed as-is without shell interpretation
  sudo -- "$cmd" "$@"
}

# Function to run commands as admin using sudo
# NOTE: This function executes shell commands with sudo bash -s
# The command is passed via stdin (<<<) which prevents many injection vectors
# but still allows legitimate shell features like pipes and redirects
run_as_admin() {
  local command="$1"
  local description="$2"

  if [[ "$MC_DRY_RUN" == "true" ]]; then
    print_info "[DRY RUN] Would run as admin: $description"
    log_message "DRY_RUN" "Would execute: $command"
    return 0
  fi

  # Ensure we have admin user detected
  if [[ -z "$MC_ADMIN_USERNAME" ]]; then
    mc_detect_admin_user || return 1
  fi

  print_info "Running $description with administrative privileges..."
  log_message "INFO" "Executing admin command: $description"

  # Validate/cache sudo credentials (use -n to fail immediately if password needed)
  if ! sudo -n -v 2>/dev/null; then
    # Try once with prompt (script always runs interactively)
    if [[ -t 0 ]] && [[ -t 1 ]]; then
      if ! sudo -v; then
        print_error "Failed to validate sudo credentials."
        log_message "ERROR" "Sudo credential validation failed"
        return 1
      fi
    else
      print_error "Sudo credentials not cached and script requires interactive terminal."
      log_message "ERROR" "Sudo credentials not cached and non-interactive terminal"
      return 1
    fi
  fi

  # SEC-2/SEC-3: Security fix - execute command via bash stdin
  # Using bash -s with here-string (<<<) prevents the command string from being
  # interpreted as shell arguments to sudo, which was the injection vector with sh -c
  # The here-string passes the command as stdin, which bash reads and executes
  # This maintains support for pipes, redirects, and other shell features while
  # preventing the command string itself from being parsed as arguments

  # Run the command with sudo (use -n to fail immediately if password needed)
  # Use bash -s to read command from stdin for controlled shell interpretation
  if sudo -n bash -s <<< "$command" 2>/dev/null || ([[ -t 0 ]] && [[ -t 1 ]] && sudo bash -s <<< "$command"); then
    log_message "SUCCESS" "Admin command completed: $description"
    return 0
  else
    print_error "Failed to execute command as administrator."
    log_message "ERROR" "Admin command failed: $description"
    return 1
  fi
}

# Export for backward compatibility
detect_admin_user() {
  mc_detect_admin_user
}

ADMIN_USERNAME=""
# Sync ADMIN_USERNAME with MC_ADMIN_USERNAME when needed
sync_admin_username() {
  if [[ -n "$MC_ADMIN_USERNAME" ]]; then
    ADMIN_USERNAME="$MC_ADMIN_USERNAME"
  fi
}
