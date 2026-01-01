#!/bin/zsh
#
# plugins/package-managers/pip.sh - pip cache cleanup plugin
#

clean_pip_cache() {
  print_header "Cleaning pip Cache"
  
  if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
    print_warning "pip is not installed."
    return
  fi
  
  local pip_cmd="pip3"
  if command -v pip &> /dev/null; then
    pip_cmd="pip"
  fi
  
  local pip_cache_dir=$($pip_cmd cache dir 2>/dev/null || echo "$HOME/Library/Caches/pip")
  local total_space_freed=0
  
  if [[ -d "$pip_cache_dir" ]]; then
    local space_before=$(calculate_size_bytes "$pip_cache_dir")
    
    if [[ "$MC_DRY_RUN" == "true" ]]; then
      print_info "[DRY RUN] Would clean pip cache ($(format_bytes $space_before))"
      log_message "DRY_RUN" "Would clean pip cache"
    else
      backup "$pip_cache_dir" "pip_cache"
      $pip_cmd cache purge 2>&1 | log_message "INFO"
      local space_after=$(calculate_size_bytes "$pip_cache_dir")
      total_space_freed=$((space_before - space_after))
      track_space_saved "pip Cache" $total_space_freed
      print_success "pip cache cleaned."
      log_message "SUCCESS" "pip cache cleaned (freed $(format_bytes $total_space_freed))"
    fi
  else
    print_warning "pip cache directory not found."
  fi
}

# Register plugin
register_plugin "pip Cache" "package-managers" "clean_pip_cache" "false"
