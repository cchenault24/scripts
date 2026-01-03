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
    backup "$chrome_cache_dir" "chrome_cache"
    safe_clean_dir "$chrome_cache_dir" "Chrome cache"
    local space_after=$(calculate_size_bytes "$chrome_cache_dir")
    total_space_freed=$((total_space_freed + space_before - space_after))
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
      backup "$dir" "chrome_${profile_name}_$dir_name"
      safe_clean_dir "$dir" "Chrome $profile_name $dir_name"
      local space_after=$(calculate_size_bytes "$dir")
      total_space_freed=$((total_space_freed + space_before - space_after))
      print_success "Cleaned Chrome $profile_name $dir_name."
    done
  fi
  
  if [[ "$chrome_found" == false ]]; then
    print_warning "Chrome does not appear to be installed or has never been run."
  else
    track_space_saved "Chrome Cache" $total_space_freed
    print_warning "You may need to restart Chrome for changes to take effect"
  fi
}

# Register plugin
register_plugin "Chrome Cache" "browsers" "clean_chrome_cache" "false"
