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

# Detect Performance core count (Apple Silicon)
detect_p_cores() {
    local p_cores
    p_cores=$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null)

    if [[ -n "$p_cores" && "$p_cores" -gt 0 ]]; then
        echo "$p_cores"
    else
        # Fallback: estimate based on total cores and chip
        local total_cores
        total_cores=$(sysctl -n hw.physicalcpu 2>/dev/null || echo "4")

        # Conservative estimate: ~50-70% are P-cores
        echo $((total_cores * 2 / 3))
    fi
}

# Detect Efficiency core count (Apple Silicon)
detect_e_cores() {
    local e_cores
    e_cores=$(sysctl -n hw.perflevel1.physicalcpu 2>/dev/null)

    if [[ -n "$e_cores" && "$e_cores" -gt 0 ]]; then
        echo "$e_cores"
    else
        # Fallback: estimate from total - P-cores
        local total_cores p_cores
        total_cores=$(sysctl -n hw.physicalcpu 2>/dev/null || echo "4")
        p_cores=$(detect_p_cores)
        echo $((total_cores - p_cores))
    fi
}

# Detect total physical cores
detect_total_cores() {
    local total_cores
    total_cores=$(sysctl -n hw.physicalcpu 2>/dev/null || echo "4")
    echo "$total_cores"
}

# Calculate optimal VRAM limit (leave 3GB for system)
calculate_optimal_vram() {
    local ram_gb
    ram_gb=$(detect_ram_gb)

    # Reserve 3GB for macOS and other apps
    local vram_gb=$((ram_gb - 3))

    # Convert to MB
    local vram_mb=$((vram_gb * 1000))

    # Ensure minimum of 10GB
    if [[ $vram_mb -lt 10000 ]]; then
        vram_mb=10000
    fi

    echo "$vram_mb"
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

# Setup Homebrew environment variables with explicit exports (security: avoid eval)
# Returns 0 on success, 1 if Homebrew not found
setup_homebrew_environment() {
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        # Apple Silicon path
        export HOMEBREW_PREFIX="/opt/homebrew"
        export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
        export HOMEBREW_REPOSITORY="/opt/homebrew/Homebrew"
        export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
        export MANPATH="/opt/homebrew/share/man${MANPATH+:$MANPATH}:"
        export INFOPATH="/opt/homebrew/share/info${INFOPATH+:$INFOPATH}"
        return 0
    elif [[ -f "/usr/local/bin/brew" ]]; then
        # Intel path
        export HOMEBREW_PREFIX="/usr/local"
        export HOMEBREW_CELLAR="/usr/local/Cellar"
        export HOMEBREW_REPOSITORY="/usr/local/Homebrew"
        export PATH="/usr/local/bin:/usr/local/sbin:$PATH"
        export MANPATH="/usr/local/share/man${MANPATH+:$MANPATH}:"
        export INFOPATH="/usr/local/share/info${INFOPATH+:$INFOPATH}"
        return 0
    else
        # Homebrew not found at expected locations
        return 1
    fi
}

# Install Homebrew
install_homebrew() {
    print_info "Installing Homebrew..."

    # Create secure temporary file
    local temp_script
    temp_script=$(mktemp) || {
        print_error "Failed to create temporary file"
        return 1
    }

    # Ensure cleanup on exit/interruption
    trap 'rm -f "$temp_script"' EXIT INT TERM

    # Download script to temp file with security flags
    if ! curl -fsSL \
        --max-time 60 \
        --tlsv1.2 \
        --proto '=https' \
        https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
        -o "$temp_script"; then
        print_error "Failed to download Homebrew installer"
        rm -f "$temp_script"
        return 1
    fi

    # Verify downloaded file is not empty
    if [[ ! -s "$temp_script" ]]; then
        print_error "Downloaded installer is empty"
        rm -f "$temp_script"
        return 1
    fi

    # Execute from file
    if ! /bin/bash "$temp_script"; then
        print_error "Homebrew installation failed"
        rm -f "$temp_script"
        return 1
    fi

    # Clean up temp file
    rm -f "$temp_script"

    # Setup Homebrew environment
    if ! setup_homebrew_environment; then
        print_warning "Homebrew installed but not found at expected location"
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
    if ! setup_homebrew_environment; then
        print_error "Homebrew not found at expected location"
        return 1
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
# Separate declaration and assignment to catch failures (SC2155)
M_CHIP=$(detect_m_chip) || M_CHIP="Unknown"
export M_CHIP

GPU_CORES=$(detect_gpu_cores) || GPU_CORES="8"
export GPU_CORES

TOTAL_RAM_GB=$(detect_ram_gb) || TOTAL_RAM_GB="16"
export TOTAL_RAM_GB

RAM_TIER=$(get_ram_tier) || RAM_TIER="tier1"
export RAM_TIER

P_CORES=$(detect_p_cores) || P_CORES="4"
export P_CORES

E_CORES=$(detect_e_cores) || E_CORES="4"
export E_CORES

TOTAL_CORES=$(detect_total_cores) || TOTAL_CORES="8"
export TOTAL_CORES

OPTIMAL_VRAM_MB=$(calculate_optimal_vram) || OPTIMAL_VRAM_MB="13000"
export OPTIMAL_VRAM_MB

# Display hardware info when sourced (optional, can be commented out)
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # File is being sourced
    : # Do nothing, keep exports silent
fi
