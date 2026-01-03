#!/bin/zsh
#
# lib/backup/storage.sh - Storage management for backup system
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Check available disk space for a given directory
# Returns available space in bytes, or 0 on error
mc_storage_check_space() {
  local target_dir="$1"
  
  if [[ -z "$target_dir" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "mc_storage_check_space: target_dir is empty"
    echo "0"
    return 1
  fi
  
  # Ensure directory exists for stat
  if [[ ! -d "$target_dir" ]]; then
    # Try parent directory
    local parent_dir=$(dirname "$target_dir" 2>/dev/null)
    if [[ -d "$parent_dir" ]]; then
      target_dir="$parent_dir"
    else
      # Fallback to HOME
      target_dir="${HOME:-/tmp}"
    fi
  fi
  
  # Use df -k (1KB blocks) for reliable cross-platform support
  # macOS df shows 1KB blocks with -k flag
  local df_output=$(df -k "$target_dir" 2>/dev/null)
  local df_exit=$?
  
  if [[ $df_exit -ne 0 || -z "$df_output" ]]; then
    log_message "${MC_LOG_LEVEL_WARNING:-WARNING}" "Failed to get disk space for $target_dir"
    echo "0"
    return 1
  fi
  
  # Parse available space from df output
  # Format: Filesystem 1024-blocks Used Available Capacity ...
  # Available is 4th field on second line
  # Use /usr/bin/awk to ensure it's available
  local available_kb=$(echo "$df_output" | /usr/bin/awk 'NR==2 {print $4}' 2>/dev/null)
  
  # Validate it's a number
  if [[ -z "$available_kb" || ! "$available_kb" =~ ^[0-9]+$ ]]; then
    log_message "${MC_LOG_LEVEL_WARNING:-WARNING}" "Invalid disk space value: $available_kb"
    echo "0"
    return 1
  fi
  
  # Convert KB to bytes
  local available_bytes=$((available_kb * 1024))
  echo "$available_bytes"
  return 0
}

# Ensure backup directory exists and is writable
# Returns 0 on success, 1 on failure
# Outputs directory path to stdout (for command substitution)
# Outputs error messages to stderr
mc_storage_ensure_dir() {
  local backup_dir="$1"
  
  if [[ -z "$backup_dir" ]]; then
    print_error "Backup directory path is empty" >&2
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "mc_storage_ensure_dir: backup_dir is empty"
    return 1
  fi
  
  # Create directory if it doesn't exist
  if [[ ! -d "$backup_dir" ]]; then
    # Ensure parent directory exists first (mkdir -p should handle this, but be explicit)
    local parent_dir=$(dirname "$backup_dir" 2>/dev/null)
    if [[ -n "$parent_dir" && "$parent_dir" != "." && "$parent_dir" != "/" && ! -d "$parent_dir" ]]; then
      mkdir -p "$parent_dir" 2>/dev/null || true
    fi
    
    if ! mkdir -p "$backup_dir" 2>/dev/null; then
      print_error "Failed to create backup directory: $backup_dir" >&2
      log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to create backup directory: $backup_dir"
      
      # Try fallback location
      local fallback_dir="${MC_BACKUP_FALLBACK_DIR:-/tmp/mac-cleanup-backups}/$(/bin/date +%Y-%m-%d-%H-%M-%S 2>/dev/null || echo 'backup')"
      print_info "Attempting fallback location: $fallback_dir" >&2
      if mkdir -p "$fallback_dir" 2>/dev/null; then
        backup_dir="$fallback_dir"
        log_message "${MC_LOG_LEVEL_WARNING:-WARNING}" "Using fallback backup directory: $backup_dir"
      else
        return 1
      fi
    fi
  fi
  
  # Verify directory is writable
  if [[ ! -w "$backup_dir" ]]; then
    print_error "Backup directory is not writable: $backup_dir" >&2
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Backup directory not writable: $backup_dir"
    return 1
  fi
  
  # Return the validated directory path to stdout (for command substitution)
  echo "$backup_dir"
  return 0
}

# Check if there's sufficient space for a backup
# Arguments: backup_dir, required_bytes
# Returns 0 if sufficient, 1 if insufficient
mc_storage_has_space() {
  local backup_dir="$1"
  local required_bytes="$2"
  
  if [[ -z "$backup_dir" || -z "$required_bytes" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "mc_storage_has_space: missing arguments"
    return 1
  fi
  
  # Validate required_bytes is numeric
  if [[ ! "$required_bytes" =~ ^[0-9]+$ ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "mc_storage_has_space: required_bytes is not numeric: $required_bytes"
    return 1
  fi
  
  # Get available space
  local available_bytes=$(mc_storage_check_space "$backup_dir")
  
  # Add 10% overhead for compression and metadata
  local needed_with_overhead=$((required_bytes + (required_bytes / 10)))
  
  if [[ $available_bytes -lt $needed_with_overhead ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Insufficient disk space: available=$(format_bytes $available_bytes), needed=$(format_bytes $needed_with_overhead)"
    return 1
  fi
  
  return 0
}

# Clean up old backup sessions
# Arguments: backup_base_dir, max_sessions (default: 10)
mc_storage_cleanup_old() {
  local backup_base_dir="$1"
  local max_sessions="${2:-10}"
  
  if [[ -z "$backup_base_dir" || ! -d "$backup_base_dir" ]]; then
    return 0
  fi
  
  # Validate max_sessions is numeric
  if [[ ! "$max_sessions" =~ ^[0-9]+$ ]]; then
    max_sessions=10
  fi
  
  # Get all backup sessions sorted by modification time (newest first)
  local sessions=($(find "$backup_base_dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | \
    xargs -0 stat -f "%m %N" 2>/dev/null | \
    sort -rn | \
    cut -d' ' -f2- | \
    tail -n +$((max_sessions + 1)) 2>/dev/null))
  
  if [[ ${#sessions[@]} -eq 0 ]]; then
    return 0
  fi
  
  local removed=0
  for session_dir in "${sessions[@]}"; do
    if [[ -d "$session_dir" ]]; then
      log_message "${MC_LOG_LEVEL_INFO:-INFO}" "Removing old backup session: $session_dir"
      rm -rf "$session_dir" 2>/dev/null && removed=$((removed + 1))
    fi
  done
  
  if [[ $removed -gt 0 ]]; then
    log_message "${MC_LOG_LEVEL_INFO:-INFO}" "Cleaned up $removed old backup session(s)"
  fi
  
  return 0
}
