#!/bin/zsh
#
# plugins/package-managers/npm.sh - npm/yarn cache cleanup plugin
#

clean_npm_cache() {
  print_header "Cleaning npm Cache"
  
  if ! command -v npm &> /dev/null; then
    print_warning "npm is not installed."
    return
  fi
  
  local total_space_freed=0
  local npm_cache_dir=$(npm config get cache 2>/dev/null || echo "$HOME/.npm")
  
  if [[ -d "$npm_cache_dir" ]]; then
    local space_before=$(calculate_size_bytes "$npm_cache_dir")
    
    if [[ "$MC_DRY_RUN" == "true" ]]; then
      print_info "[DRY RUN] Would clean npm cache ($(format_bytes $space_before))"
      log_message "DRY_RUN" "Would clean npm cache"
    else
      if ! backup "$npm_cache_dir" "npm_cache"; then
        print_error "Backup failed for npm cache. Aborting cleanup to prevent data loss."
        log_message "ERROR" "Backup failed, aborting npm cache cleanup"
        return 1
      fi
      npm cache clean --force 2>&1 | log_message "INFO"
      local space_after=$(calculate_size_bytes "$npm_cache_dir")
      total_space_freed=$((space_before - space_after))
      # Validate space_freed is not negative (directory may have grown during cleanup)
      if [[ $total_space_freed -lt 0 ]]; then
        total_space_freed=0
        log_message "WARNING" "Directory size increased during cleanup: $npm_cache_dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
      fi
      track_space_saved "npm Cache" $total_space_freed
      print_success "npm cache cleaned."
      log_message "SUCCESS" "npm cache cleaned (freed $(format_bytes $total_space_freed))"
    fi
  else
    print_warning "npm cache directory not found."
  fi
  
  # Clean yarn cache if available
  if command -v yarn &> /dev/null; then
    local yarn_cache_dir=$(yarn cache dir 2>/dev/null || echo "$HOME/.yarn/cache")
    if [[ -d "$yarn_cache_dir" ]]; then
      local space_before=$(calculate_size_bytes "$yarn_cache_dir")
      
      if [[ "$MC_DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] Would clean yarn cache ($(format_bytes $space_before))"
        log_message "DRY_RUN" "Would clean yarn cache"
      else
        if ! backup "$yarn_cache_dir" "yarn_cache"; then
          print_error "Backup failed for yarn cache. Skipping this directory."
          log_message "ERROR" "Backup failed for yarn cache, skipping"
        else
          yarn cache clean 2>&1 | log_message "INFO"
        local space_after=$(calculate_size_bytes "$yarn_cache_dir")
        local yarn_space_freed=$((space_before - space_after))
        # Validate space_freed is not negative (directory may have grown during cleanup)
        if [[ $yarn_space_freed -lt 0 ]]; then
          yarn_space_freed=0
          log_message "WARNING" "Directory size increased during cleanup: $yarn_cache_dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
        fi
          total_space_freed=$((total_space_freed + yarn_space_freed))
          track_space_saved "npm Cache" $total_space_freed
          print_success "yarn cache cleaned."
          log_message "SUCCESS" "yarn cache cleaned (freed $(format_bytes $yarn_space_freed))"
        fi
      fi
    fi
  fi
}

# Register plugin
register_plugin "npm Cache" "package-managers" "clean_npm_cache" "false"
