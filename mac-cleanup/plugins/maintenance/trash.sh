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
        rm -rf "$trash_dir"/* "$trash_dir"/.[!.]* 2>/dev/null || true
        print_success "Trash emptied."
        track_space_saved "Empty Trash" $space_before
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
