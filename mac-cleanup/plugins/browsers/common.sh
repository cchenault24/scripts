#!/bin/zsh
#
# plugins/browsers/common.sh - Common browser plugin functions
# QUAL-3: Shared functionality for browser cache cleanup plugins
#

# Common browser cache cleanup function
# Parameters:
#   - browser_name: Display name of the browser (e.g., "Chrome", "Firefox")
#   - cache_dir: Main cache directory path
#   - base_dir: Application Support base directory
#   - profile_dirs: Array of profile subdirectories to clean (e.g., ("Cache" "Code Cache"))
#   - cache_backup_name: Backup name prefix for cache directory
#   - profile_backup_prefix: Backup name prefix for profile directories
clean_browser_cache_common() {
  local browser_name="$1"
  local cache_dir="$2"
  local base_dir="$3"
  local profile_dirs=("${(@)4}")  # Array of profile subdirectories
  local cache_backup_name="$5"
  local profile_backup_prefix="$6"
  
  print_header "Cleaning ${browser_name} Cache"
  
  local browser_found=false
  local total_space_freed=0
  
  # Clean main cache directory
  if [[ -d "$cache_dir" ]]; then
    browser_found=true
    local space_before=$(calculate_size_bytes "$cache_dir")
    
    if ! backup "$cache_dir" "$cache_backup_name"; then
      print_error "Backup failed for ${browser_name} cache. Skipping this directory."
      log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Backup failed for ${browser_name} cache, skipping"
    else
      safe_clean_dir "$cache_dir" "${browser_name} cache"
      local space_after=$(calculate_size_bytes "$cache_dir")
      local space_freed=$((space_before - space_after))
      
      # Validate space_freed is not negative
      if [[ $space_freed -lt 0 ]]; then
        space_freed=0
        log_message "${MC_LOG_LEVEL_WARNING:-WARNING}" "Directory size increased during cleanup: $cache_dir"
      fi
      
      total_space_freed=$((total_space_freed + space_freed))
      print_success "Cleaned ${browser_name} cache."
    fi
  fi
  
  # Find and clean all browser profiles
  if [[ -d "$base_dir" ]]; then
    browser_found=true
    # Collect all directories to clean first
    local all_dirs=()
    for profile_dir in "$base_dir"/*/; do
      if [[ -d "$profile_dir" ]]; then
        local profile_name=$(basename "$profile_dir")
        for dir_name in "${profile_dirs[@]}"; do
          local dir="$profile_dir/$dir_name"
          [[ -d "$dir" ]] && all_dirs+=("$dir|$profile_name")
        done
      fi
    done
    
    local total_items=${#all_dirs[@]}
    local current_item=0
    
    for dir_info in "${all_dirs[@]}"; do
      current_item=$((current_item + 1))
      local dir=$(echo "$dir_info" | cut -d'|' -f1)
      local profile_name=$(echo "$dir_info" | cut -d'|' -f2)
      local dir_name=$(basename "$dir")
      update_operation_progress $current_item $total_items "$profile_name/$dir_name"
      
      local space_before=$(calculate_size_bytes "$dir")
      local backup_name="${profile_backup_prefix}_${profile_name}_$dir_name"
      
      if ! backup "$dir" "$backup_name"; then
        print_error "Backup failed for ${browser_name} $profile_name $dir_name. Skipping this directory."
        log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Backup failed for ${browser_name} $profile_name $dir_name, skipping"
      else
        safe_clean_dir "$dir" "${browser_name} $profile_name $dir_name"
        local space_after=$(calculate_size_bytes "$dir")
        local space_freed=$((space_before - space_after))
        
        # Validate space_freed is not negative
        if [[ $space_freed -lt 0 ]]; then
          space_freed=0
          log_message "${MC_LOG_LEVEL_WARNING:-WARNING}" "Directory size increased during cleanup: $dir"
        fi
        
        total_space_freed=$((total_space_freed + space_freed))
        print_success "Cleaned ${browser_name} $profile_name $dir_name."
      fi
    done
  fi
  
  if [[ "$browser_found" == false ]]; then
    print_warning "${browser_name} does not appear to be installed or has never been run."
  else
    # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we only update plugin-specific tracking
    MC_SPACE_SAVED_BY_OPERATION["${browser_name} Cache"]=$total_space_freed
    # Write to space tracking file if in background process (with locking)
    if [[ -n "${MC_SPACE_TRACKING_FILE:-}" && -f "$MC_SPACE_TRACKING_FILE" ]]; then
      _write_space_tracking_file "${browser_name} Cache" "$total_space_freed"
    fi
    print_warning "You may need to restart ${browser_name} for changes to take effect"
  fi
  
  return 0
}
