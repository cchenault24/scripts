#!/bin/zsh
#
# features/schedule.sh - Scheduling functionality for mac-cleanup
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Generate LaunchAgent plist for scheduling
generate_launchagent() {
  local schedule="$1"  # daily, weekly, monthly
  local script_path="$2"
  local plist_name="com.mac-cleanup.agent"
  local plist_path="$HOME/Library/LaunchAgents/${plist_name}.plist"
  
  # Determine interval based on schedule
  local interval=86400  # daily default
  case "$schedule" in
    daily)
      interval=86400
      ;;
    weekly)
      interval=604800
      ;;
    monthly)
      interval=2592000
      ;;
    *)
      print_error "Invalid schedule: $schedule (must be daily, weekly, or monthly)"
      return 1
      ;;
  esac
  
  # Create LaunchAgent plist
  cat > "$plist_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$plist_name</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>$script_path</string>
    <string>--quiet</string>
  </array>
  <key>StartInterval</key>
  <integer>$interval</integer>
  <key>RunAtLoad</key>
  <false/>
  <key>StandardOutPath</key>
  <string>$HOME/.mac-cleanup-backups/scheduled.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/.mac-cleanup-backups/scheduled-error.log</string>
</dict>
</plist>
EOF
  
  print_success "LaunchAgent plist created at: $plist_path"
  print_info "To activate the schedule, run:"
  print_message "$CYAN" "  launchctl load $plist_path"
  print_info "To remove the schedule, run:"
  print_message "$CYAN" "  launchctl unload $plist_path"
  
  return 0
}

# Setup scheduling
setup_schedule() {
  print_header "Setup Scheduled Cleanup"
  
  print_info "Select a schedule frequency:"
  local schedule=$(echo -e "daily\nweekly\nmonthly" | fzf)
  
  if [[ -z "$schedule" ]]; then
    print_warning "Schedule setup cancelled."
    return 1
  fi
  
  # Get script path
  local script_path="$0"
  if [[ ! "$script_path" =~ ^/ ]]; then
    # Relative path, make it absolute
    script_path="$(cd "$(dirname "$script_path")" && pwd)/$(basename "$script_path")"
  fi
  
  # Select cleanup operations for scheduled runs
  print_info "Select cleanup operations for scheduled runs (space to select, enter to confirm):"
  print_warning "Note: Scheduled runs will use default safe operations."
  
  # Generate LaunchAgent
  if generate_launchagent "$schedule" "$script_path"; then
    print_success "Scheduled cleanup configured for $schedule runs."
    print_info "The cleanup will run automatically every $schedule."
    
    if mc_confirm "Do you want to load the schedule now?"; then
      launchctl load "$HOME/Library/LaunchAgents/com.mac-cleanup.agent.plist" 2>/dev/null && {
        print_success "Schedule activated successfully!"
      } || {
        print_error "Failed to activate schedule. You may need to run: launchctl load $HOME/Library/LaunchAgents/com.mac-cleanup.agent.plist"
      }
    fi
  else
    print_error "Failed to create schedule."
    return 1
  fi
}
