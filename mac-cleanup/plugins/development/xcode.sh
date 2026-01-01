#!/bin/zsh
#
# plugins/development/xcode.sh - Xcode data cleanup plugin
#

clean_xcode_data() {
  print_header "Cleaning Xcode Data"
  
  print_warning "⚠️ CAUTION: Cleaning Xcode data will remove derived data, archives, and device support."
  print_warning "This may require Xcode to rebuild projects and re-index."
  
  if [[ "$MC_DRY_RUN" == "true" ]] || gum confirm "Are you sure you want to clean Xcode data?"; then
    local total_space_freed=0
    
    # Xcode Derived Data
    local derived_data_dir="$HOME/Library/Developer/Xcode/DerivedData"
    if [[ -d "$derived_data_dir" ]]; then
      local space_before=$(calculate_size_bytes "$derived_data_dir")
      backup "$derived_data_dir" "xcode_derived_data"
      safe_clean_dir "$derived_data_dir" "Xcode Derived Data"
      local space_after=$(calculate_size_bytes "$derived_data_dir")
      total_space_freed=$((total_space_freed + space_before - space_after))
      print_success "Cleaned Xcode Derived Data."
    fi
    
    # Xcode Archives
    local archives_dir="$HOME/Library/Developer/Xcode/Archives"
    if [[ -d "$archives_dir" ]]; then
      print_warning "Archives contain built apps. Consider backing up important archives first."
      if [[ "$MC_DRY_RUN" == "true" ]] || gum confirm "Do you want to clean Xcode Archives?"; then
        local space_before=$(calculate_size_bytes "$archives_dir")
        backup "$archives_dir" "xcode_archives"
        safe_clean_dir "$archives_dir" "Xcode Archives"
        local space_after=$(calculate_size_bytes "$archives_dir")
        total_space_freed=$((total_space_freed + space_before - space_after))
        print_success "Cleaned Xcode Archives."
      fi
    fi
    
    # Xcode Device Support
    local device_support_dir="$HOME/Library/Developer/Xcode/iOS DeviceSupport"
    if [[ -d "$device_support_dir" ]]; then
      local space_before=$(calculate_size_bytes "$device_support_dir")
      backup "$device_support_dir" "xcode_device_support"
      safe_clean_dir "$device_support_dir" "Xcode Device Support"
      local space_after=$(calculate_size_bytes "$device_support_dir")
      total_space_freed=$((total_space_freed + space_before - space_after))
      print_success "Cleaned Xcode Device Support."
    fi
    
    # Xcode Caches
    local xcode_caches_dir="$HOME/Library/Caches/com.apple.dt.Xcode"
    if [[ -d "$xcode_caches_dir" ]]; then
      local space_before=$(calculate_size_bytes "$xcode_caches_dir")
      backup "$xcode_caches_dir" "xcode_caches"
      safe_clean_dir "$xcode_caches_dir" "Xcode Caches"
      local space_after=$(calculate_size_bytes "$xcode_caches_dir")
      total_space_freed=$((total_space_freed + space_before - space_after))
      print_success "Cleaned Xcode Caches."
    fi
    
    if [[ $total_space_freed -eq 0 ]]; then
      print_warning "No Xcode data found to clean."
    else
      track_space_saved "Xcode Data" $total_space_freed
      print_warning "You may need to rebuild Xcode projects after this cleanup."
    fi
  else
    print_info "Skipping Xcode data cleanup"
  fi
}

# Register plugin
register_plugin "Xcode Data" "development" "clean_xcode_data" "false"
