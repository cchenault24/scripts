#!/bin/zsh
#
# plugins/browsers/edge.sh - Microsoft Edge cache cleanup plugin
#

clean_edge_cache() {
  print_header "Cleaning Microsoft Edge Cache"
  
  local edge_base="$HOME/Library/Application Support/Microsoft Edge"
  local edge_found=false
  local total_space_freed=0
  
  # Clean main Edge cache
  local edge_cache_dir="$HOME/Library/Caches/com.microsoft.edgemac"
  if [[ -d "$edge_cache_dir" ]]; then
    edge_found=true
    local space_before=$(calculate_size_bytes "$edge_cache_dir")
    backup "$edge_cache_dir" "edge_cache"
    safe_clean_dir "$edge_cache_dir" "Edge cache"
    local space_after=$(calculate_size_bytes "$edge_cache_dir")
    total_space_freed=$((total_space_freed + space_before - space_after))
    print_success "Cleaned Edge cache."
  fi
  
  # Find and clean all Edge profiles (similar to Chrome)
  if [[ -d "$edge_base" ]]; then
    edge_found=true
    # Collect all directories to clean first
    local all_dirs=()
    for profile_dir in "$edge_base"/*/; do
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
      backup "$dir" "edge_${profile_name}_$dir_name"
      safe_clean_dir "$dir" "Edge $profile_name $dir_name"
      local space_after=$(calculate_size_bytes "$dir")
      total_space_freed=$((total_space_freed + space_before - space_after))
      print_success "Cleaned Edge $profile_name $dir_name."
    done
  fi
  
  if [[ "$edge_found" == false ]]; then
    print_warning "Microsoft Edge does not appear to be installed or has never been run."
  else
    track_space_saved "Microsoft Edge Cache" $total_space_freed
    print_warning "You may need to restart Edge for changes to take effect"
  fi
}

# Register plugin
register_plugin "Microsoft Edge Cache" "browsers" "clean_edge_cache" "false"
