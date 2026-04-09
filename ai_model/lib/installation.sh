#!/bin/bash
# lib/installation.sh - Ollama and OpenCode installation via Homebrew
#
# Provides:
# - Ollama installation and upgrade management
# - OpenCode installation and upgrade management
# - Service cleanup (stop Homebrew services, kill processes)

set -euo pipefail

# Install or upgrade Ollama via Homebrew
# Stops any existing services/processes
install_ollama() {
    print_header "Step 1: Installing Ollama"

    if command -v ollama &> /dev/null; then
        local ollama_version
        ollama_version=$(ollama --version 2>/dev/null || echo "unknown")
        print_status "Ollama already installed: $ollama_version"

        # Check if it's outdated (disable auto-update to avoid hang)
        print_info "Checking for Ollama updates..."
        if HOMEBREW_NO_AUTO_UPDATE=1 brew outdated ollama &> /dev/null; then
            print_info "Upgrading Ollama to latest version..."
            brew upgrade ollama
            print_status "Ollama upgraded"
        else
            print_info "Ollama is up to date"
        fi
    else
        print_info "Installing Ollama via Homebrew..."
        brew install ollama
        print_status "Ollama installed"
    fi

    # Stop any existing Homebrew service
    if brew services list | grep -q "ollama.*started"; then
        print_info "Stopping Homebrew-managed ollama service..."
        brew services stop ollama 2>/dev/null || true
        print_status "Homebrew ollama service stopped"
    fi

    # Stop any running ollama processes
    if pgrep -x ollama > /dev/null; then
        print_info "Stopping running ollama processes..."
        pkill -x ollama || true
        sleep 2
        print_status "Ollama processes stopped"
    fi
}

# Install or upgrade OpenCode via Homebrew
install_opencode() {
    print_header "Step 2: Installing OpenCode"

    if command -v opencode &> /dev/null; then
        local opencode_version
        opencode_version=$(opencode --version 2>/dev/null || echo "unknown")
        print_status "OpenCode already installed: $opencode_version"

        # Check if anomalyco tap is added
        if ! brew tap | grep -q "anomalyco/tap"; then
            print_info "Adding anomalyco/tap..."
            brew tap anomalyco/tap
        fi

        # Check if it's outdated (disable auto-update to avoid hang)
        print_info "Checking for OpenCode updates..."
        if HOMEBREW_NO_AUTO_UPDATE=1 brew outdated opencode &> /dev/null; then
            print_info "Upgrading OpenCode to latest version..."
            brew upgrade opencode
            print_status "OpenCode upgraded"
        else
            print_info "OpenCode is up to date"
        fi
    else
        print_info "Adding anomalyco/tap..."
        brew tap anomalyco/tap

        print_info "Installing OpenCode via Homebrew..."
        brew install anomalyco/tap/opencode
        print_status "OpenCode installed"
    fi
}
