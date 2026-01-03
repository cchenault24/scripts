#!/bin/zsh
#
# plugins/browsers/safari.sh - Safari cache cleanup plugin
#

# This file is sourced by the main script which provides:
# - All lib functions (print_*, log_message, calculate_size, etc.)
# - Plugin registration functions from plugins/base.sh

clean_safari_cache() {
  print_header "Cleaning Safari Cache"
  
  if ! command -v safaridriver &> /dev/null && [[ ! -d "$HOME/Library/Safari" ]]; then
    print_warning "Safari does not appear to be installed or has never been run."
    return
  fi
  
  local safari_cache_dirs=(
    "$HOME/Library/Caches/com.apple.Safari"
    "$HOME/Library/Safari/LocalStorage"
    "$HOME/Library/Safari/Databases"
    "$HOME/Library/Safari/ServiceWorkers"
  )
  
  local total_space_freed=0
  local dirs_processed=0
  local dirs_with_content=0
  
  # Store initial total to calculate what safe_clean_dir adds (to avoid double-counting)
  local initial_total=$MC_TOTAL_SPACE_SAVED
  
  local total_items=${#safari_cache_dirs[@]}
  local current_item=0
  
  for dir in "${safari_cache_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      current_item=$((current_item + 1))
      dirs_processed=$((dirs_processed + 1))
      local dir_name=$(basename "$dir")
      update_operation_progress $current_item $total_items "$dir_name"
      
      local space_before=$(calculate_size_bytes "$dir")
      # Check if directory has meaningful content (more than just directory overhead ~4KB)
      if [[ $space_before -gt 4096 ]]; then
        dirs_with_content=$((dirs_with_content + 1))
        backup "$dir" "safari_$dir_name"
        safe_clean_dir "$dir" "Safari $dir_name"
        local space_after=$(calculate_size_bytes "$dir")
        local space_freed=$((space_before - space_after))
        total_space_freed=$((total_space_freed + space_freed))
        print_success "Cleaned $dir ($(format_bytes $space_freed))."
      else
        print_info "Skipped $dir (already empty or minimal content: $(format_bytes $space_before))."
      fi
    fi
  done
  
  # Calculate what safe_clean_dir actually added to MC_TOTAL_SPACE_SAVED
  local space_added_by_safe_clean=$((MC_TOTAL_SPACE_SAVED - initial_total))
  
  # Update operation-specific tracking without double-counting
  # safe_clean_dir already updated MC_TOTAL_SPACE_SAVED, so we just update per-operation tracking
  if [[ $space_added_by_safe_clean -gt 0 ]]; then
    MC_SPACE_SAVED_BY_OPERATION["Safari Cache"]=$space_added_by_safe_clean
  elif [[ $dirs_processed -gt 0 && $dirs_with_content -eq 0 ]]; then
    print_info "All Safari cache directories are already empty or contain minimal data."
    MC_SPACE_SAVED_BY_OPERATION["Safari Cache"]=0
  fi
  
  print_warning "You may need to restart Safari for changes to take effect"
}

# Register plugin
register_plugin "Safari Cache" "browsers" "clean_safari_cache" "false"
