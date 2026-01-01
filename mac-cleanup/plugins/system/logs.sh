#!/bin/zsh
#
# plugins/system/logs.sh - Application and system logs cleanup plugin
#

clean_app_logs() {
  print_header "Cleaning Application Logs"
  
  local logs_dir="$HOME/Library/Logs"
  local space_before=$(calculate_size_bytes "$logs_dir")
  
  backup "$logs_dir" "application_logs"
  find "$logs_dir" -maxdepth 1 -type d ! -path "$logs_dir" | while read dir; do
    safe_clean_dir "$dir" "$(basename "$dir") logs"
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
  
  if [[ "$MC_DRY_RUN" == "true" ]] || gum confirm "Are you sure you want to clean system logs?"; then
    print_warning "This operation requires administrative privileges"
    
    if [[ "$MC_DRY_RUN" == "true" ]] || gum confirm "Do you want to continue?"; then
      local logs_dir="/var/log"
      local space_before=0
      
      if [[ "$MC_DRY_RUN" != "true" ]]; then
        space_before=$(sudo sh -c "du -sk $logs_dir 2>/dev/null | awk '{print \$1 * 1024}'" || echo "0")
      fi
      
      backup "$logs_dir" "system_logs"
      
      if [[ "$MC_DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] Would clean system logs"
        log_message "DRY_RUN" "Would clean system logs"
      else
        # Clean log files without removing them (zero their size instead)
        run_as_admin "find $logs_dir -type f -name \"*.log\" -exec truncate -s 0 {} + 2>/dev/null || true" "system logs cleanup (current logs)"
        
        # Clean archived logs
        run_as_admin "find $logs_dir -type f -name \"*.log.*\" -delete 2>/dev/null || true" "system logs cleanup (archived logs)"
        
        local space_after=$(sudo sh -c "du -sk $logs_dir 2>/dev/null | awk '{print \$1 * 1024}'" || echo "0")
        local space_freed=$((space_before - space_after))
        track_space_saved "System Logs" $space_freed
        
        print_success "System logs cleaned."
      fi
    else
      print_info "Skipping system logs cleanup"
    fi
  else
    print_info "Skipping system logs cleanup"
  fi
}

# Register plugins
register_plugin "Application Logs" "system" "clean_app_logs" "false"
register_plugin "System Logs" "system" "clean_system_logs" "true"
