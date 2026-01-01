#!/bin/zsh
#
# plugins/package-managers/homebrew.sh - Homebrew cache cleanup plugin
#

clean_homebrew_cache() {
  print_header "Cleaning Homebrew Cache"
  
  if ! command -v brew &> /dev/null; then
    print_warning "Homebrew is not installed."
    return
  fi
  
  if [[ "$MC_DRY_RUN" == "true" ]]; then
    print_info "[DRY RUN] Would clean Homebrew cache"
    log_message "DRY_RUN" "Would clean Homebrew cache"
  else
    print_info "Cleaning Homebrew cache..."
    log_message "INFO" "Cleaning Homebrew cache"
    
    brew cleanup -s 2>&1 | log_message "INFO"
    
    print_success "Homebrew cache cleaned."
    log_message "SUCCESS" "Homebrew cache cleaned"
  fi
}

# Register plugin
register_plugin "Homebrew Cache" "package-managers" "clean_homebrew_cache" "false"
