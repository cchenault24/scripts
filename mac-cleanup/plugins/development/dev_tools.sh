#!/bin/zsh
#
# plugins/development/dev_tools.sh - Developer tool temporary files cleanup plugin
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

clean_dev_tool_temp() {
  local total_space_freed=0
  
  # IntelliJ IDEA
  local idea_dirs=(
    "$HOME/Library/Caches/JetBrains"
    "$HOME/Library/Application Support/JetBrains"
    "$HOME/Library/Logs/JetBrains"
  )
  
  for base_dir in "${idea_dirs[@]}"; do
    if [[ -d "$base_dir" ]]; then
      # Fix operator precedence: find directories named "caches" OR directories at maxdepth 1
      # Use parentheses to group conditions properly
      find "$base_dir" \( -type d -name "caches" -o -type d -maxdepth 1 \) | while read dir; do
        if [[ -d "$dir" && "$dir" != "$base_dir" ]]; then
          local space_before=$(calculate_size_bytes "$dir")
          if ! backup "$dir" "intellij_$(basename "$dir")"; then
            print_error "Backup failed for $dir. Aborting cleanup to prevent data loss."
            log_message "ERROR" "Backup failed for $dir, aborting"
            return 1
          fi
          safe_clean_dir "$dir" "IntelliJ $(basename "$dir")" || {
            print_error "Failed to clean $dir"
            return 1
          }
          
          local space_after=$(calculate_size_bytes "$dir")
          local space_freed=$((space_before - space_after))
          # Validate space_freed is not negative (directory may have grown during cleanup)
          if [[ $space_freed -lt 0 ]]; then
            space_freed=0
            log_message "WARNING" "Directory size increased during cleanup: $dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
          fi
          total_space_freed=$((total_space_freed + space_freed))
          print_success "Cleaned $dir."
        fi
      done
    fi
  done
  
  # VS Code
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
      local space_before=$(calculate_size_bytes "$dir")
      if ! backup "$dir" "vscode_$(basename "$dir")"; then
        print_error "Backup failed for $dir. Aborting cleanup to prevent data loss."
        log_message "ERROR" "Backup failed for $dir, aborting"
        return 1
      fi
      
      safe_clean_dir "$dir" "VS Code $(basename "$dir")" || {
        print_error "Failed to clean $dir"
        return 1
      }
      
      local space_after=$(calculate_size_bytes "$dir")
      local space_freed=$((space_before - space_after))
      # Validate space_freed is not negative (directory may have grown during cleanup)
      if [[ $space_freed -lt 0 ]]; then
        space_freed=0
        log_message "WARNING" "Directory size increased during cleanup: $dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
      fi
      total_space_freed=$((total_space_freed + space_freed))
      print_success "Cleaned $dir."
    fi
  done
  
  # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we only track per-operation
  track_space_saved "Developer Tool Temp Files" $total_space_freed "true"
  return 0
}

# Size calculation function for sweep
_calculate_dev_tool_temp_size_bytes() {
  local size_bytes=0
  local dev_tool_size=0
  
  # JetBrains: calculate size of subdirectories that will be cleaned
  typeset -A counted_jetbrains_dirs
  local jetbrains_base_dirs=(
    "$HOME/Library/Caches/JetBrains"
    "$HOME/Library/Application Support/JetBrains"
    "$HOME/Library/Logs/JetBrains"
  )
  for base_dir in "${jetbrains_base_dirs[@]}"; do
    if [[ -d "$base_dir" ]]; then
      while IFS= read -r dir; do
        if [[ -d "$dir" && "$dir" != "$base_dir" && -z "${counted_jetbrains_dirs[$dir]:-}" ]]; then
          counted_jetbrains_dirs[$dir]=1
          local dir_size=$(calculate_size_bytes "$dir" 2>/dev/null || echo "0")
          [[ "$dir_size" =~ ^[0-9]+$ ]] && dev_tool_size=$((dev_tool_size + dir_size))
        fi
      done < <(find "$base_dir" -maxdepth 1 -type d 2>/dev/null)
      while IFS= read -r dir; do
        if [[ -d "$dir" && "$dir" != "$base_dir" && -z "${counted_jetbrains_dirs[$dir]:-}" ]]; then
          counted_jetbrains_dirs[$dir]=1
          local dir_size=$(calculate_size_bytes "$dir" 2>/dev/null || echo "0")
          [[ "$dir_size" =~ ^[0-9]+$ ]] && dev_tool_size=$((dev_tool_size + dir_size))
        fi
      done < <(find "$base_dir" -type d -name "caches" 2>/dev/null)
    fi
  done
  
  # VS Code: specific cache directories
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
  echo "$size_bytes"
}

# Register plugin with size function
register_plugin "Developer Tool Temp Files" "development" "clean_dev_tool_temp" "false" "_calculate_dev_tool_temp_size_bytes"
