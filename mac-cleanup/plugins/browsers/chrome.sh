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
    # Find all profile directories
    for profile_dir in "$chrome_base"/*/; do
      if [[ -d "$profile_dir" ]]; then
        local profile_name=$(basename "$profile_dir")
        local profile_dirs=(
          "$profile_dir/Cache"
          "$profile_dir/Code Cache"
          "$profile_dir/Service Worker"
        )
        
        for dir in "${profile_dirs[@]}"; do
          if [[ -d "$dir" ]]; then
            local space_before=$(calculate_size_bytes "$dir")
            backup "$dir" "chrome_${profile_name}_$(basename "$dir")"
            safe_clean_dir "$dir" "Chrome $profile_name $(basename "$dir")"
            local space_after=$(calculate_size_bytes "$dir")
            total_space_freed=$((total_space_freed + space_before - space_after))
            print_success "Cleaned Chrome $profile_name $(basename "$dir")."
          fi
        done
      fi
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
