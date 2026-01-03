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

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Ensure PATH includes standard system directories
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$PATH"

# Get script directory and name
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-${(%):-%x}}")"

# Load core libraries
source "$SCRIPT_DIR/lib/constants.sh"
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/admin.sh"
source "$SCRIPT_DIR/lib/backup.sh"
source "$SCRIPT_DIR/lib/validation.sh"
source "$SCRIPT_DIR/lib/error_handler.sh"

# Load plugin base
source "$SCRIPT_DIR/plugins/base.sh"

# Sync global variables for backward compatibility
sync_globals() {
  BACKUP_DIR="$MC_BACKUP_DIR"
  DRY_RUN="$MC_DRY_RUN"
  QUIET_MODE="$MC_QUIET_MODE"
  LOG_FILE="$MC_LOG_FILE"
  TOTAL_SPACE_SAVED=$MC_TOTAL_SPACE_SAVED
  # Copy associative array - ensure it's declared as associative
  typeset -A SPACE_SAVED_BY_OPERATION
  SPACE_SAVED_BY_OPERATION=()
  for key in "${(@k)MC_SPACE_SAVED_BY_OPERATION}"; do
    local value="${MC_SPACE_SAVED_BY_OPERATION[$key]}"
    # Ensure value is numeric (default to 0 if not)
    if [[ -z "$value" || ! "$value" =~ ^[0-9]+$ ]]; then
      value=0
    fi
    SPACE_SAVED_BY_OPERATION["$key"]=$value
  done
  ADMIN_USERNAME="$MC_ADMIN_USERNAME"
}

# Discover and load plugins
load_plugins() {
  local plugins_dir="$SCRIPT_DIR/plugins"
  local load_errors=0
  
  # Load browser plugins
  if [[ -d "$plugins_dir/browsers" ]]; then
    for plugin_file in "$plugins_dir/browsers"/*.sh(N); do
      if [[ -f "$plugin_file" ]]; then
        if ! source "$plugin_file" 2>/dev/null; then
          print_error "Failed to load plugin: $plugin_file"
          log_message "ERROR" "Plugin load failure: $plugin_file"
          load_errors=$((load_errors + 1))
        fi
      fi
    done
  fi
  
  # Load package manager plugins
  if [[ -d "$plugins_dir/package-managers" ]]; then
    for plugin_file in "$plugins_dir/package-managers"/*.sh(N); do
      if [[ -f "$plugin_file" ]]; then
        if ! source "$plugin_file" 2>/dev/null; then
          print_error "Failed to load plugin: $plugin_file"
          log_message "ERROR" "Plugin load failure: $plugin_file"
          load_errors=$((load_errors + 1))
        fi
      fi
    done
  fi
  
  # Load development plugins
  if [[ -d "$plugins_dir/development" ]]; then
    for plugin_file in "$plugins_dir/development"/*.sh(N); do
      if [[ -f "$plugin_file" ]]; then
        if ! source "$plugin_file" 2>/dev/null; then
          print_error "Failed to load plugin: $plugin_file"
          log_message "ERROR" "Plugin load failure: $plugin_file"
          load_errors=$((load_errors + 1))
        fi
      fi
    done
  fi
  
  # Load system plugins
  if [[ -d "$plugins_dir/system" ]]; then
    for plugin_file in "$plugins_dir/system"/*.sh(N); do
      if [[ -f "$plugin_file" ]]; then
        local plugin_name=$(basename "$plugin_file" .sh)
        
        if ! source "$plugin_file" 2>&1; then
          print_error "Failed to load plugin: $plugin_file"
          log_message "ERROR" "Plugin load failure: $plugin_file"
          load_errors=$((load_errors + 1))
        fi
      fi
    done
  fi
  
  # Load maintenance plugins
  if [[ -d "$plugins_dir/maintenance" ]]; then
    for plugin_file in "$plugins_dir/maintenance"/*.sh(N); do
      if [[ -f "$plugin_file" ]]; then
        if ! source "$plugin_file" 2>/dev/null; then
          print_error "Failed to load plugin: $plugin_file"
          log_message "ERROR" "Plugin load failure: $plugin_file"
          load_errors=$((load_errors + 1))
        fi
      fi
    done
  fi
  
  # Warn if there were load errors, but continue (some plugins may still work)
  if [[ $load_errors -gt 0 ]]; then
    print_warning "$load_errors plugin(s) failed to load. Some cleanup operations may be unavailable."
  fi
}

# Async sweep function - runs in background to calculate plugin sizes in parallel
run_async_sweep() {
  local sweep_file="$1"
  local script_dir="$2"
  shift 2
  local plugin_list=("$@")
  
  # Source required libraries in case they're not available in subshell
  # (functions should be inherited, but this ensures they're available)
  if [[ -n "$script_dir" ]]; then
    [[ -f "$script_dir/lib/constants.sh" ]] && source "$script_dir/lib/constants.sh" 2>/dev/null || true
    [[ -f "$script_dir/lib/utils.sh" ]] && source "$script_dir/lib/utils.sh" 2>/dev/null || true
    [[ -f "$script_dir/lib/core.sh" ]] && source "$script_dir/lib/core.sh" 2>/dev/null || true
  fi
  
  # Create temp file for results
  > "$sweep_file"
  
  # Calculate sizes for all plugins in parallel
  local pids=()
  local temp_files=()
  local plugin_index=0
  
  for plugin_name in "${plugin_list[@]}"; do
    # Create temp file for this plugin's result
    local temp_file="${MC_TEMP_DIR}/${MC_TEMP_PREFIX}-sweep-$$-$plugin_index.tmp"
    temp_files+=("$temp_file")
    
    # Calculate size in background
    (
      # Ensure we have access to calculate_plugin_size_bytes and related functions
      # In zsh, functions should be inherited from parent, but verify availability
      local size_bytes=0
      local size_formatted="0B"
      
      # Try to call calculate_plugin_size_bytes if available
      if type calculate_plugin_size_bytes &>/dev/null 2>&1; then
        size_bytes=$(calculate_plugin_size_bytes "$plugin_name" 2>/dev/null || echo "0")
      elif type _calculate_plugin_size_fallback &>/dev/null 2>&1; then
        # Fallback function if main one not available
        size_bytes=$(_calculate_plugin_size_fallback "$plugin_name" 2>/dev/null || echo "0")
      else
        # Last resort: try to calculate based on plugin name
        # This is a minimal fallback - most plugins won't work without the main function
        case "$plugin_name" in
          "Empty Trash")
            [[ -d "$HOME/.Trash" ]] && size_bytes=$(calculate_size_bytes "$HOME/.Trash" 2>/dev/null || echo "0")
            ;;
        esac
      fi
      
      # Ensure size_bytes is numeric
      size_bytes=$(echo "$size_bytes" | tr -d '[:space:]')
      if [[ -z "$size_bytes" || ! "$size_bytes" =~ ^[0-9]+$ ]]; then
        size_bytes=0
      fi
      
      if [[ $size_bytes -gt 0 ]]; then
        # Ensure format_bytes is available
        if type format_bytes &>/dev/null 2>&1; then
          size_formatted=$(format_bytes $size_bytes 2>/dev/null || echo "0B")
        else
          size_formatted="0B"
        fi
      else
        size_formatted="0B"
      fi
      
      # Write to temp file: plugin_name|size_bytes|size_formatted
      printf "%s|%s|%s\n" "$plugin_name" "$size_bytes" "$size_formatted" > "$temp_file" 2>/dev/null || true
    ) &
    pids+=($!)
    plugin_index=$((plugin_index + 1))
  done
  
  # Wait for all parallel calculations to complete
  for pid in "${pids[@]}"; do
    wait $pid 2>/dev/null || true
  done
  
  # Combine results into sweep file
  for temp_file in "${temp_files[@]}"; do
    if [[ -f "$temp_file" ]]; then
      cat "$temp_file" >> "$sweep_file" 2>/dev/null || true
      rm -f "$temp_file" 2>/dev/null || true
    fi
  done
  
  # Write completion marker
  echo "SWEEP_COMPLETE" >> "$sweep_file" 2>/dev/null || true
}

# Calculate size in bytes for a plugin (with early exits for non-existent paths)
# PERF-3: First try to use registered size calculation function, fallback to case statement
calculate_plugin_size_bytes() {
  local plugin_name="$1"
  local size_bytes=0
  
  # Try to use registered size calculation function first (PERF-3)
  local normalized_name=$(_normalize_plugin_name "$plugin_name")
  local size_function="${MC_PLUGIN_SIZE_FUNCTIONS[$normalized_name]:-}"
  
  if [[ -n "$size_function" ]] && type "$size_function" &>/dev/null; then
    size_bytes=$($size_function 2>/dev/null || echo "0")
    # Ensure result is numeric
    if [[ "$size_bytes" =~ ^[0-9]+$ ]]; then
      echo "$size_bytes"
      return 0
    fi
  fi
  
  # Fallback to hardcoded case statement for backward compatibility
  case "$plugin_name" in
    "User Cache")
      [[ -d "$HOME/Library/Caches" ]] && size_bytes=$(calculate_size_bytes "$HOME/Library/Caches")
      ;;
    "System Cache")
      [[ -d "/Library/Caches" ]] && size_bytes=$(calculate_size_bytes "/Library/Caches")
      ;;
    "Application Logs")
      [[ -d "$HOME/Library/Logs" ]] && size_bytes=$(calculate_size_bytes "$HOME/Library/Logs")
      ;;
    "System Logs")
      # Calculate size of only .log files (matching what cleanup actually removes/truncates)
      # System logs cleanup only affects .log and .log.* files, not the entire /var/log directory
      if [[ -d "/var/log" ]]; then
        # Calculate size of .log files and .log.* files
        local log_files_size=0
        # Use find to get total size of log files (requires sudo, but we can try without for size calculation)
        local find_output=$(find "/var/log" -type f \( -name "*.log" -o -name "*.log.*" \) -exec du -sk {} + 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
        if [[ -n "$find_output" && "$find_output" =~ ^[0-9]+$ ]]; then
          # Use awk for large number arithmetic to prevent overflow
          log_files_size=$(echo "$find_output * 1024" | awk '{printf "%.0f", $1 * $2}')
          # Ensure result is numeric
          if [[ ! "$log_files_size" =~ ^[0-9]+$ ]]; then
            log_files_size=0
          fi
        fi
        size_bytes=$log_files_size
      fi
      ;;
    "Temporary Files")
      for temp_dir in "/tmp" "$TMPDIR" "$HOME/Library/Application Support/Temp"; do
        if [[ -d "$temp_dir" ]]; then
          local dir_size=0
          # For /tmp, calculate size excluding files that cleanup will skip (.X*, com.apple.*, and script's own temp files)
          # Use the same method as the cleanup function to ensure accuracy
          if [[ "$temp_dir" == "/tmp" ]]; then
            # Calculate size using the same method as clean_temp_files() - iterate through each item
            # Exclude script's own temp files (mac-cleanup-*) to avoid counting them
            local temp_prefix="${MC_TEMP_PREFIX:-mac-cleanup}"
            while IFS= read -r -d '' item; do
              local item_size=$(du -sk "$item" 2>/dev/null | awk '{print $1}')
              if [[ -n "$item_size" && "$item_size" =~ ^[0-9]+$ ]]; then
                dir_size=$((dir_size + item_size * 1024))
              fi
            done < <(find "$temp_dir" -mindepth 1 ! -name ".X*" ! -name "com.apple.*" ! -name "${temp_prefix}-*" -print0 2>/dev/null)
          else
            # For other temp dirs, calculate full size
            dir_size=$(calculate_size_bytes "$temp_dir")
          fi
          if [[ -n "$dir_size" && "$dir_size" =~ ^[0-9]+$ ]]; then
            size_bytes=$((size_bytes + dir_size))
          fi
        fi
      done
      ;;
    "Safari Cache")
      # Calculate size of all Safari cache directories (matching what cleanup actually removes)
      local safari_dirs=(
        "$HOME/Library/Caches/com.apple.Safari"
        "$HOME/Library/Safari/LocalStorage"
        "$HOME/Library/Safari/Databases"
        "$HOME/Library/Safari/ServiceWorkers"
      )
      for dir in "${safari_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
          local dir_size=$(calculate_size_bytes "$dir" 2>/dev/null || echo "0")
          [[ "$dir_size" =~ ^[0-9]+$ ]] && size_bytes=$((size_bytes + dir_size))
        fi
      done
      ;;
    "Chrome Cache")
      local chrome_size=0
      if [[ -d "$HOME/Library/Caches/Google/Chrome" ]]; then
        chrome_size=$(calculate_size_bytes "$HOME/Library/Caches/Google/Chrome")
      fi
      if [[ -d "$HOME/Library/Application Support/Google/Chrome" ]]; then
        for profile_dir in "$HOME/Library/Application Support/Google/Chrome"/*/; do
          if [[ -d "$profile_dir" ]]; then
            [[ -d "$profile_dir/Cache" ]] && {
              local cache_size=$(calculate_size_bytes "$profile_dir/Cache" 2>/dev/null || echo "0")
              [[ "$cache_size" =~ ^[0-9]+$ ]] && chrome_size=$((chrome_size + cache_size))
            }
            [[ -d "$profile_dir/Code Cache" ]] && {
              local code_cache_size=$(calculate_size_bytes "$profile_dir/Code Cache" 2>/dev/null || echo "0")
              [[ "$code_cache_size" =~ ^[0-9]+$ ]] && chrome_size=$((chrome_size + code_cache_size))
            }
            [[ -d "$profile_dir/Service Worker" ]] && {
              local sw_size=$(calculate_size_bytes "$profile_dir/Service Worker" 2>/dev/null || echo "0")
              [[ "$sw_size" =~ ^[0-9]+$ ]] && chrome_size=$((chrome_size + sw_size))
            }
          fi
        done
      fi
      size_bytes=$chrome_size
      ;;
    "Firefox Cache")
      local firefox_size=0
      if [[ -d "$HOME/Library/Caches/Firefox" ]]; then
        firefox_size=$(calculate_size_bytes "$HOME/Library/Caches/Firefox")
      fi
      if [[ -d "$HOME/Library/Application Support/Firefox" ]]; then
        for profile_dir in "$HOME/Library/Application Support/Firefox/Profiles"/*/; do
          if [[ -d "$profile_dir" ]]; then
            [[ -d "$profile_dir/cache2" ]] && {
              local cache2_size=$(calculate_size_bytes "$profile_dir/cache2" 2>/dev/null || echo "0")
              [[ "$cache2_size" =~ ^[0-9]+$ ]] && firefox_size=$((firefox_size + cache2_size))
            }
            [[ -d "$profile_dir/startupCache" ]] && {
              local startup_size=$(calculate_size_bytes "$profile_dir/startupCache" 2>/dev/null || echo "0")
              [[ "$startup_size" =~ ^[0-9]+$ ]] && firefox_size=$((firefox_size + startup_size))
            }
          fi
        done
      fi
      size_bytes=$firefox_size
      ;;
    "Microsoft Edge Cache")
      local edge_size=0
      if [[ -d "$HOME/Library/Caches/com.microsoft.edgemac" ]]; then
        edge_size=$(calculate_size_bytes "$HOME/Library/Caches/com.microsoft.edgemac")
      fi
      if [[ -d "$HOME/Library/Application Support/Microsoft Edge" ]]; then
        for profile_dir in "$HOME/Library/Application Support/Microsoft Edge"/*/; do
          if [[ -d "$profile_dir" ]]; then
            [[ -d "$profile_dir/Cache" ]] && {
              local edge_cache_size=$(calculate_size_bytes "$profile_dir/Cache" 2>/dev/null || echo "0")
              [[ "$edge_cache_size" =~ ^[0-9]+$ ]] && edge_size=$((edge_size + edge_cache_size))
            }
            [[ -d "$profile_dir/Code Cache" ]] && {
              local edge_code_size=$(calculate_size_bytes "$profile_dir/Code Cache" 2>/dev/null || echo "0")
              [[ "$edge_code_size" =~ ^[0-9]+$ ]] && edge_size=$((edge_size + edge_code_size))
            }
          fi
        done
      fi
      size_bytes=$edge_size
      ;;
    "Application Container Caches")
      # Calculate size of only the Caches subdirectories (matching what cleanup actually removes)
      if [[ -d "$HOME/Library/Containers" ]]; then
        local cache_size=0
        while IFS= read -r cache_dir; do
          [[ -n "$cache_dir" && -d "$cache_dir" ]] && {
            local dir_size=$(calculate_size_bytes "$cache_dir" 2>/dev/null || echo "0")
            [[ "$dir_size" =~ ^[0-9]+$ ]] && cache_size=$((cache_size + dir_size))
          }
        done < <(find "$HOME/Library/Containers" -type d -name "Caches" 2>/dev/null)
        size_bytes=$cache_size
      fi
      ;;
    "Saved Application States")
      [[ -d "$HOME/Library/Saved Application State" ]] && size_bytes=$(calculate_size_bytes "$HOME/Library/Saved Application State")
      ;;
    "Empty Trash")
      [[ -d "$HOME/.Trash" ]] && size_bytes=$(calculate_size_bytes "$HOME/.Trash")
      ;;
    "npm Cache")
      if command -v npm &> /dev/null; then
        local npm_cache_dir=$(npm config get cache 2>/dev/null || echo "$HOME/.npm")
        [[ -d "$npm_cache_dir" ]] && size_bytes=$(calculate_size_bytes "$npm_cache_dir")
      fi
      ;;
    "pip Cache")
      local pip_cmd="pip3"
      if command -v pip &> /dev/null; then
        pip_cmd="pip"
      fi
      if command -v "$pip_cmd" &> /dev/null; then
        local pip_cache_dir=$($pip_cmd cache dir 2>/dev/null || echo "$HOME/Library/Caches/pip")
        [[ -d "$pip_cache_dir" ]] && size_bytes=$(calculate_size_bytes "$pip_cache_dir")
      fi
      ;;
    "Gradle Cache")
      local gradle_size=0
      if [[ -d "$HOME/.gradle/caches" ]]; then
        gradle_size=$(calculate_size_bytes "$HOME/.gradle/caches")
      fi
      if [[ -d "$HOME/.gradle/wrapper" ]]; then
        local wrapper_size=$(calculate_size_bytes "$HOME/.gradle/wrapper")
        [[ "$wrapper_size" =~ ^[0-9]+$ ]] && gradle_size=$((gradle_size + wrapper_size))
      fi
      size_bytes=$gradle_size
      ;;
    "Maven Cache")
      [[ -d "$HOME/.m2/repository" ]] && size_bytes=$(calculate_size_bytes "$HOME/.m2/repository")
      ;;
    "Docker Cache")
      # Docker cleanup uses 'docker system prune' which cleans Docker's internal data
      # This is different from file system directories. The cleanup function doesn't track
      # exact bytes freed (returns 0), so we also return 0 here for consistency.
      # Note: docker system df could be used, but it's complex to parse and may not
      # accurately reflect what will be cleaned by 'docker system prune'.
      size_bytes=0
      ;;
    "Xcode Data")
      # Calculate size of all Xcode data directories (matching what cleanup actually removes)
      local xcode_size=0
      local xcode_dirs=(
        "$HOME/Library/Developer/Xcode/DerivedData"
        "$HOME/Library/Developer/Xcode/Archives"
        "$HOME/Library/Developer/Xcode/iOS DeviceSupport"
        "$HOME/Library/Caches/com.apple.dt.Xcode"
      )
      for dir in "${xcode_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
          local dir_size=$(calculate_size_bytes "$dir" 2>/dev/null || echo "0")
          [[ "$dir_size" =~ ^[0-9]+$ ]] && xcode_size=$((xcode_size + dir_size))
        fi
      done
      size_bytes=$xcode_size
      ;;
    "Node.js Modules")
      local node_size=0
      if [[ -d "$HOME/.node_modules" ]]; then
        local node_modules_size=$(calculate_size_bytes "$HOME/.node_modules")
        [[ "$node_modules_size" =~ ^[0-9]+$ ]] && node_size=$((node_size + node_modules_size))
      fi
      if [[ -d "$HOME/.npm-global" ]]; then
        local npm_global_size=$(calculate_size_bytes "$HOME/.npm-global")
        [[ "$npm_global_size" =~ ^[0-9]+$ ]] && node_size=$((node_size + npm_global_size))
      fi
      size_bytes=$node_size
      ;;
    "Homebrew Cache")
      local brew_cache_size=0
      if command -v brew &> /dev/null; then
        local brew_cache_dirs=(
          "$(brew --cache 2>/dev/null || echo "$HOME/Library/Caches/Homebrew")"
          "$HOME/Library/Caches/Homebrew"
        )
        for cache_dir in "${brew_cache_dirs[@]}"; do
          if [[ -d "$cache_dir" ]]; then
            local dir_size=$(calculate_size_bytes "$cache_dir")
            [[ "$dir_size" =~ ^[0-9]+$ ]] && brew_cache_size=$((brew_cache_size + dir_size))
            break
          fi
        done
      fi
      size_bytes=$brew_cache_size
      ;;
    "Developer Tool Temp Files")
      # Calculate size matching what cleanup actually removes
      # For JetBrains: only subdirectories named "caches" or maxdepth 1 directories
      # For VS Code: specific cache directories
      local dev_tool_size=0
      
      # JetBrains: calculate size of subdirectories that will be cleaned
      # The cleanup finds: directories named "caches" OR maxdepth 1 directories
      # We use an associative array to avoid double-counting
      typeset -A counted_jetbrains_dirs
      local jetbrains_base_dirs=(
        "$HOME/Library/Caches/JetBrains"
        "$HOME/Library/Application Support/JetBrains"
        "$HOME/Library/Logs/JetBrains"
      )
      for base_dir in "${jetbrains_base_dirs[@]}"; do
        if [[ -d "$base_dir" ]]; then
          # Find maxdepth 1 directories (direct children) - matching cleanup logic
          while IFS= read -r dir; do
            if [[ -d "$dir" && "$dir" != "$base_dir" && -z "${counted_jetbrains_dirs[$dir]:-}" ]]; then
              counted_jetbrains_dirs[$dir]=1
              local dir_size=$(calculate_size_bytes "$dir" 2>/dev/null || echo "0")
              [[ "$dir_size" =~ ^[0-9]+$ ]] && dev_tool_size=$((dev_tool_size + dir_size))
            fi
          done < <(find "$base_dir" -maxdepth 1 -type d 2>/dev/null)
          # Find all "caches" subdirectories (at any depth) - matching cleanup logic
          while IFS= read -r dir; do
            if [[ -d "$dir" && "$dir" != "$base_dir" && -z "${counted_jetbrains_dirs[$dir]:-}" ]]; then
              counted_jetbrains_dirs[$dir]=1
              local dir_size=$(calculate_size_bytes "$dir" 2>/dev/null || echo "0")
              [[ "$dir_size" =~ ^[0-9]+$ ]] && dev_tool_size=$((dev_tool_size + dir_size))
            fi
          done < <(find "$base_dir" -type d -name "caches" 2>/dev/null)
        fi
      done
      
      # VS Code: specific cache directories (matching cleanup exactly)
      local vscode_dirs=(
        "$HOME/Library/Application Support/Code/Cache"
        "$HOME/Library/Application Support/Code/CachedData"
        "$HOME/Library/Application Support/Code/CachedExtensionVSIXs"
        "$HOME/Library/Application Support/Code/Code Cache"
        "$HOME/Library/Caches/com.microsoft.VSCode"
        "$HOME/Library/Caches/com.microsoft.VSCode.ShipIt"
      )
      for dir in "${vscode_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
          local dir_size=$(calculate_size_bytes "$dir" 2>/dev/null || echo "0")
          [[ "$dir_size" =~ ^[0-9]+$ ]] && dev_tool_size=$((dev_tool_size + dir_size))
        fi
      done
      size_bytes=$dev_tool_size
      ;;
    "Flush DNS Cache")
      size_bytes=0
      ;;
    "Corrupted Preference Lockfiles")
      local lockfile_size=0
      local lockfile_locations=(
        "$HOME/Library/Preferences"
        "$HOME/Library/Application Support"
      )
      for location in "${lockfile_locations[@]}"; do
        if [[ -d "$location" ]]; then
          while IFS= read -r lockfile; do
            if [[ -f "$lockfile" ]]; then
              local file_size=$(calculate_size_bytes "$lockfile")
              [[ "$file_size" =~ ^[0-9]+$ ]] && lockfile_size=$((lockfile_size + file_size))
            fi
          done < <(find "$location" -name "*.lock" -type f 2>/dev/null | head -100)
        fi
      done
      size_bytes=$lockfile_size
      ;;
    *)
      size_bytes=0
      ;;
  esac
  
  echo "$size_bytes"
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
        mc_undo_cleanup
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
  
  # Phase 5: Check platform compatibility (macOS version, architecture, zsh, dependencies)
  mc_check_platform_compatibility
  
  # Check for selection tool (fzf required) and install if needed
  mc_check_selection_tool
  MC_SELECTION_TOOL=$(mc_get_selection_tool)
  
  # Load plugins (this will register them)
  load_plugins
  
  # Sync globals again after plugins load
  sync_globals
  
  # Get plugin list
  local plugin_array=()
  while IFS= read -r plugin_name; do
    # Use parameter expansion instead of multiple sed calls (PERF-5)
    plugin_name="${plugin_name#\"}"  # Remove leading quote
    plugin_name="${plugin_name%\"}"  # Remove trailing quote
    plugin_name="${plugin_name#\[}"  # Remove leading bracket
    plugin_name="${plugin_name%\]}"  # Remove trailing bracket
    [[ -n "$plugin_name" ]] && plugin_array+=("$plugin_name")
  done < <(mc_list_plugins)
  
  # Check if we have plugins
  if [[ ${#plugin_array[@]} -eq 0 ]]; then
    print_error "No plugins found! Please check plugin installation."
    exit 1
  fi
  
  # Start async sweep in background
  local sweep_file="${MC_TEMP_DIR}/${MC_TEMP_PREFIX}-sweep-$$.tmp"
  local sweep_pid=""
  if [[ ${#plugin_array[@]} -gt 0 ]]; then
    # Run sweep in background - use () to create subshell that inherits functions
    # Pass SCRIPT_DIR so the function can source utils if needed
    # Export necessary functions and variables for the subshell
    (
      # Functions should be inherited in zsh, but ensure calculate_plugin_size_bytes is available
      # by redefining it if needed (it should be inherited, but this is a safety check)
      if ! type calculate_plugin_size_bytes &>/dev/null; then
        # If function not available, we need to source the main script or redefine it
        # For now, we'll rely on function inheritance which should work in zsh
        :
      fi
      run_async_sweep "$sweep_file" "$SCRIPT_DIR" "${plugin_array[@]}"
    ) &
    sweep_pid=$!
  fi
  
  # Show welcome message
  echo ""
  print_header "macOS Cleanup Utility"
  print_info "This script will help you safely clean up your macOS system."
  echo ""
  print_info "Features:"
  print_info "  • Interactive selection of 20+ cleanup operations with size preview"
  print_info "  • Clean browser caches (Safari, Chrome, Firefox, Edge)"
  print_info "  • Remove package manager caches (Homebrew, npm, pip, Gradle, Maven)"
  print_info "  • Clean development tool temp files (Xcode, Docker, Node.js, IntelliJ, VS Code)"
  print_info "  • Remove system and user caches, logs, and temporary files"
  print_info "  • Automatic backups with undo functionality"
  print_info "  • Disk space calculation and savings summary"
  
  if [[ "$MC_DRY_RUN" == "true" ]]; then
    print_warning "DRY RUN MODE: No changes will be made"
  fi
  
  echo ""
  # Phase 4.1: Prompt user to proceed with better non-interactive handling
  if [[ -t 0 ]] && [[ -t 1 ]] && [[ -z "${MC_NON_INTERACTIVE:-}" ]]; then
    local response
    # Phase 4.1: Use timeout to prevent hanging in edge cases
    if read -t 30 -q "?Press 'y' to begin cleanup, 'n' to exit: " response 2>/dev/null; then
      echo ""
      
      if [[ "$response" != "y" && "$response" != "Y" ]]; then
        # User chose to exit - kill sweep if still running
        if [[ -n "$sweep_pid" ]]; then
          kill $sweep_pid 2>/dev/null || true
          wait $sweep_pid 2>/dev/null || true
        fi
        rm -f "$sweep_file" 2>/dev/null || true
        print_info "Exiting. Goodbye!"
        exit 0
      fi
    else
      # Phase 4.1: Timeout or read failed - check if non-interactive mode should be enabled
      echo ""
      if [[ -n "${MC_NON_INTERACTIVE:-}" ]] || [[ "${MC_NON_INTERACTIVE:-}" == "true" ]]; then
        print_info "Non-interactive mode: proceeding automatically"
      else
        print_warning "Input timeout. Assuming non-interactive mode and proceeding."
        export MC_NON_INTERACTIVE=true
      fi
    fi
  else
    # Phase 4.1: Non-interactive mode - proceed automatically
    if [[ -z "${MC_NON_INTERACTIVE:-}" ]]; then
      export MC_NON_INTERACTIVE=true
    fi
    print_info "Non-interactive mode: proceeding automatically"
  fi
  
  # Wait for sweep to complete if still running
  if [[ -n "$sweep_pid" ]]; then
    print_info "Scanning for cleanup opportunities..."
    wait $sweep_pid 2>/dev/null || true
    print_success "Scan complete!"
    echo ""
  fi
  
  # Read sweep results
  typeset -A plugin_sizes_bytes
  typeset -A plugin_sizes_formatted
  
  # Try to use async sweep results first
  local sweep_results_available=false
  if [[ -f "$sweep_file" ]]; then
    # Check if sweep completed successfully
    if grep -q "SWEEP_COMPLETE" "$sweep_file" 2>/dev/null; then
      sweep_results_available=true
      # Parse sweep results
      while IFS='|' read -r plugin_name size_bytes size_formatted; do
        # Skip completion marker
        [[ "$plugin_name" == "SWEEP_COMPLETE" ]] && continue
        
        # Clean and validate size_bytes
        size_bytes=$(echo "$size_bytes" | tr -d '[:space:]')
        
        # Use arithmetic evaluation to check if numeric
        local arithmetic_result=0
        if (( size_bytes + 0 == size_bytes )) 2>/dev/null; then
          arithmetic_result=1
        fi
        
        if [[ -n "$plugin_name" && -n "$size_bytes" && $arithmetic_result -eq 1 ]]; then
          plugin_sizes_bytes["$plugin_name"]=$size_bytes
          plugin_sizes_formatted["$plugin_name"]="$size_formatted"
        else
          plugin_sizes_bytes["$plugin_name"]=0
          plugin_sizes_formatted["$plugin_name"]="0B"
        fi
      done < "$sweep_file"
    fi
  fi
  
  # If async sweep didn't complete or results are incomplete, calculate missing ones
  if [[ "$sweep_results_available" != "true" ]] || [[ ${#plugin_sizes_bytes[@]} -lt ${#plugin_array[@]} ]]; then
    if [[ ${#plugin_array[@]} -gt 0 ]]; then
      local missing_count=$((${#plugin_array[@]} - ${#plugin_sizes_bytes[@]}))
      if [[ $missing_count -gt 0 ]]; then
        print_info "Calculating sizes for $missing_count plugins..."
      fi
    fi
    
    # Calculate sizes for plugins not in results (in parallel)
    local pids=()
    local temp_files=()
    local plugin_index=0
    
    for plugin_name in "${plugin_array[@]}"; do
      # Skip if we already have a result
      if [[ -n "${plugin_sizes_bytes[$plugin_name]:-}" ]]; then
        continue
      fi
      
      # Create temp file for this plugin's result
      local temp_file="${MC_TEMP_DIR}/${MC_TEMP_PREFIX}-size-$$-$plugin_index.tmp"
      temp_files+=("$temp_file")
      
      # Calculate size in background
      (
        local size_bytes=$(calculate_plugin_size_bytes "$plugin_name" 2>/dev/null || echo "0")
        size_bytes=$(echo "$size_bytes" | tr -d '[:space:]')
        local arithmetic_result=0
        if (( size_bytes + 0 == size_bytes )) 2>/dev/null; then
          arithmetic_result=1
        fi
        
        if [[ -n "$size_bytes" && $arithmetic_result -eq 1 ]]; then
          echo "$plugin_name|$size_bytes|$(format_bytes $size_bytes 2>/dev/null || echo "0B")" > "$temp_file"
        else
          echo "$plugin_name|0|0B" > "$temp_file"
        fi
      ) &
      pids+=($!)
      plugin_index=$((plugin_index + 1))
    done
    
    # Wait for all parallel calculations to complete
    for pid in "${pids[@]}"; do
      wait $pid 2>/dev/null || true
    done
    
    # Read results from temp files
    for temp_file in "${temp_files[@]}"; do
      if [[ -f "$temp_file" ]]; then
        while IFS='|' read -r plugin_name size_bytes size_formatted; do
          if [[ -n "$plugin_name" ]]; then
            plugin_sizes_bytes["$plugin_name"]=$size_bytes
            plugin_sizes_formatted["$plugin_name"]="$size_formatted"
          fi
        done < "$temp_file"
        rm -f "$temp_file" 2>/dev/null || true
      fi
    done
  fi
  
  # Clean up sweep file if it exists
  rm -f "$sweep_file" 2>/dev/null || true
  
  # Group plugins by category
  typeset -A plugins_by_category
  
  for plugin_name in "${plugin_array[@]}"; do
    local category=$(mc_get_plugin_category "$plugin_name")
    # Use parameter expansion instead of multiple sed calls (PERF-5)
    category="${category#\"}"  # Remove leading quote
    category="${category%\"}"  # Remove trailing quote
    category="${category//$'\n'/}"  # Remove newlines
    category="${category//$'\r'/}"  # Remove carriage returns
    
    if [[ -n "$category" && -n "$plugin_name" ]]; then
      local existing="${plugins_by_category[$category]:-}"
      if [[ -z "$existing" ]]; then
        plugins_by_category[$category]="$plugin_name"
      else
        plugins_by_category[$category]="$existing|$plugin_name"
      fi
    fi
  done
  
  # Category display names and descriptions
  declare -A category_display=(
    ["system"]="System"
    ["browsers"]="Browsers"
    ["development"]="Development"
    ["package-managers"]="Package Managers"
    ["maintenance"]="Maintenance"
  )
  
  declare -A category_descriptions=(
    ["system"]="System caches, logs, and temporary files"
    ["browsers"]="Browser cache and web data"
    ["development"]="Development tool caches and build artifacts"
    ["package-managers"]="Package manager caches and repositories"
    ["maintenance"]="System maintenance and cleanup tasks"
  )
  
  # Build category menu with sizes
  local category_list=()
  local preferred_order=("system" "browsers" "development" "package-managers" "maintenance")
  local categories_found=("${(k)plugins_by_category[@]}")
  
  # Build ordered list: preferred categories first, then any others
  local ordered_categories=()
  for pref_cat in "${preferred_order[@]}"; do
    for found_cat in "${categories_found[@]}"; do
      # Use parameter expansion instead of sed (PERF-5)
      local clean_found="${found_cat#\"}"
      clean_found="${clean_found%\"}"
      if [[ "$clean_found" == "$pref_cat" ]]; then
        ordered_categories+=("$found_cat")
        break
      fi
    done
  done
  # Add any remaining categories not in preferred order
  for found_cat in "${categories_found[@]}"; do
    local already_added=false
    for ordered_cat in "${ordered_categories[@]}"; do
      if [[ "$found_cat" == "$ordered_cat" ]]; then
        already_added=true
        break
      fi
    done
    if [[ "$already_added" == "false" ]]; then
      ordered_categories+=("$found_cat")
    fi
  done
  
  # Calculate category totals and build menu
  for category_key in "${ordered_categories[@]}"; do
    local category=$(echo "$category_key" | sed -E 's/^"//' | sed -E 's/"$//')
    local category_display_name="${category_display[$category]:-$category}"
    local category_desc="${category_descriptions[$category]:-Cleanup operations for $category_display_name}"
    
    # Get plugins in this category
    local category_plugins=()
    IFS='|' read -rA category_plugins <<< "${plugins_by_category[$category]}"
    local filtered_plugins=()
    for plugin_name in "${category_plugins[@]}"; do
      [[ -n "$plugin_name" ]] && filtered_plugins+=("$plugin_name")
    done
    category_plugins=("${filtered_plugins[@]}")
    
    # Calculate total size for category
    local total_size_bytes=0
    for plugin_name in "${category_plugins[@]}"; do
      local plugin_size_bytes="${plugin_sizes_bytes["$plugin_name"]:-0}"
      # Use arithmetic evaluation for numeric check (more reliable in zsh)
      if [[ -n "$plugin_size_bytes" ]] && (( plugin_size_bytes + 0 == plugin_size_bytes )) 2>/dev/null; then
        total_size_bytes=$((total_size_bytes + plugin_size_bytes))
      fi
    done
    
    # Only show categories with non-zero sizes
    if [[ $total_size_bytes -gt 0 ]]; then
      local size_formatted=$(format_bytes $total_size_bytes)
      category_list+=("$category_display_name ($category_desc) | $size_formatted")
    fi
  done
  
  # Phase 4.4: Check if we have categories with better messaging
  if [[ ${#category_list[@]} -eq 0 ]]; then
    print_info "No cleanup options available!"
    print_info "No categories with cleanup opportunities found."
    print_info "This could mean:"
    print_info "  • Your system is already clean (all caches are empty)"
    print_info "  • No plugins found files to clean"
    print_info "  • All cleanup targets have zero size"
    echo ""
    print_info "Found ${#plugin_array[@]} plugin(s), but none have files to clean."
    print_info "This is normal if you've recently cleaned your system or have minimal cache usage."
    mc_cleanup_selection_tool
    exit 0
  fi
  
  # Category selection menu
  echo ""
  print_info "Please select cleanup categories:"
  if [[ "$MC_SELECTION_TOOL" == "fzf" ]]; then
    print_info "(Use Space to select, Ctrl-A to select all, Enter to confirm)"
  fi
  
  local selected_category_display=()
  if [[ "$MC_SELECTION_TOOL" == "fzf" ]]; then
    local fzf_height=$(((${#category_list[@]} + 2) > 30 ? 30 : (${#category_list[@]} + 2)))
    fzf_height=$((fzf_height < 10 ? 10 : fzf_height))
    
    local fzf_opts=(
      --multi
      --height="$fzf_height"
      --prompt="Select categories: "
      --header="Use Space to select, Ctrl-A to select all, Enter to confirm"
      --border=rounded
      --border-label=" Cleanup Categories "
      --border-label-pos=1
      --layout=reverse
      --pointer=" ▶"
      --marker="✓ "
      --bind="space:toggle"
      --bind="ctrl-a:select-all"
      --color="fg:-1,bg:-1,hl:4"
      --color="fg+:-1,bg+:7,hl+:4"
      --color="border:8,header:15,gutter:-1"
      --color="marker:2,pointer:15,info:6"
    )
    
    local old_ifs="$IFS"
    IFS=$'\n'
    selected_category_display=($(printf "%s\n" "${category_list[@]}" | fzf "${fzf_opts[@]}"))
    IFS="$old_ifs"
  else
    print_error "No selection tool available!"
    exit 1
  fi
  
  # Check if any categories were selected
  if [[ ${#selected_category_display[@]} -eq 0 ]]; then
    print_warning "No categories selected. Exiting."
    mc_cleanup_selection_tool
    exit 0
  fi
  
  # Extract selected categories and get their plugins
  local selected_plugins=()
  local selected_category_names=()
  
  for display in "${selected_category_display[@]}"; do
    # Use parameter expansion instead of multiple sed calls (PERF-5)
    display="${display#\"}"
    display="${display%\"}"
    local option_text="${display%% |*}"  # Remove everything after " | "
    # Extract category name by removing description in parentheses
    # Use sed to avoid glob pattern issues with parentheses in zsh
    local category_name=$(echo "$option_text" | sed 's/ (.*$//')
    category_name="${category_name%"${category_name##*[![:space:]]}"}"  # Trim trailing whitespace
    
    # Find category and get its plugins
    for category_key in "${ordered_categories[@]}"; do
      local category="${category_key#\"}"
      category="${category%\"}"
      local category_display_name="${category_display[$category]:-$category}"
      
      if [[ "$category_display_name" == "$category_name" ]]; then
        selected_category_names+=("$category_display_name")
        
        # Get plugins in this category
        local plugins_raw="${plugins_by_category[$category]}"
        IFS='|' read -rA category_plugins <<< "$plugins_raw"
        
        for plugin_name in "${category_plugins[@]}"; do
          [[ -n "$plugin_name" ]] && selected_plugins+=("$plugin_name")
        done
        break
      fi
    done
  done
  
  # Show selected categories
  echo ""
  print_info "Selected categories:"
  for category in "${selected_category_names[@]}"; do
    print_message "$CYAN" "  - $category"
    log_message "INFO" "Selected category: $category"
  done
  
  # Plugin selection menu
  echo ""
  print_info "Please select specific cleanup operations:"
  if [[ "$MC_SELECTION_TOOL" == "fzf" ]]; then
    print_info "(Use Space to select, Ctrl-A to select all, Enter to confirm)"
  fi
  
  # Build plugin menu with sizes
  local plugin_option_list=()
  local plugin_option_names=()
  
  for plugin_name in "${selected_plugins[@]}"; do
    local plugin_size="${plugin_sizes_formatted["$plugin_name"]:-0B}"
    local plugin_size_bytes="${plugin_sizes_bytes["$plugin_name"]:-0}"
    
    # Only show plugins with non-zero sizes - use arithmetic evaluation for numeric check
    if [[ -n "$plugin_size_bytes" ]] && (( plugin_size_bytes + 0 == plugin_size_bytes && plugin_size_bytes > 0 )) 2>/dev/null; then
      plugin_option_list+=("$plugin_name | $plugin_size")
      plugin_option_names+=("$plugin_name")
    fi
  done
  
  # Phase 4.4: Check if we have plugins to show with better messaging
  if [[ ${#plugin_option_list[@]} -eq 0 ]]; then
    print_info "No plugins with cleanup opportunities in selected categories."
    print_info "This means all selected cleanup targets are already empty or have no data to clean."
    print_info "Try selecting different categories or check back later after using your system."
    mc_cleanup_selection_tool
    exit 0
  fi
  
  # Show plugin selection menu
  local selected_plugin_display=()
  if [[ "$MC_SELECTION_TOOL" == "fzf" ]]; then
    local fzf_height=$(((${#plugin_option_list[@]} + 2) > 30 ? 30 : (${#plugin_option_list[@]} + 2)))
    fzf_height=$((fzf_height < 10 ? 10 : fzf_height))
    
    local fzf_opts=(
      --multi
      --height="$fzf_height"
      --prompt="Select plugins: "
      --header="Use Space to select, Ctrl-A to select all, Enter to confirm"
      --border=rounded
      --border-label=" Plugin Selection "
      --border-label-pos=1
      --layout=reverse
      --pointer=" ▶"
      --marker="✓ "
      --bind="space:toggle"
      --bind="ctrl-a:select-all"
      --color="fg:-1,bg:-1,hl:4"
      --color="fg+:-1,bg+:7,hl+:4"
      --color="border:8,header:15,gutter:-1"
      --color="marker:2,pointer:15,info:6"
    )
    
    local old_ifs="$IFS"
    IFS=$'\n'
    selected_plugin_display=($(printf "%s\n" "${plugin_option_list[@]}" | fzf "${fzf_opts[@]}"))
    IFS="$old_ifs"
  else
    print_error "No selection tool available!"
    exit 1
  fi
  
  # Check if any plugins were selected
  if [[ ${#selected_plugin_display[@]} -eq 0 ]]; then
    print_warning "No plugins selected. Exiting."
    mc_cleanup_selection_tool
    exit 0
  fi
  
  # Extract selected plugin names
  local selected_options=()
  for display in "${selected_plugin_display[@]}"; do
    # Use parameter expansion instead of multiple sed calls (PERF-5)
    display="${display#\"}"
    display="${display%\"}"
    local plugin_name="${display%% |*}"  # Remove everything after " | "
    plugin_name="${plugin_name%"${plugin_name##*[![:space:]]}"}"  # Trim trailing whitespace
    
    for stored_name in "${plugin_option_names[@]}"; do
      if [[ "$stored_name" == "$plugin_name" ]]; then
        selected_options+=("$plugin_name")
        break
      fi
    done
  done
  
  # Show final selection
  echo ""
  print_info "Selected cleanup operations:"
  for plugin in "${selected_options[@]}"; do
    print_message "$CYAN" "  - $plugin"
    log_message "INFO" "Selected plugin: $plugin"
  done
  
  # Execute selected cleanup operations
  echo ""
  print_info "Starting cleanup operations..."
  
  # Create temp files for cleanup output, progress tracking, and space tracking
  local cleanup_output_file="${MC_TEMP_DIR}/${MC_TEMP_PREFIX}-output-$$.tmp"
  local progress_file="${MC_TEMP_DIR}/${MC_TEMP_PREFIX}-progress-$$.tmp"
  local space_tracking_file="${MC_TEMP_DIR}/${MC_TEMP_PREFIX}-space-$$.tmp"
  : > "$cleanup_output_file" 2>&1 || true
  : > "$progress_file" 2>&1 || true
  : > "$space_tracking_file" 2>&1 || true
  
  local total_operations=${#selected_options[@]}
  
  # Run cleanup with progress tracking
  # Set MC_NON_INTERACTIVE flag since we're running in background
  # This prevents interactive prompts from hanging
  (
    # Source required libraries in subshell to ensure functions are available
    # Functions should be inherited in zsh, but explicitly sourcing ensures availability
    [[ -f "$SCRIPT_DIR/lib/constants.sh" ]] && source "$SCRIPT_DIR/lib/constants.sh" 2>&1 || true
    [[ -f "$SCRIPT_DIR/lib/core.sh" ]] && source "$SCRIPT_DIR/lib/core.sh" 2>&1 || true
    [[ -f "$SCRIPT_DIR/lib/ui.sh" ]] && source "$SCRIPT_DIR/lib/ui.sh" 2>&1 || true
    [[ -f "$SCRIPT_DIR/lib/utils.sh" ]] && source "$SCRIPT_DIR/lib/utils.sh" 2>&1 || true
    [[ -f "$SCRIPT_DIR/lib/admin.sh" ]] && source "$SCRIPT_DIR/lib/admin.sh" 2>&1 || true
    
    if [[ -f "$SCRIPT_DIR/lib/backup.sh" ]]; then
      source "$SCRIPT_DIR/lib/backup.sh" 2>&1 || true
    fi
    
    [[ -f "$SCRIPT_DIR/lib/validation.sh" ]] && source "$SCRIPT_DIR/lib/validation.sh" 2>&1 || true
    [[ -f "$SCRIPT_DIR/lib/error_handler.sh" ]] && source "$SCRIPT_DIR/lib/error_handler.sh" 2>&1 || true
    [[ -f "$SCRIPT_DIR/plugins/base.sh" ]] && source "$SCRIPT_DIR/plugins/base.sh" 2>&1 || true
    
    # Re-register plugins in subshell since plugin registry is not inherited
    # The plugin registry is an associative array that doesn't persist across subshells
    # We need to reload plugins to rebuild the registry
    load_plugins
    
    export MC_NON_INTERACTIVE=true
    export MC_SPACE_TRACKING_FILE="$space_tracking_file"
    export MC_PROGRESS_FILE="$progress_file"
    local current_op=0
    for option in "${selected_options[@]}"; do
      current_op=$((current_op + 1))
      # Write progress update BEFORE starting the operation (SAFE-7: with locking)
      # Format: operation_index|total_operations|operation_name|current_item|total_items|item_name
      _write_progress_file "$progress_file" "$current_op|$total_operations|$option|0|0|"
      
      local function=$(mc_get_plugin_function "$option")
      
      # Phase 4.3: Check if function exists - if not, it means the plugin file wasn't sourced properly
      if [[ -z "$function" ]]; then
        print_error "Plugin function not found for: $option" >> "$cleanup_output_file"
        print_info "This plugin may not be properly installed or loaded." >> "$cleanup_output_file"
        print_info "Check the log file for details: $MC_LOG_FILE" >> "$cleanup_output_file"
        log_message "ERROR" "Plugin function not found: $function (for plugin: $option)"
        _write_progress_file "$progress_file" "$current_op|$total_operations|$option|0|0|"
        continue
      fi
      
      # Phase 4.3: Verify function actually exists (not just registered)
      if ! type "$function" &>/dev/null; then
        print_error "Plugin function '$function' is registered but not defined for: $option" >> "$cleanup_output_file"
        print_info "This indicates a plugin configuration issue." >> "$cleanup_output_file"
        print_info "Check the log file for details: $MC_LOG_FILE" >> "$cleanup_output_file"
        log_message "ERROR" "Plugin function '$function' registered but not available (for plugin: $option)"
        _write_progress_file "$progress_file" "$current_op|$total_operations|$option|0|0|"
        continue
      fi
      
      if [[ -n "$function" ]] && mc_validate_plugin_function "$function" "$option"; then
        # SAFE-8: Add timeout for plugin execution (default 30 minutes per plugin)
        local plugin_timeout="${MC_PLUGIN_TIMEOUT:-1800}"  # 30 minutes default
        
        # Use a timeout mechanism that works with zsh functions
        # Run function in background and monitor with timeout
        $function >> "$cleanup_output_file" 2>&1 &
        local func_pid=$!
        
        # Wait for function to complete or timeout
        local waited=0
        while kill -0 $func_pid 2>/dev/null && [[ $waited -lt $plugin_timeout ]]; do
          sleep 1
          waited=$((waited + 1))
        done
        
        # Phase 4.3: If still running after timeout, kill it with better error message
        if kill -0 $func_pid 2>/dev/null; then
          print_error "Plugin '$option' timed out after $plugin_timeout seconds" >> "$cleanup_output_file"
          print_info "This may indicate the plugin is processing a large amount of data." >> "$cleanup_output_file"
          print_info "The plugin has been stopped to prevent hanging. Check the log for details." >> "$cleanup_output_file"
          log_message "ERROR" "Plugin $option timed out after $plugin_timeout seconds"
          kill -TERM $func_pid 2>/dev/null || true
          sleep 2
          # Force kill if still running
          kill -KILL $func_pid 2>/dev/null || true
          wait $func_pid 2>/dev/null || true
        else
          # Phase 4.3: Function completed, wait for it to get exit code with better error message
          wait $func_pid 2>/dev/null || {
            local exit_code=$?
            if [[ $exit_code -ne 0 ]]; then
              print_error "Plugin '$option' failed with exit code $exit_code" >> "$cleanup_output_file"
              print_info "Check the log file for detailed error information: $MC_LOG_FILE" >> "$cleanup_output_file"
              log_message "ERROR" "Plugin $option failed with exit code $exit_code"
            fi
          }
        fi
        # Clear size cache after plugin execution to ensure fresh calculations for next plugin
        clear_size_cache
        sync_globals
        # Write progress update AFTER completing the operation (SAFE-7: with locking)
        _write_progress_file "$progress_file" "$current_op|$total_operations|$option|0|0|"
      else
        print_error "Plugin function not found or invalid: $function (for plugin: $option)" >> "$cleanup_output_file"
        log_message "ERROR" "Plugin function not found: $function (for plugin: $option)"
        # Still mark as completed even if function not found
        _write_progress_file "$progress_file" "$current_op|$total_operations|$option|0|0|"
      fi
    done
    # Mark completion (SAFE-7: with locking)
    _write_progress_file "$progress_file" "$total_operations|$total_operations|Complete|0|0|"
  ) &
  local cleanup_pid=$!
  MC_CLEANUP_PID=$cleanup_pid  # Store in global for interrupt handler
  
  # Show progress bar while cleanup runs
  (
    
    # Check if we can use colors and progress bar (stderr must be a TTY)
    local use_colors=false
    local use_progress_bar=false
    if [[ -t 2 ]]; then
      use_colors=true
      use_progress_bar=true
    fi
    
    # Set up color codes (use %b format for printf to interpret escape sequences)
    local cyan_code=""
    local reset_code=""
    if [[ "$use_colors" == "true" ]]; then
      cyan_code="\033[0;36m"
      reset_code="\033[0m"
    fi
    
    # Show initial progress state (0%)
    if [[ "$use_progress_bar" == "true" ]]; then
      local initial_bar=$(printf "%40s" | /usr/bin/tr ' ' '░' 2>/dev/null || printf "%40s" | sed 's/ /░/g')
      printf '\r\033[K%b[0/%d] Starting... %s 0%%%b' \
        "$cyan_code" \
        "$total_operations" \
        "$initial_bar" \
        "$reset_code" >&2
    else
      printf '\r[0/%d] Starting... 0%%' "$total_operations" >&2
    fi
    
    # Track last displayed operation to avoid redundant updates
    local last_operation=""
    local last_percent=-1
    
    local loop_count=0
    local last_displayed_percent=-1
    while kill -0 $cleanup_pid 2>/dev/null; do
      loop_count=$((loop_count + 1))
      
      # Throttle progress updates: only check every 5 loops (0.5 seconds) to reduce overhead
      if [[ $((loop_count % 5)) -eq 0 || $loop_count -eq 1 ]]; then
        if [[ -f "$progress_file" ]]; then
          # SAFE-7: Read progress file with locking to prevent race conditions
          local progress_line=$(_read_progress_file "$progress_file")
        
        if [[ -n "$progress_line" ]]; then
          local current=$(echo "$progress_line" | cut -d'|' -f1)
          local total=$(echo "$progress_line" | cut -d'|' -f2)
          local operation=$(echo "$progress_line" | cut -d'|' -f3)
          local current_item=$(echo "$progress_line" | cut -d'|' -f4)
          local total_items=$(echo "$progress_line" | cut -d'|' -f5)
          local item_name=$(echo "$progress_line" | cut -d'|' -f6-)
          
          if [[ -n "$current" && -n "$total" && "$current" =~ ^[0-9]+$ && "$total" =~ ^[0-9]+$ ]]; then
            # Calculate overall percentage
            # Base: operations completed (current-1) / total operations
            # Add: current operation progress (current_item / total_items) / total operations
            local overall_percent=0
            
            if [[ "$operation" == "Complete" ]]; then
              overall_percent=100
            else
              # Calculate base progress from completed operations
              local base_percent=0
              if [[ $current -gt 1 ]]; then
                base_percent=$(((current - 1) * 100 / total))
              fi
              
              # Calculate progress within current operation
              local operation_percent=0
              if [[ -n "$total_items" && "$total_items" =~ ^[0-9]+$ && $total_items -gt 0 ]]; then
                if [[ -n "$current_item" && "$current_item" =~ ^[0-9]+$ ]]; then
                  operation_percent=$((current_item * 100 / total_items))
                fi
              fi
              
              # Add current operation's contribution to overall progress
              local operation_contribution=$((operation_percent / total))
              overall_percent=$((base_percent + operation_contribution))
              
              # Cap at 100%
              [[ $overall_percent -gt 100 ]] && overall_percent=100
            fi
            
            # Build display string with item-level info if available
            local display_op="$operation"
            if [[ -n "$total_items" && "$total_items" =~ ^[0-9]+$ && $total_items -gt 0 ]]; then
              if [[ -n "$current_item" && "$current_item" =~ ^[0-9]+$ ]]; then
                local item_display=""
                if [[ -n "$item_name" && "$item_name" != "" ]]; then
                  # Truncate item name if too long
                  local short_item_name="$item_name"
                  if [[ ${#short_item_name} -gt 20 ]]; then
                    short_item_name="${short_item_name:0:17}..."
                  fi
                  item_display=" ($current_item/$total_items: $short_item_name)"
                else
                  item_display=" ($current_item/$total_items)"
                fi
                display_op="${operation}${item_display}"
              fi
            fi
            
            # Truncate operation name if too long
            if [[ ${#display_op} -gt 50 ]]; then
              display_op="${display_op:0:47}..."
            fi
            
            # Only update if operation, item, or percent changed (reduce flicker)
            local progress_key="${operation}|${current_item}|${total_items}"
            if [[ "$progress_key" != "$last_operation" || $overall_percent != $last_percent ]]; then
              last_operation="$progress_key"
              last_percent=$overall_percent
              
              if [[ "$use_progress_bar" == "true" ]]; then
                # Use progress bar with colors
                local filled=$((overall_percent * 40 / 100))
                local empty=$((40 - filled))
                local bar_chars=""
                if [[ $filled -gt 0 ]]; then
                  bar_chars=$(printf "%${filled}s" | /usr/bin/tr ' ' '█' 2>/dev/null || printf "%${filled}s" | sed 's/ /█/g')
                fi
                if [[ $empty -gt 0 ]]; then
                  bar_chars="${bar_chars}$(printf "%${empty}s" | /usr/bin/tr ' ' '░' 2>/dev/null || printf "%${empty}s" | sed 's/ /░/g')"
                fi
                
                # Clear line and print progress (use %b to interpret escape sequences)
                # Use \r to return to start of line, \033[K to clear to end, no trailing newline
                printf '\r\033[K%b[%d/%d] %s... %s %d%%%b' \
                  "$cyan_code" \
                  "$current" \
                  "$total" \
                  "$display_op" \
                  "$bar_chars" \
                  "$overall_percent" \
                  "$reset_code" >&2
              else
                # Simple text output for non-TTY
                printf '\r[%d/%d] %s... %d%%' \
                  "$current" \
                  "$total" \
                  "$display_op" \
                  "$overall_percent" >&2
              fi
            fi
          fi
        fi
        fi
      fi
      sleep 0.15
    done
    # Clear the progress line completely
    printf '\r\033[K' >&2
  ) &
  local progress_pid=$!
  MC_PROGRESS_PID=$progress_pid  # Store in global for interrupt handler
  
  # Wait for cleanup to complete
  wait $cleanup_pid
  local wait_exit_code=$?
  
  # Read space saved data from background process
  # Aggregate by plugin name since safe_clean_dir may write multiple entries
  if [[ -f "$space_tracking_file" ]]; then
    local total_from_file=0
    # Use associative array to aggregate by plugin name
    typeset -A space_by_plugin
    local file_content=$(cat "$space_tracking_file" 2>/dev/null || echo "")
    while IFS='|' read -r plugin_name space_bytes; do
      if [[ -n "$plugin_name" && -n "$space_bytes" && "$space_bytes" =~ ^[0-9]+$ ]]; then
        # Aggregate by plugin name (sum if multiple entries exist)
        local current_value="${space_by_plugin[$plugin_name]:-0}"
        space_by_plugin["$plugin_name"]=$((current_value + space_bytes))
      fi
    done < "$space_tracking_file" 2>/dev/null || true
    
    # Now update MC_SPACE_SAVED_BY_OPERATION and calculate total
    for plugin_name in "${(@k)space_by_plugin}"; do
      local space_bytes="${space_by_plugin[$plugin_name]}"
      MC_SPACE_SAVED_BY_OPERATION["$plugin_name"]=$space_bytes
      total_from_file=$((total_from_file + space_bytes))
    done
    
    if [[ $total_from_file -gt 0 ]]; then
      MC_TOTAL_SPACE_SAVED=$((MC_TOTAL_SPACE_SAVED + total_from_file))
    fi
    rm -f "$space_tracking_file" 2>/dev/null || true
  fi
  
  # Stop progress display
  kill $progress_pid 2>/dev/null || true
  wait $progress_pid 2>/dev/null || true
  
  # Clean up progress file
  rm -f "$progress_file" 2>/dev/null || true
  
  # Display cleanup output (filter out spinner artifacts and show meaningful messages)
  if [[ -f "$cleanup_output_file" && -s "$cleanup_output_file" ]]; then
    # Filter and display output, removing:
    # - Empty lines
    # - Spinner artifacts and control characters
    # - Individual "Cleaning..." and "Cleaned..." messages (keep only plugin headers and summaries)
    # - Duplicate success messages
    local output_lines=$(cat "$cleanup_output_file" 2>/dev/null | \
      grep -v "^$" | \
      grep -v "Cleaning. Please wait" | \
      grep -v "^Cleaning " | \
      grep -v "^Cleaned " | \
      grep -v "^\r" | \
      sed -E 's/\x1b\[[0-9;]*m//g' | \
      sed -E 's/\r//g' | \
      awk '!seen[$0]++' | \
      head -50)
    if [[ -n "$output_lines" ]]; then
      echo ""
      echo "$output_lines"
    fi
  fi
  
  # Clean up temp file
  rm -f "$cleanup_output_file" 2>/dev/null || true
  
  # Show summary
  echo ""
  print_header "Cleanup Summary"
  
  # Sync globals for final summary
  sync_globals
  
  # Calculate total from associative array if MC_TOTAL_SPACE_SAVED is 0 but we have operation data
  if [[ $MC_TOTAL_SPACE_SAVED -eq 0 && ${#MC_SPACE_SAVED_BY_OPERATION[@]} -gt 0 ]]; then
    local calculated_total=0
    for operation in "${(@k)MC_SPACE_SAVED_BY_OPERATION}"; do
      local space=${MC_SPACE_SAVED_BY_OPERATION[$operation]}
      if [[ -n "$space" && "$space" =~ ^[0-9]+$ && $space -gt 0 ]]; then
        calculated_total=$((calculated_total + space))
      fi
    done
    if [[ $calculated_total -gt 0 ]]; then
      MC_TOTAL_SPACE_SAVED=$calculated_total
    fi
  fi
  
  # Display success message with space saved
  if [[ $MC_TOTAL_SPACE_SAVED -gt 0 ]]; then
    print_success "Cleanup completed successfully! Cleaned up $(format_bytes $MC_TOTAL_SPACE_SAVED)!"
    log_message "INFO" "Total space freed: $(format_bytes $MC_TOTAL_SPACE_SAVED)"
  fi
  
  # Display space saved summary
  if [[ $MC_TOTAL_SPACE_SAVED -gt 0 ]]; then
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
    if [[ "$MC_DRY_RUN" == "true" ]]; then
      print_info "No space was freed (dry-run mode - no changes were made)"
    else
      print_info "No space was freed - selected directories were already empty or contained minimal data."
      print_info "See details above for specific information about each directory."
    fi
  fi
  
  if [[ "$MC_DRY_RUN" != "true" ]]; then
    echo ""
    print_info "Backups saved to: $MC_BACKUP_DIR"
    print_info "Log file: $MC_LOG_FILE"
  fi
  
  # Clean up selection tool if it was installed by this script
  mc_cleanup_selection_tool
  
  log_message "INFO" "Cleanup completed"
}

# Run main function
main "$@"
