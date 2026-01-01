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
  
  for dir in "${safari_cache_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      local space_before=$(calculate_size_bytes "$dir")
      backup "$dir" "safari_$(basename "$dir")"
      safe_clean_dir "$dir" "Safari $(basename "$dir")"
      local space_after=$(calculate_size_bytes "$dir")
      total_space_freed=$((total_space_freed + space_before - space_after))
      print_success "Cleaned $dir."
    fi
  done
  
  track_space_saved "Safari Cache" $total_space_freed
  
  print_warning "You may need to restart Safari for changes to take effect"
}

# Register plugin
register_plugin "Safari Cache" "browsers" "clean_safari_cache" "false"
