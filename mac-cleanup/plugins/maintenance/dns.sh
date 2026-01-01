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
  else
    run_as_admin "dscacheutil -flushcache; killall -HUP mDNSResponder" "DNS cache flush"
    print_success "DNS Cache flushed"
  fi
}

# Register plugin
register_plugin "Flush DNS Cache" "maintenance" "flush_dns_cache" "true"
