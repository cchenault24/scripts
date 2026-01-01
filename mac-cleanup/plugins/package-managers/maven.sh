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
    
    if [[ "$MC_DRY_RUN" == "true" ]] || gum confirm "Are you sure you want to clean the Maven repository?"; then
      local space_before=$(calculate_size_bytes "$maven_repo_dir")
      
      if [[ "$MC_DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] Would clean Maven repository ($(format_bytes $space_before))"
        log_message "DRY_RUN" "Would clean Maven repository"
      else
        backup "$maven_repo_dir" "maven_repository"
        safe_clean_dir "$maven_repo_dir" "Maven repository"
        local space_after=$(calculate_size_bytes "$maven_repo_dir")
        total_space_freed=$((space_before - space_after))
        track_space_saved "Maven Cache" $total_space_freed
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
