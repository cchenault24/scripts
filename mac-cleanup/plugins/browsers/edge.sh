#!/bin/zsh
#
# plugins/browsers/edge.sh - Microsoft Edge cache cleanup plugin
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

clean_edge_cache() {
  local edge_base="$HOME/Library/Application Support/Microsoft Edge"
  local edge_found=false
  local total_space_freed=0
  
  # Clean main Edge cache
  local edge_cache_dir="$HOME/Library/Caches/com.microsoft.edgemac"
  if [[ -d "$edge_cache_dir" ]]; then
    edge_found=true
    local space_before=$(calculate_size_bytes "$edge_cache_dir")
    if ! backup "$edge_cache_dir" "edge_cache"; then
      print_error "Backup failed for Edge cache. Aborting cleanup to prevent data loss."
      log_message "ERROR" "Backup failed for Edge cache, aborting"
      return 1
    fi
    
    safe_clean_dir "$edge_cache_dir" "Edge cache" || {
      print_error "Failed to clean Edge cache"
      return 1
    }
    
    local space_after=$(calculate_size_bytes "$edge_cache_dir")
    local space_freed=$((space_before - space_after))
    # Validate space_freed is not negative (directory may have grown during cleanup)
    if [[ $space_freed -lt 0 ]]; then
      space_freed=0
      log_message "WARNING" "Directory size increased during cleanup: $edge_cache_dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
    fi
      total_space_freed=$((total_space_freed + space_freed))
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
      if ! backup "$dir" "edge_${profile_name}_$dir_name"; then
        print_error "Backup failed for Edge $profile_name $dir_name. Aborting cleanup to prevent data loss."
        log_message "ERROR" "Backup failed for Edge $profile_name $dir_name, aborting"
        return 1
      fi
      
      safe_clean_dir "$dir" "Edge $profile_name $dir_name" || {
        print_error "Failed to clean Edge $profile_name $dir_name"
        return 1
      }
      
      local space_after=$(calculate_size_bytes "$dir")
      local space_freed=$((space_before - space_after))
      # Validate space_freed is not negative (directory may have grown during cleanup)
      if [[ $space_freed -lt 0 ]]; then
        space_freed=0
        log_message "WARNING" "Directory size increased during cleanup: $dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
      fi
      total_space_freed=$((total_space_freed + space_freed))
    done
  fi
  
  if [[ "$edge_found" == false ]]; then
    print_warning "Microsoft Edge does not appear to be installed or has never been run."
    track_space_saved "Microsoft Edge Cache" 0
    return 0
  fi
  
  # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we only track per-operation
  track_space_saved "Microsoft Edge Cache" $total_space_freed "true"
  return 0
}

# Size calculation function for sweep
_calculate_edge_cache_size_bytes() {
  local size_bytes=0
  local edge_size=0
  
  if [[ -d "$HOME/Library/Caches/com.microsoft.edgemac" ]]; then
    edge_size=$(calculate_size_bytes "$HOME/Library/Caches/com.microsoft.edgemac" 2>/dev/null || echo "0")
    [[ "$edge_size" =~ ^[0-9]+$ ]] && size_bytes=$((size_bytes + edge_size))
  fi
  
  if [[ -d "$HOME/Library/Application Support/Microsoft Edge" ]]; then
    for profile_dir in "$HOME/Library/Application Support/Microsoft Edge"/*/; do
      if [[ -d "$profile_dir" ]]; then
        [[ -d "$profile_dir/Cache" ]] && {
          local edge_cache_size=$(calculate_size_bytes "$profile_dir/Cache" 2>/dev/null || echo "0")
          [[ "$edge_cache_size" =~ ^[0-9]+$ ]] && size_bytes=$((size_bytes + edge_cache_size))
        }
        [[ -d "$profile_dir/Code Cache" ]] && {
          local edge_code_size=$(calculate_size_bytes "$profile_dir/Code Cache" 2>/dev/null || echo "0")
          [[ "$edge_code_size" =~ ^[0-9]+$ ]] && size_bytes=$((size_bytes + edge_code_size))
        }
      fi
    done
  fi
  
  echo "$size_bytes"
}

# Register plugin with size function
register_plugin "Microsoft Edge Cache" "browsers" "clean_edge_cache" "false" "_calculate_edge_cache_size_bytes"
