#!/bin/zsh
#
# plugins/development/dev_tools.sh - Developer tool temporary files cleanup plugin
#

clean_dev_tool_temp() {
  print_header "Cleaning Developer Tool Temporary Files"
  
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
            print_error "Backup failed for $dir. Skipping this directory."
            log_message "ERROR" "Backup failed for $dir, skipping"
            continue
          fi
          safe_clean_dir "$dir" "IntelliJ $(basename "$dir")"
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
        print_error "Backup failed for $dir. Skipping this directory."
        log_message "ERROR" "Backup failed for $dir, skipping"
        continue
      fi
      safe_clean_dir "$dir" "VS Code $(basename "$dir")"
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
  
  # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we only update plugin-specific tracking
  MC_SPACE_SAVED_BY_OPERATION["Developer Tool Temp Files"]=$total_space_freed
  # Write to space tracking file if in background process (with locking)
  if [[ -n "${MC_SPACE_TRACKING_FILE:-}" && -f "$MC_SPACE_TRACKING_FILE" ]]; then
    _write_space_tracking_file "Developer Tool Temp Files" "$total_space_freed"
  fi
}

# Register plugin
register_plugin "Developer Tool Temp Files" "development" "clean_dev_tool_temp" "false"
