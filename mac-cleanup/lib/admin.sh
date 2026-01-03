#!/bin/zsh
#
# lib/admin.sh - Admin/sudo operations for mac-cleanup
#

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

# Function to run commands as admin using sudo
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
  # In non-interactive mode, we need cached credentials
  if ! sudo -n -v 2>/dev/null; then
    # Try once with prompt (only if interactive)
    if [[ -t 0 ]] && [[ -t 1 ]] && [[ -z "${MC_NON_INTERACTIVE:-}" ]]; then
      if ! sudo -v; then
        print_error "Failed to validate sudo credentials."
        log_message "ERROR" "Sudo credential validation failed"
        return 1
      fi
    else
      print_error "Sudo credentials not cached. Please run 'sudo -v' first to cache credentials."
      log_message "ERROR" "Sudo credentials not cached in non-interactive mode"
      return 1
    fi
  fi
  
  # Run the command with sudo (use -n to fail immediately if password needed)
  if sudo -n sh -c "$command" 2>/dev/null || ([[ -t 0 ]] && [[ -t 1 ]] && [[ -z "${MC_NON_INTERACTIVE:-}" ]] && sudo sh -c "$command"); then
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
