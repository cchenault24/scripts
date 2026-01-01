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
  
  local selected=$(printf "%s\n" "${backup_options[@]}" | gum choose --height=10)
  
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
  if ! gum confirm "Are you sure you want to restore from this backup?"; then
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
    
    for backup_file in "$selected_backup"/*.tar.gz; do
      if [[ -f "$backup_file" ]]; then
        local backup_name=$(basename "$backup_file" .tar.gz)
        print_info "Restoring $backup_name..."
        # Note: Without manifest, we can't determine original path, so this is limited
        print_warning "Cannot determine original path without manifest. Manual restoration may be needed."
      fi
    done
  fi
  
  print_success "Undo operation completed."
}
