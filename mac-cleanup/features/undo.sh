#!/bin/zsh
#
# features/undo.sh - Undo/restore functionality for mac-cleanup
#

# Undo cleanup - restore from backup
undo_cleanup() {
  print_header "Undo Cleanup"
  
  mc_list_backups || return 1
  
  local backup_base="$HOME/.mac-cleanup-backups"
  local backups=($(find "$backup_base" -mindepth 1 -maxdepth 1 -type d | sort -r))
  
  if [[ ${#backups[@]} -eq 0 ]]; then
    return 1
  fi
  
  print_info "Select a backup session to restore:"
  local backup_options=()
  for backup_dir in "${backups[@]}"; do
    local backup_name=$(basename "$backup_dir")
    local backup_date=$(echo "$backup_name" | sed 's/-/ /g' | awk '{print $1"-"$2"-"$3" "$4":"$5":"$6}')
    backup_options+=("$backup_date")
  done
  
  local selected=$(printf "%s\n" "${backup_options[@]}" | fzf --height=10)
  
  if [[ -z "$selected" ]]; then
    print_warning "No backup selected. Cancelling undo."
    return 1
  fi
  
  # Find the selected backup directory
  local selected_backup=""
  local index=1
  for backup_dir in "${backups[@]}"; do
    local backup_name=$(basename "$backup_dir")
    local backup_date=$(echo "$backup_name" | sed 's/-/ /g' | awk '{print $1"-"$2"-"$3" "$4":"$5":"$6}')
    if [[ "$backup_date" == "$selected" ]]; then
      selected_backup="$backup_dir"
      break
    fi
    index=$((index + 1))
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
  
  # Check for backup manifest
  local manifest_file="$selected_backup/backup_manifest.txt"
  if [[ -f "$manifest_file" ]]; then
    print_info "Found backup manifest. Restoring files..."
    local restored=0
    local failed=0
    
    while IFS='|' read -r original_path backup_name backup_date; do
      if [[ -z "$original_path" ]] || [[ -z "$backup_name" ]]; then
        continue
      fi
      
      local backup_file="$selected_backup/${backup_name}.tar.gz"
      if [[ ! -f "$backup_file" ]]; then
        backup_file="$selected_backup/${backup_name}"
      fi
      
      if [[ -f "$backup_file" ]]; then
        print_info "Restoring $original_path..."
        
        if [[ "$backup_file" == *.tar.gz ]]; then
          # Extract tar.gz backup
          local parent_dir=$(dirname "$original_path")
          mkdir -p "$parent_dir" 2>/dev/null
          tar -xzf "$backup_file" -C "$parent_dir" 2>/dev/null && {
            print_success "Restored $original_path"
            restored=$((restored + 1))
            log_message "SUCCESS" "Restored: $original_path"
          } || {
            print_error "Failed to restore $original_path"
            failed=$((failed + 1))
            log_message "ERROR" "Failed to restore: $original_path"
          }
        else
          # Copy file backup
          mkdir -p "$(dirname "$original_path")" 2>/dev/null
          cp "$backup_file" "$original_path" 2>/dev/null && {
            print_success "Restored $original_path"
            restored=$((restored + 1))
            log_message "SUCCESS" "Restored: $original_path"
          } || {
            print_error "Failed to restore $original_path"
            failed=$((failed + 1))
            log_message "ERROR" "Failed to restore: $original_path"
          }
        fi
      else
        print_warning "Backup file not found: $backup_name"
        failed=$((failed + 1))
      fi
    done < "$manifest_file"
    
    print_header "Restore Summary"
    print_success "Restored $restored file(s)"
    if [[ $failed -gt 0 ]]; then
      print_warning "Failed to restore $failed file(s)"
    fi
  else
    print_warning "Backup manifest not found. Attempting to restore all backups..."
    print_info "Restoring all files from backup directory..."
    
    # Use nullglob to handle case where no .tar.gz files exist
    setopt local_options nullglob
    local backup_files_found=0
    
    # Check for .tar.gz backup files
    for backup_file in "$selected_backup"/*.tar.gz; do
      if [[ -f "$backup_file" ]]; then
        local backup_name=$(basename "$backup_file" .tar.gz)
        # Skip log files
        if [[ "$backup_name" == cleanup.log* ]] || [[ "$backup_name" == *.log ]]; then
          continue
        fi
        print_info "Found backup: $backup_name"
        # Note: Without manifest, we can't determine original path, so this is limited
        print_warning "Cannot determine original path without manifest. Manual restoration may be needed."
        print_info "To restore manually, extract with: tar -xzf \"$backup_file\" -C /destination/path/"
        backup_files_found=$((backup_files_found + 1))
      fi
    done
    
    # Also check for non-tar.gz backup files (excluding log files)
    for backup_file in "$selected_backup"/*(N); do
      if [[ -f "$backup_file" ]]; then
        local backup_name=$(basename "$backup_file")
        # Skip tar.gz files (already processed), manifest, and any log files
        if [[ "$backup_file" == *.tar.gz ]] || \
           [[ "$backup_file" == */backup_manifest.txt ]] || \
           [[ "$backup_file" == */cleanup.log* ]] || \
           [[ "$backup_name" == *.log ]] || \
           [[ "$backup_name" == *.log.gz ]]; then
          continue
        fi
        print_info "Found backup file: $backup_name"
        print_warning "Cannot determine original path without manifest. Manual restoration may be needed."
        print_info "To restore manually, copy with: cp \"$backup_file\" /destination/path/"
        backup_files_found=$((backup_files_found + 1))
      fi
    done
    
    unsetopt local_options nullglob
    
    if [[ $backup_files_found -eq 0 ]]; then
      print_warning "No backup files found in this backup session."
      print_info "The backup directory may be empty or contain only log files."
    else
      print_info "Found $backup_files_found backup file(s), but cannot restore automatically without manifest."
    fi
  fi
  
  print_success "Undo operation completed."
}
