#!/bin/bash
#
# hardware.sh - Hardware detection and tier classification for setup-local-llm.sh
#
# Depends on: constants.sh, logger.sh, ui.sh

# Hardware detection
detect_hardware() {
  print_header "🔍 Hardware Detection"
  
  # CPU architecture
  local cpu_brand cpu_arch cpu_cores ram_bytes ram_gb disk_available
  cpu_brand=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
  cpu_arch=$(uname -m)
  cpu_cores=$(sysctl -n hw.physicalcpu 2>/dev/null || echo "0")
  
  # RAM detection
  ram_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
  ram_gb=$((ram_bytes / 1024 / 1024 / 1024))
  
  # Disk space
  disk_available=$(df -h "$HOME" | awk 'NR==2 {print $4}' | sed 's/[^0-9.]//g' || echo "0")
  
  print_info "CPU: $cpu_brand"
  print_info "Architecture: $cpu_arch"
  print_info "Cores: $cpu_cores"
  print_info "RAM: ${ram_gb}GB"
  print_info "Available Disk: ${disk_available}GB"
  
  # Classify tier
  if [[ $ram_gb -ge $TIER_S_MIN ]]; then
    HARDWARE_TIER="S"
    TIER_LABEL="Tier S (≥49GB RAM)"
  elif [[ $ram_gb -ge $TIER_A_MIN ]]; then
    HARDWARE_TIER="A"
    TIER_LABEL="Tier A (33-48GB RAM)"
  elif [[ $ram_gb -ge $TIER_B_MIN ]]; then
    HARDWARE_TIER="B"
    TIER_LABEL="Tier B (17-32GB RAM)"
  else
    HARDWARE_TIER="C"
    TIER_LABEL="Tier C (<17GB RAM)"
  fi
  
  log_info "Hardware tier: $HARDWARE_TIER ($TIER_LABEL)"
  print_success "Detected: $TIER_LABEL"
  
  # Store hardware info
  CPU_ARCH="$cpu_arch"
  CPU_CORES="$cpu_cores"
  RAM_GB="$ram_gb"
  DISK_AVAILABLE="$disk_available"
  
  # Validate Apple Silicon
  if [[ "$cpu_arch" != "arm64" ]]; then
    log_error "This script is optimized for Apple Silicon (arm64). Detected: $cpu_arch"
    exit 1
  fi
}
