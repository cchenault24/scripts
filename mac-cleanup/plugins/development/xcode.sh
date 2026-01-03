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
        safe_clean_dir "$derived_data_dir" "Xcode Derived Data"
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
        else
          safe_clean_dir "$archives_dir" "Xcode Archives"
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
    fi
    
    # Xcode Device Support
    local device_support_dir="$HOME/Library/Developer/Xcode/iOS DeviceSupport"
    if [[ -d "$device_support_dir" ]]; then
      local space_before=$(calculate_size_bytes "$device_support_dir")
      if ! backup "$device_support_dir" "xcode_device_support"; then
        print_error "Backup failed for Xcode Device Support. Skipping this directory."
        log_message "ERROR" "Backup failed for Xcode Device Support, skipping"
      else
        safe_clean_dir "$device_support_dir" "Xcode Device Support"
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
    fi
    
    # Xcode Caches
    local xcode_caches_dir="$HOME/Library/Caches/com.apple.dt.Xcode"
    if [[ -d "$xcode_caches_dir" ]]; then
      local space_before=$(calculate_size_bytes "$xcode_caches_dir")
      if ! backup "$xcode_caches_dir" "xcode_caches"; then
        print_error "Backup failed for Xcode Caches. Skipping this directory."
        log_message "ERROR" "Backup failed for Xcode Caches, skipping"
      else
        safe_clean_dir "$xcode_caches_dir" "Xcode Caches"
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
    fi
    
    if [[ $total_space_freed -eq 0 ]]; then
      print_warning "No Xcode data found to clean."
    else
      # safe_clean_dir already updates MC_TOTAL_SPACE_SAVED, so we only update plugin-specific tracking
      MC_SPACE_SAVED_BY_OPERATION["Xcode Data"]=$total_space_freed
      # Write to space tracking file if in background process (with locking)
      if [[ -n "${MC_SPACE_TRACKING_FILE:-}" && -f "$MC_SPACE_TRACKING_FILE" ]]; then
        _write_space_tracking_file "Xcode Data" "$total_space_freed"
      fi
      print_warning "You may need to rebuild Xcode projects after this cleanup."
    fi
  else
    print_info "Skipping Xcode data cleanup"
  fi
}

# Register plugin
register_plugin "Xcode Data" "development" "clean_xcode_data" "false"
