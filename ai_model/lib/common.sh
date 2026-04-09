#!/bin/bash
# lib/common.sh - Core utilities for ai_model scripts
#
# Provides:
# - Color definitions
# - Print functions (print_header, print_info, print_status, print_warning, print_error, print_action, print_dry_run)
# - Hardware detection functions
# - Display formatting utilities

set -euo pipefail

#############################################
# Color Definitions
#############################################
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#############################################
# Print Functions
#############################################

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_status() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}" >&2
}

print_action() {
    echo -e "${CYAN}→ $1${NC}"
}

print_dry_run() {
    echo -e "${YELLOW}[DRY-RUN]${NC} $1"
}

#############################################
# Hardware Detection Functions
#############################################

# Detect hardware profile in a single batch call (more efficient than separate sysctl calls)
# Returns: "M_CHIP RAM_GB CPU_CORES"
detect_hardware_profile() {
    local cpu_brand ram_bytes cpu_cores

    # Batch sysctl call - gets all values in one subprocess
    cpu_brand=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
    ram_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
    cpu_cores=$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "8")

    # Parse chip generation
    local m_chip="Unknown"
    if echo "$cpu_brand" | grep -q "Apple M5"; then
        m_chip="M5"
    elif echo "$cpu_brand" | grep -q "Apple M4"; then
        m_chip="M4"
    elif echo "$cpu_brand" | grep -q "Apple M3"; then
        m_chip="M3"
    elif echo "$cpu_brand" | grep -q "Apple M2"; then
        m_chip="M2"
    elif echo "$cpu_brand" | grep -q "Apple M1"; then
        m_chip="M1"
    fi

    local ram_gb=$((ram_bytes / 1024 / 1024 / 1024))

    echo "$m_chip $ram_gb $cpu_cores"
}

#############################################
# Display Formatting Utilities
#############################################

# Get size of file or directory in bytes
get_size() {
    local path="$1"
    if [[ -e "$path" ]]; then
        # du handles both files and directories efficiently
        du -sk "$path" 2>/dev/null | awk '{print $1 * 1024}' || echo "0"
    else
        echo "0"
    fi
}

# Format bytes to human-readable format
format_bytes() {
    local bytes=$1
    if command -v numfmt &> /dev/null; then
        numfmt --to=iec-i --suffix=B "$bytes" 2>/dev/null || echo "${bytes} bytes"
    else
        # Fallback if numfmt not available
        local gb=$((bytes / 1024 / 1024 / 1024))
        if [[ $gb -gt 0 ]]; then
            echo "${gb}GB"
        else
            local mb=$((bytes / 1024 / 1024))
            if [[ $mb -gt 0 ]]; then
                echo "${mb}MB"
            else
                echo "$((bytes / 1024))KB"
            fi
        fi
    fi
}
