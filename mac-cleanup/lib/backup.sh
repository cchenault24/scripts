#!/bin/zsh
#
# lib/backup.sh - Backup and restore functionality for mac-cleanup
#

# Backup a directory or file before cleaning
backup() {
  local path="$1"
  local backup_name="$2"
  
  if [[ "$MC_DRY_RUN" == "true" ]]; then
    local size=$(calculate_size "$path")
    print_info "[DRY RUN] Would backup $path ($size) to $backup_name"
    log_message "DRY_RUN" "Would backup: $path -> $backup_name"
    return 0
  fi
  
  if [[ -e "$path" ]]; then
    # Check if directory is empty before backing up
    if [[ -d "$path" ]]; then
      # Use full paths to ensure commands are found
      local wc_cmd="wc"
      local tr_cmd="tr"
      if [[ -x "/usr/bin/wc" ]]; then
        wc_cmd="/usr/bin/wc"
      fi
      if [[ -x "/usr/bin/tr" ]]; then
        tr_cmd="/usr/bin/tr"
      fi
      local item_count=$(find "$path" -mindepth 1 -maxdepth 1 2>/dev/null | $wc_cmd -l 2>/dev/null | $tr_cmd -d ' ' 2>/dev/null || echo "0")
      if [[ $item_count -eq 0 ]]; then
        print_info "Skipping backup of empty directory: $path"
        log_message "INFO" "Skipped backup of empty directory: $path"
        return 0
      fi
    fi
    
    print_info "Backing up $path..."
    log_message "INFO" "Creating backup: $path -> $backup_name"
    
    # Save backup metadata for undo functionality
    # Use /usr/bin/date to ensure it's found even if PATH is not set correctly
    local timestamp=""
    if [[ -x "/usr/bin/date" ]]; then
      timestamp=$(/usr/bin/date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    else
      timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "NO-TIME")
    fi
    echo "$path|$backup_name|$timestamp" >> "$MC_BACKUP_DIR/backup_manifest.txt" 2>/dev/null
    
    if [[ -d "$path" ]]; then
      # Use a background process for large directories
      tar -czf "$MC_BACKUP_DIR/${backup_name}.tar.gz" -C "$(dirname "$path")" "$(basename "$path")" 2>/dev/null &
      local pid=$!
      show_spinner "Creating backup of $(basename "$path")" $pid
      
      # Verify backup was created successfully
      if [[ -f "$MC_BACKUP_DIR/${backup_name}.tar.gz" ]]; then
        print_success "Backup complete: $backup_name"
        log_message "SUCCESS" "Backup created: $backup_name.tar.gz"
        return 0
      else
        print_warning "Backup verification failed, but continuing with cleanup..."
        log_message "WARNING" "Backup verification failed for: $backup_name"
        return 1
      fi
    else
      if cp "$path" "$MC_BACKUP_DIR/${backup_name}" 2>/dev/null; then
        print_success "Backup complete: $backup_name"
        log_message "SUCCESS" "Backup created: $backup_name"
        return 0
      else
        print_warning "Backup failed, but continuing with cleanup..."
        log_message "WARNING" "Backup failed for: $backup_name"
        return 1
      fi
    fi
  fi
  
  return 0
}

# List available backup sessions
mc_list_backups() {
  local backup_base="$HOME/.mac-cleanup-backups"
  
  if [[ ! -d "$backup_base" ]]; then
    print_warning "No backup directory found."
    return 1
  fi
  
  local backups=($(find "$backup_base" -mindepth 1 -maxdepth 1 -type d | sort -r))
  
  if [[ ${#backups[@]} -eq 0 ]]; then
    print_warning "No backup sessions found."
    return 1
  fi
  
  print_info "Available backup sessions:"
  local index=1
  for backup_dir in "${backups[@]}"; do
    local backup_name=$(basename "$backup_dir")
    # Use awk with fallback to full path
    local awk_cmd="awk"
    if ! command -v awk &> /dev/null; then
      awk_cmd="/usr/bin/awk"
    fi
    local backup_date=$(echo "$backup_name" | sed 's/-/ /g' | $awk_cmd '{print $1"-"$2"-"$3" "$4":"$5":"$6}')
    local backup_size=$(calculate_size "$backup_dir")
    print_message "$CYAN" "  $index. $backup_date ($backup_size)"
    index=$((index + 1))
  done
  
  return 0
}

# Export for backward compatibility
list_backups() {
  mc_list_backups
}
