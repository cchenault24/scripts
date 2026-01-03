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

# Ensure PATH includes standard system directories
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$PATH"

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

# Async sweep function - runs in background to calculate plugin sizes
run_async_sweep() {
  local sweep_file="$1"
  local script_dir="$2"
  shift 2
  local plugin_list=("$@")
  
  # Source required libraries in case they're not available in subshell
  # (functions should be inherited, but this ensures they're available)
  if [[ -n "$script_dir" && -f "$script_dir/lib/utils.sh" ]]; then
    source "$script_dir/lib/utils.sh" 2>/dev/null || true
  fi
  
  # Create temp file for results
  > "$sweep_file"
  
  # Calculate sizes for all plugins
  for plugin_name in "${plugin_list[@]}"; do
    local size_bytes=0
    # Call the function - it should be available from parent shell
    size_bytes=$(calculate_plugin_size_bytes "$plugin_name" 2>/dev/null || echo "0")
    local size_formatted=""
    
    # Ensure size_bytes is numeric
    if [[ -z "$size_bytes" || ! "$size_bytes" =~ ^[0-9]+$ ]]; then
      size_bytes=0
    fi
    
    if [[ $size_bytes -gt 0 ]]; then
      size_formatted=$(format_bytes $size_bytes 2>/dev/null || echo "0B")
    else
      size_formatted="0B"
    fi
    
    # Write to temp file: plugin_name|size_bytes|size_formatted
    # Use printf for more reliable output
    printf "%s|%s|%s\n" "$plugin_name" "$size_bytes" "$size_formatted" >> "$sweep_file" 2>/dev/null || true
  done
  
  # Write completion marker
  echo "SWEEP_COMPLETE" >> "$sweep_file" 2>/dev/null || true
}

# Calculate size in bytes for a plugin
calculate_plugin_size_bytes() {
  local plugin_name="$1"
  local size_bytes=0
  
  case "$plugin_name" in
    "User Cache")
      size_bytes=$(calculate_size_bytes "$HOME/Library/Caches")
      ;;
    "System Cache")
      size_bytes=$(calculate_size_bytes "/Library/Caches")
      ;;
    "Application Logs")
      size_bytes=$(calculate_size_bytes "$HOME/Library/Logs")
      ;;
    "System Logs")
      size_bytes=$(calculate_size_bytes "/var/log")
      ;;
    "Temporary Files")
      for temp_dir in "/tmp" "$TMPDIR" "$HOME/Library/Application Support/Temp"; do
        if [[ -d "$temp_dir" ]]; then
          local dir_size=$(calculate_size_bytes "$temp_dir")
          if [[ -n "$dir_size" && "$dir_size" =~ ^[0-9]+$ ]]; then
            size_bytes=$((size_bytes + dir_size))
          fi
        fi
      done
      ;;
    "Safari Cache")
      size_bytes=$(calculate_size_bytes "$HOME/Library/Caches/com.apple.Safari")
      ;;
    "Chrome Cache")
      local chrome_size=0
      if [[ -d "$HOME/Library/Caches/Google/Chrome" ]]; then
        chrome_size=$(calculate_size_bytes "$HOME/Library/Caches/Google/Chrome")
      fi
      if [[ -d "$HOME/Library/Application Support/Google/Chrome" ]]; then
        for profile_dir in "$HOME/Library/Application Support/Google/Chrome"/*/; do
          if [[ -d "$profile_dir" ]]; then
            local cache_size=$(calculate_size_bytes "$profile_dir/Cache" 2>/dev/null || echo "0")
            local code_cache_size=$(calculate_size_bytes "$profile_dir/Code Cache" 2>/dev/null || echo "0")
            local sw_size=$(calculate_size_bytes "$profile_dir/Service Worker" 2>/dev/null || echo "0")
            [[ "$cache_size" =~ ^[0-9]+$ ]] && chrome_size=$((chrome_size + cache_size))
            [[ "$code_cache_size" =~ ^[0-9]+$ ]] && chrome_size=$((chrome_size + code_cache_size))
            [[ "$sw_size" =~ ^[0-9]+$ ]] && chrome_size=$((chrome_size + sw_size))
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
            local cache2_size=$(calculate_size_bytes "$profile_dir/cache2" 2>/dev/null || echo "0")
            local startup_size=$(calculate_size_bytes "$profile_dir/startupCache" 2>/dev/null || echo "0")
            [[ "$cache2_size" =~ ^[0-9]+$ ]] && firefox_size=$((firefox_size + cache2_size))
            [[ "$startup_size" =~ ^[0-9]+$ ]] && firefox_size=$((firefox_size + startup_size))
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
            local edge_cache_size=$(calculate_size_bytes "$profile_dir/Cache" 2>/dev/null || echo "0")
            local edge_code_size=$(calculate_size_bytes "$profile_dir/Code Cache" 2>/dev/null || echo "0")
            [[ "$edge_cache_size" =~ ^[0-9]+$ ]] && edge_size=$((edge_size + edge_cache_size))
            [[ "$edge_code_size" =~ ^[0-9]+$ ]] && edge_size=$((edge_size + edge_code_size))
          fi
        done
      fi
      size_bytes=$edge_size
      ;;
    "Application Container Caches")
      size_bytes=$(calculate_size_bytes "$HOME/Library/Containers")
      ;;
    "Saved Application States")
      size_bytes=$(calculate_size_bytes "$HOME/Library/Saved Application State")
      ;;
    "Empty Trash")
      size_bytes=$(calculate_size_bytes "$HOME/.Trash")
      ;;
    "npm Cache")
      local npm_cache_dir=$(npm config get cache 2>/dev/null || echo "$HOME/.npm")
      size_bytes=$(calculate_size_bytes "$npm_cache_dir")
      ;;
    "pip Cache")
      local pip_cmd="pip3"
      if command -v pip &> /dev/null; then
        pip_cmd="pip"
      fi
      local pip_cache_dir=$($pip_cmd cache dir 2>/dev/null || echo "$HOME/Library/Caches/pip")
      size_bytes=$(calculate_size_bytes "$pip_cache_dir")
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
      size_bytes=$(calculate_size_bytes "$HOME/.m2/repository")
      ;;
    "Docker Cache")
      local docker_size=0
      if command -v docker &> /dev/null && docker info &> /dev/null 2>&1; then
        local docker_data_dirs=(
          "$HOME/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
          "$HOME/Library/Containers/com.docker.docker/Data"
          "$HOME/.docker"
        )
        for docker_dir in "${docker_data_dirs[@]}"; do
          if [[ -e "$docker_dir" ]]; then
            local dir_size=$(calculate_size_bytes "$docker_dir" 2>/dev/null || echo "0")
            [[ "$dir_size" =~ ^[0-9]+$ ]] && docker_size=$((docker_size + dir_size))
            if [[ "$docker_dir" == *"Docker.raw" ]]; then
              break
            fi
          fi
        done
      fi
      size_bytes=$docker_size
      ;;
    "Xcode Data")
      local xcode_size=0
      if [[ -d "$HOME/Library/Developer/Xcode/DerivedData" ]]; then
        local derived_data_size=$(calculate_size_bytes "$HOME/Library/Developer/Xcode/DerivedData")
        [[ "$derived_data_size" =~ ^[0-9]+$ ]] && xcode_size=$((xcode_size + derived_data_size))
      fi
      if [[ -d "$HOME/Library/Developer/Xcode/Archives" ]]; then
        local archives_size=$(calculate_size_bytes "$HOME/Library/Developer/Xcode/Archives")
        [[ "$archives_size" =~ ^[0-9]+$ ]] && xcode_size=$((xcode_size + archives_size))
      fi
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
      local dev_tool_size=0
      local jetbrains_dirs=(
        "$HOME/Library/Caches/JetBrains"
        "$HOME/Library/Application Support/JetBrains"
        "$HOME/Library/Logs/JetBrains"
      )
      for dir in "${jetbrains_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
          local dir_size=$(calculate_size_bytes "$dir")
          [[ "$dir_size" =~ ^[0-9]+$ ]] && dev_tool_size=$((dev_tool_size + dir_size))
        fi
      done
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
          local dir_size=$(calculate_size_bytes "$dir")
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
  
  # Check dependencies
  mc_check_dependencies
  
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
    plugin_name=$(echo "$plugin_name" | sed -E 's/^"//' | sed -E 's/"$//' | sed -E 's/^\[//' | sed -E 's/\]$//')
    [[ -n "$plugin_name" ]] && plugin_array+=("$plugin_name")
  done < <(mc_list_plugins)
  
  # Check if we have plugins
  if [[ ${#plugin_array[@]} -eq 0 ]]; then
    print_error "No plugins found! Please check plugin installation."
    exit 1
  fi
  
  # Start async sweep in background
  local sweep_file="/tmp/mac-cleanup-sweep-$$.tmp"
  local sweep_pid=""
  if [[ ${#plugin_array[@]} -gt 0 ]]; then
    # Run sweep in background - use () to create subshell that inherits functions
    # Pass SCRIPT_DIR so the function can source utils if needed
    (
      run_async_sweep "$sweep_file" "$SCRIPT_DIR" "${plugin_array[@]}"
    ) &
    sweep_pid=$!
  fi
  
  # Show welcome message
  echo ""
  print_header "macOS Cleanup Utility"
  print_info "This script will help you safely clean up your macOS system."
  
  if [[ "$MC_DRY_RUN" == "true" ]]; then
    print_warning "DRY RUN MODE: No changes will be made"
  fi
  
  echo ""
  # Prompt user to proceed
  if [[ -t 0 ]]; then
    local response
    read -q "?Press 'y' to begin cleanup, 'n' to exit: " response
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
    # Non-interactive mode - proceed automatically
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
  
  # Always calculate synchronously to ensure we have reliable results
  # The async sweep runs in background for speed, but we calculate here for accuracy
  if [[ ${#plugin_array[@]} -gt 0 ]]; then
    print_info "Calculating sizes for ${#plugin_array[@]} plugins..."
  fi
  
  for plugin_name in "${plugin_array[@]}"; do
    local size_bytes=$(calculate_plugin_size_bytes "$plugin_name" 2>/dev/null || echo "0")
    
    # Clean and validate size_bytes - strip whitespace and check if numeric
    size_bytes=$(echo "$size_bytes" | tr -d '[:space:]')
    
    # Use arithmetic evaluation to check if numeric (more reliable in zsh)
    local arithmetic_result=0
    if (( size_bytes + 0 == size_bytes )) 2>/dev/null; then
      arithmetic_result=1
    fi
    
    if [[ -n "$size_bytes" && $arithmetic_result -eq 1 ]]; then
      plugin_sizes_bytes["$plugin_name"]=$size_bytes
      plugin_sizes_formatted["$plugin_name"]=$(format_bytes $size_bytes 2>/dev/null || echo "0B")
    else
      plugin_sizes_bytes["$plugin_name"]=0
      plugin_sizes_formatted["$plugin_name"]="0B"
    fi
  done
  
  # Clean up sweep file if it exists
  rm -f "$sweep_file" 2>/dev/null || true
  
  # Group plugins by category
  typeset -A plugins_by_category
  
  for plugin_name in "${plugin_array[@]}"; do
    local category=$(mc_get_plugin_category "$plugin_name")
    category=$(echo "$category" | sed -E 's/^"//' | sed -E 's/"$//' | tr -d '\n' | tr -d '\r')
    
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
      local clean_found=$(echo "$found_cat" | sed -E 's/^"//' | sed -E 's/"$//')
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
  
  # Check if we have categories
  if [[ ${#category_list[@]} -eq 0 ]]; then
    print_error "No cleanup options available!"
    print_info "No categories with cleanup opportunities found."
    print_info "This could mean:"
    print_info "  - Your system is already clean (all caches are empty)"
    print_info "  - No plugins found files to clean"
    print_info "  - All cleanup targets have zero size"
    echo ""
    print_info "Found ${#plugin_array[@]} plugins, but none have files to clean."
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
    display=$(echo "$display" | sed -E 's/^"//' | sed -E 's/"$//')
    local option_text=$(echo "$display" | sed -E 's/ \| .*$//')
    local category_name=$(echo "$option_text" | sed -E 's/ \(.*$//')
    category_name=$(echo "$category_name" | sed 's/[[:space:]]*$//')
    
    # Find category and get its plugins
    for category_key in "${ordered_categories[@]}"; do
      local category=$(echo "$category_key" | sed -E 's/^"//' | sed -E 's/"$//')
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
  
  # Check if we have plugins to show
  if [[ ${#plugin_option_list[@]} -eq 0 ]]; then
    print_warning "No plugins with cleanup opportunities in selected categories."
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
    display=$(echo "$display" | sed -E 's/^"//' | sed -E 's/"$//')
    local plugin_name=$(echo "$display" | sed -E 's/ \| .*$//')
    plugin_name=$(echo "$plugin_name" | sed 's/[[:space:]]*$//')
    
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
  
  # Create temp file to capture cleanup output
  local cleanup_output_file="/tmp/mac-cleanup-output-$$.tmp"
  > "$cleanup_output_file"
  
  # Run cleanup with spinner
  (
    for option in "${selected_options[@]}"; do
      local function=$(mc_get_plugin_function "$option")
      if [[ -n "$function" ]]; then
        $function >> "$cleanup_output_file" 2>&1
        sync_globals
      else
        print_error "Unknown cleanup function for: $option" >> "$cleanup_output_file"
        log_message "ERROR" "Unknown cleanup function for: $option"
      fi
    done
  ) &
  local cleanup_pid=$!
  
  # Show spinner while cleanup runs
  local spin='⣾⣽⣻⢿⡿⣟⣯⣷'
  local i=0
  
  (
    while kill -0 $cleanup_pid 2>/dev/null; do
      i=$(((i + 3) % ${#spin}))
      printf "\r* Cleaning. Please wait... %s" "${spin:$i:3}" >&2
      sleep 0.1
    done
  ) &
  local spinner_pid=$!
  
  # Wait for cleanup to complete
  wait $cleanup_pid
  
  # Stop spinner and clear line
  kill $spinner_pid 2>/dev/null || true
  wait $spinner_pid 2>/dev/null || true
  printf "\r\033[K" >&2
  
  # Display cleanup output (filter out spinner artifacts and show meaningful messages)
  if [[ -f "$cleanup_output_file" && -s "$cleanup_output_file" ]]; then
    # Filter and display output, removing empty lines and spinner artifacts
    local output_lines=$(cat "$cleanup_output_file" 2>/dev/null | grep -v "^$" | grep -v "Cleaning. Please wait" | grep -v "^\r" | head -30)
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
  else
    print_success "Cleanup completed successfully!"
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
