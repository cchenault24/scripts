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
  local index=1
  for backup_dir in "${backups[@]}"; do
    local backup_name=$(basename "$backup_dir")
    # Use /usr/bin/awk to ensure it's available
    local backup_date=$(echo "$backup_name" | sed 's/-/ /g' | /usr/bin/awk '{print $1"-"$2"-"$3" "$4":"$5":"$6}' 2>/dev/null || echo "$backup_name")
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
    # Check if manifest is empty (no backups were made in this session)
    if [[ ! -s "$manifest_file" ]]; then
      print_warning "Backup manifest exists but is empty."
      print_info "No backups were created in this session (all items may have been skipped as empty or too small)."
      print_success "Undo operation completed (nothing to restore)."
      return 0
    fi
    
    print_info "Found backup manifest. Restoring files..."
    local restored=0
    local failed=0
    local failed_paths=()
    local skipped_paths=()
    
    while IFS='|' read -r original_path backup_name backup_date; do
      # Skip empty lines and malformed entries
      if [[ -z "$original_path" ]] || [[ -z "$backup_name" ]]; then
        # Log skipped entries for debugging
        if [[ -n "$original_path" || -n "$backup_name" ]]; then
          log_message "WARNING" "Skipping malformed manifest entry: original_path='$original_path', backup_name='$backup_name'"
          skipped_paths+=("$original_path")
        fi
        continue
      fi
      
      # Trim whitespace from fields
      original_path=$(echo "$original_path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      backup_name=$(echo "$backup_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      
      local backup_file="$selected_backup/${backup_name}.tar.gz"
      if [[ ! -f "$backup_file" ]]; then
        backup_file="$selected_backup/${backup_name}"
      fi
      
      # Check backup file integrity before restore
      if [[ ! -f "$backup_file" ]]; then
        print_warning "Backup file not found: $backup_name (path: $original_path)"
        log_message "ERROR" "Backup file not found: $backup_name (original path: $original_path)"
        failed=$((failed + 1))
        failed_paths+=("$original_path (backup file missing: $backup_name)")
        continue
      fi
      
      # Verify backup file is readable and not empty
      if [[ ! -r "$backup_file" ]]; then
        print_error "Backup file is not readable: $backup_name"
        log_message "ERROR" "Backup file not readable: $backup_name (original path: $original_path)"
        failed=$((failed + 1))
        failed_paths+=("$original_path (backup file not readable: $backup_name)")
        continue
      fi
      
      if [[ ! -s "$backup_file" ]]; then
        print_error "Backup file is empty: $backup_name"
        log_message "ERROR" "Backup file is empty: $backup_name (original path: $original_path)"
        failed=$((failed + 1))
        failed_paths+=("$original_path (backup file empty: $backup_name)")
        continue
      fi
      
      # For tar.gz files, verify integrity before restore
      if [[ "$backup_file" == *.tar.gz ]]; then
        if ! tar -tzf "$backup_file" &>/dev/null; then
          print_error "Backup file integrity check failed (corrupted): $backup_name"
          log_message "ERROR" "Backup file integrity check failed: $backup_name (original path: $original_path)"
          failed=$((failed + 1))
          failed_paths+=("$original_path (backup file corrupted: $backup_name)")
          continue
        fi
      fi
      
      print_info "Restoring $original_path..."
      
      if [[ "$backup_file" == *.tar.gz ]]; then
        # Extract tar.gz backup
        local parent_dir=$(dirname "$original_path")
        local basename_path=$(basename "$original_path")
        
        # Create parent directory if it doesn't exist
        if ! mkdir -p "$parent_dir" 2>/dev/null; then
          print_error "Failed to create parent directory: $parent_dir"
          log_message "ERROR" "Failed to create parent directory: $parent_dir (for: $original_path)")
          failed=$((failed + 1))
          failed_paths+=("$original_path (cannot create parent directory)")
          continue
        fi
        
        # Extract the backup
        if tar -xzf "$backup_file" -C "$parent_dir" 2>/dev/null; then
          # Verify restore succeeded - check if file/directory exists
          if [[ -e "$original_path" ]]; then
            # For directories, verify they have content
            if [[ -d "$original_path" ]]; then
              if [[ -z "$(ls -A "$original_path" 2>/dev/null)" ]]; then
                print_warning "Restored directory is empty: $original_path (may be expected)"
                log_message "WARNING" "Restored directory is empty: $original_path"
              fi
            fi
            print_success "Restored $original_path"
            restored=$((restored + 1))
            log_message "SUCCESS" "Restored: $original_path"
          else
            print_error "Restore verification failed: $original_path does not exist after restore"
            log_message "ERROR" "Restore verification failed: $original_path (backup: $backup_name)")
            failed=$((failed + 1))
            failed_paths+=("$original_path (verification failed)")
          fi
        else
          print_error "Failed to extract backup: $backup_name"
          log_message "ERROR" "Failed to extract backup: $backup_name (original path: $original_path)")
          failed=$((failed + 1))
          failed_paths+=("$original_path (extraction failed)")
        fi
      else
        # Copy file backup
        local parent_dir=$(dirname "$original_path")
        
        # Create parent directory if it doesn't exist
        if ! mkdir -p "$parent_dir" 2>/dev/null; then
          print_error "Failed to create parent directory: $parent_dir"
          log_message "ERROR" "Failed to create parent directory: $parent_dir (for: $original_path)")
          failed=$((failed + 1))
          failed_paths+=("$original_path (cannot create parent directory)")
          continue
        fi
        
        # Get backup file size for verification
        local backup_size=$(stat -f%z "$backup_file" 2>/dev/null || echo "0")
        
        # Copy the backup file
        if cp "$backup_file" "$original_path" 2>/dev/null; then
          # Verify restore succeeded - check if file exists and size matches
          if [[ -f "$original_path" ]]; then
            local restored_size=$(stat -f%z "$original_path" 2>/dev/null || echo "0")
            if [[ "$restored_size" == "$backup_size" && "$restored_size" != "0" ]]; then
              print_success "Restored $original_path"
              restored=$((restored + 1))
              log_message "SUCCESS" "Restored: $original_path (size verified: $(format_bytes $restored_size))"
            else
              print_error "Restore verification failed: size mismatch for $original_path (expected: $(format_bytes $backup_size), got: $(format_bytes $restored_size))"
              log_message "ERROR" "Restore verification failed: $original_path (size mismatch: expected $backup_size, got $restored_size)")
              failed=$((failed + 1))
              failed_paths+=("$original_path (size mismatch)")
            fi
          else
            print_error "Restore verification failed: $original_path does not exist after restore"
            log_message "ERROR" "Restore verification failed: $original_path (backup: $backup_name)")
            failed=$((failed + 1))
            failed_paths+=("$original_path (verification failed)")
          fi
        else
          print_error "Failed to copy backup: $backup_name"
          log_message "ERROR" "Failed to copy backup: $backup_name (original path: $original_path)")
          failed=$((failed + 1))
          failed_paths+=("$original_path (copy failed)")
        fi
      fi
    done < "$manifest_file"
    
    print_header "Restore Summary"
    if [[ $restored -gt 0 ]]; then
      print_success "Successfully restored $restored file(s)"
    fi
    if [[ ${#skipped_paths[@]} -gt 0 ]]; then
      print_warning "Skipped ${#skipped_paths[@]} malformed manifest entry/entries"
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
      print_info "No files were restored (manifest may be empty or all entries were skipped)"
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
