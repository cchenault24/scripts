#!/bin/zsh
#
# plugins/system/temp_files.sh - Temporary files cleanup plugin
#

clean_temp_files() {
  print_header "Cleaning Temporary Files"
  
  local temp_dirs=("/tmp" "$TMPDIR" "$HOME/Library/Application Support/Temp")
  local total_space_freed=0
  
  for temp_dir in "${temp_dirs[@]}"; do
    # Skip non-existent directories
    if [[ ! -d "$temp_dir" ]]; then
      continue
    fi
    
    # Check if directory is empty
    local is_empty=false
    if [[ -z "$(ls -A "$temp_dir" 2>/dev/null)" ]]; then
      is_empty=true
    fi
    
    # For /tmp, cache find results to avoid running find twice (PERF-4)
    local space_before=0
    local files_to_clean=()
    
    if [[ "$temp_dir" == "/tmp" ]]; then
      # Single find operation: collect files and calculate size in one pass
      # Exclude script's own temp files (mac-cleanup-*) to avoid cleaning them
      local temp_prefix="${MC_TEMP_PREFIX:-mac-cleanup}"
      while IFS= read -r -d '' item; do
        files_to_clean+=("$item")
        # Calculate size incrementally (more efficient than separate find)
        local item_size=$(du -sk "$item" 2>/dev/null | awk '{print $1}')
        if [[ -n "$item_size" && "$item_size" =~ ^[0-9]+$ ]]; then
          space_before=$((space_before + item_size * 1024))
        fi
      done < <(find "$temp_dir" -mindepth 1 ! -name ".X*" ! -name "com.apple.*" ! -name "${temp_prefix}-*" -print0 2>/dev/null)
    else
      space_before=$(calculate_size_bytes "$temp_dir")
    fi
    
    # If nothing to clean, remove the directory itself (except /tmp which is a system directory)
    if [[ $space_before -eq 0 ]] || [[ "$is_empty" == "true" ]]; then
      
      # Never remove /tmp (it's a system directory)
      if [[ "$temp_dir" != "/tmp" ]]; then
        # Calculate directory size before removal
        local dir_size=$(calculate_size_bytes "$temp_dir")
        
        if [[ $dir_size -gt 0 ]]; then
          # Backup before removing directory
          if backup "$temp_dir" "temp_dir_$(basename "$temp_dir")"; then
            # Remove the empty directory
            if rmdir "$temp_dir" 2>/dev/null || rm -rf "$temp_dir" 2>/dev/null; then
              print_success "Removed empty directory: $temp_dir (freed $(format_bytes $dir_size))."
              log_message "SUCCESS" "Removed empty directory: $temp_dir (freed $(format_bytes $dir_size))"
              total_space_freed=$((total_space_freed + dir_size))
              MC_TOTAL_SPACE_SAVED=$((MC_TOTAL_SPACE_SAVED + dir_size))
            else
              print_warning "Could not remove directory: $temp_dir"
              log_message "WARNING" "Could not remove directory: $temp_dir"
            fi
          else
            print_warning "Backup failed for empty directory: $temp_dir. Skipping removal."
            log_message "WARNING" "Backup failed for empty directory: $temp_dir"
          fi
        else
          print_info "Directory $temp_dir is already empty (no space to free)."
        fi
      else
        print_info "No files to clean in $temp_dir (already empty)."
      fi
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
  done
  
  # safe_clean_dir/safe_remove already update MC_TOTAL_SPACE_SAVED, so we only track per-operation
  track_space_saved "Temporary Files" $total_space_freed "true"
  return 0
}

# Size calculation function for sweep
_calculate_temp_files_size_bytes() {
  local size_bytes=0
  for temp_dir in "/tmp" "$TMPDIR" "$HOME/Library/Application Support/Temp"; do
    if [[ -d "$temp_dir" ]]; then
      local dir_size=0
      # For /tmp, calculate size excluding files that cleanup will skip (.X*, com.apple.*, and script's own temp files)
      if [[ "$temp_dir" == "/tmp" ]]; then
        local temp_prefix="${MC_TEMP_PREFIX:-mac-cleanup}"
        while IFS= read -r -d '' item; do
          local item_size=$(du -sk "$item" 2>/dev/null | awk '{print $1}')
          if [[ -n "$item_size" && "$item_size" =~ ^[0-9]+$ ]]; then
            dir_size=$((dir_size + item_size * 1024))
          fi
        done < <(find "$temp_dir" -mindepth 1 ! -name ".X*" ! -name "com.apple.*" ! -name "${temp_prefix}-*" -print0 2>/dev/null)
      else
        dir_size=$(calculate_size_bytes "$temp_dir" 2>/dev/null || echo "0")
      fi
      [[ "$dir_size" =~ ^[0-9]+$ ]] && size_bytes=$((size_bytes + dir_size))
    fi
  done
  echo "$size_bytes"
}

# Register plugin with size function
register_plugin "Temporary Files" "system" "clean_temp_files" "false" "_calculate_temp_files_size_bytes"
