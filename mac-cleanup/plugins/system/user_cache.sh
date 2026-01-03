#!/bin/zsh
#
# plugins/system/user_cache.sh - User cache cleanup plugin
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

clean_user_cache() {
  local cache_dir="$HOME/Library/Caches"
  
  # Early exit for non-existent or empty directories (PERF-6)
  if [[ ! -d "$cache_dir" ]] || [[ -z "$(ls -A "$cache_dir" 2>/dev/null)" ]]; then
    track_space_saved "User Cache" 0
    return 0
  fi
  
  # Calculate size once before cleanup (PERF-1: avoid redundant calculations)
  local space_before=$(calculate_size_bytes "$cache_dir")
  
  if ! backup "$cache_dir" "user_caches"; then
    print_error "Backup failed for user cache. Aborting cleanup to prevent data loss."
    log_message "ERROR" "Backup failed, aborting user cache cleanup"
    return 1
  fi
  
  # Collect all cache directories first
  local cache_dirs=()
  while IFS= read -r dir; do
    [[ -n "$dir" && -d "$dir" ]] && cache_dirs+=("$dir")
  done < <(find "$cache_dir" -maxdepth 1 -type d ! -path "$cache_dir" 2>/dev/null)
  
  # Early exit if no cache directories found
  if [[ ${#cache_dirs[@]} -eq 0 ]]; then
    track_space_saved "User Cache" 0
    return 0
  fi
  
  local total_items=${#cache_dirs[@]}
  local current_item=0
  
  for dir in "${cache_dirs[@]}"; do
    current_item=$((current_item + 1))
    local dir_name=$(basename "$dir")
    update_operation_progress $current_item $total_items "$dir_name"
    safe_clean_dir "$dir" "$dir_name cache" || {
      print_error "Failed to clean $dir_name cache"
      return 1
    }
  done
  
  # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we calculate total for display only
  # Invalidate cache first to ensure fresh calculation (PERF-1)
  invalidate_size_cache "$cache_dir"
  local space_after=$(calculate_size_bytes "$cache_dir")
  local space_freed=$((space_before - space_after))
  
  # Validate space_freed is not negative
  if [[ $space_freed -lt 0 ]]; then
    space_freed=0
    log_message "WARNING" "Directory size increased during cleanup: $cache_dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
  fi
  
  # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we only track per-operation
  track_space_saved "User Cache" $space_freed "true"
  
  return 0
}

# Size calculation function for sweep
_calculate_user_cache_size_bytes() {
  local size_bytes=0
  if [[ -d "$HOME/Library/Caches" ]]; then
    size_bytes=$(calculate_size_bytes "$HOME/Library/Caches" 2>/dev/null || echo "0")
  fi
  echo "$size_bytes"
}

# Register plugin with size function
register_plugin "User Cache" "system" "clean_user_cache" "false" "_calculate_user_cache_size_bytes"
