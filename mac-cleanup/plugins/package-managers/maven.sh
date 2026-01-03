#!/bin/zsh
#
# plugins/package-managers/maven.sh - Maven cache cleanup plugin
#

clean_maven_cache() {
  print_header "Cleaning Maven Cache"
  
  local maven_repo_dir="$HOME/.m2/repository"
  local total_space_freed=0
  
  if [[ -d "$maven_repo_dir" ]]; then
    print_warning "Cleaning Maven repository will require re-downloading dependencies on next build."
    
    if [[ "$MC_DRY_RUN" == "true" ]] || mc_confirm "Are you sure you want to clean the Maven repository?"; then
      local space_before=$(calculate_size_bytes "$maven_repo_dir")
      
      if [[ "$MC_DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] Would clean Maven repository ($(format_bytes $space_before))"
        log_message "DRY_RUN" "Would clean Maven repository"
      else
        if ! backup "$maven_repo_dir" "maven_repository"; then
          print_error "Backup failed for Maven repository. Aborting cleanup to prevent data loss."
          log_message "ERROR" "Backup failed, aborting Maven cache cleanup"
          return 1
        fi
        safe_clean_dir "$maven_repo_dir" "Maven repository"
        local space_after=$(calculate_size_bytes "$maven_repo_dir")
        total_space_freed=$((space_before - space_after))
        # Validate space_freed is not negative (directory may have grown during cleanup)
        if [[ $total_space_freed -lt 0 ]]; then
          total_space_freed=0
          log_message "WARNING" "Directory size increased during cleanup: $maven_repo_dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
        fi
        # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we only update plugin-specific tracking
        MC_SPACE_SAVED_BY_OPERATION["Maven Cache"]=$total_space_freed
        # Write to space tracking file if in background process (with locking)
        if [[ -n "${MC_SPACE_TRACKING_FILE:-}" && -f "$MC_SPACE_TRACKING_FILE" ]]; then
          _write_space_tracking_file "Maven Cache" "$total_space_freed"
        fi
        print_success "Maven repository cleaned."
        log_message "SUCCESS" "Maven repository cleaned (freed $(format_bytes $total_space_freed))"
      fi
    else
      print_info "Skipping Maven cache cleanup"
    fi
  else
    print_warning "Maven repository not found."
  fi
}

# Register plugin
register_plugin "Maven Cache" "package-managers" "clean_maven_cache" "false"
