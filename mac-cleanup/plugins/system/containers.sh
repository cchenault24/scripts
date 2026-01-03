#!/bin/zsh
#
# plugins/system/containers.sh - Application container caches and saved states cleanup plugin
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

clean_container_caches() {
  print_header "Cleaning Application Container Caches"
  
  local containers_dir="$HOME/Library/Containers"
  local total_space_freed=0
  
  if [[ -d "$containers_dir" ]]; then
    if ! backup "$containers_dir" "app_containers"; then
      print_error "Backup failed for application containers. Aborting cleanup to prevent data loss."
      log_message "ERROR" "Backup failed, aborting container caches cleanup"
      return 1
    fi
    
    # Collect all cache directories first
    local cache_dirs=()
    while IFS= read -r dir; do
      [[ -n "$dir" && -d "$dir" ]] && cache_dirs+=("$dir")
    done < <(find "$containers_dir" -type d -name "Caches" 2>/dev/null)
    
    if [[ ${#cache_dirs[@]} -eq 0 ]]; then
      print_info "No container cache directories found."
      track_space_saved "Application Container Caches" 0
      return 0
    fi
    
    # Process all cache directories with minimal verbosity
    local cache_count=${#cache_dirs[@]}
    if [[ $cache_count -eq 1 ]]; then
      print_info "Cleaning 1 container cache directory..."
    else
      print_info "Cleaning $cache_count container cache directories..."
    fi
    
    local processed_count=0
    local total_items=${#cache_dirs[@]}
    local current_item=0
    
    for dir in "${cache_dirs[@]}"; do
      current_item=$((current_item + 1))
      # Extract app name from path: /Users/.../Library/Containers/com.app.name/Data/Library/Caches
      # We want "com.app.name" which is the container bundle ID
      local app_name=$(echo "$dir" | sed -E 's|.*/Containers/([^/]+)/.*|\1|')
      [[ -z "$app_name" ]] && app_name="Unknown"
      
      update_operation_progress $current_item $total_items "$app_name"
      
      local space_before=$(calculate_size_bytes "$dir")
      if [[ $space_before -gt 0 ]]; then
        # Clean the directory silently (we'll show summary at end)
        # SAFE-1: Use safe_clean_dir to safely handle symlinks and permissions
        if [[ -d "$dir" ]]; then
          safe_clean_dir "$dir" "container cache: $app_name" || {
            # Fallback: try find -delete if safe_clean_dir fails
            # Backup is already done at line 15 for entire containers_dir, but ensure backup for this specific dir
            if ! backup "$dir" "container_cache_${app_name}"; then
              print_error "Backup failed for $app_name container cache. Skipping fallback cleanup."
              log_message "ERROR" "Backup failed for fallback cleanup: $dir"
              continue
            fi
            find "$dir" -mindepth 1 -delete 2>/dev/null || {
              find "$dir" -mindepth 1 -maxdepth 1 ! -name ".*" -delete 2>/dev/null
              find "$dir" -mindepth 1 -maxdepth 1 -name ".*" -delete 2>/dev/null
            }
          }
          invalidate_size_cache "$dir"
        fi
        local space_after=$(calculate_size_bytes "$dir")
        local space_freed=$((space_before - space_after))
        # Validate space_freed is not negative (directory may have grown during cleanup)
        if [[ $space_freed -lt 0 ]]; then
          space_freed=0
          log_message "WARNING" "Directory size increased during cleanup: $dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
        fi
        total_space_freed=$((total_space_freed + space_freed))
        processed_count=$((processed_count + 1))
        log_message "INFO" "Cleaned container cache: $app_name (freed $(format_bytes $space_freed))"
      fi
    done
    
    if [[ $processed_count -gt 0 ]]; then
      if [[ $processed_count -eq 1 ]]; then
        print_success "Cleaned 1 container cache directory ($(format_bytes $total_space_freed) freed)."
      else
        print_success "Cleaned $processed_count container cache directories ($(format_bytes $total_space_freed) freed)."
      fi
    else
      print_info "Container caches were already empty."
    fi
    
    # Manual cleanup doesn't use safe_clean_dir, so we need to track space manually
    # Manual cleanup doesn't use safe_clean_dir, so we update the total (don't skip)
    track_space_saved "Application Container Caches" $total_space_freed
  else
    print_warning "No application containers found."
    track_space_saved "Application Container Caches" 0
  fi
  return 0
}

clean_saved_states() {
  print_header "Cleaning Saved Application States"
  
  local saved_states_dir="$HOME/Library/Saved Application State"
  
  if [[ -d "$saved_states_dir" ]]; then
    local space_before=$(calculate_size_bytes "$saved_states_dir")
    if ! backup "$saved_states_dir" "saved_app_states"; then
      print_error "Backup failed for saved application states. Aborting cleanup to prevent data loss."
      log_message "ERROR" "Backup failed, aborting saved states cleanup"
      return 1
    fi
    safe_clean_dir "$saved_states_dir" "saved application states"
    local space_after=$(calculate_size_bytes "$saved_states_dir")
    local space_freed=$((space_before - space_after))
    # Validate space_freed is not negative (directory may have grown during cleanup)
    if [[ $space_freed -lt 0 ]]; then
      space_freed=0
      log_message "WARNING" "Directory size increased during cleanup: $saved_states_dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
    fi
    # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we only track per-operation
    track_space_saved "Saved Application States" $space_freed "true"
    print_success "Cleaned saved application states."
  else
    print_warning "No saved application states found."
    track_space_saved "Saved Application States" 0
  fi
  return 0
}

# Size calculation functions for sweep
_calculate_container_caches_size_bytes() {
  local size_bytes=0
  if [[ -d "$HOME/Library/Containers" ]]; then
    local cache_size=0
    while IFS= read -r cache_dir; do
      [[ -n "$cache_dir" && -d "$cache_dir" ]] && {
        local dir_size=$(calculate_size_bytes "$cache_dir" 2>/dev/null || echo "0")
        [[ "$dir_size" =~ ^[0-9]+$ ]] && cache_size=$((cache_size + dir_size))
      }
    done < <(find "$HOME/Library/Containers" -type d -name "Caches" 2>/dev/null)
    size_bytes=$cache_size
  fi
  echo "$size_bytes"
}

_calculate_saved_states_size_bytes() {
  local size_bytes=0
  if [[ -d "$HOME/Library/Saved Application State" ]]; then
    size_bytes=$(calculate_size_bytes "$HOME/Library/Saved Application State" 2>/dev/null || echo "0")
  fi
  echo "$size_bytes"
}

# Register plugins with size functions
register_plugin "Application Container Caches" "system" "clean_container_caches" "false" "_calculate_container_caches_size_bytes"
register_plugin "Saved Application States" "system" "clean_saved_states" "false" "_calculate_saved_states_size_bytes"
