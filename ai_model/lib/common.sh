#!/bin/bash
# lib/common.sh - Core utilities for ai_model scripts
#
# Provides:
# - Color definitions
# - Print functions (print_header, print_info, print_status, print_warning, print_error, print_action, print_dry_run)
# - Hardware detection functions
# - Display formatting utilities
# - Verbosity control (VERBOSITY_LEVEL: 0=quiet, 1=normal, 2=verbose)

set -euo pipefail

#############################################
# Verbosity Control
#############################################
# 0 = Quiet (only errors and final summary)
# 1 = Normal (default, standard output)
# 2 = Verbose (all details including debug info)
VERBOSITY_LEVEL=${VERBOSITY_LEVEL:-1}

#############################################
# Color Definitions
#############################################
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Byte conversion constant
readonly BYTES_PER_GB=$((1024 * 1024 * 1024))

#############################################
# Print Functions
#############################################

# Clean, compact header (always shown)
print_header() {
    [[ $VERBOSITY_LEVEL -eq 0 ]] && return
    if [[ $VERBOSITY_LEVEL -ge 2 ]]; then
        # Verbose: show traditional headers
        echo -e "\n${BLUE}========================================${NC}"
        echo -e "${BLUE}$1${NC}"
        echo -e "${BLUE}========================================${NC}\n"
    else
        # Normal: clean compact header
        echo ""
        echo -e "${BOLD}${BLUE}▸ $1${NC}"
    fi
}

# Info messages (hidden in quiet mode)
print_info() {
    [[ $VERBOSITY_LEVEL -eq 0 ]] && return
    echo -e "${GRAY}  $1${NC}"
}

# Verbose-only info (only shown with -v)
print_verbose() {
    [[ $VERBOSITY_LEVEL -lt 2 ]] && return
    echo -e "${GRAY}  [v] $1${NC}"
}

# Status messages (always shown except quiet mode)
print_status() {
    [[ $VERBOSITY_LEVEL -eq 0 ]] && return
    echo -e "${GREEN}✓${NC} $1"
}

# Warning messages (always shown)
print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Error messages (always shown)
print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

# Action messages (shown in normal/verbose)
print_action() {
    [[ $VERBOSITY_LEVEL -eq 0 ]] && return
    echo -e "${CYAN}→${NC} $1"
}

# Dry run messages
print_dry_run() {
    [[ $VERBOSITY_LEVEL -eq 0 ]] && return
    echo -e "${YELLOW}[DRY-RUN]${NC} $1"
}

# Step indicator (compact, always shown except quiet)
print_step() {
    [[ $VERBOSITY_LEVEL -eq 0 ]] && return
    local step_num=$1
    local step_desc=$2
    echo -e "\n${BOLD}[$step_num]${NC} $step_desc"
}

# Compact summary line (always shown except quiet)
print_summary() {
    [[ $VERBOSITY_LEVEL -eq 0 ]] && return
    echo -e "${BLUE}▸${NC} $1"
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

#############################################
# Summary Display Functions
#############################################

# Print final setup summary in table format
print_setup_summary() {
    local chip=$1
    local ram=$2
    local cores=$3
    local gemma_model=$4
    local context=$5
    local codegemma=${6:-""}
    local ide_tools=$7

    echo ""
    echo -e "${BOLD}${GREEN}✨ Setup Complete!${NC}"
    echo ""

    # Configuration table
    echo "Configuration:"
    echo "┌─────────────────┬──────────────────────────────────────────────┐"
    printf "│ %-15s │ %-44s │\n" "Hardware" "${chip}, ${ram}GB RAM, ${cores} cores"
    printf "│ %-15s │ %-44s │\n" "Gemma4 Model" "${gemma_model} (${context}K)"
    if [[ -n "$codegemma" ]]; then
        printf "│ %-15s │ %-44s │\n" "CodeGemma" "${codegemma} (8K)"
    fi
    printf "│ %-15s │ %-44s │\n" "IDE Tools" "${ide_tools}"
    echo "└─────────────────┴──────────────────────────────────────────────┘"
    echo ""

    # Quick start
    echo -e "${BOLD}Quick Start:${NC}"
    if [[ "$ide_tools" == *"OpenCode"* ]] || [[ "$ide_tools" == *"opencode"* ]]; then
        echo "  opencode                             # Launch OpenCode"
    fi
    echo "  ollama run ${gemma_model}           # Test model"
    echo ""

    # Next steps
    echo -e "${BOLD}Next Steps:${NC}"
    if [[ "$ide_tools" == *"JetBrains"* ]] || [[ "$ide_tools" == *"jetbrains"* ]]; then
        echo "  • Configure JetBrains AI Assistant (see: ~/.config/gemma4-setup/jetbrains-config-reference.txt)"
    fi
    if [[ "$ide_tools" == *"OpenCode"* ]] || [[ "$ide_tools" == *"opencode"* ]]; then
        echo "  • Run 'opencode' to start coding"
    fi
    echo ""
    echo -e "${GRAY}Run './setup-gemma4-opencode.sh --help' for more options${NC}"
}
