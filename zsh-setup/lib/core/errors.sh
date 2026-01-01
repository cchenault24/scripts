#!/usr/bin/env bash

#==============================================================================
# errors.sh - Error Handling and Retry Logic
#
# Provides namespaced error handling functions
#==============================================================================

# Load dependencies
if [[ -n "${ZSH_SETUP_ROOT:-}" ]]; then
    source "$ZSH_SETUP_ROOT/lib/core/config.sh"
    source "$ZSH_SETUP_ROOT/lib/core/logger.sh"
fi

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------

zsh_setup::core::errors::_get_max_retries() {
    zsh_setup::core::config::get max_retries "3"
}

zsh_setup::core::errors::_get_retry_delay() {
    zsh_setup::core::config::get retry_delay "2"
}

zsh_setup::core::errors::_get_backoff_multiplier() {
    zsh_setup::core::config::get retry_backoff_multiplier "2"
}

#------------------------------------------------------------------------------
# Error Handling
#------------------------------------------------------------------------------

# Execute command with retry logic
zsh_setup::core::errors::execute_with_retry() {
    local description="$1"
    shift
    local cmd=("$@")
    local max_retries=$(zsh_setup::core::errors::_get_max_retries)
    local retry_delay=$(zsh_setup::core::errors::_get_retry_delay)
    local backoff=$(zsh_setup::core::errors::_get_backoff_multiplier)
    local attempt=1
    local delay=$retry_delay
    local last_error=""
    
    while [[ $attempt -le $max_retries ]]; do
        zsh_setup::core::logger::info "Attempting: $description (attempt $attempt/$max_retries)"
        
        if "${cmd[@]}" 2>&1; then
            if [[ $attempt -gt 1 ]]; then
                zsh_setup::core::logger::success "$description succeeded on attempt $attempt"
            fi
            return 0
        else
            last_error=$?
            if [[ $attempt -lt $max_retries ]]; then
                zsh_setup::core::logger::warn "$description failed (exit code: $last_error). Retrying in ${delay}s..."
                sleep "$delay"
                delay=$((delay * backoff))
            fi
        fi
        
        ((attempt++))
    done
    
    zsh_setup::core::logger::error "$description failed after $max_retries attempts (last exit code: $last_error)"
    return $last_error
}

# Execute network operation with retry
zsh_setup::core::errors::execute_network_with_retry() {
    local description="$1"
    shift
    local cmd=("$@")
    
    # Check network connectivity first
    if ! zsh_setup::core::errors::check_network_connectivity; then
        zsh_setup::core::logger::error "Network connectivity check failed. Cannot proceed with: $description"
        return 1
    fi
    
    zsh_setup::core::errors::execute_with_retry "$description" "${cmd[@]}"
}

# Check network connectivity
zsh_setup::core::errors::check_network_connectivity() {
    local test_hosts=("8.8.8.8" "1.1.1.1" "github.com")
    local connected=false
    
    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 2 "$host" &>/dev/null 2>&1 || \
           curl -s --max-time 2 "https://$host" &>/dev/null 2>&1; then
            connected=true
            break
        fi
    done
    
    if ! $connected; then
        zsh_setup::core::logger::error "No network connectivity detected"
        return 1
    fi
    
    return 0
}

# Validate URL format
zsh_setup::core::errors::validate_url() {
    local url="$1"
    
    # Basic URL validation
    if [[ "$url" =~ ^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/.*)?$ ]]; then
        return 0
    fi
    
    # Git SSH URL validation
    if [[ "$url" =~ ^git@[a-zA-Z0-9.-]+:[a-zA-Z0-9._/-]+\.git$ ]]; then
        return 0
    fi
    
    return 1
}

# Handle errors with context
zsh_setup::core::errors::handle() {
    local exit_code="$1"
    local context="$2"
    local suggestion="${3:-}"
    
    if [[ $exit_code -ne 0 ]]; then
        zsh_setup::core::logger::error "Error in $context (exit code: $exit_code)"
        
        if [[ -n "$suggestion" ]]; then
            zsh_setup::core::logger::info "Suggestion: $suggestion"
        fi
        
        # Provide common troubleshooting tips
        case "$context" in
            *"git clone"*)
                zsh_setup::core::errors::_show_git_troubleshooting
                ;;
            *"curl"*|*"download"*)
                zsh_setup::core::errors::_show_network_troubleshooting
                ;;
            *"brew"*)
                zsh_setup::core::errors::_show_brew_troubleshooting
                ;;
            *)
                local log_file=$(zsh_setup::core::config::get log_file "/tmp/zsh_setup.log")
                zsh_setup::core::logger::info "Check the log file for more details: $log_file"
                ;;
        esac
    fi
    
    return $exit_code
}

zsh_setup::core::errors::_show_git_troubleshooting() {
    zsh_setup::core::logger::info "Troubleshooting tips:"
    zsh_setup::core::logger::info "  - Check your internet connection"
    zsh_setup::core::logger::info "  - Verify the repository URL is correct"
    zsh_setup::core::logger::info "  - Ensure you have git installed: git --version"
}

zsh_setup::core::errors::_show_network_troubleshooting() {
    zsh_setup::core::logger::info "Troubleshooting tips:"
    zsh_setup::core::logger::info "  - Check your internet connection"
    zsh_setup::core::logger::info "  - Verify the URL is accessible"
    zsh_setup::core::logger::info "  - Check firewall/proxy settings"
}

zsh_setup::core::errors::_show_brew_troubleshooting() {
    zsh_setup::core::logger::info "Troubleshooting tips:"
    zsh_setup::core::logger::info "  - Ensure Homebrew is installed: brew --version"
    zsh_setup::core::logger::info "  - Update Homebrew: brew update"
    zsh_setup::core::logger::info "  - Check Homebrew status: brew doctor"
}

# Set up error trap
zsh_setup::core::errors::setup_trap() {
    local context="${1:-script execution}"
    trap "zsh_setup::core::errors::handle \$? '$context' 'Check the log file for details: $(zsh_setup::core::config::get log_file)'" ERR
}

# Backward compatibility functions
execute_with_retry() {
    zsh_setup::core::errors::execute_with_retry "$@"
}

execute_network_with_retry() {
    zsh_setup::core::errors::execute_network_with_retry "$@"
}

check_network_connectivity() {
    zsh_setup::core::errors::check_network_connectivity "$@"
}

validate_url() {
    zsh_setup::core::errors::validate_url "$@"
}

setup_error_trap() {
    zsh_setup::core::errors::setup_trap "$@"
}
