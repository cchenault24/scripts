#!/bin/zsh
#
# plugins/development/docker.sh - Docker cache cleanup plugin
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

clean_docker_cache() {
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
  
  if [[ "$MC_DRY_RUN" == "true" ]] || mc_confirm "Are you sure you want to clean Docker cache?"; then
    if [[ "$MC_DRY_RUN" == "true" ]]; then
      print_info "[DRY RUN] Would clean Docker cache"
      print_info "[DRY RUN] Would run: docker system prune -a --volumes -f"
      log_message "DRY_RUN" "Would clean Docker cache"
    else
      log_message "INFO" "Starting Docker cleanup"
      
      # Get disk usage before (parse docker system df output)
      # docker system df shows: TYPE, TOTAL, ACTIVE, SIZE, RECLAIMABLE
      # We want the SIZE column (4th column) for all types
      local docker_size_before=0
      local docker_df_before=$(docker system df --format "table {{.Type}}\t{{.Size}}" 2>/dev/null)
      if [[ -n "$docker_df_before" ]]; then
        # Parse sizes and convert to bytes
        # Format: "TYPE SIZE" where SIZE is like "1.2GB", "500MB", etc.
        while IFS= read -r line; do
          # Skip header line
          [[ "$line" =~ ^TYPE ]] && continue
          local size_str=$(echo "$line" | awk '{print $2}')
          if [[ -n "$size_str" ]]; then
            # Convert size string to bytes
            local size_bytes=0
            if [[ "$size_str" =~ ^([0-9.]+)([KMGT]?B)$ ]]; then
              local num=$(echo "$size_str" | sed -E 's/([KMGT]?B)$//')
              local unit=$(echo "$size_str" | sed -E 's/^[0-9.]+//')
              # Load constants if not already loaded
              if [[ -z "${MC_BYTES_PER_GB:-}" ]]; then
                local MC_BYTES_PER_GB=1073741824
                local MC_BYTES_PER_MB=1048576
                local MC_BYTES_PER_KB=1024
              fi
              case "$unit" in
                GB) size_bytes=$(echo "$num * $MC_BYTES_PER_GB" | awk '{printf "%.0f", $1 * $2}') ;;
                MB) size_bytes=$(echo "$num * $MC_BYTES_PER_MB" | awk '{printf "%.0f", $1 * $2}') ;;
                KB) size_bytes=$(echo "$num * $MC_BYTES_PER_KB" | awk '{printf "%.0f", $1 * $2}') ;;
                B|"") size_bytes=$(echo "$num" | awk '{printf "%.0f", $1}') ;;
              esac
            fi
            docker_size_before=$((docker_size_before + size_bytes))
          fi
        done <<< "$docker_df_before"
      fi
      
      # Note: Docker data is managed internally by Docker and stored in Docker's data directory.
      # Backing up Docker's entire data directory would be extremely large (potentially 100GB+).
      # Docker has its own mechanisms for managing images/containers, and users can restore
      # by re-pulling images. However, for Phase 3 compliance, we attempt to backup Docker's
      # data directory if it exists and is accessible.
      local docker_data_dir=""
      if [[ -d "$HOME/Library/Containers/com.docker.docker/Data" ]]; then
        docker_data_dir="$HOME/Library/Containers/com.docker.docker/Data"
      elif [[ -d "/var/lib/docker" ]] && [[ -w "/var/lib/docker" ]]; then
        docker_data_dir="/var/lib/docker"
      fi
      
      # Attempt backup if Docker data directory is accessible (may be very large)
      if [[ -n "$docker_data_dir" ]]; then
        if ! backup "$docker_data_dir" "docker_data"; then
          print_warning "Backup failed for Docker data directory. Docker cleanup will proceed, but restore may not be possible."
          print_warning "Docker images can be restored by re-pulling them."
          log_message "WARNING" "Backup failed for Docker data directory, proceeding with cleanup"
          # Don't abort - Docker cleanup can proceed without backup (images can be re-pulled)
        fi
      else
        print_warning "Docker data directory not accessible for backup. Docker cleanup will proceed."
        print_warning "Docker images can be restored by re-pulling them."
        log_message "WARNING" "Docker data directory not accessible for backup"
      fi
      
      # Clean unused data
      local docker_output
      docker_output=$(docker system prune -a --volumes -f 2>&1) || {
        print_error "Failed to clean Docker cache"
        log_message "ERROR" "Docker cleanup failed: $docker_output"
        return 1
      }
      # Log docker output if it contains useful information
      if [[ -n "$docker_output" ]]; then
        log_message "INFO" "Docker cleanup output: $docker_output"
      fi
      
      # Get disk usage after
      local docker_size_after=0
      local docker_df_after=$(docker system df --format "table {{.Type}}\t{{.Size}}" 2>/dev/null)
      if [[ -n "$docker_df_after" ]]; then
        while IFS= read -r line; do
          [[ "$line" =~ ^TYPE ]] && continue
          local size_str=$(echo "$line" | awk '{print $2}')
          if [[ -n "$size_str" ]]; then
            local size_bytes=0
            if [[ "$size_str" =~ ^([0-9.]+)([KMGT]?B)$ ]]; then
              local num=$(echo "$size_str" | sed -E 's/([KMGT]?B)$//')
              local unit=$(echo "$size_str" | sed -E 's/^[0-9.]+//')
              # Load constants if not already loaded
              if [[ -z "${MC_BYTES_PER_GB:-}" ]]; then
                local MC_BYTES_PER_GB=1073741824
                local MC_BYTES_PER_MB=1048576
                local MC_BYTES_PER_KB=1024
              fi
              case "$unit" in
                GB) size_bytes=$(echo "$num * $MC_BYTES_PER_GB" | awk '{printf "%.0f", $1 * $2}') ;;
                MB) size_bytes=$(echo "$num * $MC_BYTES_PER_MB" | awk '{printf "%.0f", $1 * $2}') ;;
                KB) size_bytes=$(echo "$num * $MC_BYTES_PER_KB" | awk '{printf "%.0f", $1 * $2}') ;;
                B|"") size_bytes=$(echo "$num" | awk '{printf "%.0f", $1}') ;;
              esac
            fi
            docker_size_after=$((docker_size_after + size_bytes))
          fi
        done <<< "$docker_df_after"
      fi
      
      # Calculate space freed
      local docker_space_freed=$((docker_size_before - docker_size_after))
      # Validate space_freed is not negative
      if [[ $docker_space_freed -lt 0 ]]; then
        docker_space_freed=0
        log_message "WARNING" "Docker size increased during cleanup (before: $(format_bytes $docker_size_before), after: $(format_bytes $docker_size_after))"
      fi
      
      log_message "SUCCESS" "Docker cache cleaned (freed $(format_bytes $docker_space_freed))"
      track_space_saved "Docker Cache" $docker_space_freed
      return 0
    fi
  else
    track_space_saved "Docker Cache" 0
    return 0
  fi
}

# Size calculation function for sweep
# Docker cleanup uses 'docker system prune' which cleans Docker's internal data
# This is different from file system directories. The cleanup function doesn't track
# exact bytes freed (returns 0), so we also return 0 here for consistency.
_calculate_docker_cache_size_bytes() {
  echo "0"
}

# Register plugin with size function
register_plugin "Docker Cache" "development" "clean_docker_cache" "false" "_calculate_docker_cache_size_bytes"
