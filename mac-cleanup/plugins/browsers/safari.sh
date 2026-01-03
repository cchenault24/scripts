#!/bin/zsh
#
# plugins/browsers/safari.sh - Safari cache cleanup plugin
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# This file is sourced by the main script which provides:
# - All lib functions (print_*, log_message, calculate_size, etc.)
# - Plugin registration functions from plugins/base.sh

clean_safari_cache() {
  if ! command -v safaridriver &> /dev/null && [[ ! -d "$HOME/Library/Safari" ]]; then
    print_warning "Safari does not appear to be installed or has never been run."
    track_space_saved "Safari Cache" 0
    return 0
  fi
  
  local safari_cache_dirs=(
    "$HOME/Library/Caches/com.apple.Safari"
    "$HOME/Library/Safari/LocalStorage"
    "$HOME/Library/Safari/Databases"
    "$HOME/Library/Safari/ServiceWorkers"
  )
  
  local total_space_freed=0
  local total_items=${#safari_cache_dirs[@]}
  local current_item=0
  
  for dir in "${safari_cache_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      current_item=$((current_item + 1))
      local dir_name=$(basename "$dir")
      update_operation_progress $current_item $total_items "$dir_name"
      
      local space_before=$(calculate_size_bytes "$dir")
      # Load constants if not already loaded
      if [[ -z "${MC_MIN_DIR_SIZE:-}" ]]; then
        local MC_MIN_DIR_SIZE=4096  # Fallback if constants not loaded
      fi
      # Check if directory has meaningful content (more than just directory overhead ~4KB)
      if [[ $space_before -gt $MC_MIN_DIR_SIZE ]]; then
        if ! backup "$dir" "safari_$dir_name"; then
          print_error "Backup failed for Safari $dir_name. Aborting cleanup to prevent data loss."
          log_message "ERROR" "Backup failed for Safari $dir_name, aborting"
          return 1
        fi
        
        safe_clean_dir "$dir" "Safari $dir_name" || {
          print_error "Failed to clean Safari $dir_name"
          return 1
        }
        
        local space_after=$(calculate_size_bytes "$dir")
        local space_freed=$((space_before - space_after))
        # Validate space_freed is not negative (directory may have grown during cleanup)
        if [[ $space_freed -lt 0 ]]; then
          space_freed=0
          log_message "WARNING" "Directory size increased during cleanup: $dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
        fi
        total_space_freed=$((total_space_freed + space_freed))
      fi
    fi
  done
  
  # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we only track per-operation
  track_space_saved "Safari Cache" $total_space_freed "true"
  return 0
}

# Size calculation function for sweep
_calculate_safari_cache_size_bytes() {
  local size_bytes=0
  local safari_dirs=(
    "$HOME/Library/Caches/com.apple.Safari"
    "$HOME/Library/Safari/LocalStorage"
    "$HOME/Library/Safari/Databases"
    "$HOME/Library/Safari/ServiceWorkers"
  )
  for dir in "${safari_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      local dir_size=$(calculate_size_bytes "$dir" 2>/dev/null || echo "0")
      [[ "$dir_size" =~ ^[0-9]+$ ]] && size_bytes=$((size_bytes + dir_size))
    fi
  done
  echo "$size_bytes"
}

# Register plugin with size function
register_plugin "Safari Cache" "browsers" "clean_safari_cache" "false" "_calculate_safari_cache_size_bytes"
