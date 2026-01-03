#!/bin/zsh
#
# plugins/system/temp_files.sh - Temporary files cleanup plugin
#

clean_temp_files() {
  print_header "Cleaning Temporary Files"
  
  local temp_dirs=("/tmp" "$TMPDIR" "$HOME/Library/Application Support/Temp")
  local total_space_freed=0
  
  for temp_dir in "${temp_dirs[@]}"; do
    # Early exit for non-existent or empty directories (PERF-6)
    if [[ ! -d "$temp_dir" ]] || [[ -z "$(ls -A "$temp_dir" 2>/dev/null)" ]]; then
      continue
    fi
    
    # For /tmp, cache find results to avoid running find twice (PERF-4)
    local space_before=0
    local files_to_clean=()
    
    if [[ "$temp_dir" == "/tmp" ]]; then
      # Single find operation: collect files and calculate size in one pass
      while IFS= read -r -d '' item; do
        files_to_clean+=("$item")
        # Calculate size incrementally (more efficient than separate find)
        local item_size=$(du -sk "$item" 2>/dev/null | awk '{print $1}')
        if [[ -n "$item_size" && "$item_size" =~ ^[0-9]+$ ]]; then
          space_before=$((space_before + item_size * 1024))
        fi
      done < <(find "$temp_dir" -mindepth 1 ! -name ".X*" ! -name "com.apple.*" -print0 2>/dev/null)
    else
      space_before=$(calculate_size_bytes "$temp_dir")
    fi
    
    # Early exit if nothing to clean
    if [[ $space_before -eq 0 ]]; then
      print_info "No files to clean in $temp_dir (already empty)."
      continue
    fi
    
    if ! backup "$temp_dir" "temp_files_$(basename "$temp_dir")"; then
      print_error "Backup failed for $temp_dir. Skipping this directory."
      log_message "ERROR" "Backup failed for $temp_dir, skipping"
      continue
    fi
    
    # Skip certain system files in /tmp
    if [[ "$temp_dir" == "/tmp" ]]; then
      # Use cached file list for deletion (reuse find results from above)
      if [[ ${#files_to_clean[@]} -gt 0 ]]; then
        # Batch delete using the cached list
        printf '%s\0' "${files_to_clean[@]}" | xargs -0 rm -rf 2>/dev/null || {
          # Fallback: delete individually if batch fails
          for item in "${files_to_clean[@]}"; do
            safe_remove "$item" "$(basename "$item")"
          done
        }
      fi
      # Invalidate cache after manual cleanup
      invalidate_size_cache "$temp_dir"
    else
      safe_clean_dir "$temp_dir" "$(basename "$temp_dir")"
    fi
      
      # Clear cache and recalculate to get accurate space_after
      invalidate_size_cache "$temp_dir"
      local space_after=$(calculate_size_bytes "$temp_dir")
      local space_freed=$((space_before - space_after))
      
      # Validate space_freed is not negative (directory may have grown during cleanup)
      if [[ $space_freed -lt 0 ]]; then
        space_freed=0
        log_message "WARNING" "Directory size increased during cleanup: $temp_dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
      fi
      
      total_space_freed=$((total_space_freed + space_freed))
      
      if [[ $space_freed -gt 0 ]]; then
        print_success "Cleaned $temp_dir (freed $(format_bytes $space_freed))."
      else
        print_info "No files to clean in $temp_dir (already empty)."
      fi
    fi
  done
  
  # safe_clean_dir/safe_remove already update MC_TOTAL_SPACE_SAVED, so we only update plugin-specific tracking
  MC_SPACE_SAVED_BY_OPERATION["Temporary Files"]=$total_space_freed
  # Write to space tracking file if in background process (with locking)
  if [[ -n "${MC_SPACE_TRACKING_FILE:-}" && -f "$MC_SPACE_TRACKING_FILE" ]]; then
    _write_space_tracking_file "Temporary Files" "$total_space_freed"
  fi
}

# Register plugin
register_plugin "Temporary Files" "system" "clean_temp_files" "false"
