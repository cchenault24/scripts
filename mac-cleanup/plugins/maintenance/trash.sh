#!/bin/zsh
#
# plugins/maintenance/trash.sh - Empty Trash plugin
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

empty_trash() {
  print_header "Emptying Trash"
  
  local trash_dir="$HOME/.Trash"
  
  if [[ -d "$trash_dir" && "$(ls -A "$trash_dir" 2>/dev/null)" ]]; then
    local space_before=$(calculate_size_bytes "$trash_dir")
    print_warning "This will permanently delete all items in your Trash"
    # In non-interactive mode, skip confirmation and proceed with cleanup
    if [[ "$MC_DRY_RUN" == "true" ]] || [[ -n "${MC_NON_INTERACTIVE:-}" ]] || mc_confirm "Are you sure you want to empty the Trash?"; then
      if [[ "$MC_DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] Would empty Trash ($(format_bytes $space_before))"
        log_message "DRY_RUN" "Would empty Trash"
      else
        # Use safe_clean_dir for proper error handling and space tracking
        # This ensures proper handling of hidden files, symlinks, and edge cases
        if ! backup "$trash_dir" "trash"; then
          print_error "Backup failed for Trash. Aborting cleanup to prevent data loss."
          log_message "ERROR" "Backup failed, aborting Trash cleanup"
          return 1
        fi
        safe_clean_dir "$trash_dir" "Trash" || {
          print_error "Failed to empty Trash"
          return 1
        }
        
        # Calculate space actually freed (after safe_clean_dir which already updated total)
        local space_after=$(calculate_size_bytes "$trash_dir")
        local space_freed=$((space_before - space_after))
        if [[ $space_freed -lt 0 ]]; then
          space_freed=0
        fi
        
        # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we only track per-operation
        track_space_saved "Empty Trash" $space_freed "true"
        print_success "Trash emptied."
        log_message "SUCCESS" "Emptied Trash (freed $(format_bytes $space_freed))"
      fi
    else
      print_info "Skipping Trash cleanup"
      track_space_saved "Empty Trash" 0
    fi
  else
    print_info "Trash is already empty"
    track_space_saved "Empty Trash" 0
  fi
  
  return 0
}

# Size calculation function for sweep
_calculate_empty_trash_size_bytes() {
  local size_bytes=0
  if [[ -d "$HOME/.Trash" ]]; then
    size_bytes=$(calculate_size_bytes "$HOME/.Trash" 2>/dev/null || echo "0")
  fi
  echo "$size_bytes"
}

# Register plugin with size function
register_plugin "Empty Trash" "maintenance" "empty_trash" "false" "_calculate_empty_trash_size_bytes"
