#!/bin/zsh
#
# plugins/development/docker.sh - Docker cache cleanup plugin
#

clean_docker_cache() {
  print_header "Cleaning Docker Cache"
  
  if ! command -v docker &> /dev/null; then
    print_warning "Docker is not installed."
    return
  fi
  
  if ! docker info &> /dev/null; then
    print_warning "Docker is not running. Please start Docker Desktop and try again."
    return
  fi
  
  print_warning "This will remove unused Docker images, containers, volumes, and build cache."
  print_warning "This may require re-downloading images and rebuilding containers."
  
  if [[ "$MC_DRY_RUN" == "true" ]] || gum confirm "Are you sure you want to clean Docker cache?"; then
    if [[ "$MC_DRY_RUN" == "true" ]]; then
      print_info "[DRY RUN] Would clean Docker cache"
      print_info "[DRY RUN] Would run: docker system prune -a --volumes -f"
      log_message "DRY_RUN" "Would clean Docker cache"
    else
      print_info "Cleaning Docker cache (this may take a while)..."
      log_message "INFO" "Starting Docker cleanup"
      
      # Get disk usage before
      local docker_info=$(docker system df --format "{{.Size}}" 2>/dev/null | head -1)
      
      # Clean unused data
      docker system prune -a --volumes -f 2>&1 | log_message "INFO"
      
      # Get disk usage after
      local docker_info_after=$(docker system df --format "{{.Size}}" 2>/dev/null | head -1)
      
      print_success "Docker cache cleaned."
      log_message "SUCCESS" "Docker cache cleaned"
      track_space_saved "Docker Cache" 0  # Docker doesn't report exact bytes freed easily
    fi
  else
    print_info "Skipping Docker cache cleanup"
  fi
}

# Register plugin
register_plugin "Docker Cache" "development" "clean_docker_cache" "false"
