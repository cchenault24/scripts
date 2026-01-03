#!/bin/zsh
#
# lib/error_handler.sh - Standardized error handling functions for mac-cleanup
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Standard error handling wrapper for plugin operations
# Usage: mc_handle_plugin_error <operation> <path> <error_code>
mc_handle_plugin_error() {
  local operation="$1"
  local path="$2"
  local error_code="${3:-1}"
  local plugin_name="${4:-Unknown}"
  
  print_error "Failed to $operation: $path"
  log_message "$MC_LOG_LEVEL_ERROR" "Plugin error in $plugin_name: Failed to $operation: $path (code: $error_code)"
  
  return $error_code
}

# Handle backup errors consistently
mc_handle_backup_error() {
  local path="$1"
  local backup_name="$2"
  local plugin_name="${3:-Unknown}"
  
  print_error "Backup failed for $backup_name. Aborting cleanup to prevent data loss."
  log_message "$MC_LOG_LEVEL_ERROR" "Backup failed in $plugin_name: $path -> $backup_name"
  
  return 1
}

# Handle cleanup errors consistently
mc_handle_cleanup_error() {
  local path="$1"
  local description="$2"
  local plugin_name="${3:-Unknown}"
  
  print_error "Failed to clean $description: $path"
  log_message "$MC_LOG_LEVEL_ERROR" "Cleanup error in $plugin_name: Failed to clean $description: $path"
  
  return 1
}

# Execute command with error handling
# Usage: mc_execute_with_error_handling <command> <description> <plugin_name>
mc_execute_with_error_handling() {
  local command="$1"
  local description="$2"
  local plugin_name="${3:-Unknown}"
  
  if eval "$command" 2>&1; then
    return 0
  else
    local error_code=$?
    mc_handle_plugin_error "$description" "" "$error_code" "$plugin_name"
    return $error_code
  fi
}

# Check return value and handle error
# Usage: mc_check_return_value <return_code> <success_message> <error_message> <plugin_name>
mc_check_return_value() {
  local return_code=$1
  local success_message="$2"
  local error_message="$3"
  local plugin_name="${4:-Unknown}"
  
  if [[ $return_code -eq 0 ]]; then
    if [[ -n "$success_message" ]]; then
      print_success "$success_message"
      log_message "$MC_LOG_LEVEL_SUCCESS" "$success_message"
    fi
    return 0
  else
    if [[ -n "$error_message" ]]; then
      print_error "$error_message"
      log_message "$MC_LOG_LEVEL_ERROR" "Error in $plugin_name: $error_message (code: $return_code)"
    fi
    return $return_code
  fi
}
