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
    backup "$gradle_cache_dir" "gradle_cache"
    safe_clean_dir "$gradle_cache_dir" "Gradle cache"
    local space_after=$(calculate_size_bytes "$gradle_cache_dir")
    total_space_freed=$((total_space_freed + space_before - space_after))
    print_success "Cleaned Gradle cache."
  fi
  
  if [[ -d "$gradle_wrapper_dir" ]]; then
    local space_before=$(calculate_size_bytes "$gradle_wrapper_dir")
    backup "$gradle_wrapper_dir" "gradle_wrapper"
    safe_clean_dir "$gradle_wrapper_dir" "Gradle wrapper"
    local space_after=$(calculate_size_bytes "$gradle_wrapper_dir")
    total_space_freed=$((total_space_freed + space_before - space_after))
    print_success "Cleaned Gradle wrapper cache."
  fi
  
  if [[ $total_space_freed -eq 0 ]]; then
    print_warning "Gradle cache not found."
  else
    track_space_saved "Gradle Cache" $total_space_freed
  fi
}

# Register plugin
register_plugin "Gradle Cache" "package-managers" "clean_gradle_cache" "false"
