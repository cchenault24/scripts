#!/bin/zsh
#
# plugins/system/user_cache.sh - User cache cleanup plugin
#

clean_user_cache() {
  print_header "Cleaning User Cache"
  
  local cache_dir="$HOME/Library/Caches"
  local space_before=$(calculate_size_bytes "$cache_dir")
  
  backup "$cache_dir" "user_caches"
  
  # Collect all cache directories first
  local cache_dirs=()
  while IFS= read -r dir; do
    [[ -n "$dir" && -d "$dir" ]] && cache_dirs+=("$dir")
  done < <(find "$cache_dir" -maxdepth 1 -type d ! -path "$cache_dir" 2>/dev/null)
  
  local total_items=${#cache_dirs[@]}
  local current_item=0
  
  for dir in "${cache_dirs[@]}"; do
    current_item=$((current_item + 1))
    local dir_name=$(basename "$dir")
    update_operation_progress $current_item $total_items "$dir_name"
    safe_clean_dir "$dir" "$dir_name cache"
  done
  
  local space_after=$(calculate_size_bytes "$cache_dir")
  local space_freed=$((space_before - space_after))
  track_space_saved "User Cache" $space_freed
  
  print_success "User cache cleaned."
}

# Register plugin
register_plugin "User Cache" "system" "clean_user_cache" "false"
