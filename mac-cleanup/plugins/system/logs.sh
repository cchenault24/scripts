#!/bin/zsh
#
# plugins/system/logs.sh - Application and system logs cleanup plugin
#

clean_app_logs() {
  print_header "Cleaning Application Logs"
  
  local logs_dir="$HOME/Library/Logs"
  local space_before=$(calculate_size_bytes "$logs_dir")
  
  backup "$logs_dir" "application_logs"
  
  # Collect all log directories first
  local log_dirs=()
  while IFS= read -r dir; do
    [[ -n "$dir" && -d "$dir" ]] && log_dirs+=("$dir")
  done < <(find "$logs_dir" -maxdepth 1 -type d ! -path "$logs_dir" 2>/dev/null)
  
  local total_items=${#log_dirs[@]}
  local current_item=0
  
  for dir in "${log_dirs[@]}"; do
    current_item=$((current_item + 1))
    local dir_name=$(basename "$dir")
    update_operation_progress $current_item $total_items "$dir_name"
    safe_clean_dir "$dir" "$dir_name logs"
  done
  
  local space_after=$(calculate_size_bytes "$logs_dir")
  local space_freed=$((space_before - space_after))
  track_space_saved "Application Logs" $space_freed
  
  print_success "Application logs cleaned."
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
      space_before=$(sudo -n sh -c "du -sk $logs_dir 2>/dev/null | awk '{print \$1 * 1024}'" 2>&1 || echo "0")
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
      # Properly escape logs_dir to prevent command injection
      run_as_admin "find \"$logs_dir\" -type f -name '*.log' -exec truncate -s 0 {} + 2>/dev/null || true" "system logs cleanup (current logs)"
      
      # Clean archived logs
      run_as_admin "find \"$logs_dir\" -type f -name '*.log.*' -delete 2>/dev/null || true" "system logs cleanup (archived logs)"
      
      local space_after=$(sudo -n sh -c "du -sk $logs_dir 2>/dev/null | awk '{print \$1 * 1024}'" 2>&1 || echo "0")
      local space_freed=$((space_before - space_after))
      track_space_saved "System Logs" $space_freed
      
      print_success "System logs cleaned."
    fi
  else
    print_info "Skipping system logs cleanup"
  fi
}

# Register plugins
register_plugin "Application Logs" "system" "clean_app_logs" "false"
register_plugin "System Logs" "system" "clean_system_logs" "true"
