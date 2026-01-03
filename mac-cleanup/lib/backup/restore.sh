#!/bin/zsh
#
# lib/backup/restore.sh - Restore engine for backup system
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Load dependencies
# Get script directory - use MC_SCRIPT_DIR if available, otherwise calculate it
restore_script_dir=""
if [[ -n "${MC_SCRIPT_DIR:-}" && -d "$MC_SCRIPT_DIR/lib" ]]; then
  restore_script_dir="$MC_SCRIPT_DIR/lib"
elif [[ -n "${SCRIPT_DIR:-}" && -d "$SCRIPT_DIR/lib" ]]; then
  restore_script_dir="$SCRIPT_DIR/lib"
else
  # Fallback: calculate script directory
  restore_script_file="${(%):-%x}"
  if [[ -z "$restore_script_file" ]]; then
    restore_script_file="${BASH_SOURCE[0]:-}"
  fi
  if [[ -n "$restore_script_file" && -f "$restore_script_file" ]]; then
    restore_script_dir="$(cd "$(/usr/bin/dirname "$restore_script_file" 2>/dev/null || echo ".")" && pwd)"
  else
    restore_script_dir="$(pwd)/lib"
  fi
fi

# Source manifest.sh for mc_manifest_validate and mc_manifest_migrate_old
if [[ -f "$restore_script_dir/backup/manifest.sh" ]]; then
  source "$restore_script_dir/backup/manifest.sh" 2>/dev/null
fi

# Source validation.sh for mc_validate_backup and mc_verify_restore
if [[ -f "$restore_script_dir/backup/validation.sh" ]]; then
  source "$restore_script_dir/backup/validation.sh" 2>/dev/null
fi

# Restore all items from a manifest
# Arguments: manifest_path, backup_dir
# Returns 0 on success, 1 on failure
mc_restore_from_manifest() {
  local manifest_path="$1"
  local backup_dir="$2"
  
  if [[ -z "$manifest_path" || -z "$backup_dir" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "mc_restore_from_manifest: missing arguments"
    return 1
  fi
  
  # Validate manifest
  if ! mc_manifest_validate "$manifest_path"; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Manifest validation failed: $manifest_path"
    return 1
  fi
  
  # Check if manifest is empty (no backups)
  # Look for backup entries: check if the backups array contains any backup objects
  # Empty array: "backups": []
  # Non-empty array: "backups": [ { ... }, { ... } ] or formatted with newlines
  # Simple approach: check if there are backup entry fields like "original_path" or "backup_file" 
  # that appear after "backups": [ - these indicate backup objects exist
  local has_backups=false
  
  # Extract the backups array section and check if it contains backup objects
  # Look for fields that are unique to backup entries (not in the root object)
  # Use /usr/bin/awk to ensure it's available
  # The pattern matches "backups" followed by optional whitespace and [
  local found_backup_entry=""
  found_backup_entry=$(/usr/bin/awk '
    /"backups"/ { 
      if ($0 ~ /\[/) {
        if ($0 ~ /"original_path"/ || $0 ~ /"backup_file"/ || $0 ~ /"backup_name"/) {
          print "found"
          exit 0
        }
        if ($0 ~ /\]/) {
          exit 1
        }
        in_backups=1
      } else {
        in_backups=1
        next
      }
    }
    in_backups {
      if ($0 ~ /"original_path"/ || $0 ~ /"backup_file"/ || $0 ~ /"backup_name"/) {
        print "found"
        exit 0
      }
      if ($0 ~ /\]/) {
        exit 1
      }
    }
  ' "$manifest_path" 2>/dev/null || echo "")
  
  if [[ "$found_backup_entry" == "found" ]]; then
    has_backups=true
  fi
  
  if [[ "$has_backups" == "false" ]]; then
    print_info "No backups found in manifest (manifest may be empty)"
    return 0
  fi
  
  # Extract backup entries from manifest
  local restored=0
  local failed=0
  local failed_paths=()
  
  # Parse JSON entries (simple approach - extract each backup object)
  # This is a simplified parser - for production, consider using jq
  local in_entry=false
  local entry_data=""
  local original_path=""
  local backup_file=""
  local backup_type=""
  local size_bytes=""
  
  while IFS= read -r line; do
    # Look for backup entry start
    if [[ "$line" =~ \"original_path\" ]]; then
      in_entry=true
      entry_data="$line"
      # Extract original_path
      original_path=$(echo "$line" | sed -n 's/.*"original_path":\s*"\([^"]*\)".*/\1/p')
    elif [[ "$in_entry" == "true" ]]; then
      entry_data="$entry_data $line"
      
      # Extract other fields
      if [[ "$line" =~ \"backup_file\" ]]; then
        backup_file=$(echo "$line" | sed -n 's/.*"backup_file":\s*"\([^"]*\)".*/\1/p')
      fi
      if [[ "$line" =~ \"type\" ]]; then
        backup_type=$(echo "$line" | sed -n 's/.*"type":\s*"\([^"]*\)".*/\1/p')
      fi
      if [[ "$line" =~ \"size_bytes\" ]]; then
        size_bytes=$(echo "$line" | sed -n 's/.*"size_bytes":\s*\([0-9]*\).*/\1/p')
      fi
      
      # Check for entry end (closing brace)
      if [[ "$line" =~ ^\s*\}\s*,?\s*$ ]]; then
        # Process this entry
        if [[ -n "$original_path" && -n "$backup_file" ]]; then
          if mc_restore_item "$backup_dir/$backup_file" "$original_path" "$backup_type" "$size_bytes"; then
            restored=$((restored + 1))
          else
            failed=$((failed + 1))
            failed_paths+=("$original_path")
          fi
        fi
        
        # Reset for next entry
        in_entry=false
        entry_data=""
        original_path=""
        backup_file=""
        backup_type=""
        size_bytes=""
      fi
    fi
  done < "$manifest_path"
  
  # Print summary
  print_header "Restore Summary"
  if [[ $restored -gt 0 ]]; then
    print_success "Successfully restored $restored file(s)"
  fi
  if [[ $failed -gt 0 ]]; then
    print_error "Failed to restore $failed file(s)"
    echo ""
    print_info "Failed restores:"
    for failed_path in "${failed_paths[@]}"; do
      print_message "$RED" "  - $failed_path"
    done
    echo ""
    print_info "You may need to manually restore these files or check backup integrity."
  fi
  if [[ $restored -eq 0 && $failed -eq 0 ]]; then
    print_info "No files were restored (manifest may be empty)"
  fi
  
  return $((failed > 0 ? 1 : 0))
}

# Restore a single item
# Arguments: backup_file_path, original_path, backup_type, expected_size (optional)
# Returns 0 on success, 1 on failure
mc_restore_item() {
  local backup_file="$1"
  local original_path="$2"
  local backup_type="${3:-unknown}"
  local expected_size="${4:-}"
  
  if [[ -z "$backup_file" || -z "$original_path" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "mc_restore_item: missing arguments"
    return 1
  fi
  
  # Check backup file exists
  if [[ ! -f "$backup_file" ]]; then
    print_error "Backup file not found: $backup_file"
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Backup file not found: $backup_file (original: $original_path)"
    return 1
  fi
  
  # Verify backup file integrity
  if ! mc_validate_backup "$backup_file" "$backup_type"; then
    print_error "Backup file integrity check failed: $backup_file"
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Backup file integrity check failed: $backup_file"
    return 1
  fi
  
  print_info "Restoring $original_path..."
  
  # Create parent directory if needed
  local parent_dir=$(dirname "$original_path" 2>/dev/null)
  if [[ -n "$parent_dir" && ! -d "$parent_dir" ]]; then
    if ! mkdir -p "$parent_dir" 2>/dev/null; then
      print_error "Failed to create parent directory: $parent_dir"
      log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to create parent directory: $parent_dir"
      return 1
    fi
  fi
  
  # Restore based on type
  if [[ "$backup_file" == *.tar.gz || "$backup_type" == "directory" ]]; then
    # Extract tar.gz backup
    if ! tar -xzf "$backup_file" -C "$parent_dir" 2>/dev/null; then
      print_error "Failed to extract backup: $backup_file"
      log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to extract backup: $backup_file"
      return 1
    fi
  else
    # Copy file backup
    if ! cp "$backup_file" "$original_path" 2>/dev/null; then
      print_error "Failed to copy backup: $backup_file"
      log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to copy backup: $backup_file"
      return 1
    fi
  fi
  
  # Verify restore succeeded
  if ! mc_verify_restore "$original_path" "$backup_type" "$expected_size"; then
    print_error "Restore verification failed: $original_path"
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Restore verification failed: $original_path"
    return 1
  fi
  
  print_success "Restored $original_path"
  log_message "${MC_LOG_LEVEL_SUCCESS:-SUCCESS}" "Restored: $original_path"
  return 0
}

# List available backup sessions
# Arguments: backup_base_dir
# Outputs: list of backup sessions
mc_restore_list_sessions() {
  local backup_base_dir="${1:-$HOME/.mac-cleanup-backups}"
  
  if [[ ! -d "$backup_base_dir" ]]; then
    print_warning "No backup directory found: $backup_base_dir"
    return 1
  fi
  
  local sessions=($(find "$backup_base_dir" -mindepth 1 -maxdepth 1 -type d | sort -r))
  
  if [[ ${#sessions[@]} -eq 0 ]]; then
    print_warning "No backup sessions found."
    return 1
  fi
  
  print_info "Available backup sessions:"
  local index=1
  for session_dir in "${sessions[@]}"; do
    local session_name=$(basename "$session_dir")
    # Parse timestamp from session name (format: YYYY-MM-DD-HH-MM-SS)
    local session_date=$(echo "$session_name" | sed 's/-/ /g' | /usr/bin/awk '{print $1"-"$2"-"$3" "$4":"$5":"$6}' 2>/dev/null || echo "$session_name")
    local session_size=$(calculate_size "$session_dir" 2>/dev/null || echo "")
    print_message "$CYAN" "  $index. $session_date${session_size:+ ($session_size)}"
    index=$((index + 1))
  done
  
  return 0
}

# Get manifest path for a backup session
# Arguments: backup_session_dir
# Outputs: manifest_path (or empty if not found)
mc_restore_get_manifest() {
  local session_dir="$1"
  
  if [[ -z "$session_dir" || ! -d "$session_dir" ]]; then
    echo ""
    return 1
  fi
  
  # Check for new JSON manifest first
  local json_manifest="$session_dir/backup_manifest.json"
  if [[ -f "$json_manifest" ]]; then
    echo "$json_manifest"
    return 0
  fi
  
  # Check for old text manifest
  local text_manifest="$session_dir/backup_manifest.txt"
  if [[ -f "$text_manifest" ]]; then
    echo "$text_manifest"
    return 0
  fi
  
  echo ""
  return 1
}

# Migrate old manifest format and restore
# Arguments: old_manifest_path, backup_dir, session_id
mc_restore_migrate_and_restore() {
  local old_manifest="$1"
  local backup_dir="$2"
  local session_id="$3"
  
  if [[ -z "$old_manifest" || ! -f "$old_manifest" ]]; then
    return 1
  fi
  
  # Create new JSON manifest
  local new_manifest="$backup_dir/backup_manifest.json"
  if ! mc_manifest_migrate_old "$old_manifest" "$new_manifest" "$session_id"; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to migrate old manifest"
    return 1
  fi
  
  # Restore using new manifest
  mc_restore_from_manifest "$new_manifest" "$backup_dir"
}
