#!/bin/zsh
#
# lib/backup/validation.sh - Validation and integrity checking for backup system
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Calculate SHA256 checksum of a file
# Arguments: file_path
# Outputs: checksum string (format: sha256:hexdigest)
mc_calculate_checksum() {
  local file_path="$1"
  
  if [[ -z "$file_path" || ! -f "$file_path" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "mc_calculate_checksum: file does not exist: $file_path"
    echo ""
    return 1
  fi
  
  # Use shasum (macOS) or sha256sum (Linux)
  local checksum=""
  if command -v shasum &>/dev/null; then
    checksum=$(shasum -a 256 "$file_path" 2>/dev/null | /usr/bin/awk '{print $1}')
  elif command -v sha256sum &>/dev/null; then
    checksum=$(sha256sum "$file_path" 2>/dev/null | /usr/bin/awk '{print $1}')
  else
    log_message "${MC_LOG_LEVEL_WARNING:-WARNING}" "No SHA256 tool available, skipping checksum"
    echo ""
    return 1
  fi
  
  if [[ -z "$checksum" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to calculate checksum for: $file_path"
    echo ""
    return 1
  fi
  
  echo "sha256:$checksum"
  return 0
}

# Verify checksum of a file
# Arguments: file_path, expected_checksum
# Returns 0 if match, 1 if mismatch or error
mc_verify_checksum() {
  local file_path="$1"
  local expected_checksum="$2"
  
  if [[ -z "$file_path" || -z "$expected_checksum" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "mc_verify_checksum: missing arguments"
    return 1
  fi
  
  # Remove sha256: prefix if present
  expected_checksum="${expected_checksum#sha256:}"
  
  local actual_checksum=$(mc_calculate_checksum "$file_path")
  if [[ -z "$actual_checksum" ]]; then
    return 1
  fi
  
  # Remove sha256: prefix for comparison
  actual_checksum="${actual_checksum#sha256:}"
  
  if [[ "$actual_checksum" == "$expected_checksum" ]]; then
    return 0
  else
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Checksum mismatch for $file_path (expected: $expected_checksum, got: $actual_checksum)"
    return 1
  fi
}

# Validate backup file integrity
# Arguments: backup_file_path, backup_type (file|directory)
# Returns 0 if valid, 1 if invalid
mc_validate_backup() {
  local backup_file="$1"
  local backup_type="${2:-unknown}"
  
  if [[ -z "$backup_file" || ! -f "$backup_file" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "mc_validate_backup: backup file does not exist: $backup_file"
    return 1
  fi
  
  # Check file is not empty
  local file_size=$(stat -f%z "$backup_file" 2>/dev/null || echo "0")
  if [[ -z "$file_size" || "$file_size" == "0" ]]; then
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
  
  # For directories (tar.gz), verify we can list contents
  if [[ "$backup_type" == "directory" && "$backup_file" == *.tar.gz ]]; then
    local file_count=$(tar -tzf "$backup_file" 2>/dev/null | wc -l | tr -d ' ')
    if [[ -z "$file_count" || "$file_count" == "0" ]]; then
      log_message "${MC_LOG_LEVEL_WARNING:-WARNING}" "Backup archive appears empty: $backup_file"
      # Don't fail for empty archives (they might be valid)
    fi
  fi
  
  return 0
}

# Verify restore operation succeeded
# Arguments: original_path, backup_type, expected_size (optional)
# Returns 0 if restore verified, 1 if verification failed
mc_verify_restore() {
  local original_path="$1"
  local backup_type="${2:-unknown}"
  local expected_size="${3:-}"
  
  if [[ -z "$original_path" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "mc_verify_restore: original_path is empty"
    return 1
  fi
  
  # Check path exists
  if [[ ! -e "$original_path" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Restored path does not exist: $original_path"
    return 1
  fi
  
  # Verify type matches
  if [[ "$backup_type" == "directory" ]]; then
    if [[ ! -d "$original_path" ]]; then
      log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Restored path is not a directory: $original_path"
      return 1
    fi
  elif [[ "$backup_type" == "file" ]]; then
    if [[ ! -f "$original_path" ]]; then
      log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Restored path is not a file: $original_path"
      return 1
    fi
  fi
  
  # Verify size if provided
  if [[ -n "$expected_size" && "$expected_size" =~ ^[0-9]+$ ]]; then
    local actual_size=0
    if [[ -f "$original_path" ]]; then
      actual_size=$(stat -f%z "$original_path" 2>/dev/null || echo "0")
    elif [[ -d "$original_path" ]]; then
      # For directories, calculate total size
      actual_size=$(du -sk "$original_path" 2>/dev/null | /usr/bin/awk '{print $1 * 1024}' || echo "0")
    fi
    
    # Allow 1% tolerance for size differences (compression, metadata, etc.)
    local tolerance=$((expected_size / 100))
    local diff=$((actual_size > expected_size ? actual_size - expected_size : expected_size - actual_size))
    
    if [[ $diff -gt $tolerance ]]; then
      log_message "${MC_LOG_LEVEL_WARNING:-WARNING}" "Size mismatch for restored path: $original_path (expected: $expected_size, got: $actual_size)"
      # Don't fail, just warn (sizes can vary due to filesystem differences)
    fi
  fi
  
  return 0
}

# Validate path before backup
# Arguments: path
# Returns 0 if valid, 1 if invalid
mc_validate_path() {
  local path="$1"
  
  if [[ -z "$path" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "mc_validate_path: path is empty"
    return 1
  fi
  
  # Check path exists
  if [[ ! -e "$path" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Path does not exist: $path"
    return 1
  fi
  
  # Check path is readable
  if [[ ! -r "$path" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Path is not readable: $path"
    return 1
  fi
  
  # Check path is not a symlink (we backup the target, not the link)
  if [[ -L "$path" ]]; then
    log_message "${MC_LOG_LEVEL_WARNING:-WARNING}" "Path is a symlink, will backup target: $path"
  fi
  
  return 0
}

# Get file or directory size in bytes
# Arguments: path
# Outputs: size in bytes
mc_get_path_size() {
  local path="$1"
  
  if [[ -z "$path" || ! -e "$path" ]]; then
    echo "0"
    return 1
  fi
  
  if [[ -f "$path" ]]; then
    stat -f%z "$path" 2>/dev/null || echo "0"
  elif [[ -d "$path" ]]; then
    # Use du for directories (more accurate)
    # Use /usr/bin/awk to ensure it's available
    du -sk "$path" 2>/dev/null | /usr/bin/awk '{print $1 * 1024}' || echo "0"
  else
    echo "0"
  fi
}
