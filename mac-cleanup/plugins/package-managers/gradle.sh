#!/bin/zsh
#
# plugins/package-managers/gradle.sh - Gradle cache cleanup plugin
#

clean_gradle_cache() {
  print_header "Cleaning Gradle Cache"
  
  local gradle_cache_dir="$HOME/.gradle/caches"
  local gradle_wrapper_dir="$HOME/.gradle/wrapper"
  local total_space_freed=0
  
  if [[ -d "$gradle_cache_dir" ]]; then
    local space_before=$(calculate_size_bytes "$gradle_cache_dir")
    if ! backup "$gradle_cache_dir" "gradle_cache"; then
      print_error "Backup failed for Gradle cache. Aborting cleanup to prevent data loss."
      log_message "ERROR" "Backup failed, aborting Gradle cache cleanup"
      return 1
    fi
    safe_clean_dir "$gradle_cache_dir" "Gradle cache"
    local space_after=$(calculate_size_bytes "$gradle_cache_dir")
    local space_freed=$((space_before - space_after))
    # Validate space_freed is not negative (directory may have grown during cleanup)
    if [[ $space_freed -lt 0 ]]; then
      space_freed=0
      log_message "WARNING" "Directory size increased during cleanup: $gradle_cache_dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
    fi
    total_space_freed=$((total_space_freed + space_freed))
    print_success "Cleaned Gradle cache."
  fi
  
  if [[ -d "$gradle_wrapper_dir" ]]; then
    local space_before=$(calculate_size_bytes "$gradle_wrapper_dir")
    if ! backup "$gradle_wrapper_dir" "gradle_wrapper"; then
      print_error "Backup failed for Gradle wrapper. Aborting cleanup to prevent data loss."
      log_message "ERROR" "Backup failed, aborting Gradle wrapper cleanup"
      return 1
    fi
    safe_clean_dir "$gradle_wrapper_dir" "Gradle wrapper"
    local space_after=$(calculate_size_bytes "$gradle_wrapper_dir")
    local space_freed=$((space_before - space_after))
    # Validate space_freed is not negative (directory may have grown during cleanup)
    if [[ $space_freed -lt 0 ]]; then
      space_freed=0
      log_message "WARNING" "Directory size increased during cleanup: $gradle_wrapper_dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
    fi
    total_space_freed=$((total_space_freed + space_freed))
    print_success "Cleaned Gradle wrapper cache."
  fi
  
  if [[ $total_space_freed -eq 0 ]]; then
    print_warning "Gradle cache not found."
  else
    # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we only update plugin-specific tracking
    MC_SPACE_SAVED_BY_OPERATION["Gradle Cache"]=$total_space_freed
    # Write to space tracking file if in background process (with locking)
    if [[ -n "${MC_SPACE_TRACKING_FILE:-}" && -f "$MC_SPACE_TRACKING_FILE" ]]; then
      _write_space_tracking_file "Gradle Cache" "$total_space_freed"
    fi
  fi
}

# Register plugin
register_plugin "Gradle Cache" "package-managers" "clean_gradle_cache" "false"
