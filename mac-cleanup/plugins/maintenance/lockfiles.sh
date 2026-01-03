#!/bin/zsh
#
# plugins/maintenance/lockfiles.sh - Corrupted preference lockfiles cleanup plugin
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

clean_pref_lockfiles() {
  local plist_locks=($(find "$HOME/Library/Preferences" -name "*.plist.lockfile" 2>/dev/null))
  local total_space_freed=0
  
  if [[ ${#plist_locks[@]} -eq 0 ]]; then
    print_warning "No preference lockfiles found."
    track_space_saved "Corrupted Preference Lockfiles" 0
    return 0
  fi
  
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
      safe_remove "$lock" "orphaned lockfile $(basename "$lock")" || {
        print_error "Failed to remove lockfile $(basename "$lock")"
        return 1
      }
      # safe_remove already updates MC_TOTAL_SPACE_SAVED, so we track per-operation separately
      total_space_freed=$((total_space_freed + space_before))
    fi
  done
  
  # safe_remove already updates MC_TOTAL_SPACE_SAVED, so we only track per-operation
  # We pass "true" to skip updating the total to avoid double-counting
  track_space_saved "Corrupted Preference Lockfiles" $total_space_freed "true"
  print_success "Cleaned corrupted preference lockfiles."
  return 0
}

# Size calculation function for sweep
_calculate_pref_lockfiles_size_bytes() {
  local size_bytes=0
  local lockfile_size=0
  local lockfile_locations=(
    "$HOME/Library/Preferences"
    "$HOME/Library/Application Support"
  )
  for location in "${lockfile_locations[@]}"; do
    if [[ -d "$location" ]]; then
      while IFS= read -r lockfile; do
        if [[ -f "$lockfile" ]]; then
          local file_size=$(calculate_size_bytes "$lockfile" 2>/dev/null || echo "0")
          [[ "$file_size" =~ ^[0-9]+$ ]] && lockfile_size=$((lockfile_size + file_size))
        fi
      done < <(find "$location" -name "*.lock" -type f 2>/dev/null | head -100)
    fi
  done
  size_bytes=$lockfile_size
  echo "$size_bytes"
}

# Register plugin with size function
register_plugin "Corrupted Preference Lockfiles" "maintenance" "clean_pref_lockfiles" "false" "_calculate_pref_lockfiles_size_bytes"
