#!/bin/zsh
#
# plugins/package-managers/homebrew.sh - Homebrew cache cleanup plugin
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

clean_homebrew_cache() {
  print_header "Cleaning Homebrew Cache"
  
  if ! command -v brew &> /dev/null; then
    print_warning "Homebrew is not installed."
    print_info "To install Homebrew: Visit https://brew.sh or run: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    track_space_saved "Homebrew Cache" 0
    return 0
  fi
  
  local brew_cache_dirs=(
    "$(brew --cache 2>/dev/null || echo "$HOME/Library/Caches/Homebrew")"
    "$HOME/Library/Caches/Homebrew"
  )
  
  local space_before=0
  for cache_dir in "${brew_cache_dirs[@]}"; do
    if [[ -d "$cache_dir" ]]; then
      space_before=$(calculate_size_bytes "$cache_dir" 2>/dev/null || echo "0")
      break
    fi
  done
  
  if [[ "$MC_DRY_RUN" == "true" ]]; then
    print_info "[DRY RUN] Would clean Homebrew cache ($(format_bytes $space_before))"
    log_message "DRY_RUN" "Would clean Homebrew cache"
    track_space_saved "Homebrew Cache" 0
    return 0
  else
    # Find the actual cache directory to backup
    local cache_dir_to_backup=""
    for cache_dir in "${brew_cache_dirs[@]}"; do
      if [[ -d "$cache_dir" ]]; then
        cache_dir_to_backup="$cache_dir"
        break
      fi
    done
    
    # Backup cache directory before cleanup
    if [[ -n "$cache_dir_to_backup" ]]; then
      if ! backup "$cache_dir_to_backup" "homebrew_cache"; then
        print_error "Backup failed for Homebrew cache. Aborting cleanup to prevent data loss."
        log_message "ERROR" "Backup failed, aborting Homebrew cache cleanup"
        return 1
      fi
    fi
    
    print_info "Cleaning Homebrew cache..."
    log_message "INFO" "Cleaning Homebrew cache"
    
    brew cleanup -s 2>&1 | log_message "INFO" || {
      print_error "Failed to clean Homebrew cache"
      return 1
    }
    
    local space_after=0
    for cache_dir in "${brew_cache_dirs[@]}"; do
      if [[ -d "$cache_dir" ]]; then
        space_after=$(calculate_size_bytes "$cache_dir" 2>/dev/null || echo "0")
        break
      fi
    done
    
    local space_freed=$((space_before - space_after))
    if [[ $space_freed -lt 0 ]]; then
      space_freed=0
      log_message "WARNING" "Homebrew cache size increased during cleanup (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
    fi
    
    track_space_saved "Homebrew Cache" $space_freed
    print_success "Homebrew cache cleaned."
    log_message "SUCCESS" "Homebrew cache cleaned (freed $(format_bytes $space_freed))"
    return 0
  fi
}

# Size calculation function for sweep
_calculate_homebrew_cache_size_bytes() {
  local size_bytes=0
  if command -v brew &> /dev/null; then
    local brew_cache_dirs=(
      "$(brew --cache 2>/dev/null || echo "$HOME/Library/Caches/Homebrew")"
      "$HOME/Library/Caches/Homebrew"
    )
    for cache_dir in "${brew_cache_dirs[@]}"; do
      if [[ -d "$cache_dir" ]]; then
        size_bytes=$(calculate_size_bytes "$cache_dir" 2>/dev/null || echo "0")
        break
      fi
    done
  fi
  echo "$size_bytes"
}

# Register plugin with size function
register_plugin "Homebrew Cache" "package-managers" "clean_homebrew_cache" "false" "_calculate_homebrew_cache_size_bytes"
