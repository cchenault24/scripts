#!/bin/zsh
#
# lib/backup.sh - Backup and restore functionality for mac-cleanup
# Wrapper for new backup engine (backward compatible)
#

# Load backup modules
_backup_modules_loaded=false
_load_backup_modules() {
  if [[ "$_backup_modules_loaded" == "true" ]]; then
    return 0
  fi
  
  # Get script directory - use MC_SCRIPT_DIR if available, otherwise calculate it
  local script_dir=""
  if [[ -n "${MC_SCRIPT_DIR:-}" && -d "$MC_SCRIPT_DIR/lib" ]]; then
    # Use MC_SCRIPT_DIR which is set in core.sh
    script_dir="$MC_SCRIPT_DIR/lib"
  elif [[ -n "${SCRIPT_DIR:-}" && -d "$SCRIPT_DIR/lib" ]]; then
    # Use SCRIPT_DIR from main script
    script_dir="$SCRIPT_DIR/lib"
  else
    # Fallback: calculate script directory using full path to dirname
    # Ensure PATH includes standard locations
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:${PATH:-}"
    
    # Try to get the script file path
    local script_file="${(%):-%x}"
    if [[ -z "$script_file" || "$script_file" == *"backup.sh"* ]]; then
      # If %x doesn't work or points to backup.sh itself, try BASH_SOURCE
      script_file="${BASH_SOURCE[0]:-}"
    fi
    
    if [[ -n "$script_file" && "$script_file" != /* ]]; then
      # Relative path - make it absolute
      script_file="$(pwd)/$script_file"
    fi
    
    if [[ -n "$script_file" && -f "$script_file" ]]; then
      # Use /usr/bin/dirname explicitly to avoid PATH issues
      local dirname_cmd="/usr/bin/dirname"
      if [[ ! -x "$dirname_cmd" ]]; then
        # Try to find dirname in PATH
        dirname_cmd=$(command -v dirname 2>/dev/null || echo "dirname")
      fi
      script_dir="$($dirname_cmd "$script_file" 2>/dev/null || echo ".")"
      script_dir="$(cd "$script_dir" 2>/dev/null && pwd || echo "$(pwd)/lib")"
    else
      # Last resort: try to infer from current working directory
      if [[ -d "lib/backup" ]]; then
        script_dir="$(pwd)/lib"
      elif [[ -d "../lib/backup" ]]; then
        script_dir="$(cd .. && pwd)/lib"
      else
        # Absolute last resort
        script_dir="${HOME}/Documents/scripts/mac-cleanup/lib"
      fi
    fi
  fi
  
  # Verify script_dir exists and contains backup subdirectory
  if [[ ! -d "$script_dir/backup" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Invalid script directory: $script_dir/backup does not exist"
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "MC_SCRIPT_DIR=${MC_SCRIPT_DIR:-not set}, SCRIPT_DIR=${SCRIPT_DIR:-not set}"
    return 1
  fi
  
  # Load backup modules with error checking
  local load_errors=0
  
  # Source directly (not in subshell) to ensure functions are available
  source "$script_dir/backup/storage.sh" 2>/dev/null
  local source_exit=$?
  if [[ $source_exit -ne 0 ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to load backup/storage.sh from $script_dir/backup/storage.sh"
    load_errors=$((load_errors + 1))
  fi
  
  source "$script_dir/backup/manifest.sh" 2>/dev/null
  source_exit=$?
  if [[ $source_exit -ne 0 ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to load backup/manifest.sh from $script_dir/backup/manifest.sh"
    load_errors=$((load_errors + 1))
  fi
  
  source "$script_dir/backup/validation.sh" 2>/dev/null
  source_exit=$?
  if [[ $source_exit -ne 0 ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to load backup/validation.sh from $script_dir/backup/validation.sh"
    load_errors=$((load_errors + 1))
  fi
  
  source "$script_dir/backup/engine.sh" 2>/dev/null
  source_exit=$?
  if [[ $source_exit -ne 0 ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to load backup/engine.sh from $script_dir/backup/engine.sh"
    load_errors=$((load_errors + 1))
  fi
  
  if [[ $load_errors -gt 0 ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to load $load_errors backup module(s). Script directory: $script_dir"
    return 1
  fi
  
  _backup_modules_loaded=true
  return 0
}

# Initialize backup system (called from core.sh)
mc_backup_init() {
  # #region agent log
  echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"D\",\"location\":\"backup.sh:110\",\"message\":\"mc_backup_init() called\",\"data\":{\"MC_BACKUP_DIR\":\"${MC_BACKUP_DIR:-empty}\"},\"timestamp\":$(/bin/date +%s 2>/dev/null || echo 0)}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
  # #endregion
  
  # Load modules
  if ! _load_backup_modules; then
    return 1
  fi
  
  # Verify function exists before calling (safety check)
  if ! type mc_storage_ensure_dir &>/dev/null; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "mc_storage_ensure_dir function not available after loading modules"
    # Try to reload storage module directly
    local script_dir=""
    if [[ -n "${MC_SCRIPT_DIR:-}" && -d "$MC_SCRIPT_DIR/lib" ]]; then
      script_dir="$MC_SCRIPT_DIR/lib"
    elif [[ -n "${SCRIPT_DIR:-}" && -d "$SCRIPT_DIR/lib" ]]; then
      script_dir="$SCRIPT_DIR/lib"
    fi
    if [[ -n "$script_dir" && -f "$script_dir/backup/storage.sh" ]]; then
      source "$script_dir/backup/storage.sh" 2>/dev/null || {
        log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to reload storage.sh"
        return 1
      }
      if ! type mc_storage_ensure_dir &>/dev/null; then
        log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Function still not available after reload"
        return 1
      fi
    else
      log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Cannot determine script directory for reload"
      return 1
    fi
  fi
  
  # Ensure backup directory exists
  # #region agent log
  echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"D\",\"location\":\"backup.sh:142\",\"message\":\"Before mc_storage_ensure_dir\",\"data\":{\"MC_BACKUP_DIR\":\"$MC_BACKUP_DIR\",\"dir_exists\":\"$([ -d \"$MC_BACKUP_DIR\" ] && echo 'yes' || echo 'no')\"},\"timestamp\":$(/bin/date +%s 2>/dev/null || echo 0)}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
  # #endregion
  local backup_dir=$(mc_storage_ensure_dir "$MC_BACKUP_DIR")
  local ensure_exit=$?
  # #region agent log
  echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"D\",\"location\":\"backup.sh:144\",\"message\":\"After mc_storage_ensure_dir\",\"data\":{\"backup_dir\":\"$backup_dir\",\"exit_code\":\"$ensure_exit\",\"is_empty\":\"$([ -z \"$backup_dir\" ] && echo 'yes' || echo 'no')\"},\"timestamp\":$(/bin/date +%s 2>/dev/null || echo 0)}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
  # #endregion
  if [[ -z "$backup_dir" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to ensure backup directory"
    return 1
  fi
  
  MC_BACKUP_DIR="$backup_dir"
  
  # Get session ID from backup directory name
  local session_id=$(basename "$MC_BACKUP_DIR" 2>/dev/null || echo "$(date +%Y-%m-%d-%H-%M-%S 2>/dev/null || echo 'backup')")
  
  # Initialize JSON manifest
  local manifest_path="$MC_BACKUP_DIR/backup_manifest.json"
  
  # Check if old manifest exists and migrate it
  local old_manifest="$MC_BACKUP_DIR/backup_manifest.txt"
  if [[ -f "$old_manifest" && ! -f "$manifest_path" ]]; then
    if mc_manifest_migrate_old "$old_manifest" "$manifest_path" "$session_id"; then
      log_message "${MC_LOG_LEVEL_INFO:-INFO}" "Migrated old manifest to JSON format"
    fi
  fi
  
  # Initialize new manifest if it doesn't exist
  if [[ ! -f "$manifest_path" ]]; then
    if ! mc_manifest_init "$manifest_path" "$session_id"; then
      log_message "${MC_LOG_LEVEL_WARNING:-WARNING}" "Failed to initialize JSON manifest, falling back to text manifest"
      # Fallback: create old-style manifest for compatibility
      touch "$old_manifest" 2>/dev/null || true
    fi
  fi
  
  return 0
}

# Backup a directory or file before cleaning (backward compatible API)
# Arguments: path, backup_name
backup() {
  local path="$1"
  local backup_name="$2"
  
  # Load modules if not already loaded
  if ! _load_backup_modules; then
    print_error "Failed to load backup modules"
    return 1
  fi
  
  # Handle dry run
  if [[ "$MC_DRY_RUN" == "true" ]]; then
    local size=$(calculate_size "$path" 2>/dev/null || echo "")
    print_info "[DRY RUN] Would backup $path${size:+ ($size)} to $backup_name"
    log_message "DRY_RUN" "Would backup: $path -> $backup_name"
    return 0
  fi
  
  # Ensure backup directory is set
  if [[ -z "$MC_BACKUP_DIR" ]]; then
    print_error "Backup directory not set. Cannot create backup."
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Backup directory not set (MC_BACKUP_DIR is empty)"
    return 1
  fi
  
  # Ensure backup system is initialized
  if ! mc_backup_init; then
    print_error "Failed to initialize backup system"
    return 1
  fi
  
  # Determine manifest path (prefer JSON, fallback to text)
  local manifest_path="$MC_BACKUP_DIR/backup_manifest.json"
  if [[ ! -f "$manifest_path" ]]; then
    manifest_path="$MC_BACKUP_DIR/backup_manifest.txt"
  fi
  
  # Use new backup engine
  if mc_backup_create "$path" "$backup_name" "$MC_BACKUP_DIR" "$manifest_path"; then
    return 0
  else
    return 1
  fi
}

# List available backup sessions (backward compatible)
mc_list_backups() {
  # Load restore module if needed
  local script_dir=""
  if [[ -n "${MC_SCRIPT_DIR:-}" ]]; then
    script_dir="$MC_SCRIPT_DIR/lib"
  else
    local script_file="${(%):-%x}"
    if [[ -z "$script_file" ]]; then
      script_file="${BASH_SOURCE[0]:-}"
    fi
    if [[ -n "$script_file" ]]; then
      script_dir="$(cd "$(/usr/bin/dirname "$script_file" 2>/dev/null || echo ".")" && pwd)"
    else
      script_dir="$(pwd)"
    fi
  fi
  
  source "$script_dir/backup/restore.sh" 2>/dev/null || {
    print_error "Failed to load restore module from $script_dir/backup/restore.sh"
    return 1
  }
  
  mc_restore_list_sessions
}

# Export for backward compatibility
list_backups() {
  mc_list_backups
}
