#!/bin/zsh
#
# plugins/system/temp_files.sh - Temporary files cleanup plugin
#

clean_temp_files() {
  print_header "Cleaning Temporary Files"
  
  local temp_dirs=("/tmp" "$TMPDIR" "$HOME/Library/Application Support/Temp")
  local total_space_freed=0
  
  for temp_dir in "${temp_dirs[@]}"; do
    if [[ -d "$temp_dir" ]]; then
      local space_before=$(calculate_size_bytes "$temp_dir")
      backup "$temp_dir" "temp_files_$(basename "$temp_dir")"
      
      # Skip certain system files in /tmp
      if [[ "$temp_dir" == "/tmp" ]]; then
        find "$temp_dir" -mindepth 1 ! -name ".X*" ! -name "com.apple.*" -delete 2>/dev/null || {
          find "$temp_dir" -mindepth 1 ! -name ".X*" ! -name "com.apple.*" | while read item; do
            safe_remove "$item" "$(basename "$item")"
          done
        }
      else
        safe_clean_dir "$temp_dir" "$(basename "$temp_dir")"
      fi
      
      local space_after=$(calculate_size_bytes "$temp_dir")
      local space_freed=$((space_before - space_after))
      total_space_freed=$((total_space_freed + space_freed))
      
      print_success "Cleaned $temp_dir."
    fi
  done
  
  track_space_saved "Temporary Files" $total_space_freed
}

# Register plugin
register_plugin "Temporary Files" "system" "clean_temp_files" "false"
