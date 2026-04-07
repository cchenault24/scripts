#!/bin/bash
# common.sh - Core utilities library for AI model setup
# This file should be sourced, not executed directly

#############################################
# Color Definitions
#############################################
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

#############################################
# Print Functions
#############################################

# Print a bold blue header with separator line
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Print blue info message
print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Print green status with checkmark
print_status() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Print yellow warning
print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Print red error message
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

#############################################
# Hardware Detection Functions
#############################################

# Detect Apple Silicon chip (M1, M2, M3, M4, M5)
detect_m_chip() {
    local brand_string
    brand_string=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "")

    if [[ "$brand_string" =~ "Apple M1" ]]; then
        echo "M1"
    elif [[ "$brand_string" =~ "Apple M2" ]]; then
        echo "M2"
    elif [[ "$brand_string" =~ "Apple M3" ]]; then
        echo "M3"
    elif [[ "$brand_string" =~ "Apple M4" ]]; then
        echo "M4"
    elif [[ "$brand_string" =~ "Apple M5" ]]; then
        echo "M5"
    else
        echo "Unknown"
    fi
}

# Detect number of GPU cores
detect_gpu_cores() {
    local gpu_info cores
    gpu_info=$(system_profiler SPDisplaysDataType 2>/dev/null)

    # Try to extract core count from system profiler output
    # Look for patterns like "Total Number of Cores: 20" or similar
    cores=$(echo "$gpu_info" | grep -i "cores" | grep -Eo '[0-9]+' | head -1)

    if [[ -n "$cores" ]]; then
        echo "$cores"
    else
        # Fallback: estimate based on chip type if we can't detect directly
        local chip
        chip=$(detect_m_chip)
        case "$chip" in
            "M1")
                echo "8"  # M1 base typically has 7-8 cores
                ;;
            "M2")
                echo "10" # M2 base typically has 10 cores
                ;;
            "M3")
                echo "10" # M3 base typically has 10 cores
                ;;
            "M4")
                echo "10" # M4 base typically has 10 cores
                ;;
            *)
                echo "8"  # Conservative default
                ;;
        esac
    fi
}

# Detect total RAM in GB
detect_ram_gb() {
    local ram_bytes ram_gb
    ram_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
    ram_gb=$((ram_bytes / 1024 / 1024 / 1024))
    echo "$ram_gb"
}

# Get RAM tier (tier1=16GB, tier2=32GB, tier3=48GB+)
get_ram_tier() {
    local ram_gb
    ram_gb=$(detect_ram_gb)

    if [[ "$ram_gb" -ge 48 ]]; then
        echo "tier3"
    elif [[ "$ram_gb" -ge 32 ]]; then
        echo "tier2"
    else
        echo "tier1"
    fi
}

#############################################
# Prerequisites Check Functions
#############################################

# Check if Homebrew is installed
check_homebrew() {
    if command -v brew &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Install Homebrew
install_homebrew() {
    print_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1

    # Add Homebrew to PATH for Apple Silicon
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi

    print_status "Homebrew installed successfully"
}

# Check and install prerequisites
check_prerequisites() {
    set -euo pipefail

    print_header "Checking Prerequisites"

    # Check Homebrew
    if ! check_homebrew; then
        print_warning "Homebrew not found"
        install_homebrew || {
            print_error "Failed to install Homebrew"
            return 1
        }
    else
        print_status "Homebrew is installed"
    fi

    # Ensure Homebrew is in PATH
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
    fi

    # Check and install Git
    if ! command -v git &> /dev/null; then
        print_info "Installing Git..."
        brew install git || {
            print_error "Failed to install Git"
            return 1
        }
        print_status "Git installed successfully"
    else
        print_status "Git is installed"
    fi

    # Check and install Go
    if ! command -v go &> /dev/null; then
        print_info "Installing Go (required for Ollama)..."
        brew install go || {
            print_error "Failed to install Go"
            return 1
        }
        print_status "Go installed successfully"
    else
        print_status "Go is installed"
    fi

    # Check and install Bun
    if ! command -v bun &> /dev/null; then
        print_info "Installing Bun (required for OpenCode)..."
        brew install bun || {
            print_error "Failed to install Bun"
            return 1
        }
        print_status "Bun installed successfully"
    else
        print_status "Bun is installed"
    fi

    # Check and install Docker
    if ! command -v docker &> /dev/null; then
        print_info "Installing Docker (required for Open WebUI)..."
        brew install --cask docker || {
            print_error "Failed to install Docker"
            return 1
        }
        print_warning "Docker installed. You may need to start Docker Desktop manually."
    else
        print_status "Docker is installed"
    fi

    print_status "All prerequisites checked"
}

#############################################
# Directory Setup Functions
#############################################

# Setup required directories
setup_directories() {
    set -euo pipefail

    print_info "Setting up directories..."

    # Create PID directory
    mkdir -p ~/.local/var || true

    # Create log directory
    mkdir -p ~/.local/var/log || true

    if [[ -d ~/.local/var ]] && [[ -d ~/.local/var/log ]]; then
        print_status "Directories created: ~/.local/var and ~/.local/var/log"
    else
        print_error "Failed to create required directories"
        return 1
    fi
}

#############################################
# Initialize Hardware Detection
#############################################

# Export hardware information when this file is sourced
export M_CHIP=$(detect_m_chip)
export GPU_CORES=$(detect_gpu_cores)
export TOTAL_RAM_GB=$(detect_ram_gb)
export RAM_TIER=$(get_ram_tier)

# Display hardware info when sourced (optional, can be commented out)
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # File is being sourced
    : # Do nothing, keep exports silent
fi
