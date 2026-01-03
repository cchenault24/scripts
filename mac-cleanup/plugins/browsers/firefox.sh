#!/bin/zsh
#
# plugins/browsers/firefox.sh - Firefox cache cleanup plugin
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

clean_firefox_cache() {
  local firefox_base="$HOME/Library/Application Support/Firefox"
  local firefox_found=false
  local total_space_freed=0
  
  # Clean main Firefox cache
  local firefox_cache_dir="$HOME/Library/Caches/Firefox"
  if [[ -d "$firefox_cache_dir" ]]; then
    firefox_found=true
    local space_before=$(calculate_size_bytes "$firefox_cache_dir")
    if ! backup "$firefox_cache_dir" "firefox_cache"; then
      print_error "Backup failed for Firefox cache. Aborting cleanup to prevent data loss."
      log_message "ERROR" "Backup failed for Firefox cache, aborting"
      return 1
    fi
    
    safe_clean_dir "$firefox_cache_dir" "Firefox cache" || {
      print_error "Failed to clean Firefox cache"
      return 1
    }
    
    local space_after=$(calculate_size_bytes "$firefox_cache_dir")
    local space_freed=$((space_before - space_after))
    
    # Validate space_freed is not negative
    if [[ $space_freed -lt 0 ]]; then
      space_freed=0
      log_message "WARNING" "Directory size increased during cleanup: $firefox_cache_dir"
    fi
    
    total_space_freed=$((total_space_freed + space_freed))
    print_success "Cleaned Firefox cache."
  fi
  
  # Find and clean all Firefox profiles
  if [[ -d "$firefox_base" ]]; then
    firefox_found=true
    # Collect all directories to clean first
    local all_dirs=()
    for profile_dir in "$firefox_base"/Profiles/*/; do
      if [[ -d "$profile_dir" ]]; then
        local profile_name=$(basename "$profile_dir")
        local profile_dirs=(
          "$profile_dir/cache2"
          "$profile_dir/startupCache"
          "$profile_dir/OfflineCache"
        )
        for dir in "${profile_dirs[@]}"; do
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
      if ! backup "$dir" "firefox_${profile_name}_$dir_name"; then
        print_error "Backup failed for Firefox $profile_name $dir_name. Aborting cleanup to prevent data loss."
        log_message "ERROR" "Backup failed for Firefox $profile_name $dir_name, aborting"
        return 1
      fi
      
      safe_clean_dir "$dir" "Firefox $profile_name $dir_name" || {
        print_error "Failed to clean Firefox $profile_name $dir_name"
        return 1
      }
      
      local space_after=$(calculate_size_bytes "$dir")
      local space_freed=$((space_before - space_after))
      
      # Validate space_freed is not negative
      if [[ $space_freed -lt 0 ]]; then
        space_freed=0
        log_message "WARNING" "Directory size increased during cleanup: $dir"
      fi
      
      total_space_freed=$((total_space_freed + space_freed))
      print_success "Cleaned Firefox $profile_name $dir_name."
    done
  fi
  
  if [[ "$firefox_found" == false ]]; then
    print_warning "Firefox does not appear to be installed or has never been run."
    track_space_saved "Firefox Cache" 0
    return 0
  fi
  
  # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we only track per-operation
  track_space_saved "Firefox Cache" $total_space_freed "true"
  print_warning "You may need to restart Firefox for changes to take effect"
  return 0
}

# Size calculation function for sweep
_calculate_firefox_cache_size_bytes() {
  local size_bytes=0
  local firefox_size=0
  
  if [[ -d "$HOME/Library/Caches/Firefox" ]]; then
    firefox_size=$(calculate_size_bytes "$HOME/Library/Caches/Firefox" 2>/dev/null || echo "0")
    [[ "$firefox_size" =~ ^[0-9]+$ ]] && size_bytes=$((size_bytes + firefox_size))
  fi
  
  if [[ -d "$HOME/Library/Application Support/Firefox" ]]; then
    for profile_dir in "$HOME/Library/Application Support/Firefox/Profiles"/*/; do
      if [[ -d "$profile_dir" ]]; then
        [[ -d "$profile_dir/cache2" ]] && {
          local cache2_size=$(calculate_size_bytes "$profile_dir/cache2" 2>/dev/null || echo "0")
          [[ "$cache2_size" =~ ^[0-9]+$ ]] && size_bytes=$((size_bytes + cache2_size))
        }
        [[ -d "$profile_dir/startupCache" ]] && {
          local startup_size=$(calculate_size_bytes "$profile_dir/startupCache" 2>/dev/null || echo "0")
          [[ "$startup_size" =~ ^[0-9]+$ ]] && size_bytes=$((size_bytes + startup_size))
        }
      fi
    done
  fi
  
  echo "$size_bytes"
}

# Register plugin with size function
register_plugin "Firefox Cache" "browsers" "clean_firefox_cache" "false" "_calculate_firefox_cache_size_bytes"
