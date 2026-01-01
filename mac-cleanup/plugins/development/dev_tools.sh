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
      find "$base_dir" -type d -name "caches" -o -type d -maxdepth 1 | while read dir; do
        if [[ -d "$dir" ]]; then
          local space_before=$(calculate_size_bytes "$dir")
          backup "$dir" "intellij_$(basename "$dir")"
          safe_clean_dir "$dir" "IntelliJ $(basename "$dir")"
          local space_after=$(calculate_size_bytes "$dir")
          total_space_freed=$((total_space_freed + space_before - space_after))
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
      backup "$dir" "vscode_$(basename "$dir")"
      safe_clean_dir "$dir" "VS Code $(basename "$dir")"
      local space_after=$(calculate_size_bytes "$dir")
      total_space_freed=$((total_space_freed + space_before - space_after))
      print_success "Cleaned $dir."
    fi
  done
  
  track_space_saved "Developer Tool Temp Files" $total_space_freed
}

# Register plugin
register_plugin "Developer Tool Temp Files" "development" "clean_dev_tool_temp" "false"
