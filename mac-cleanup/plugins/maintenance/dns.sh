#!/bin/zsh
#
# plugins/maintenance/dns.sh - DNS cache flush plugin
#

flush_dns_cache() {
  print_header "Flushing DNS Cache"
  
  print_info "Flushing DNS Cache..."
  
  if [[ "$MC_DRY_RUN" == "true" ]]; then
    print_info "[DRY RUN] Would flush DNS cache"
    log_message "DRY_RUN" "Would flush DNS cache"
    track_space_saved "Flush DNS Cache" 0
    return 0
  else
    # DNS cache flush command doesn't use variables, but ensure it's properly quoted
    run_as_admin "dscacheutil -flushcache && killall -HUP mDNSResponder" "DNS cache flush" || {
      print_error "Failed to flush DNS cache"
      return 1
    }
    print_success "DNS Cache flushed"
    # DNS flush doesn't free disk space, but we track it for consistency
    track_space_saved "Flush DNS Cache" 0
    return 0
  fi
}

# Size calculation function for sweep (DNS flush doesn't free space)
_calculate_flush_dns_cache_size_bytes() {
  echo "0"
}

# Register plugin with size function
register_plugin "Flush DNS Cache" "maintenance" "flush_dns_cache" "true" "_calculate_flush_dns_cache_size_bytes"
