#!/bin/zsh
#
# plugins/system/containers.sh - Application container caches and saved states cleanup plugin
#

clean_container_caches() {
  print_header "Cleaning Application Container Caches"
  
  local containers_dir="$HOME/Library/Containers"
  local total_space_freed=0
  
  if [[ -d "$containers_dir" ]]; then
    backup "$containers_dir" "app_containers"
    
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
        if [[ -d "$dir" ]]; then
          find "$dir" -mindepth 1 -delete 2>/dev/null || {
            find "$dir" -mindepth 1 -maxdepth 1 ! -name ".*" -delete 2>/dev/null || true
            find "$dir" -mindepth 1 -maxdepth 1 -name ".*" -delete 2>/dev/null || true
            if [[ -n "${ZSH_VERSION:-}" ]]; then
              rm -rf "${dir:?}"/*(N) "${dir:?}"/.[!.]*(N) 2>/dev/null || true
            else
              rm -rf "${dir:?}"/* "${dir:?}"/.[!.]* 2>/dev/null || true
            fi
          }
          invalidate_size_cache "$dir"
        fi
        local space_after=$(calculate_size_bytes "$dir")
        local space_freed=$((space_before - space_after))
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
    
    track_space_saved "Application Container Caches" $total_space_freed
  else
    print_warning "No application containers found."
    track_space_saved "Application Container Caches" 0
  fi
}

clean_saved_states() {
  print_header "Cleaning Saved Application States"
  
  local saved_states_dir="$HOME/Library/Saved Application State"
  
  if [[ -d "$saved_states_dir" ]]; then
    local space_before=$(calculate_size_bytes "$saved_states_dir")
    backup "$saved_states_dir" "saved_app_states"
    safe_clean_dir "$saved_states_dir" "saved application states"
    local space_after=$(calculate_size_bytes "$saved_states_dir")
    local space_freed=$((space_before - space_after))
    # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we only update plugin-specific tracking
    MC_SPACE_SAVED_BY_OPERATION["Saved Application States"]=$space_freed
    # Write to space tracking file if in background process (with locking)
    if [[ -n "${MC_SPACE_TRACKING_FILE:-}" && -f "$MC_SPACE_TRACKING_FILE" ]]; then
      _write_space_tracking_file "Saved Application States" "$space_freed"
    fi
    print_success "Cleaned saved application states."
  else
    print_warning "No saved application states found."
  fi
}

# Register plugins
register_plugin "Application Container Caches" "system" "clean_container_caches" "false"
register_plugin "Saved Application States" "system" "clean_saved_states" "false"
