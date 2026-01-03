#!/bin/zsh
#
# plugins/system/system_cache.sh - System cache cleanup plugin
#

clean_system_cache() {
  print_header "Cleaning System Cache"
  
  print_warning "This operation requires administrative privileges"
  if [[ "$MC_DRY_RUN" == "true" ]] || mc_confirm "Do you want to continue?"; then
    local cache_dir="/Library/Caches"
    local space_before=0
    
    if [[ "$MC_DRY_RUN" != "true" ]]; then
      # Get size before cleanup (requires sudo)
      space_before=$(sudo sh -c "du -sk $cache_dir 2>/dev/null | awk '{print \$1 * 1024}'" || echo "0")
    fi
    
    if ! backup "$cache_dir" "system_caches"; then
      print_error "Backup failed for system cache. Aborting cleanup to prevent data loss."
      log_message "ERROR" "Backup failed, aborting system cache cleanup"
      return 1
    fi
    
    if [[ "$MC_DRY_RUN" == "true" ]]; then
      print_info "[DRY RUN] Would clean system cache"
      log_message "DRY_RUN" "Would clean system cache"
    else
      # Properly escape cache_dir to prevent command injection - use printf %q for safe escaping
      local escaped_cache_dir=$(printf '%q' "$cache_dir")
      run_as_admin "find $escaped_cache_dir -maxdepth 1 -type d ! -path $escaped_cache_dir -exec rm -rf {} + 2>/dev/null || true" "system cache cleanup"
      
      local space_after=$(sudo sh -c "du -sk $cache_dir 2>/dev/null | awk '{print \$1 * 1024}'" || echo "0")
      local space_freed=$((space_before - space_after))
      
      # Validate space_freed is not negative
      if [[ $space_freed -lt 0 ]]; then
        space_freed=0
        log_message "WARNING" "Directory size increased during cleanup: $cache_dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
      fi
      
      track_space_saved "System Cache" $space_freed
      
      print_success "System cache cleaned."
    fi
  else
    print_info "Skipping system cache cleanup"
  fi
}

# Register plugin
register_plugin "System Cache" "system" "clean_system_cache" "true"
