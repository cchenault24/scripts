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
      track_space_saved "System Cache" 0
      return 0
    else
      # Properly escape cache_dir to prevent command injection - use printf %q for safe escaping
      local escaped_cache_dir=$(printf '%q' "$cache_dir")
      run_as_admin "find $escaped_cache_dir -maxdepth 1 -type d ! -path $escaped_cache_dir -exec rm -rf {} + 2>/dev/null" "system cache cleanup" || {
        print_error "Failed to clean system cache"
        return 1
      }
      
      local space_after=$(sudo sh -c "du -sk $cache_dir 2>/dev/null | awk '{print \$1 * 1024}'" || echo "0")
      local space_freed=$((space_before - space_after))
      
      # Validate space_freed is not negative
      if [[ $space_freed -lt 0 ]]; then
        space_freed=0
        log_message "WARNING" "Directory size increased during cleanup: $cache_dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
      fi
      
      track_space_saved "System Cache" $space_freed
      
      print_success "System cache cleaned."
      return 0
    fi
  else
    print_info "Skipping system cache cleanup"
    track_space_saved "System Cache" 0
    return 0
  fi
}

# Size calculation function for sweep
_calculate_system_cache_size_bytes() {
  local size_bytes=0
  if [[ -d "/Library/Caches" ]]; then
    # Requires sudo for system directories, but we can try without for size calculation
    size_bytes=$(sudo sh -c "du -sk /Library/Caches 2>/dev/null | awk '{print \$1 * 1024}'" 2>/dev/null || echo "0")
  fi
  echo "$size_bytes"
}

# Register plugin with size function
register_plugin "System Cache" "system" "clean_system_cache" "true" "_calculate_system_cache_size_bytes"
