#!/bin/zsh
#
# plugins/system/user_cache.sh - User cache cleanup plugin
#

clean_user_cache() {
  print_header "Cleaning User Cache"
  
  local cache_dir="$HOME/Library/Caches"
  
  # Early exit for non-existent or empty directories (PERF-6)
  if [[ ! -d "$cache_dir" ]] || [[ -z "$(ls -A "$cache_dir" 2>/dev/null)" ]]; then
    print_info "User cache directory is empty or doesn't exist."
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
    print_info "No cache directories found to clean."
    return 0
  fi
  
  local total_items=${#cache_dirs[@]}
  local current_item=0
  
  for dir in "${cache_dirs[@]}"; do
    current_item=$((current_item + 1))
    local dir_name=$(basename "$dir")
    update_operation_progress $current_item $total_items "$dir_name"
    safe_clean_dir "$dir" "$dir_name cache"
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
  
  # Update plugin-specific tracking (but don't double-count in total)
  MC_SPACE_SAVED_BY_OPERATION["User Cache"]=$space_freed
  # Write to space tracking file if in background process (with locking)
  if [[ -n "${MC_SPACE_TRACKING_FILE:-}" && -f "$MC_SPACE_TRACKING_FILE" ]]; then
    _write_space_tracking_file "User Cache" "$space_freed"
  fi
  
  print_success "User cache cleaned."
}

# Register plugin
register_plugin "User Cache" "system" "clean_user_cache" "false"
