#!/bin/zsh
#
# plugins/system/containers.sh - Application container caches and saved states cleanup plugin
#

clean_container_caches() {
  print_header "Cleaning Application Container Caches"
  
  local containers_dir="$HOME/Library/Containers"
  local total_space_freed=0
  
  if [[ -d "$containers_dir" ]]; then
    backup "$containers_dir" "app_containers"
    
    while IFS= read -r dir; do
      [[ -z "$dir" ]] && continue
      local app_name=$(echo "$dir" | awk -F'/' '{print $(NF-2)}')
      local space_before=$(calculate_size_bytes "$dir")
      safe_clean_dir "$dir" "$app_name container cache"
      local space_after=$(calculate_size_bytes "$dir")
      total_space_freed=$((total_space_freed + space_before - space_after))
      print_success "Cleaned $app_name container cache."
    done < <(find "$containers_dir" -type d -name "Caches" 2>/dev/null)
    
    track_space_saved "Application Container Caches" $total_space_freed
  else
    print_warning "No application containers found."
  fi
}

clean_saved_states() {
  print_header "Cleaning Saved Application States"
  
  local saved_states_dir="$HOME/Library/Saved Application State"
  
  if [[ -d "$saved_states_dir" ]]; then
    local space_before=$(calculate_size_bytes "$saved_states_dir")
    backup "$saved_states_dir" "saved_app_states"
    safe_clean_dir "$saved_states_dir" "saved application states"
    local space_after=$(calculate_size_bytes "$saved_states_dir")
    track_space_saved "Saved Application States" $((space_before - space_after))
    print_success "Cleaned saved application states."
  else
    print_warning "No saved application states found."
  fi
}

# Register plugins
register_plugin "Application Container Caches" "system" "clean_container_caches" "false"
register_plugin "Saved Application States" "system" "clean_saved_states" "false"
