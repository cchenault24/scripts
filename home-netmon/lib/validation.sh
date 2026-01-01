#!/bin/bash
# Home Network Monitor - Validation Functions
# Input validation (IP, ports, sanitization)
# Compatible with macOS default Bash 3.2

# Prevent direct execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "This is a library file and should be sourced, not executed."
  exit 1
fi

#------------------------------------------------------------------------------
# Validation Functions
#------------------------------------------------------------------------------

validate_ip() {
  local ip="$1"
  
  # Basic format check (bash 3.2 compatible - no regex)
  local octet1 octet2 octet3 octet4
  IFS='.' read -r octet1 octet2 octet3 octet4 <<< "$ip" || return 1
  
  # Check we have 4 octets
  if [ -z "$octet1" ] || [ -z "$octet2" ] || [ -z "$octet3" ] || [ -z "$octet4" ]; then
    return 1
  fi
  
  # Validate each octet is numeric and in range
  for octet in "$octet1" "$octet2" "$octet3" "$octet4"; do
    case "$octet" in
      *[!0-9]*) return 1 ;;
    esac
    if [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ]; then
      return 1
    fi
  done
  
  return 0
}

validate_port() {
  local port="$1"
  
  # Check if numeric
  case "$port" in
    *[!0-9]*) return 1 ;;
  esac
  
  # Check range
  if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    return 1
  fi
  
  # Check if port is in use (if lsof is available)
  if command_exists lsof; then
    if lsof -i ":$port" >/dev/null 2>&1; then
      return 1
    fi
  fi
  
  return 0
}

prompt_ip() {
  local label="$1"
  local hint="$2"
  local def="$3"
  local ip=""

  while true; do
    echo ""
    echo "$label"
    echo "($hint)"
    read -r -p "[default: ${def}]: " ip || true
    ip="${ip:-$def}"
    
    if command -v sanitize_input >/dev/null 2>&1; then
      ip=$(sanitize_input "$ip")
    fi

    if ! validate_ip "$ip"; then
      if command -v warn >/dev/null 2>&1; then
        warn "Invalid IP address format. Please enter a valid IP (e.g., 192.168.1.1)"
      fi
      continue
    fi

    if command -v ping_ok >/dev/null 2>&1 && ping_ok "$ip"; then
      echo "$ip"
      return 0
    fi

    if command -v warn >/dev/null 2>&1; then
      warn "Ping to $ip failed."
    fi
    if command -v confirm >/dev/null 2>&1 && confirm "Accept this IP anyway?" "n"; then
      echo "$ip"
      return 0
    fi
  done
}
