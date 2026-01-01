#!/bin/zsh
#
# plugins/system/user_cache.sh - User cache cleanup plugin
#

clean_user_cache() {
  print_header "Cleaning User Cache"
  
  local cache_dir="$HOME/Library/Caches"
  local space_before=$(calculate_size_bytes "$cache_dir")
  
  backup "$cache_dir" "user_caches"
  find "$cache_dir" -maxdepth 1 -type d ! -path "$cache_dir" | while read dir; do
    safe_clean_dir "$dir" "$(basename "$dir") cache"
  done
  
  local space_after=$(calculate_size_bytes "$cache_dir")
  local space_freed=$((space_before - space_after))
  track_space_saved "User Cache" $space_freed
  
  print_success "User cache cleaned."
}

# Register plugin
register_plugin "User Cache" "system" "clean_user_cache" "false"
