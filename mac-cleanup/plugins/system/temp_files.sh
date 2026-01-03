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
      # For /tmp, calculate size excluding files that will be skipped
      local space_before=0
      if [[ "$temp_dir" == "/tmp" ]]; then
        # Calculate size of files that will actually be cleaned
        local find_output=$(find "$temp_dir" -mindepth 1 ! -name ".X*" ! -name "com.apple.*" -print0 2>/dev/null | xargs -0 du -sk 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
        if [[ -n "$find_output" && "$find_output" =~ ^[0-9]+$ ]]; then
          space_before=$((find_output * 1024))
        fi
      else
        space_before=$(calculate_size_bytes "$temp_dir")
      fi
      backup "$temp_dir" "temp_files_$(basename "$temp_dir")"
      
      # Skip certain system files in /tmp
      if [[ "$temp_dir" == "/tmp" ]]; then
        find "$temp_dir" -mindepth 1 ! -name ".X*" ! -name "com.apple.*" -delete 2>/dev/null || {
          find "$temp_dir" -mindepth 1 ! -name ".X*" ! -name "com.apple.*" | while read item; do
            safe_remove "$item" "$(basename "$item")"
          done
        }
        # Invalidate cache after manual cleanup
        invalidate_size_cache "$temp_dir"
      else
        safe_clean_dir "$temp_dir" "$(basename "$temp_dir")"
      fi
      
      # Clear cache and recalculate to get accurate space_after
      invalidate_size_cache "$temp_dir"
      local space_after=$(calculate_size_bytes "$temp_dir")
      local space_freed=$((space_before - space_after))
      total_space_freed=$((total_space_freed + space_freed))
      
      if [[ $space_freed -gt 0 ]]; then
        print_success "Cleaned $temp_dir (freed $(format_bytes $space_freed))."
      else
        print_info "No files to clean in $temp_dir (already empty)."
      fi
    fi
  done
  
  track_space_saved "Temporary Files" $total_space_freed
}

# Register plugin
register_plugin "Temporary Files" "system" "clean_temp_files" "false"
