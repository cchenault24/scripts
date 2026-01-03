#!/bin/zsh
#
# plugins/browsers/chrome.sh - Chrome cache cleanup plugin
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

clean_chrome_cache() {
  local chrome_base="$HOME/Library/Application Support/Google/Chrome"
  local chrome_found=false
  local total_space_freed=0
  
  # Clean main Chrome cache
  local chrome_cache_dir="$HOME/Library/Caches/Google/Chrome"
  
  if [[ -d "$chrome_cache_dir" ]]; then
    chrome_found=true
    local space_before=$(calculate_size_bytes "$chrome_cache_dir")
    if ! backup "$chrome_cache_dir" "chrome_cache"; then
      print_error "Backup failed for Chrome cache. Aborting cleanup to prevent data loss."
      log_message "ERROR" "Backup failed for Chrome cache, aborting"
      return 1
    fi
    
    safe_clean_dir "$chrome_cache_dir" "Chrome cache" || {
      print_error "Failed to clean Chrome cache"
      return 1
    }
    
    local space_after=$(calculate_size_bytes "$chrome_cache_dir")
    local space_freed=$((space_before - space_after))
    
    # Validate space_freed is not negative
    if [[ $space_freed -lt 0 ]]; then
      space_freed=0
      log_message "WARNING" "Directory size increased during cleanup: $chrome_cache_dir"
    fi
    
    total_space_freed=$((total_space_freed + space_freed))
    print_success "Cleaned Chrome cache."
  fi
  
  # Find and clean all Chrome profiles (not just Default)
  if [[ -d "$chrome_base" ]]; then
    chrome_found=true
    # Collect all directories to clean first
    local all_dirs=()
    for profile_dir in "$chrome_base"/*/; do
      if [[ -d "$profile_dir" ]]; then
        local profile_name=$(basename "$profile_dir")
        local profile_dirs=(
          "$profile_dir/Cache"
          "$profile_dir/Code Cache"
          "$profile_dir/Service Worker"
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
      if ! backup "$dir" "chrome_${profile_name}_$dir_name"; then
        print_error "Backup failed for Chrome $profile_name $dir_name. Aborting cleanup to prevent data loss."
        log_message "ERROR" "Backup failed for Chrome $profile_name $dir_name, aborting"
        return 1
      fi
      
      safe_clean_dir "$dir" "Chrome $profile_name $dir_name" || {
        print_error "Failed to clean Chrome $profile_name $dir_name"
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
      print_success "Cleaned Chrome $profile_name $dir_name."
    done
  fi
  
  if [[ "$chrome_found" == false ]]; then
    print_warning "Chrome does not appear to be installed or has never been run."
    track_space_saved "Chrome Cache" 0
    return 0
  fi
  
  # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we only track per-operation
  track_space_saved "Chrome Cache" $total_space_freed "true"
  print_warning "You may need to restart Chrome for changes to take effect"
  return 0
}

# Size calculation function for sweep
_calculate_chrome_cache_size_bytes() {
  local size_bytes=0
  local chrome_size=0
  
  if [[ -d "$HOME/Library/Caches/Google/Chrome" ]]; then
    chrome_size=$(calculate_size_bytes "$HOME/Library/Caches/Google/Chrome" 2>/dev/null || echo "0")
    [[ "$chrome_size" =~ ^[0-9]+$ ]] && size_bytes=$((size_bytes + chrome_size))
  fi
  
  if [[ -d "$HOME/Library/Application Support/Google/Chrome" ]]; then
    for profile_dir in "$HOME/Library/Application Support/Google/Chrome"/*/; do
      if [[ -d "$profile_dir" ]]; then
        [[ -d "$profile_dir/Cache" ]] && {
          local cache_size=$(calculate_size_bytes "$profile_dir/Cache" 2>/dev/null || echo "0")
          [[ "$cache_size" =~ ^[0-9]+$ ]] && size_bytes=$((size_bytes + cache_size))
        }
        [[ -d "$profile_dir/Code Cache" ]] && {
          local code_cache_size=$(calculate_size_bytes "$profile_dir/Code Cache" 2>/dev/null || echo "0")
          [[ "$code_cache_size" =~ ^[0-9]+$ ]] && size_bytes=$((size_bytes + code_cache_size))
        }
        [[ -d "$profile_dir/Service Worker" ]] && {
          local sw_size=$(calculate_size_bytes "$profile_dir/Service Worker" 2>/dev/null || echo "0")
          [[ "$sw_size" =~ ^[0-9]+$ ]] && size_bytes=$((size_bytes + sw_size))
        }
      fi
    done
  fi
  
  echo "$size_bytes"
}

# Register plugin with size function
register_plugin "Chrome Cache" "browsers" "clean_chrome_cache" "false" "_calculate_chrome_cache_size_bytes"
