#!/bin/bash
#
# Common utilities and shared functions
#

# Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export DIM='\033[2m'
export NC='\033[0m' # No Color

# Configuration
export OLLAMA_BUILD_DIR="/tmp/ollama-build"
export OPENCODE_BUILD_DIR="/tmp/opencode-build"
export PORT="3456"
export INSTALL_EMBEDDING_MODEL="${INSTALL_EMBEDDING_MODEL:-false}"  # Default to false

# Detect system RAM (in GB)
export TOTAL_RAM_MB=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024)}')
export TOTAL_RAM_GB=$((TOTAL_RAM_MB / 1024))

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Print functions
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check Apple Silicon
    if [ "$(uname -m)" != "arm64" ]; then
        print_error "This script requires Apple Silicon (arm64)"
        exit 1
    fi
    print_status "Apple Silicon detected (arm64)"

    # Check for Homebrew Ollama installation
    if brew list ollama &>/dev/null; then
        echo ""
        print_warning "Homebrew Ollama detected!"
        print_warning "This conflicts with the custom-built Ollama."
        echo ""
        print_info "To remove Homebrew Ollama and continue, run:"
        print_info "  ./kill-all-ollama.sh"
        echo ""
        read -p "Remove Homebrew Ollama now? (y/N) " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Uninstalling Homebrew Ollama..."
            brew services stop ollama 2>/dev/null || true
            brew uninstall ollama 2>/dev/null || true
            print_status "Homebrew Ollama removed"
        else
            print_error "Cannot proceed with Homebrew Ollama installed"
            exit 1
        fi
    fi

    # Check for missing dependencies
    MISSING_DEPS=()
    for cmd in git go bun; do
        if ! command_exists "$cmd"; then
            MISSING_DEPS+=("$cmd")
        else
            print_status "$cmd installed"
        fi
    done

    # Auto-install missing dependencies via Homebrew
    if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
        echo ""
        print_info "Missing dependencies: ${MISSING_DEPS[*]}"

        if ! command_exists brew; then
            print_error "Homebrew not found. Please install: https://brew.sh"
            exit 1
        fi

        print_info "Installing missing dependencies with Homebrew..."
        for dep in "${MISSING_DEPS[@]}"; do
            print_info "Installing $dep..."
            brew install "$dep"
        done
    fi

    echo ""
}
