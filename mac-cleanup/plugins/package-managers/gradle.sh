#!/bin/zsh
#
# plugins/package-managers/gradle.sh - Gradle cache cleanup plugin
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

clean_gradle_cache() {
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
    safe_clean_dir "$gradle_cache_dir" "Gradle cache" || {
      print_error "Failed to clean Gradle cache"
      return 1
    }
    
    local space_after=$(calculate_size_bytes "$gradle_cache_dir")
    local space_freed=$((space_before - space_after))
    # Validate space_freed is not negative (directory may have grown during cleanup)
    if [[ $space_freed -lt 0 ]]; then
      space_freed=0
      log_message "WARNING" "Directory size increased during cleanup: $gradle_cache_dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
    fi
    total_space_freed=$((total_space_freed + space_freed))
  fi
  
  if [[ -d "$gradle_wrapper_dir" ]]; then
    local space_before=$(calculate_size_bytes "$gradle_wrapper_dir")
    if ! backup "$gradle_wrapper_dir" "gradle_wrapper"; then
      print_error "Backup failed for Gradle wrapper. Aborting cleanup to prevent data loss."
      log_message "ERROR" "Backup failed, aborting Gradle wrapper cleanup"
      return 1
    fi
    
    safe_clean_dir "$gradle_wrapper_dir" "Gradle wrapper" || {
      print_error "Failed to clean Gradle wrapper"
      return 1
    }
    
    local space_after=$(calculate_size_bytes "$gradle_wrapper_dir")
    local space_freed=$((space_before - space_after))
    # Validate space_freed is not negative (directory may have grown during cleanup)
    if [[ $space_freed -lt 0 ]]; then
      space_freed=0
      log_message "WARNING" "Directory size increased during cleanup: $gradle_wrapper_dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
    fi
    total_space_freed=$((total_space_freed + space_freed))
  fi
  
  if [[ $total_space_freed -eq 0 ]]; then
    print_warning "Gradle cache not found."
    track_space_saved "Gradle Cache" 0
  else
    # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we only track per-operation
    track_space_saved "Gradle Cache" $total_space_freed "true"
  fi
  
  return 0
}

# Size calculation function for sweep
_calculate_gradle_cache_size_bytes() {
  local size_bytes=0
  local gradle_size=0
  if [[ -d "$HOME/.gradle/caches" ]]; then
    gradle_size=$(calculate_size_bytes "$HOME/.gradle/caches" 2>/dev/null || echo "0")
    [[ "$gradle_size" =~ ^[0-9]+$ ]] && size_bytes=$((size_bytes + gradle_size))
  fi
  if [[ -d "$HOME/.gradle/wrapper" ]]; then
    local wrapper_size=$(calculate_size_bytes "$HOME/.gradle/wrapper" 2>/dev/null || echo "0")
    [[ "$wrapper_size" =~ ^[0-9]+$ ]] && size_bytes=$((size_bytes + wrapper_size))
  fi
  echo "$size_bytes"
}

# Register plugin with size function
register_plugin "Gradle Cache" "package-managers" "clean_gradle_cache" "false" "_calculate_gradle_cache_size_bytes"
