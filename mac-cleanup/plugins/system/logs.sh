#!/bin/zsh
#
# plugins/system/logs.sh - Application and system logs cleanup plugin
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

clean_app_logs() {
  print_header "Cleaning Application Logs"
  
  local logs_dir="$HOME/Library/Logs"
  local space_before=$(calculate_size_bytes "$logs_dir")
  
  if ! backup "$logs_dir" "application_logs"; then
    print_error "Backup failed for application logs. Aborting cleanup to prevent data loss."
    log_message "ERROR" "Backup failed, aborting application logs cleanup"
    return 1
  fi
  
  # Collect all log directories first
  local log_dirs=()
  while IFS= read -r dir; do
    [[ -n "$dir" && -d "$dir" ]] && log_dirs+=("$dir")
  done < <(find "$logs_dir" -maxdepth 1 -type d ! -path "$logs_dir" 2>/dev/null)
  
  # Early exit if no log directories found
  if [[ ${#log_dirs[@]} -eq 0 ]]; then
    print_info "No log directories found to clean."
    track_space_saved "Application Logs" 0
    return 0
  fi
  
  local total_items=${#log_dirs[@]}
  local current_item=0
  
  for dir in "${log_dirs[@]}"; do
    current_item=$((current_item + 1))
    local dir_name=$(basename "$dir")
    update_operation_progress $current_item $total_items "$dir_name"
    safe_clean_dir "$dir" "$dir_name logs" || {
      print_error "Failed to clean $dir_name logs"
      return 1
    }
  done
  
  # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we calculate total for display only
  # Invalidate cache first to ensure fresh calculation
  invalidate_size_cache "$logs_dir"
  local space_after=$(calculate_size_bytes "$logs_dir")
  local space_freed=$((space_before - space_after))
  
  # Validate space_freed is not negative
  if [[ $space_freed -lt 0 ]]; then
    space_freed=0
    log_message "WARNING" "Directory size increased during cleanup: $logs_dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
  fi
  
  # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we only track per-operation
  track_space_saved "Application Logs" $space_freed "true"
  
  print_success "Application logs cleaned."
  return 0
}

clean_system_logs() {
  print_header "Cleaning System Logs"
  
  print_warning "⚠️ CAUTION: System logs can be important for troubleshooting system issues"
  print_warning "Only proceed if you understand the potential consequences"
  
  # Check if we're in an interactive environment
  local is_interactive=false
  if [[ -t 0 ]] && [[ -t 1 ]]; then
    is_interactive=true
  fi
  
  # In non-interactive mode (background process), skip confirmations since user already selected this
  local should_proceed=false
  if [[ "$MC_DRY_RUN" == "true" ]]; then
    should_proceed=true
  elif [[ "$is_interactive" == "true" ]]; then
    if mc_confirm "Are you sure you want to clean system logs?"; then
      print_warning "This operation requires administrative privileges"
      if mc_confirm "Do you want to continue?"; then
        should_proceed=true
      fi
    fi
  else
    # Non-interactive: user already selected this, so proceed
    # But still show the warning
    print_warning "This operation requires administrative privileges"
    print_info "Proceeding with system logs cleanup (non-interactive mode)"
    should_proceed=true
  fi
  
  if [[ "$should_proceed" == "true" ]]; then
    local logs_dir="/var/log"
    local space_before=0
    
    if [[ "$MC_DRY_RUN" != "true" ]]; then
      # SAFE-6: Properly quote logs_dir to prevent command injection
      local escaped_logs_dir_size=$(printf '%q' "$logs_dir")
      space_before=$(sudo -n sh -c "du -sk $escaped_logs_dir_size 2>/dev/null | awk '{print \$1 * 1024}'" 2>&1 || echo "0")
    fi
    
    if ! backup "$logs_dir" "system_logs"; then
      print_error "Backup failed for system logs. Aborting cleanup to prevent data loss."
      log_message "ERROR" "Backup failed, aborting system logs cleanup"
      return 1
    fi
    
    if [[ "$MC_DRY_RUN" == "true" ]]; then
      print_info "[DRY RUN] Would clean system logs"
      log_message "DRY_RUN" "Would clean system logs"
    else
      # Clean log files without removing them (zero their size instead)
      # Properly escape logs_dir to prevent command injection - use printf %q for safe escaping
      local escaped_logs_dir=$(printf '%q' "$logs_dir")
      run_as_admin "find $escaped_logs_dir -type f -name '*.log' -exec truncate -s 0 {} + 2>/dev/null" "system logs cleanup (current logs)" || {
        print_error "Failed to clean current system logs"
        return 1
      }
      
      # Clean archived logs
      # Backup is already done at line 106, but ensure backup is called immediately before this operation
      if ! backup "$logs_dir" "system_logs_archived"; then
        print_error "Backup failed before cleaning archived logs. Aborting."
        return 1
      fi
      run_as_admin "find $escaped_logs_dir -type f -name '*.log.*' -delete 2>/dev/null" "system logs cleanup (archived logs)" || {
        print_error "Failed to clean archived system logs"
        return 1
      }
      
      # SAFE-6: Properly quote logs_dir to prevent command injection
      local escaped_logs_dir_after=$(printf '%q' "$logs_dir")
      local space_after=$(sudo -n sh -c "du -sk $escaped_logs_dir_after 2>/dev/null | awk '{print \$1 * 1024}'" 2>&1 || echo "0")
      local space_freed=$((space_before - space_after))
      
      # Validate space_freed is not negative
      if [[ $space_freed -lt 0 ]]; then
        space_freed=0
        log_message "WARNING" "Directory size increased during cleanup: $logs_dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
      fi
      
      track_space_saved "System Logs" $space_freed
      
      print_success "System logs cleaned."
    fi
  else
    print_info "Skipping system logs cleanup"
  fi
}

# Size calculation functions for sweep
_calculate_app_logs_size_bytes() {
  local size_bytes=0
  if [[ -d "$HOME/Library/Logs" ]]; then
    size_bytes=$(calculate_size_bytes "$HOME/Library/Logs" 2>/dev/null || echo "0")
  fi
  echo "$size_bytes"
}

_calculate_system_logs_size_bytes() {
  local size_bytes=0
  if [[ -d "/var/log" ]]; then
    # Calculate size of only .log files (matching what cleanup actually removes/truncates)
    local find_output=$(find "/var/log" -type f \( -name "*.log" -o -name "*.log.*" \) -exec du -sk {} + 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
    if [[ -n "$find_output" && "$find_output" =~ ^[0-9]+$ ]]; then
      size_bytes=$(echo "$find_output * 1024" | awk '{printf "%.0f", $1 * $2}')
      [[ ! "$size_bytes" =~ ^[0-9]+$ ]] && size_bytes=0
    fi
  fi
  echo "$size_bytes"
}

# Register plugins with size functions
register_plugin "Application Logs" "system" "clean_app_logs" "false" "_calculate_app_logs_size_bytes"
register_plugin "System Logs" "system" "clean_system_logs" "true" "_calculate_system_logs_size_bytes"
