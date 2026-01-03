#!/bin/zsh
#
# lib/utils.sh - Utility functions for mac-cleanup
#

# Log message to file if logging is enabled
log_message() {
  local level="$1"
  local message="$2"
  if [[ -n "$MC_LOG_FILE" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$MC_LOG_FILE"
  fi
}

# Calculate size of a directory or file
calculate_size() {
  local path="$1"
  if [[ -e "$path" ]]; then
    # Use du to get size in human-readable format
    du -sh "$path" 2>/dev/null | awk '{print $1}'
  else
    echo "0B"
  fi
}

# Calculate size in bytes for accurate tracking
calculate_size_bytes() {
  local path="$1"
  
  if [[ -e "$path" ]]; then
    # Use /usr/bin/du explicitly and capture output more reliably
    local du_output=""
    du_output=$(/usr/bin/du -sk "$path" 2>/dev/null) || du_output=""
    
    if [[ -n "$du_output" ]]; then
      local kb=$(echo "$du_output" | /usr/bin/awk '{print $1}')
      
      if [[ -n "$kb" && "$kb" =~ ^[0-9]+$ ]]; then
        local result=$((kb * 1024))
        echo "$result"
      else
        echo "0"
      fi
    else
      echo "0"
    fi
  else
    echo "0"
  fi
}

# Format bytes to human-readable format
format_bytes() {
  local bytes=$1
  if [[ $bytes -ge 1073741824 ]]; then
    local gb=$((bytes / 1073741824))
    local mb=$(((bytes % 1073741824) / 1048576))
    if [[ $mb -gt 0 ]]; then
      printf "%d.%02d GB" $gb $((mb * 100 / 1024))
    else
      printf "%d GB" $gb
    fi
  elif [[ $bytes -ge 1048576 ]]; then
    local mb=$((bytes / 1048576))
    local kb=$(((bytes % 1048576) / 1024))
    if [[ $kb -gt 0 ]]; then
      printf "%d.%02d MB" $mb $((kb * 100 / 1024))
    else
      printf "%d MB" $mb
    fi
  elif [[ $bytes -ge 1024 ]]; then
    local kb=$((bytes / 1024))
    local b=$((bytes % 1024))
    if [[ $b -gt 0 ]]; then
      printf "%d.%02d KB" $kb $((b * 100 / 1024))
    else
      printf "%d KB" $kb
    fi
  else
    printf "%d B" $bytes
  fi
}

# Safely remove a directory or file
safe_remove() {
  local path="$1"
  local description="$2"
  
  if [[ "$MC_DRY_RUN" == "true" ]]; then
    local size=$(calculate_size "$path")
    print_info "[DRY RUN] Would remove $description ($size)"
    log_message "DRY_RUN" "Would remove: $path"
    return 0
  fi
  
  if [[ -e "$path" ]]; then
    local size_before=$(calculate_size_bytes "$path")
    print_info "Cleaning $description..."
    log_message "INFO" "Removing: $path"
    
    if [[ -d "$path" ]]; then
      rm -rf "$path" 2>/dev/null || true
    else
      rm -f "$path" 2>/dev/null || true
    fi
    
    if [[ ! -e "$path" ]]; then
      print_success "Cleaned $description"
      log_message "SUCCESS" "Removed: $path (freed $(format_bytes $size_before))"
      MC_TOTAL_SPACE_SAVED=$((MC_TOTAL_SPACE_SAVED + size_before))
    else
      print_warning "Failed to completely remove $description"
      log_message "WARNING" "Failed to remove: $path"
    fi
  fi
}

# Safely clean a directory (remove contents but keep the directory)
safe_clean_dir() {
  local path="$1"
  local description="$2"
  
  if [[ "$MC_DRY_RUN" == "true" ]]; then
    if [[ -d "$path" ]]; then
      local size=$(calculate_size "$path")
      print_info "[DRY RUN] Would clean $description ($size)"
      log_message "DRY_RUN" "Would clean directory: $path"
    fi
    return 0
  fi
  
  if [[ -d "$path" ]]; then
    local size_before=$(calculate_size_bytes "$path")
    print_info "Cleaning $description..."
    log_message "INFO" "Cleaning directory: $path"
    
    # Remove all contents including hidden files
    find "$path" -mindepth 1 -delete 2>/dev/null || {
      rm -rf "${path:?}"/* "${path:?}"/.[!.]* 2>/dev/null || true
    }
    
    print_success "Cleaned $description"
    local size_after=$(calculate_size_bytes "$path")
    local space_freed=$((size_before - size_after))
    log_message "SUCCESS" "Cleaned: $path (freed $(format_bytes $space_freed))"
    MC_TOTAL_SPACE_SAVED=$((MC_TOTAL_SPACE_SAVED + space_freed))
  fi
}
