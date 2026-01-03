#!/bin/zsh
#
# plugins/maintenance/lockfiles.sh - Corrupted preference lockfiles cleanup plugin
#

clean_pref_lockfiles() {
  print_header "Cleaning Corrupted Preference Lockfiles"
  
  local plist_locks=($(find "$HOME/Library/Preferences" -name "*.plist.lockfile" 2>/dev/null))
  local total_space_freed=0
  
  if [[ ${#plist_locks[@]} -eq 0 ]]; then
    print_warning "No preference lockfiles found."
    return
  fi
  
  print_info "Found ${#plist_locks[@]} preference lockfiles"
  
  for lock in "${plist_locks[@]}"; do
    local plist_file="${lock%.lockfile}"
    
    # Check if the plist file exists
    if [[ ! -f "$plist_file" ]]; then
      local space_before=$(calculate_size_bytes "$lock")
      if ! backup "$lock" "$(basename "$lock")"; then
        print_error "Backup failed for lockfile $(basename "$lock"). Skipping this file."
        log_message "ERROR" "Backup failed for lockfile $(basename "$lock"), skipping"
        continue
      fi
      safe_remove "$lock" "orphaned lockfile $(basename "$lock")"
      total_space_freed=$((total_space_freed + space_before))
    fi
  done
  
  # safe_remove already updates MC_TOTAL_SPACE_SAVED, so we only update plugin-specific tracking
  MC_SPACE_SAVED_BY_OPERATION["Corrupted Preference Lockfiles"]=$total_space_freed
  # Write to space tracking file if in background process (with locking)
  if [[ -n "${MC_SPACE_TRACKING_FILE:-}" && -f "$MC_SPACE_TRACKING_FILE" ]]; then
    _write_space_tracking_file "Corrupted Preference Lockfiles" "$total_space_freed"
  fi
  print_success "Cleaned corrupted preference lockfiles."
}

# Register plugin
register_plugin "Corrupted Preference Lockfiles" "maintenance" "clean_pref_lockfiles" "false"
