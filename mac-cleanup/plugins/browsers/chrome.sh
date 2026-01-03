#!/bin/zsh
#
# plugins/browsers/chrome.sh - Chrome cache cleanup plugin
#

clean_chrome_cache() {
  print_header "Cleaning Chrome Cache"
  
  local chrome_base="$HOME/Library/Application Support/Google/Chrome"
  local chrome_found=false
  
  # Clean main Chrome cache
  local chrome_cache_dir="$HOME/Library/Caches/Google/Chrome"
  local total_space_freed=0
  
  if [[ -d "$chrome_cache_dir" ]]; then
    chrome_found=true
    local space_before=$(calculate_size_bytes "$chrome_cache_dir")
    if ! backup "$chrome_cache_dir" "chrome_cache"; then
      print_error "Backup failed for Chrome cache. Skipping this directory."
      log_message "ERROR" "Backup failed for Chrome cache, skipping"
    else
      safe_clean_dir "$chrome_cache_dir" "Chrome cache"
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
        print_error "Backup failed for Chrome $profile_name $dir_name. Skipping this directory."
        log_message "ERROR" "Backup failed for Chrome $profile_name $dir_name, skipping"
      else
        safe_clean_dir "$dir" "Chrome $profile_name $dir_name"
        local space_after=$(calculate_size_bytes "$dir")
        local space_freed=$((space_before - space_after))
        
        # Validate space_freed is not negative
        if [[ $space_freed -lt 0 ]]; then
          space_freed=0
          log_message "WARNING" "Directory size increased during cleanup: $dir"
        fi
        
        total_space_freed=$((total_space_freed + space_freed))
        print_success "Cleaned Chrome $profile_name $dir_name."
      fi
    done
  fi
  
  if [[ "$chrome_found" == false ]]; then
    print_warning "Chrome does not appear to be installed or has never been run."
  else
    # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we only update plugin-specific tracking
    MC_SPACE_SAVED_BY_OPERATION["Chrome Cache"]=$total_space_freed
    # Write to space tracking file if in background process (with locking)
    if [[ -n "${MC_SPACE_TRACKING_FILE:-}" && -f "$MC_SPACE_TRACKING_FILE" ]]; then
      _write_space_tracking_file "Chrome Cache" "$total_space_freed"
    fi
    print_warning "You may need to restart Chrome for changes to take effect"
  fi
}

# Register plugin
register_plugin "Chrome Cache" "browsers" "clean_chrome_cache" "false"
