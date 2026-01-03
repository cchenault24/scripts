#!/bin/zsh
#
# lib/error_handler.sh - Standardized error handling functions for mac-cleanup
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Standard error handling wrapper for plugin operations
# Phase 4.3: Enhanced with actionable error messages
# Usage: mc_handle_plugin_error <operation> <path> <error_code> <plugin_name> <suggestion>
mc_handle_plugin_error() {
  local operation="$1"
  local path="$2"
  local error_code="${3:-1}"
  local plugin_name="${4:-Unknown}"
  local suggestion="${5:-}"
  
  # Phase 4.3: Provide clear, actionable error message
  if [[ -n "$path" ]]; then
    print_error "Failed to $operation: $path"
  else
    print_error "Failed to $operation"
  fi
  
  # Phase 4.3: Add actionable suggestion if provided
  if [[ -n "$suggestion" ]]; then
    print_info "Suggestion: $suggestion"
  fi
  
  log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Plugin error in $plugin_name: Failed to $operation: ${path:-N/A} (code: $error_code)"
  
  return $error_code
}

# Handle backup errors consistently
# Phase 4.3: Enhanced with actionable error messages
mc_handle_backup_error() {
  local path="$1"
  local backup_name="$2"
  local plugin_name="${3:-Unknown}"
  local reason="${4:-}"
  
  # Phase 4.3: Provide clear error message with context
  print_error "Backup failed for $backup_name. Aborting cleanup to prevent data loss."
  
  # Phase 4.3: Add specific reason if provided
  if [[ -n "$reason" ]]; then
    print_info "Reason: $reason"
  fi
  
  # Phase 4.3: Provide actionable next steps
  print_info "Next steps:"
  print_info "  • Check available disk space: df -h"
  print_info "  • Verify backup directory is writable: $MC_BACKUP_DIR"
  print_info "  • Check log file for details: $MC_LOG_FILE"
  
  log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Backup failed in $plugin_name: $path -> $backup_name${reason:+ (reason: $reason)}"
  
  return 1
}

# Handle cleanup errors consistently
# Phase 4.3: Enhanced with actionable error messages
mc_handle_cleanup_error() {
  local path="$1"
  local description="$2"
  local plugin_name="${3:-Unknown}"
  local reason="${4:-}"
  
  # Phase 4.3: Provide clear error message
  print_error "Failed to clean $description: $path"
  
  # Phase 4.3: Add specific reason if provided
  if [[ -n "$reason" ]]; then
    print_info "Reason: $reason"
  fi
  
  # Phase 4.3: Provide actionable next steps based on common causes
  if [[ "$reason" == *"permission"* ]] || [[ "$reason" == *"Permission denied"* ]]; then
    print_info "Next steps:"
    print_info "  • Check file permissions: ls -la \"$path\""
    print_info "  • Try running with appropriate permissions"
  elif [[ "$reason" == *"in use"* ]] || [[ "$reason" == *"busy"* ]]; then
    print_info "Next steps:"
    print_info "  • Close any applications using this file/directory"
    print_info "  • Wait a few moments and try again"
  elif [[ "$reason" == *"disk space"* ]] || [[ "$reason" == *"No space"* ]]; then
    print_info "Next steps:"
    print_info "  • Free up disk space: df -h"
    print_info "  • Remove old backups: $MC_BACKUP_DIR"
  else
    print_info "Next steps:"
    print_info "  • Check log file for details: $MC_LOG_FILE"
    print_info "  • Verify the path exists and is accessible"
  fi
  
  log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Cleanup error in $plugin_name: Failed to clean $description: $path${reason:+ (reason: $reason)}"
  
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
