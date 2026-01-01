#!/bin/zsh
#
# mac-cleanup.sh - Interactive macOS system cleanup utility
# 
# Modular, plugin-based architecture for easy extension and maintenance
#
# Author: Generated with Claude
# Date: March 24, 2025
# License: MIT
#

# Get script directory and name
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-${(%):-%x}}")"

# Load core libraries
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/admin.sh"
source "$SCRIPT_DIR/lib/backup.sh"

# Load plugin base
source "$SCRIPT_DIR/plugins/base.sh"

# Sync global variables for backward compatibility
sync_globals() {
  BACKUP_DIR="$MC_BACKUP_DIR"
  DRY_RUN="$MC_DRY_RUN"
  QUIET_MODE="$MC_QUIET_MODE"
  LOG_FILE="$MC_LOG_FILE"
  TOTAL_SPACE_SAVED=$MC_TOTAL_SPACE_SAVED
  # Copy associative array
  SPACE_SAVED_BY_OPERATION=()
  for key in "${(@k)MC_SPACE_SAVED_BY_OPERATION}"; do
    SPACE_SAVED_BY_OPERATION["$key"]="${MC_SPACE_SAVED_BY_OPERATION[$key]}"
  done
  GUM_INSTALLED_BY_SCRIPT="$MC_GUM_INSTALLED_BY_SCRIPT"
  ADMIN_USERNAME="$MC_ADMIN_USERNAME"
}

# Discover and load plugins
load_plugins() {
  local plugins_dir="$SCRIPT_DIR/plugins"
  
  # Load browser plugins
  if [[ -d "$plugins_dir/browsers" ]]; then
    for plugin_file in "$plugins_dir/browsers"/*.sh(N); do
      if [[ -f "$plugin_file" ]]; then
        source "$plugin_file"
      fi
    done
  fi
  
  # Load package manager plugins
  if [[ -d "$plugins_dir/package-managers" ]]; then
    for plugin_file in "$plugins_dir/package-managers"/*.sh(N); do
      if [[ -f "$plugin_file" ]]; then
        source "$plugin_file"
      fi
    done
  fi
  
  # Load development plugins
  if [[ -d "$plugins_dir/development" ]]; then
    for plugin_file in "$plugins_dir/development"/*.sh(N); do
      if [[ -f "$plugin_file" ]]; then
        source "$plugin_file"
      fi
    done
  fi
  
  # Load system plugins
  if [[ -d "$plugins_dir/system" ]]; then
    for plugin_file in "$plugins_dir/system"/*.sh(N); do
      if [[ -f "$plugin_file" ]]; then
        source "$plugin_file"
      fi
    done
  fi
  
  # Load maintenance plugins
  if [[ -d "$plugins_dir/maintenance" ]]; then
    for plugin_file in "$plugins_dir/maintenance"/*.sh(N); do
      if [[ -f "$plugin_file" ]]; then
        source "$plugin_file"
      fi
    done
  fi
}

# Calculate size for a plugin (helper function for menu)
calculate_plugin_size() {
  local plugin_name="$1"
  local size=""
  
  case "$plugin_name" in
    "User Cache")
      size=$(calculate_size "$HOME/Library/Caches")
      ;;
    "System Cache")
      size=$(calculate_size "/Library/Caches")
      ;;
    "Application Logs")
      size=$(calculate_size "$HOME/Library/Logs")
      ;;
    "System Logs")
      size=$(calculate_size "/var/log")
      ;;
    "Temporary Files")
      local temp_size=0
      for temp_dir in "/tmp" "$TMPDIR" "$HOME/Library/Application Support/Temp"; do
        if [[ -d "$temp_dir" ]]; then
          temp_size=$((temp_size + $(calculate_size_bytes "$temp_dir")))
        fi
      done
      size=$(format_bytes $temp_size)
      ;;
    "Safari Cache")
      size=$(calculate_size "$HOME/Library/Caches/com.apple.Safari")
      ;;
    "Chrome Cache")
      local chrome_size=0
      if [[ -d "$HOME/Library/Caches/Google/Chrome" ]]; then
        chrome_size=$(calculate_size_bytes "$HOME/Library/Caches/Google/Chrome")
      fi
      if [[ -d "$HOME/Library/Application Support/Google/Chrome" ]]; then
        for profile_dir in "$HOME/Library/Application Support/Google/Chrome"/*/; do
          if [[ -d "$profile_dir" ]]; then
            chrome_size=$((chrome_size + $(calculate_size_bytes "$profile_dir/Cache" 2>/dev/null || echo "0")))
            chrome_size=$((chrome_size + $(calculate_size_bytes "$profile_dir/Code Cache" 2>/dev/null || echo "0")))
            chrome_size=$((chrome_size + $(calculate_size_bytes "$profile_dir/Service Worker" 2>/dev/null || echo "0")))
          fi
        done
      fi
      if [[ $chrome_size -gt 0 ]]; then
        size=$(format_bytes $chrome_size)
      else
        size="0B"
      fi
      ;;
    "Firefox Cache")
      local firefox_size=0
      if [[ -d "$HOME/Library/Caches/Firefox" ]]; then
        firefox_size=$(calculate_size_bytes "$HOME/Library/Caches/Firefox")
      fi
      if [[ -d "$HOME/Library/Application Support/Firefox" ]]; then
        for profile_dir in "$HOME/Library/Application Support/Firefox/Profiles"/*/; do
          if [[ -d "$profile_dir" ]]; then
            firefox_size=$((firefox_size + $(calculate_size_bytes "$profile_dir/cache2" 2>/dev/null || echo "0")))
            firefox_size=$((firefox_size + $(calculate_size_bytes "$profile_dir/startupCache" 2>/dev/null || echo "0")))
          fi
        done
      fi
      if [[ $firefox_size -gt 0 ]]; then
        size=$(format_bytes $firefox_size)
      else
        size="0B"
      fi
      ;;
    "Microsoft Edge Cache")
      local edge_size=0
      if [[ -d "$HOME/Library/Caches/com.microsoft.edgemac" ]]; then
        edge_size=$(calculate_size_bytes "$HOME/Library/Caches/com.microsoft.edgemac")
      fi
      if [[ -d "$HOME/Library/Application Support/Microsoft Edge" ]]; then
        for profile_dir in "$HOME/Library/Application Support/Microsoft Edge"/*/; do
          if [[ -d "$profile_dir" ]]; then
            edge_size=$((edge_size + $(calculate_size_bytes "$profile_dir/Cache" 2>/dev/null || echo "0")))
            edge_size=$((edge_size + $(calculate_size_bytes "$profile_dir/Code Cache" 2>/dev/null || echo "0")))
          fi
        done
      fi
      if [[ $edge_size -gt 0 ]]; then
        size=$(format_bytes $edge_size)
      else
        size="0B"
      fi
      ;;
    "Application Container Caches")
      size=$(calculate_size "$HOME/Library/Containers")
      ;;
    "Saved Application States")
      size=$(calculate_size "$HOME/Library/Saved Application State")
      ;;
    "Empty Trash")
      size=$(calculate_size "$HOME/.Trash")
      ;;
    "npm Cache")
      local npm_cache_dir=$(npm config get cache 2>/dev/null || echo "$HOME/.npm")
      size=$(calculate_size "$npm_cache_dir")
      ;;
    "pip Cache")
      local pip_cmd="pip3"
      if command -v pip &> /dev/null; then
        pip_cmd="pip"
      fi
      local pip_cache_dir=$($pip_cmd cache dir 2>/dev/null || echo "$HOME/Library/Caches/pip")
      size=$(calculate_size "$pip_cache_dir")
      ;;
    "Gradle Cache")
      local gradle_size=0
      if [[ -d "$HOME/.gradle/caches" ]]; then
        gradle_size=$(calculate_size_bytes "$HOME/.gradle/caches")
      fi
      if [[ -d "$HOME/.gradle/wrapper" ]]; then
        gradle_size=$((gradle_size + $(calculate_size_bytes "$HOME/.gradle/wrapper")))
      fi
      if [[ $gradle_size -gt 0 ]]; then
        size=$(format_bytes $gradle_size)
      else
        size="0B"
      fi
      ;;
    "Maven Cache")
      size=$(calculate_size "$HOME/.m2/repository")
      ;;
    "Docker Cache")
      if command -v docker &> /dev/null && docker info &> /dev/null; then
        size="N/A"  # Docker doesn't report size easily
      else
        size="0B"
      fi
      ;;
    "Xcode Data")
      local xcode_size=0
      if [[ -d "$HOME/Library/Developer/Xcode/DerivedData" ]]; then
        xcode_size=$((xcode_size + $(calculate_size_bytes "$HOME/Library/Developer/Xcode/DerivedData")))
      fi
      if [[ -d "$HOME/Library/Developer/Xcode/Archives" ]]; then
        xcode_size=$((xcode_size + $(calculate_size_bytes "$HOME/Library/Developer/Xcode/Archives")))
      fi
      if [[ $xcode_size -gt 0 ]]; then
        size=$(format_bytes $xcode_size)
      else
        size="0B"
      fi
      ;;
    "Node.js Modules")
      local node_size=0
      if [[ -d "$HOME/.node_modules" ]]; then
        node_size=$((node_size + $(calculate_size_bytes "$HOME/.node_modules")))
      fi
      if [[ $node_size -gt 0 ]]; then
        size=$(format_bytes $node_size)
      else
        size="0B"
      fi
      ;;
    *)
      size="N/A"
      ;;
  esac
  
  echo "$size"
}

# Parse command line arguments
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --dry-run)
        MC_DRY_RUN=true
        shift
        ;;
      --undo)
        source "$SCRIPT_DIR/features/undo.sh"
        undo_cleanup
        exit $?
        ;;
      --schedule)
        source "$SCRIPT_DIR/features/schedule.sh"
        setup_schedule
        exit $?
        ;;
      --quiet)
        MC_QUIET_MODE=true
        shift
        ;;
      --help|-h)
        echo "Usage: $SCRIPT_NAME [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --dry-run    Preview operations without making changes"
        echo "  --undo       Restore files from a previous backup"
        echo "  --schedule   Setup automated scheduling (daily/weekly/monthly)"
        echo "  --quiet      Run in quiet mode (for automated runs)"
        echo "  --help, -h   Show this help message"
        exit 0
        ;;
      *)
        print_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
    esac
  done
}

main() {
  # Parse command line arguments
  parse_arguments "$@"
  
  # Initialize core
  mc_core_init
  sync_globals
  
  # Set up traps
  mc_setup_traps
  
  print_header "macOS Cleanup Utility"
  print_info "This script will help you safely clean up your macOS system."
  
  if [[ "$MC_DRY_RUN" == "true" ]]; then
    print_warning "DRY RUN MODE: No changes will be made"
  fi
  
  # Check dependencies
  mc_check_dependencies
  
  # Check for gum and install if needed
  mc_check_gum
  
  # Load plugins (this will register them)
  load_plugins
  
  # Sync globals again after plugins load
  sync_globals
  
  # Build option list with sizes for display
  local option_names=()
  local option_list=()
  
  for plugin_name in $(mc_list_plugins); do
    local size=$(calculate_plugin_size "$plugin_name")
    
    if [[ "$size" != "0B" && "$size" != "N/A" && -n "$size" ]]; then
      option_list+=("$plugin_name ($size)")
    else
      option_list+=("$plugin_name")
    fi
    option_names+=("$plugin_name")
  done
  
  # Allow user to select options
  print_info "Please select the cleanup operations you'd like to perform (space to select, enter to confirm):"
  
  # Calculate appropriate height for the selection list
  local height=$((${#option_list[@]} + 2))
  height=$((height > 20 ? 20 : height)) # Cap height at 20
  
  # Use printf to send the options to gum to prevent word splitting
  local selected_display=($(printf "%s\n" "${option_list[@]}" | gum choose --no-limit --height="$height"))
  
  # Check if any options were selected
  if [[ ${#selected_display[@]} -eq 0 ]]; then
    print_warning "No cleanup options selected. Exiting."
    mc_cleanup_gum
    exit 0
  fi
  
  # Extract option names from display strings (remove size info)
  local selected_options=()
  for display in "${selected_display[@]}"; do
    # Remove size in parentheses if present
    local option_name=$(echo "$display" | sed 's/ (.*)$//')
    selected_options+=("$option_name")
  done
  
  # Get list of selected operations
  print_info "You've selected the following cleanup operations:"
  for option in "${selected_options[@]}"; do
    print_message "$CYAN" "  - $option"
    log_message "INFO" "Selected operation: $option"
  done
  
  if ! gum confirm "Do you want to proceed with these cleanup operations?"; then
    print_warning "Cleanup cancelled. Exiting."
    mc_cleanup_gum
    exit 0
  fi
  
  # Perform selected cleanup operations
  for option in "${selected_options[@]}"; do
    local function=$(mc_get_plugin_function "$option")
    if [[ -n "$function" ]]; then
      $function
      sync_globals  # Sync after each operation
    else
      print_error "Unknown cleanup function for: $option"
      log_message "ERROR" "Unknown cleanup function for: $option"
    fi
  done
  
  print_header "Cleanup Summary"
  print_success "Cleanup completed successfully!"
  
  # Sync globals for final summary
  sync_globals
  
  # Display space saved summary
  if [[ $MC_TOTAL_SPACE_SAVED -gt 0 ]]; then
    echo ""
    print_info "Space freed: $(format_bytes $MC_TOTAL_SPACE_SAVED)"
    log_message "INFO" "Total space freed: $(format_bytes $MC_TOTAL_SPACE_SAVED)"
    
    # Show breakdown by operation
    if [[ ${#MC_SPACE_SAVED_BY_OPERATION[@]} -gt 0 ]]; then
      echo ""
      print_info "Breakdown by operation:"
      for operation in "${(@k)MC_SPACE_SAVED_BY_OPERATION}"; do
        local space=${MC_SPACE_SAVED_BY_OPERATION[$operation]}
        if [[ $space -gt 0 ]]; then
          print_message "$CYAN" "  - $operation: $(format_bytes $space)"
        fi
      done
    fi
  else
    print_info "No space was freed (directories were empty or dry-run mode)"
  fi
  
  if [[ "$MC_DRY_RUN" != "true" ]]; then
    print_info "Backups saved to: $MC_BACKUP_DIR"
    print_info "Log file: $MC_LOG_FILE"
  fi
  
  # Clean up gum if it was installed by this script
  mc_cleanup_gum
  
  log_message "INFO" "Cleanup completed"
}

# Run main function
main "$@"
