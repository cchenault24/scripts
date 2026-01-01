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
      backup "$lock" "$(basename "$lock")"
      safe_remove "$lock" "orphaned lockfile $(basename "$lock")"
      total_space_freed=$((total_space_freed + space_before))
    fi
  done
  
  track_space_saved "Corrupted Preference Lockfiles" $total_space_freed
  print_success "Cleaned corrupted preference lockfiles."
}

# Register plugin
register_plugin "Corrupted Preference Lockfiles" "maintenance" "clean_pref_lockfiles" "false"
