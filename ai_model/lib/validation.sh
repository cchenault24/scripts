#!/bin/bash
# lib/validation.sh - Platform and prerequisite validation
#
# Provides:
# - macOS and Apple Silicon detection
# - Homebrew validation

set -euo pipefail

# Check if running on macOS and minimum version
check_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        print_error "This script requires macOS"
        exit 1
    fi

    # Check minimum macOS version (10.14+, Mojave+)
    local os_version
    os_version=$(sw_vers -productVersion)
    local major minor
    IFS='.' read -r major minor _ <<< "$os_version"

    if [[ $major -lt 10 ]] || [[ $major -eq 10 && $minor -lt 14 ]]; then
        print_error "This script requires macOS 10.14 (Mojave) or later"
        print_info "Your version: $os_version"
        print_info "Reason: Homebrew requires macOS 10.14+"
        exit 1
    fi

    print_status "macOS $os_version detected"
}

# Check if running on Apple Silicon
# Warns but allows continuation on Intel
check_apple_silicon() {
    if ! sysctl -n machdep.cpu.brand_string 2>/dev/null | grep -q "Apple"; then
        print_warning "This script is optimized for Apple Silicon (M1/M2/M3/M4)"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Check if Homebrew is installed
check_homebrew() {
    if ! command -v brew &> /dev/null; then
        print_error "Homebrew is not installed"
        print_info "Install Homebrew: https://brew.sh"
        exit 1
    fi
    print_status "Homebrew found: $(brew --version | head -1)"
}
