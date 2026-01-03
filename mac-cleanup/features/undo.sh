#!/bin/zsh
#
# features/undo.sh - Undo/restore functionality for mac-cleanup
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Undo cleanup - restore from backup
mc_undo_cleanup() {
  print_header "Undo Cleanup"
  
  # Load restore module
  local script_dir=""
  if [[ -n "${MC_SCRIPT_DIR:-}" ]]; then
    # Use MC_SCRIPT_DIR which is set in core.sh
    script_dir="$MC_SCRIPT_DIR/lib"
  elif [[ -n "${SCRIPT_DIR:-}" ]]; then
    # Use SCRIPT_DIR from main script
    script_dir="$SCRIPT_DIR/lib"
  else
    # Fallback: calculate script directory using full path to dirname
    local script_file="${(%):-%x}"
    if [[ -z "$script_file" ]]; then
      script_file="${BASH_SOURCE[0]:-}"
    fi
    if [[ -n "$script_file" ]]; then
      script_dir="$(cd "$(/usr/bin/dirname "$script_file" 2>/dev/null || echo ".")/.." && pwd)/lib"
    else
      # Last resort: assume we're in features/ directory
      script_dir="$(pwd)/lib"
    fi
  fi
  
  source "$script_dir/backup/restore.sh" 2>/dev/null || {
    print_error "Failed to load restore module from $script_dir/backup/restore.sh"
    return 1
  }
  
  # List available backup sessions
  local backup_base="$HOME/.mac-cleanup-backups"
  if ! mc_restore_list_sessions "$backup_base"; then
    return 1
  fi
  
  local backups=($(find "$backup_base" -mindepth 1 -maxdepth 1 -type d | sort -r))
  
  if [[ ${#backups[@]} -eq 0 ]]; then
    return 1
  fi
  
  print_info "Select a backup session to restore:"
  local backup_options=()
  for backup_dir in "${backups[@]}"; do
    local backup_name=$(basename "$backup_dir")
    # Use /usr/bin/awk to ensure it's available
    local backup_date=$(echo "$backup_name" | sed 's/-/ /g' | /usr/bin/awk '{print $1"-"$2"-"$3" "$4":"$5":"$6}' 2>/dev/null || echo "$backup_name")
    backup_options+=("$backup_date")
  done
  
  local selected=$(printf "%s\n" "${backup_options[@]}" | fzf --height=10)
  
  if [[ -z "$selected" ]]; then
    print_warning "No backup selected. Cancelling undo."
    return 1
  fi
  
  # Find the selected backup directory
  local selected_backup=""
  for backup_dir in "${backups[@]}"; do
    local backup_name=$(basename "$backup_dir")
    local backup_date=$(echo "$backup_name" | sed 's/-/ /g' | /usr/bin/awk '{print $1"-"$2"-"$3" "$4":"$5":"$6}' 2>/dev/null || echo "$backup_name")
    if [[ "$backup_date" == "$selected" ]]; then
      selected_backup="$backup_dir"
      break
    fi
  done
  
  if [[ -z "$selected_backup" ]] || [[ ! -d "$selected_backup" ]]; then
    print_error "Selected backup not found."
    return 1
  fi
  
  print_warning "This will restore files from the backup session."
  if ! mc_confirm "Are you sure you want to restore from this backup?"; then
    print_info "Restore cancelled."
    return 1
  fi
  
  # Get manifest path (prefer JSON, fallback to text)
  local manifest_path=$(mc_restore_get_manifest "$selected_backup")
  
  if [[ -n "$manifest_path" ]]; then
    # Check if it's an old text manifest
    if [[ "$manifest_path" == *.txt ]]; then
      # Migrate old manifest and restore
      local session_id=$(basename "$selected_backup")
      if mc_restore_migrate_and_restore "$manifest_path" "$selected_backup" "$session_id"; then
        print_success "Undo operation completed."
        return 0
      else
        print_error "Failed to restore from backup session."
        return 1
      fi
    else
      # Use new JSON manifest
      if mc_restore_from_manifest "$manifest_path" "$selected_backup"; then
        print_success "Undo operation completed."
        return 0
      else
        print_error "Failed to restore from backup session."
        return 1
      fi
    fi
  else
    # No manifest found - try to restore manually
    print_warning "Backup manifest not found. Cannot restore automatically."
    print_info "The backup directory contains:"
    
    local backup_files_found=0
    setopt local_options nullglob
    
    # List .tar.gz files
    for backup_file in "$selected_backup"/*.tar.gz; do
      if [[ -f "$backup_file" ]]; then
        local backup_name=$(basename "$backup_file" .tar.gz)
        if [[ "$backup_name" != cleanup.log* && "$backup_name" != *.log ]]; then
          print_info "  - $backup_name.tar.gz"
          backup_files_found=$((backup_files_found + 1))
        fi
      fi
    done
    
    # List other backup files
    for backup_file in "$selected_backup"/*(N); do
      if [[ -f "$backup_file" ]]; then
        local backup_name=$(basename "$backup_file")
        if [[ "$backup_file" != *.tar.gz ]] && \
           [[ "$backup_file" != */backup_manifest.* ]] && \
           [[ "$backup_name" != *.log ]] && \
           [[ "$backup_name" != *.log.gz ]]; then
          print_info "  - $backup_name"
          backup_files_found=$((backup_files_found + 1))
        fi
      fi
    done
    
    unsetopt local_options nullglob
    
    if [[ $backup_files_found -eq 0 ]]; then
      print_warning "No backup files found in this backup session."
    else
      print_info "Found $backup_files_found backup file(s), but cannot restore automatically without manifest."
      print_info "To restore manually:"
      print_info "  - For directories: tar -xzf \"$selected_backup/backup_name.tar.gz\" -C /destination/path/"
      print_info "  - For files: cp \"$selected_backup/backup_name\" /destination/path/"
    fi
    
    print_success "Undo operation completed (no automatic restore possible)."
    return 0
  fi
}
