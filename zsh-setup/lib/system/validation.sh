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
    # Load progress module if available
    if [[ -f "$ZSH_SETUP_ROOT/lib/core/progress.sh" ]]; then
        source "$ZSH_SETUP_ROOT/lib/core/progress.sh" 2>/dev/null || true
    fi
fi

#------------------------------------------------------------------------------
# System Requirements
#------------------------------------------------------------------------------

# Helper function to safely get version info with timeout
zsh_setup::system::validation::_get_version() {
    local cmd="$1"
    local timeout="${2:-2}"
    
    # Try to get version with timeout
    if command -v timeout &>/dev/null; then
        timeout "$timeout" "$cmd" --version 2>/dev/null | head -n1 || echo "installed"
    elif command -v gtimeout &>/dev/null; then
        gtimeout "$timeout" "$cmd" --version 2>/dev/null | head -n1 || echo "installed"
    else
        # Fallback: try to get version, but don't wait forever
        # Use a background process with a kill after timeout
        local version_file=$(mktemp)
        (
            "$cmd" --version 2>/dev/null | head -n1 > "$version_file" 2>/dev/null || echo "installed" > "$version_file"
        ) &
        local pid=$!
        local count=0
        while [[ $count -lt $((timeout * 10)) ]] && kill -0 "$pid" 2>/dev/null; do
            sleep 0.1
            count=$((count + 1))
        done
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        local result="installed"
        if [[ -f "$version_file" ]]; then
            result=$(cat "$version_file")
            rm -f "$version_file"
        fi
        echo "$result"
    fi
}

# Check system requirements
zsh_setup::system::validation::check_requirements() {
    local spinner_pid=""
    if declare -f zsh_setup::core::progress::spinner_start &>/dev/null; then
        spinner_pid=$(zsh_setup::core::progress::spinner_start "Checking system requirements")
    else
        zsh_setup::core::logger::info "Checking system requirements..."
    fi
    
    # Ensure spinner is stopped on exit - use inline trap (bash doesn't support local functions)
    trap 'if [[ -n "$spinner_pid" ]] && declare -f zsh_setup::core::progress::spinner_stop &>/dev/null; then zsh_setup::core::progress::spinner_stop "$spinner_pid" "" "" 0 2>/dev/null || true; fi' EXIT
    
    local requirements_met=true
    local version_info=""

    # Check if Zsh is installed (required)
    if ! command -v zsh &>/dev/null; then
        if [[ -n "$spinner_pid" ]]; then
            zsh_setup::core::progress::spinner_stop "$spinner_pid" "" "❌ Zsh is not installed" 1
        fi
        zsh_setup::core::logger::error "Zsh is not installed. Please install Zsh first using your system package manager."
        zsh_setup::system::validation::_suggest_installation "zsh"
        requirements_met=false
    else
        version_info=$(zsh_setup::system::validation::_get_version "zsh" 2)
        if [[ -n "$spinner_pid" ]]; then
            zsh_setup::core::progress::spinner_stop "$spinner_pid" "✓ Zsh is installed: $version_info" "" 0
            spinner_pid=$(zsh_setup::core::progress::spinner_start "Checking Git")
        else
            zsh_setup::core::logger::info "✓ Zsh is installed: $version_info"
        fi
    fi

    # Check if Git is installed (required)
    if ! command -v git &>/dev/null; then
        if [[ -n "$spinner_pid" ]]; then
            zsh_setup::core::progress::spinner_stop "$spinner_pid" "" "❌ Git is not installed" 1
        fi
        zsh_setup::core::logger::error "Git is not installed. Please install Git first."
        zsh_setup::system::validation::_suggest_installation "git"
        requirements_met=false
    else
        version_info=$(zsh_setup::system::validation::_get_version "git" 2)
        if [[ -n "$spinner_pid" ]]; then
            zsh_setup::core::progress::spinner_stop "$spinner_pid" "✓ Git is installed: $version_info" "" 0
            if [[ "$(uname)" == "Darwin" ]]; then
                spinner_pid=$(zsh_setup::core::progress::spinner_start "Checking Homebrew")
            else
                spinner_pid=$(zsh_setup::core::progress::spinner_start "Checking selection tools")
            fi
        else
            zsh_setup::core::logger::info "✓ Git is installed: $version_info"
        fi
    fi

    # Check for Homebrew (optional, macOS only)
    if [[ "$(uname)" == "Darwin" ]]; then
        if command -v brew &>/dev/null; then
            version_info=$(zsh_setup::system::validation::_get_version "brew" 2)
            if [[ -n "$spinner_pid" ]]; then
                zsh_setup::core::progress::spinner_stop "$spinner_pid" "✓ Homebrew is installed: $version_info" "" 0
                spinner_pid=$(zsh_setup::core::progress::spinner_start "Checking selection tools")
            else
                zsh_setup::core::logger::info "✓ Homebrew is installed: $version_info"
            fi
        else
            if [[ -n "$spinner_pid" ]]; then
                zsh_setup::core::progress::spinner_stop "$spinner_pid" "ⓘ Homebrew not found. Some features may be limited." "" 0
                spinner_pid=$(zsh_setup::core::progress::spinner_start "Checking selection tools")
            else
                zsh_setup::core::logger::info "ⓘ Homebrew not found. Some features may be limited."
            fi
        fi
    fi

    # Check for selection tools (optional)
    if command -v fzf &>/dev/null; then
        version_info=$(zsh_setup::system::validation::_get_version "fzf" 2)
        if [[ -n "$spinner_pid" ]]; then
            zsh_setup::core::progress::spinner_stop "$spinner_pid" "✓ Selection tool available: fzf $version_info" "" 0
        else
            zsh_setup::core::logger::info "✓ Selection tool available: fzf $version_info"
        fi
    else
        if [[ -n "$spinner_pid" ]]; then
            zsh_setup::core::progress::spinner_stop "$spinner_pid" "ⓘ No selection tool (fzf) found. Will use fallback selection method." "" 0
        else
            zsh_setup::core::logger::info "ⓘ No selection tool (fzf) found. Will use fallback selection method."
        fi
    fi

    # Exit if required tools are missing
    if ! $requirements_met; then
        zsh_setup::core::logger::error "System requirements check failed. Please install missing components."
        trap - EXIT
        return 1
    fi

    # Remove trap before normal exit
    trap - EXIT
    
    if declare -f zsh_setup::core::progress::status_line &>/dev/null; then
        zsh_setup::core::progress::status_line "System requirements check completed successfully."
    else
        zsh_setup::core::logger::info "System requirements check completed successfully."
    fi
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

#------------------------------------------------------------------------------
# Privilege Detection
#------------------------------------------------------------------------------

# Check if user has sudo/admin privileges
zsh_setup::system::validation::check_privileges() {
    local force_prompt="${1:-false}"
    local has_privileges=false
    
    # Check if already determined (from config or environment)
    if [[ -n "${ZSH_SETUP_HAS_PRIVILEGES:-}" ]]; then
        if [[ "${ZSH_SETUP_HAS_PRIVILEGES}" == "true" ]]; then
            has_privileges=true
        else
            has_privileges=false
        fi
    elif zsh_setup::core::config::has "has_privileges"; then
        if [[ "$(zsh_setup::core::config::get has_privileges)" == "true" ]]; then
            has_privileges=true
        else
            has_privileges=false
        fi
    else
        # Need to determine privileges
        if [[ "$force_prompt" == "true" ]] || [[ -t 0 ]]; then
            # Interactive mode - prompt user
            echo ""
            zsh_setup::core::logger::info "Checking for sudo/admin privileges..."
            read -p "Do you have sudo/admin privileges? (y/n): " -r response
            echo ""
            
            if [[ "$response" =~ ^[Yy]$ ]]; then
                # Test actual sudo access
                if sudo -n true 2>/dev/null || sudo -v 2>/dev/null; then
                    has_privileges=true
                    zsh_setup::core::logger::success "Sudo privileges confirmed"
                else
                    zsh_setup::core::logger::warn "Sudo access test failed, but continuing with user privileges"
                    has_privileges=false
                fi
            else
                has_privileges=false
                zsh_setup::core::logger::info "Continuing without sudo/admin privileges"
            fi
        else
            # Non-interactive mode - test silently
            if sudo -n true 2>/dev/null; then
                has_privileges=true
            else
                has_privileges=false
            fi
        fi
        
        # Store in config
        zsh_setup::core::config::set has_privileges "$has_privileges"
        export ZSH_SETUP_HAS_PRIVILEGES="$has_privileges"
    fi
    
    if [[ "$has_privileges" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Check if privileges are available (without prompting)
zsh_setup::system::validation::has_privileges() {
    zsh_setup::system::validation::check_privileges false
}

