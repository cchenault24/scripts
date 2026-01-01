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
    for profile_dir in "$edge_base"/*/; do
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
            backup "$dir" "edge_${profile_name}_$(basename "$dir")"
            safe_clean_dir "$dir" "Edge $profile_name $(basename "$dir")"
            local space_after=$(calculate_size_bytes "$dir")
            total_space_freed=$((total_space_freed + space_before - space_after))
            print_success "Cleaned Edge $profile_name $(basename "$dir")."
          fi
        done
      fi
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
