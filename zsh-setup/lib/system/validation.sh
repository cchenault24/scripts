#!/usr/bin/env bash

#==============================================================================
# validation.sh - System Validation
#
# Provides system requirement checking and validation
#==============================================================================

# Load dependencies
if [[ -n "${ZSH_SETUP_ROOT:-}" ]]; then
    source "$ZSH_SETUP_ROOT/lib/core/config.sh"
    source "$ZSH_SETUP_ROOT/lib/core/logger.sh"
fi

#------------------------------------------------------------------------------
# System Requirements
#------------------------------------------------------------------------------

# Check system requirements
zsh_setup::system::validation::check_requirements() {
    zsh_setup::core::logger::info "Checking system requirements..."
    local requirements_met=true

    # Check if Zsh is installed (required)
    if ! command -v zsh &>/dev/null; then
        zsh_setup::core::logger::error "Zsh is not installed. Please install Zsh first using your system package manager."
        zsh_setup::system::validation::_suggest_installation "zsh"
        requirements_met=false
    else
        zsh_setup::core::logger::info "✓ Zsh is installed: $(zsh --version | head -n1)"
    fi

    # Check if Git is installed (required)
    if ! command -v git &>/dev/null; then
        zsh_setup::core::logger::error "Git is not installed. Please install Git first."
        zsh_setup::system::validation::_suggest_installation "git"
        requirements_met=false
    else
        zsh_setup::core::logger::info "✓ Git is installed: $(git --version)"
    fi

    # Check for Homebrew (optional, macOS only)
    if [[ "$(uname)" == "Darwin" ]]; then
        if command -v brew &>/dev/null; then
            zsh_setup::core::logger::info "✓ Homebrew is installed: $(brew --version | head -n1)"
        else
            zsh_setup::core::logger::info "ⓘ Homebrew not found. Some features may be limited."
        fi
    fi

    # Check for selection tools (optional)
    if command -v fzf &>/dev/null; then
        zsh_setup::core::logger::info "✓ Selection tool available: fzf $(fzf --version)"
    else
        zsh_setup::core::logger::info "ⓘ No selection tool (fzf) found. Will use fallback selection method."
    fi

    # Exit if required tools are missing
    if ! $requirements_met; then
        zsh_setup::core::logger::error "System requirements check failed. Please install missing components."
        return 1
    fi

    zsh_setup::core::logger::info "System requirements check completed successfully."
    return 0
}

# Suggest installation commands
zsh_setup::system::validation::_suggest_installation() {
    local software="$1"
    echo "Installation suggestions:"
    
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "  On macOS: brew install $software"
    elif [[ -f /etc/debian_version ]]; then
        echo "  On Debian/Ubuntu: sudo apt install $software"
    elif [[ -f /etc/fedora-release ]]; then
        echo "  On Fedora: sudo dnf install $software"
    elif [[ -f /etc/arch-release ]]; then
        echo "  On Arch Linux: sudo pacman -S $software"
    else
        echo "  Please check your distribution's package manager to install $software"
    fi
}

# Backward compatibility
check_system_requirements() {
    zsh_setup::system::validation::check_requirements
}
