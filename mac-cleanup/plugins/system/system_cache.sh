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
    
    backup "$cache_dir" "system_caches"
    
    if [[ "$MC_DRY_RUN" == "true" ]]; then
      print_info "[DRY RUN] Would clean system cache"
      log_message "DRY_RUN" "Would clean system cache"
    else
      # Properly escape cache_dir to prevent command injection
      run_as_admin "find \"$cache_dir\" -maxdepth 1 -type d ! -path \"$cache_dir\" -exec rm -rf {} + 2>/dev/null || true" "system cache cleanup"
      
      local space_after=$(sudo sh -c "du -sk $cache_dir 2>/dev/null | awk '{print \$1 * 1024}'" || echo "0")
      local space_freed=$((space_before - space_after))
      track_space_saved "System Cache" $space_freed
      
      print_success "System cache cleaned."
    fi
  else
    print_info "Skipping system cache cleanup"
  fi
}

# Register plugin
register_plugin "System Cache" "system" "clean_system_cache" "true"
