#!/bin/zsh
#
# plugins/development/xcode.sh - Xcode data cleanup plugin
#

clean_xcode_data() {
  print_header "Cleaning Xcode Data"
  
  print_warning "⚠️ CAUTION: Cleaning Xcode data will remove derived data, archives, and device support."
  print_warning "This may require Xcode to rebuild projects and re-index."
  
  if [[ "$MC_DRY_RUN" == "true" ]] || mc_confirm "Are you sure you want to clean Xcode data?"; then
    local total_space_freed=0
    
    # Xcode Derived Data
    local derived_data_dir="$HOME/Library/Developer/Xcode/DerivedData"
    if [[ -d "$derived_data_dir" ]]; then
      local space_before=$(calculate_size_bytes "$derived_data_dir")
      if ! backup "$derived_data_dir" "xcode_derived_data"; then
        print_error "Backup failed for Xcode Derived Data. Skipping this directory."
        log_message "ERROR" "Backup failed for Xcode Derived Data, skipping"
      else
        safe_clean_dir "$derived_data_dir" "Xcode Derived Data" || {
          print_error "Failed to clean Xcode Derived Data"
          return 1
        }
        
        local space_after=$(calculate_size_bytes "$derived_data_dir")
        local space_freed=$((space_before - space_after))
        
        # Validate space_freed is not negative
        if [[ $space_freed -lt 0 ]]; then
          space_freed=0
          log_message "WARNING" "Directory size increased during cleanup: $derived_data_dir"
        fi
        
        total_space_freed=$((total_space_freed + space_freed))
        print_success "Cleaned Xcode Derived Data."
      fi
    fi
    
    # Xcode Archives
    local archives_dir="$HOME/Library/Developer/Xcode/Archives"
    if [[ -d "$archives_dir" ]]; then
      print_warning "Archives contain built apps. Consider backing up important archives first."
      if [[ "$MC_DRY_RUN" == "true" ]] || mc_confirm "Do you want to clean Xcode Archives?"; then
        local space_before=$(calculate_size_bytes "$archives_dir")
        if ! backup "$archives_dir" "xcode_archives"; then
          print_error "Backup failed for Xcode Archives. Aborting cleanup to prevent data loss."
          log_message "ERROR" "Backup failed, aborting Xcode Archives cleanup"
          return 1
        fi
        
        safe_clean_dir "$archives_dir" "Xcode Archives" || {
          print_error "Failed to clean Xcode Archives"
          return 1
        }
        
        local space_after=$(calculate_size_bytes "$archives_dir")
        local space_freed=$((space_before - space_after))
        
        # Validate space_freed is not negative
        if [[ $space_freed -lt 0 ]]; then
          space_freed=0
          log_message "WARNING" "Directory size increased during cleanup: $archives_dir"
        fi
        
        total_space_freed=$((total_space_freed + space_freed))
        print_success "Cleaned Xcode Archives."
      fi
    fi
    
    # Xcode Device Support
    local device_support_dir="$HOME/Library/Developer/Xcode/iOS DeviceSupport"
    if [[ -d "$device_support_dir" ]]; then
      local space_before=$(calculate_size_bytes "$device_support_dir")
      if ! backup "$device_support_dir" "xcode_device_support"; then
        print_error "Backup failed for Xcode Device Support. Aborting cleanup to prevent data loss."
        log_message "ERROR" "Backup failed for Xcode Device Support, aborting"
        return 1
      fi
      
      safe_clean_dir "$device_support_dir" "Xcode Device Support" || {
        print_error "Failed to clean Xcode Device Support"
        return 1
      }
      
      local space_after=$(calculate_size_bytes "$device_support_dir")
      local space_freed=$((space_before - space_after))
      
      # Validate space_freed is not negative
      if [[ $space_freed -lt 0 ]]; then
        space_freed=0
        log_message "WARNING" "Directory size increased during cleanup: $device_support_dir"
      fi
      
      total_space_freed=$((total_space_freed + space_freed))
      print_success "Cleaned Xcode Device Support."
    fi
    
    # Xcode Caches
    local xcode_caches_dir="$HOME/Library/Caches/com.apple.dt.Xcode"
    if [[ -d "$xcode_caches_dir" ]]; then
      local space_before=$(calculate_size_bytes "$xcode_caches_dir")
      if ! backup "$xcode_caches_dir" "xcode_caches"; then
        print_error "Backup failed for Xcode Caches. Aborting cleanup to prevent data loss."
        log_message "ERROR" "Backup failed for Xcode Caches, aborting"
        return 1
      fi
      
      safe_clean_dir "$xcode_caches_dir" "Xcode Caches" || {
        print_error "Failed to clean Xcode Caches"
        return 1
      }
      
      local space_after=$(calculate_size_bytes "$xcode_caches_dir")
      local space_freed=$((space_before - space_after))
      
      # Validate space_freed is not negative
      if [[ $space_freed -lt 0 ]]; then
        space_freed=0
        log_message "WARNING" "Directory size increased during cleanup: $xcode_caches_dir"
      fi
      
      total_space_freed=$((total_space_freed + space_freed))
      print_success "Cleaned Xcode Caches."
    fi
    
    if [[ $total_space_freed -eq 0 ]]; then
      print_warning "No Xcode data found to clean."
      track_space_saved "Xcode Data" 0
    else
      # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we only track per-operation
      track_space_saved "Xcode Data" $total_space_freed "true"
      print_warning "You may need to rebuild Xcode projects after this cleanup."
    fi
  else
    print_info "Skipping Xcode data cleanup"
    track_space_saved "Xcode Data" 0
  fi
  
  return 0
}

# Size calculation function for sweep
_calculate_xcode_data_size_bytes() {
  local size_bytes=0
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
  echo "$size_bytes"
}

# Register plugin with size function
register_plugin "Xcode Data" "development" "clean_xcode_data" "false" "_calculate_xcode_data_size_bytes"
