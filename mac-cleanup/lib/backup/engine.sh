#!/bin/zsh
#
# lib/backup/engine.sh - Core backup engine with atomic operations
#

# Main backup function - creates atomic backup of file or directory
# Arguments: path, backup_name, backup_dir, manifest_path
# Returns 0 on success, 1 on failure
mc_backup_create() {
  local path="$1"
  local backup_name="$2"
  local backup_dir="$3"
  local manifest_path="$4"
  
  if [[ -z "$path" || -z "$backup_name" || -z "$backup_dir" || -z "$manifest_path" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "mc_backup_create: missing required arguments"
    return 1
  fi
  
  # Validate path exists and is readable
  if ! mc_validate_path "$path"; then
    return 1
  fi
  
  # Determine backup type
  local backup_type="file"
  if [[ -d "$path" ]]; then
    backup_type="directory"
  fi
  
  # Check if path is too small to backup (skip empty/small directories)
  if [[ "$backup_type" == "directory" ]]; then
    local dir_size=$(mc_get_path_size "$path")
    if [[ -n "${MC_MIN_BACKUP_SIZE:-}" && $dir_size -lt $MC_MIN_BACKUP_SIZE ]]; then
      print_info "Skipping backup of small directory (< $(format_bytes $MC_MIN_BACKUP_SIZE)): $path"
      log_message "${MC_LOG_LEVEL_INFO:-INFO}" "Skipped backup of small directory: $path ($(format_bytes $dir_size))"
      return 0
    fi
  fi
  
  # Get path size for disk space check
  local path_size=$(mc_get_path_size "$path")
  
  # Check disk space
  if ! mc_storage_has_space "$backup_dir" "$path_size"; then
    local available=$(mc_storage_check_space "$backup_dir")
    print_error "Insufficient disk space for backup. Available: $(format_bytes $available), Needed: $(format_bytes $path_size)"
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Insufficient disk space for backup: $backup_name"
    return 1
  fi
  
  # Create backup
  print_info "Backing up $path..."
  log_message "${MC_LOG_LEVEL_INFO:-INFO}" "Creating backup: $path -> $backup_name"
  
  local backup_file=""
  local checksum=""
  
  if [[ "$backup_type" == "directory" ]]; then
    if ! backup_file=$(mc_backup_directory "$path" "$backup_name" "$backup_dir"); then
      return 1
    fi
  else
    if ! backup_file=$(mc_backup_file "$path" "$backup_name" "$backup_dir"); then
      return 1
    fi
  fi
  
  # Calculate checksum
  checksum=$(mc_calculate_checksum "$backup_file")
  
  # Verify backup integrity
  if ! mc_validate_backup "$backup_file" "$backup_type"; then
    print_error "Backup validation failed: $backup_name"
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Backup validation failed: $backup_file"
    rm -f "$backup_file" 2>/dev/null
    return 1
  fi
  
  # Add to manifest
  if ! mc_manifest_add "$manifest_path" "$path" "$backup_name" "$(basename "$backup_file")" "$backup_type" "$path_size" "$checksum"; then
    print_error "Failed to add backup to manifest: $backup_name"
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to add backup to manifest: $backup_name"
    # Don't remove backup file - it's valid, just manifest update failed
    return 1
  fi
  
  print_success "Backup complete: $backup_name"
  log_message "${MC_LOG_LEVEL_SUCCESS:-SUCCESS}" "Backup created and verified: $backup_name"
  return 0
}

# Backup a directory (atomic operation)
# Arguments: path, backup_name, backup_dir
# Outputs: backup_file_path on success
mc_backup_directory() {
  local path="$1"
  local backup_name="$2"
  local backup_dir="$3"
  
  if [[ -z "$path" || -z "$backup_name" || -z "$backup_dir" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "mc_backup_directory: missing arguments"
    return 1
  fi
  
  local backup_file="$backup_dir/${backup_name}.tar.gz"
  local temp_file="${backup_file}.tmp"
  
  # Get parent directory and basename for tar
  local parent_dir=$(dirname "$path" 2>/dev/null)
  local basename_path=$(basename "$path" 2>/dev/null)
  
  if [[ -z "$parent_dir" || -z "$basename_path" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to parse path: $path"
    return 1
  fi
  
  # Create backup atomically: write to temp file first
  # Use pipefail to catch errors in pipeline
  (
    set -o pipefail
    cd "$parent_dir" 2>/dev/null || return 1
    tar -czf "$temp_file" "$basename_path" 2>/dev/null || return 1
  )
  
  local tar_exit=$?
  if [[ $tar_exit -ne 0 ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "tar command failed for: $path"
    rm -f "$temp_file" 2>/dev/null
    return 1
  fi
  
  # Verify temp file was created and is not empty
  if [[ ! -f "$temp_file" || ! -s "$temp_file" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Backup file is empty or missing: $temp_file"
    rm -f "$temp_file" 2>/dev/null
    return 1
  fi
  
  # Verify archive integrity
  if ! tar -tzf "$temp_file" &>/dev/null; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Backup archive integrity check failed: $temp_file"
    rm -f "$temp_file" 2>/dev/null
    return 1
  fi
  
  # Atomically move temp file to final location
  if ! mv "$temp_file" "$backup_file" 2>/dev/null; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to move backup file atomically: $temp_file -> $backup_file"
    rm -f "$temp_file" 2>/dev/null
    return 1
  fi
  
  # Verify final file exists
  if [[ ! -f "$backup_file" || ! -s "$backup_file" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Backup file verification failed: $backup_file"
    rm -f "$backup_file" 2>/dev/null
    return 1
  fi
  
  echo "$backup_file"
  return 0
}

# Backup a file (atomic operation)
# Arguments: path, backup_name, backup_dir
# Outputs: backup_file_path on success
mc_backup_file() {
  local path="$1"
  local backup_name="$2"
  local backup_dir="$3"
  
  if [[ -z "$path" || -z "$backup_name" || -z "$backup_dir" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "mc_backup_file: missing arguments"
    return 1
  fi
  
  local backup_file="$backup_dir/$backup_name"
  local temp_file="${backup_file}.tmp"
  
  # Copy file to temp location
  if ! cp "$path" "$temp_file" 2>/dev/null; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to copy file: $path -> $temp_file"
    rm -f "$temp_file" 2>/dev/null
    return 1
  fi
  
  # Verify temp file was created and matches original size
  if [[ ! -f "$temp_file" || ! -s "$temp_file" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Backup file is empty or missing: $temp_file"
    rm -f "$temp_file" 2>/dev/null
    return 1
  fi
  
  local original_size=$(stat -f%z "$path" 2>/dev/null || echo "0")
  local backup_size=$(stat -f%z "$temp_file" 2>/dev/null || echo "0")
  
  if [[ "$original_size" != "$backup_size" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Backup file size mismatch: original=$original_size, backup=$backup_size"
    rm -f "$temp_file" 2>/dev/null
    return 1
  fi
  
  # Atomically move temp file to final location
  if ! mv "$temp_file" "$backup_file" 2>/dev/null; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to move backup file atomically: $temp_file -> $backup_file"
    rm -f "$temp_file" 2>/dev/null
    return 1
  fi
  
  # Verify final file exists and size matches
  if [[ ! -f "$backup_file" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Backup file verification failed: $backup_file"
    rm -f "$backup_file" 2>/dev/null
    return 1
  fi
  
  local final_size=$(stat -f%z "$backup_file" 2>/dev/null || echo "0")
  if [[ "$final_size" != "$original_size" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Final backup file size mismatch: expected=$original_size, got=$final_size"
    rm -f "$backup_file" 2>/dev/null
    return 1
  fi
  
  echo "$backup_file"
  return 0
}

# Verify backup file exists and is valid
# Arguments: backup_file_path
# Returns 0 if valid, 1 if invalid
mc_backup_verify() {
  local backup_file="$1"
  
  if [[ -z "$backup_file" ]]; then
    return 1
  fi
  
  # Check file exists
  if [[ ! -f "$backup_file" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Backup file does not exist: $backup_file"
    return 1
  fi
  
  # Check file is not empty
  if [[ ! -s "$backup_file" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Backup file is empty: $backup_file"
    return 1
  fi
  
  # Check file is readable
  if [[ ! -r "$backup_file" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Backup file is not readable: $backup_file"
    return 1
  fi
  
  # For tar.gz files, verify archive integrity
  if [[ "$backup_file" == *.tar.gz ]]; then
    if ! tar -tzf "$backup_file" &>/dev/null; then
      log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Backup archive integrity check failed: $backup_file"
      return 1
    fi
  fi
  
  return 0
}
