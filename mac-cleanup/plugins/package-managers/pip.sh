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
      if ! backup "$pip_cache_dir" "pip_cache"; then
        print_error "Backup failed for pip cache. Aborting cleanup to prevent data loss."
        log_message "ERROR" "Backup failed, aborting pip cache cleanup"
        return 1
      fi
      $pip_cmd cache purge 2>&1 | log_message "INFO" || {
        print_error "Failed to clean pip cache"
        return 1
      }
      
      local space_after=$(calculate_size_bytes "$pip_cache_dir")
      total_space_freed=$((space_before - space_after))
      # Validate space_freed is not negative (directory may have grown during cleanup)
      if [[ $total_space_freed -lt 0 ]]; then
        total_space_freed=0
        log_message "WARNING" "Directory size increased during cleanup: $pip_cache_dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
      fi
      track_space_saved "pip Cache" $total_space_freed
      print_success "pip cache cleaned."
      log_message "SUCCESS" "pip cache cleaned (freed $(format_bytes $total_space_freed))"
    fi
  else
    print_warning "pip cache directory not found."
    track_space_saved "pip Cache" 0
  fi
  
  return 0
}

# Size calculation function for sweep
_calculate_pip_cache_size_bytes() {
  local size_bytes=0
  local pip_cmd="pip3"
  if command -v pip &> /dev/null; then
    pip_cmd="pip"
  fi
  if command -v "$pip_cmd" &> /dev/null; then
    local pip_cache_dir=$($pip_cmd cache dir 2>/dev/null || echo "$HOME/Library/Caches/pip")
    if [[ -d "$pip_cache_dir" ]]; then
      size_bytes=$(calculate_size_bytes "$pip_cache_dir" 2>/dev/null || echo "0")
    fi
  fi
  echo "$size_bytes"
}

# Register plugin with size function
register_plugin "pip Cache" "package-managers" "clean_pip_cache" "false" "_calculate_pip_cache_size_bytes"
