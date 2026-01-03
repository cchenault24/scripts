#!/bin/zsh
#
# lib/utils.sh - Utility functions for mac-cleanup
#

# Size calculation cache (associative array)
typeset -A MC_SIZE_CACHE

# Progress reporting function for plugins
# Usage: update_operation_progress current_item total_items "item_name"
# This allows plugins to report progress as they process multiple items
update_operation_progress() {
  local current_item=$1
  local total_items=$2
  local item_name="${3:-}"
  
  # Only update if progress file is set (we're in a cleanup operation)
  if [[ -n "${MC_PROGRESS_FILE:-}" && -f "$MC_PROGRESS_FILE" ]]; then
    # Read current operation info from progress file
    local progress_line=$(cat "$MC_PROGRESS_FILE" 2>/dev/null || echo "")
    if [[ -n "$progress_line" ]]; then
      local op_index=$(echo "$progress_line" | cut -d'|' -f1)
      local total_ops=$(echo "$progress_line" | cut -d'|' -f2)
      local op_name=$(echo "$progress_line" | cut -d'|' -f3- | cut -d'|' -f1)
      
      # Update progress file with item-level progress
      # Format: operation_index|total_operations|operation_name|current_item|total_items|item_name
      echo "$op_index|$total_ops|$op_name|$current_item|$total_items|$item_name" > "$MC_PROGRESS_FILE"
    fi
  fi
}

# Log message to file if logging is enabled
log_message() {
  local level="$1"
  local message="$2"
  if [[ -n "$MC_LOG_FILE" ]]; then
    # Use full path to date to ensure it's available in subshells
    echo "[$(/bin/date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$MC_LOG_FILE"
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

# Calculate size in bytes for accurate tracking (with caching)
calculate_size_bytes() {
  local path="$1"
  
  # Early exit for non-existent paths
  if [[ ! -e "$path" ]]; then
    echo "0"
    return
  fi
  
  # Check cache first
  local cache_key="$path"
  if [[ -n "${MC_SIZE_CACHE[$cache_key]:-}" ]]; then
    echo "${MC_SIZE_CACHE[$cache_key]}"
    return
  fi
  
  # Use /usr/bin/du explicitly and capture output more reliably
  local du_output=""
  du_output=$(/usr/bin/du -sk "$path" 2>/dev/null) || du_output=""
  
  local result=0
  if [[ -n "$du_output" ]]; then
    local kb=$(echo "$du_output" | /usr/bin/awk '{print $1}')
    
    if [[ -n "$kb" && "$kb" =~ ^[0-9]+$ ]]; then
      # Use awk for large number arithmetic to prevent overflow
      # On 32-bit systems, shell arithmetic can overflow at 2GB (2,097,152 KB)
      result=$(echo "$kb * 1024" | /usr/bin/awk '{printf "%.0f", $1 * $2}')
      # Ensure result is numeric (awk might return scientific notation for very large numbers)
      if [[ ! "$result" =~ ^[0-9]+$ ]]; then
        # Fallback: if awk fails, try bc if available, otherwise use shell arithmetic with overflow check
        if command -v bc &>/dev/null; then
          result=$(echo "$kb * 1024" | bc 2>/dev/null | awk '{printf "%.0f", $1}')
        else
          # Shell arithmetic with overflow protection (max 2^31-1 bytes = 2GB)
          local max_kb=2097152
          if [[ $kb -gt $max_kb ]]; then
            result=2147483647  # Max 32-bit signed integer
            log_message "WARNING" "Size calculation overflow protection: $path (KB: $kb)"
          else
            result=$((kb * 1024))
          fi
        fi
      fi
    fi
  fi
  
  # Cache the result
  MC_SIZE_CACHE[$cache_key]=$result
  echo "$result"
}

# Clear size calculation cache (useful after cleanup operations)
clear_size_cache() {
  MC_SIZE_CACHE=()
}

# Invalidate cache entry for a specific path
invalidate_size_cache() {
  local path="$1"
  unset "MC_SIZE_CACHE[$path]"
}

# Format bytes to human-readable format
# Uses floating point arithmetic for accurate rounding
format_bytes() {
  local bytes=$1
  
  # Use awk for floating point calculations to avoid rounding errors
  if command -v awk &>/dev/null; then
    if [[ $bytes -ge 1073741824 ]]; then
      # GB with 2 decimal places
      awk -v b=$bytes 'BEGIN {
        gb = b / 1073741824
        printf "%.2f GB", gb
      }'
    elif [[ $bytes -ge 1048576 ]]; then
      # MB with 2 decimal places
      awk -v b=$bytes 'BEGIN {
        mb = b / 1048576
        printf "%.2f MB", mb
      }'
    elif [[ $bytes -ge 1024 ]]; then
      # KB with 2 decimal places
      awk -v b=$bytes 'BEGIN {
        kb = b / 1024
        printf "%.2f KB", kb
      }'
    else
      printf "%d B" $bytes
    fi
  else
    # Fallback to integer arithmetic if awk not available
    if [[ $bytes -ge 1073741824 ]]; then
      local gb=$((bytes / 1073741824))
      local remainder=$((bytes % 1073741824))
      local mb=$((remainder / 1048576))
      # Calculate decimal part more accurately
      local decimal=$((remainder * 100 / 1048576))
      if [[ $decimal -gt 0 ]]; then
        printf "%d.%02d GB" $gb $decimal
      else
        printf "%d GB" $gb
      fi
    elif [[ $bytes -ge 1048576 ]]; then
      local mb=$((bytes / 1048576))
      local remainder=$((bytes % 1048576))
      local kb=$((remainder / 1024))
      local decimal=$((remainder * 100 / 1024))
      if [[ $decimal -gt 0 ]]; then
        printf "%d.%02d MB" $mb $decimal
      else
        printf "%d MB" $mb
      fi
    elif [[ $bytes -ge 1024 ]]; then
      local kb=$((bytes / 1024))
      local b=$((bytes % 1024))
      local decimal=$((b * 100 / 1024))
      if [[ $decimal -gt 0 ]]; then
        printf "%d.%02d KB" $kb $decimal
      else
        printf "%d KB" $kb
      fi
    else
      printf "%d B" $bytes
    fi
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
    
    # Invalidate cache for this path since it was removed
    invalidate_size_cache "$path"
    
    if [[ ! -e "$path" ]]; then
      print_success "Cleaned $description"
      log_message "SUCCESS" "Removed: $path (freed $(format_bytes $size_before))"
      MC_TOTAL_SPACE_SAVED=$((MC_TOTAL_SPACE_SAVED + size_before))
      # Write to space tracking file if in background process (with locking)
      # safe_remove is typically used standalone, so we write to the file
      if [[ -n "${MC_SPACE_TRACKING_FILE:-}" && -f "$MC_SPACE_TRACKING_FILE" ]]; then
        # Use helper function from base.sh if available, otherwise use simple write
        if type _write_space_tracking_file &>/dev/null; then
          _write_space_tracking_file "$description" "$size_before"
        else
          echo "$description|$size_before" >> "$MC_SPACE_TRACKING_FILE" 2>/dev/null || true
        fi
      fi
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
    
    # Optimized batch deletion: use find with -delete for better performance
    # Important: Use -not -type l to avoid following symbolic links (prevents deleting files outside target)
    # Try find -delete first (fastest), fallback to rm -rf
    find "$path" -mindepth 1 -not -type l -delete 2>/dev/null || {
      # Also delete symbolic links themselves (but don't follow them)
      find "$path" -mindepth 1 -type l -delete 2>/dev/null || true
      # Fallback: batch delete visible and hidden files separately
      find "$path" -mindepth 1 -maxdepth 1 ! -name ".*" -not -type l -delete 2>/dev/null || true
      find "$path" -mindepth 1 -maxdepth 1 -name ".*" -not -type l -delete 2>/dev/null || true
      find "$path" -mindepth 1 -maxdepth 1 -type l -delete 2>/dev/null || true
      # Final fallback for stubborn files - use (N) qualifier to handle empty globs in zsh
      # In zsh, we need to handle globs that might not match
      # Note: rm -rf will follow symlinks, so we try to remove symlinks first
      if [[ -n "${ZSH_VERSION:-}" ]]; then
        # Zsh: use (N) qualifier to return empty if no matches
        # Remove symlinks first (don't follow), then regular files
        find "$path" -mindepth 1 -maxdepth 1 -type l -delete 2>/dev/null || true
        rm -rf "${path:?}"/*(N) "${path:?}"/.[!.]*(N) 2>/dev/null || true
      else
        # Bash: use nullglob or just try and ignore errors
        # Remove symlinks first (don't follow), then regular files
        find "$path" -mindepth 1 -maxdepth 1 -type l -delete 2>/dev/null || true
        rm -rf "${path:?}"/* "${path:?}"/.[!.]* 2>/dev/null || true
      fi
    }
    
    # Invalidate cache for this path since it changed
    invalidate_size_cache "$path"
    
    print_success "Cleaned $description"
    local size_after=$(calculate_size_bytes "$path")
    local space_freed=$((size_before - size_after))
    
    # Validate space_freed is not negative (directory may have grown during cleanup)
    if [[ $space_freed -lt 0 ]]; then
      space_freed=0
      log_message "WARNING" "Directory size increased during cleanup: $path (before: $(format_bytes $size_before), after: $(format_bytes $size_after))"
    fi
    
    log_message "SUCCESS" "Cleaned: $path (freed $(format_bytes $space_freed))"
    MC_TOTAL_SPACE_SAVED=$((MC_TOTAL_SPACE_SAVED + space_freed))
    # Note: We don't write individual safe_clean_dir entries to space tracking file
    # because plugins that use safe_clean_dir typically call track_space_saved() 
    # with the total, which will write to the file. Writing both would cause double-counting.
  fi
}
