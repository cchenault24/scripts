#!/bin/zsh
#
# plugins/package-managers/maven.sh - Maven cache cleanup plugin
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

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
        safe_clean_dir "$maven_repo_dir" "Maven repository" || {
          print_error "Failed to clean Maven repository"
          return 1
        }
        
        local space_after=$(calculate_size_bytes "$maven_repo_dir")
        total_space_freed=$((space_before - space_after))
        # Validate space_freed is not negative (directory may have grown during cleanup)
        if [[ $total_space_freed -lt 0 ]]; then
          total_space_freed=0
          log_message "WARNING" "Directory size increased during cleanup: $maven_repo_dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
        fi
        # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we only track per-operation
        track_space_saved "Maven Cache" $total_space_freed "true"
        print_success "Maven repository cleaned."
        log_message "SUCCESS" "Maven repository cleaned (freed $(format_bytes $total_space_freed))"
      fi
    else
      print_info "Skipping Maven cache cleanup"
      track_space_saved "Maven Cache" 0
    fi
  else
    print_warning "Maven repository not found."
    track_space_saved "Maven Cache" 0
  fi
  
  return 0
}

# Size calculation function for sweep
_calculate_maven_cache_size_bytes() {
  local size_bytes=0
  if [[ -d "$HOME/.m2/repository" ]]; then
    size_bytes=$(calculate_size_bytes "$HOME/.m2/repository" 2>/dev/null || echo "0")
  fi
  echo "$size_bytes"
}

# Register plugin with size function
register_plugin "Maven Cache" "package-managers" "clean_maven_cache" "false" "_calculate_maven_cache_size_bytes"
