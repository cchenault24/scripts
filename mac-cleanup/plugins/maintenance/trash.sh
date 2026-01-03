#!/bin/zsh
#
# plugins/maintenance/trash.sh - Empty Trash plugin
#

empty_trash() {
  print_header "Emptying Trash"
  
  local trash_dir="$HOME/.Trash"
  
  if [[ -d "$trash_dir" && "$(ls -A "$trash_dir" 2>/dev/null)" ]]; then
    local space_before=$(calculate_size_bytes "$trash_dir")
    print_warning "This will permanently delete all items in your Trash"
    if [[ "$MC_DRY_RUN" == "true" ]] || mc_confirm "Are you sure you want to empty the Trash?"; then
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
        safe_clean_dir "$trash_dir" "Trash"
        # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we only update plugin-specific tracking
        MC_SPACE_SAVED_BY_OPERATION["Empty Trash"]=$space_before
        # Write to space tracking file if in background process (with locking)
        if [[ -n "${MC_SPACE_TRACKING_FILE:-}" && -f "$MC_SPACE_TRACKING_FILE" ]]; then
          _write_space_tracking_file "Empty Trash" "$space_before"
        fi
        print_success "Trash emptied."
        log_message "SUCCESS" "Emptied Trash (freed $(format_bytes $space_before))"
      fi
    else
      print_info "Skipping Trash cleanup"
    fi
  else
    print_info "Trash is already empty"
  fi
}

# Register plugin
register_plugin "Empty Trash" "maintenance" "empty_trash" "false"
