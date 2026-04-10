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
    print_step "1/6" "Installing Ollama"

    if command -v ollama &> /dev/null; then
        local ollama_version
        ollama_version=$(ollama --version 2>/dev/null || echo "unknown")

        if [[ $VERBOSITY_LEVEL -ge 2 ]]; then
            # Verbose: show tree structure
            tree_node 0 0 "✓" "Found: Ollama $ollama_version"
            tree_node 0 0 "⣾" "Checking for updates..."
        fi

        # Check if it's outdated (disable auto-update to avoid hang)
        if HOMEBREW_NO_AUTO_UPDATE=1 brew outdated ollama &> /dev/null; then
            if [[ $VERBOSITY_LEVEL -ge 2 ]]; then
                tree_node 0 1 "↻" "Upgrading Ollama..."
            fi
            brew upgrade ollama 2>&1 | grep -v "Downloading" | grep -v "Pouring" | grep -v "Warning:" || true
            if [[ $VERBOSITY_LEVEL -ge 2 ]]; then
                tree_node 0 1 "✓" "Ollama upgraded"
            fi
        else
            if [[ $VERBOSITY_LEVEL -ge 2 ]]; then
                tree_node 0 1 "✓" "Up to date"
            fi
        fi

        print_status "Ollama ($ollama_version)"
    else
        if [[ $VERBOSITY_LEVEL -ge 2 ]]; then
            tree_node 0 0 "⣾" "Installing Ollama via Homebrew..."
        fi
        brew install ollama 2>&1 | grep -v "Downloading" | grep -v "Pouring" | grep -v "Warning:" || true
        print_status "Ollama installed"
    fi

    # Stop any existing Homebrew service
    if brew services list | grep -q "ollama.*started"; then
        print_verbose "Stopping Homebrew-managed ollama service..."
        brew services stop ollama 2>/dev/null || true
    fi

    # Stop any running ollama processes
    if pgrep -x ollama > /dev/null; then
        print_verbose "Stopping running ollama processes..."
        pkill -x ollama || true
        sleep 2
    fi
}

# Install or upgrade OpenCode via Homebrew
install_opencode() {
    print_step "2/6" "Installing OpenCode"

    if command -v opencode &> /dev/null; then
        local opencode_version
        opencode_version=$(opencode --version 2>/dev/null || echo "unknown")
        print_status "OpenCode ($opencode_version)"

        # Check if anomalyco tap is added
        if ! brew tap | grep -q "anomalyco/tap"; then
            print_verbose "Adding anomalyco/tap..."
            brew tap anomalyco/tap 2>&1 | tail -1
        fi

        # Check if it's outdated (disable auto-update to avoid hang)
        print_verbose "Checking for OpenCode updates..."
        if HOMEBREW_NO_AUTO_UPDATE=1 brew outdated opencode &> /dev/null; then
            print_verbose "Upgrading OpenCode to latest version..."
            brew upgrade opencode 2>&1 | grep -v "Downloading" | grep -v "Pouring" | grep -v "Warning:" || true
        fi
    else
        print_verbose "Adding anomalyco/tap..."
        brew tap anomalyco/tap 2>&1 | tail -1

        print_verbose "Installing OpenCode via Homebrew..."
        brew install anomalyco/tap/opencode 2>&1 | grep -v "Downloading" | grep -v "Pouring" | grep -v "Warning:" || true
        print_status "OpenCode installed"
    fi
}
