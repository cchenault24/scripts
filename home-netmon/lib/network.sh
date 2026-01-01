#!/bin/bash
# Home Network Monitor - Network Detection Functions
# Network detection (gateway, AdGuard, discovery)
# Compatible with macOS default Bash 3.2

# Prevent direct execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "This is a library file and should be sourced, not executed."
  exit 1
fi

#------------------------------------------------------------------------------
# Network Detection Functions
#------------------------------------------------------------------------------

detect_gateway() {
  route -n get default 2>/dev/null | awk '/gateway:/{print $2}' || true
}

ping_ok() {
  ping -c 1 -W 1000 "$1" >/dev/null 2>&1
}

detect_adguard_dns_port() {
  if ! command_exists docker; then
    return 1
  fi
  
  docker ps --format '{{.Names}}|{{.Ports}}' 2>/dev/null | awk -F'|' '
    tolower($1) ~ /adguard/ {
      if (match($2, /([0-9]{2,5})->53\/(tcp|udp)/, m)) {
        print m[1]; exit
      }
    }
  ' || true
}

discover_network_devices() {
  # Network device discovery (placeholder for future enhancement)
  # This will scan the local network and identify devices
  local gateway
  gateway=$(detect_gateway)
  
  if [ -z "$gateway" ]; then
    return 1
  fi
  
  # Extract network prefix (e.g., 192.168.1 from 192.168.1.1)
  local network_prefix
  network_prefix=$(echo "$gateway" | awk -F'.' '{print $1"."$2"."$3}')
  
  if [ -z "$network_prefix" ]; then
    return 1
  fi
  
  # Return network prefix for scanning
  echo "$network_prefix"
  return 0
}

get_network_info() {
  local info=""
  local gateway
  gateway=$(detect_gateway)
  
  if [ -n "$gateway" ]; then
    info="Gateway: $gateway"
  fi
  
  local adguard_port
  adguard_port=$(detect_adguard_dns_port)
  if [ -n "$adguard_port" ]; then
    if [ -n "$info" ]; then
      info="$info, AdGuard DNS: $adguard_port"
    else
      info="AdGuard DNS: $adguard_port"
    fi
  fi
  
  echo "$info"
}
