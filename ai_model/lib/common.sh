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

# Byte conversion constants
readonly BYTES_PER_GB=$((1024 * 1024 * 1024))
readonly BYTES_PER_MB=$((1024 * 1024))
readonly BYTES_PER_KB=1024

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
    local m_chip
    case "$cpu_brand" in
        *"Apple M5"*) m_chip="M5" ;;
        *"Apple M4"*) m_chip="M4" ;;
        *"Apple M3"*) m_chip="M3" ;;
        *"Apple M2"*) m_chip="M2" ;;
        *"Apple M1"*) m_chip="M1" ;;
        *) m_chip="Unknown" ;;
    esac

    local ram_gb=$((ram_bytes / BYTES_PER_GB))

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

# Format context length to K notation (e.g., 65536 -> "64K")
format_context_k() {
    local context_tokens=$1
    echo "$((context_tokens / 1024))K"
}

# Format context for display (K notation if >= 100K, otherwise comma-separated)
format_context_display() {
    local context_tokens=$1
    if [[ $context_tokens -ge 100000 ]]; then
        format_context_k "$context_tokens"
    else
        printf "%'d" "$context_tokens"
    fi
}

# Generate custom model name with context suffix
generate_custom_model_name() {
    local model_size=$1
    local context_tokens=$2
    local context_k=$((context_tokens / 1024))
    echo "gemma4-optimized-${model_size}-${context_k}k"
}

# Validate model name against allowed list
validate_model_name() {
    local model="$1"

    # First check against allowed patterns
    case "$model" in
        gemma4:e2b|gemma4:latest|gemma4:26b|gemma4:31b)
            # Verify exact length to detect null bytes or other hidden characters
            # gemma4:e2b=10, gemma4:latest=13, gemma4:26b=10, gemma4:31b=10
            # Bash preserves null bytes in length, so 'gemma4:e2b\0' would be length 11
            local expected_len
            case "$model" in
                gemma4:latest) expected_len=13 ;;
                gemma4:e2b|gemma4:26b|gemma4:31b) expected_len=10 ;;
            esac

            if [ ${#model} -ne "$expected_len" ]; then
                print_error "Invalid model name: contains invalid characters"
                return 1
            fi
            return 0
            ;;
        *)
            print_error "Invalid model name: $model"
            print_info "Allowed models: gemma4:e2b, gemma4:latest, gemma4:26b, gemma4:31b"
            return 1
            ;;
    esac
}

# Get ollama list output (cached to avoid multiple subprocess calls)
OLLAMA_LIST_CACHE=""
get_ollama_list() {
    if [[ -z "$OLLAMA_LIST_CACHE" ]]; then
        OLLAMA_LIST_CACHE=$(ollama list 2>/dev/null || echo "")
    fi
    echo "$OLLAMA_LIST_CACHE"
}

# Clear ollama list cache (call after pulling new models)
clear_ollama_cache() {
    OLLAMA_LIST_CACHE=""
}
