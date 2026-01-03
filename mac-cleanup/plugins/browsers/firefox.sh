#!/bin/zsh
#
# plugins/browsers/firefox.sh - Firefox cache cleanup plugin
#

clean_firefox_cache() {
  print_header "Cleaning Firefox Cache"
  
  local firefox_base="$HOME/Library/Application Support/Firefox"
  local firefox_found=false
  local total_space_freed=0
  
  # Clean main Firefox cache
  local firefox_cache_dir="$HOME/Library/Caches/Firefox"
  if [[ -d "$firefox_cache_dir" ]]; then
    firefox_found=true
    local space_before=$(calculate_size_bytes "$firefox_cache_dir")
    backup "$firefox_cache_dir" "firefox_cache"
    safe_clean_dir "$firefox_cache_dir" "Firefox cache"
    local space_after=$(calculate_size_bytes "$firefox_cache_dir")
    total_space_freed=$((total_space_freed + space_before - space_after))
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
      backup "$dir" "firefox_${profile_name}_$dir_name"
      safe_clean_dir "$dir" "Firefox $profile_name $dir_name"
      local space_after=$(calculate_size_bytes "$dir")
      total_space_freed=$((total_space_freed + space_before - space_after))
      print_success "Cleaned Firefox $profile_name $dir_name."
    done
  fi
  
  if [[ "$firefox_found" == false ]]; then
    print_warning "Firefox does not appear to be installed or has never been run."
  else
    track_space_saved "Firefox Cache" $total_space_freed
    print_warning "You may need to restart Firefox for changes to take effect"
  fi
}

# Register plugin
register_plugin "Firefox Cache" "browsers" "clean_firefox_cache" "false"
