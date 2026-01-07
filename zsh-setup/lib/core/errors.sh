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
        echo ""
        zsh_setup::core::logger::error "❌ Error in $context (exit code: $exit_code)"
        
        if [[ -n "$suggestion" ]]; then
            echo ""
            zsh_setup::core::logger::info "💡 Suggestion: $suggestion"
        fi
        
        # Provide common troubleshooting tips with more context
        case "$context" in
            *"git clone"*|*"git"*)
                zsh_setup::core::errors::_show_git_troubleshooting
                ;;
            *"curl"*|*"download"*|*"network"*)
                zsh_setup::core::errors::_show_network_troubleshooting
                ;;
            *"brew"*|*"Homebrew"*)
                zsh_setup::core::errors::_show_brew_troubleshooting
                ;;
            *"Configuration validation"*|*"config"*)
                zsh_setup::core::errors::_show_config_troubleshooting
                ;;
            *"shell"*|*"chsh"*)
                zsh_setup::core::errors::_show_shell_troubleshooting
                ;;
            *)
                local log_file=$(zsh_setup::core::config::get log_file "/tmp/zsh_setup.log")
                echo ""
                zsh_setup::core::logger::info "📋 For more details, check the log file:"
                zsh_setup::core::logger::info "   $log_file"
                zsh_setup::core::logger::info ""
                zsh_setup::core::logger::info "📖 For help, run: zsh-setup help"
                ;;
        esac
        echo ""
    fi
    
    return $exit_code
}

zsh_setup::core::errors::_show_git_troubleshooting() {
    echo ""
    zsh_setup::core::logger::info "🔧 Troubleshooting Git issues:"
    zsh_setup::core::logger::info "   1. Check your internet connection:"
    zsh_setup::core::logger::info "      ping -c 3 github.com"
    zsh_setup::core::logger::info "   2. Verify Git is installed:"
    zsh_setup::core::logger::info "      git --version"
    zsh_setup::core::logger::info "   3. Test repository access:"
    zsh_setup::core::logger::info "      git ls-remote <repository-url>"
    zsh_setup::core::logger::info "   4. Check Git configuration:"
    zsh_setup::core::logger::info "      git config --list"
    zsh_setup::core::logger::info ""
    zsh_setup::core::logger::info "   If the issue persists, try installing the plugin manually:"
    zsh_setup::core::logger::info "   git clone <repository-url> ~/.oh-my-zsh/custom/plugins/<plugin-name>"
}

zsh_setup::core::errors::_show_network_troubleshooting() {
    echo ""
    zsh_setup::core::logger::info "🔧 Troubleshooting Network issues:"
    zsh_setup::core::logger::info "   1. Check internet connectivity:"
    zsh_setup::core::logger::info "      curl -I https://github.com"
    zsh_setup::core::logger::info "   2. Verify DNS resolution:"
    zsh_setup::core::logger::info "      nslookup github.com"
    zsh_setup::core::logger::info "   3. Check firewall/proxy settings"
    zsh_setup::core::logger::info "   4. Try accessing the URL in a browser"
    zsh_setup::core::logger::info ""
    zsh_setup::core::logger::info "   If behind a corporate firewall, you may need to configure:"
    zsh_setup::core::logger::info "   - HTTP_PROXY and HTTPS_PROXY environment variables"
    zsh_setup::core::logger::info "   - Git proxy settings: git config --global http.proxy <proxy-url>"
}

zsh_setup::core::errors::_show_brew_troubleshooting() {
    echo ""
    zsh_setup::core::logger::info "🔧 Troubleshooting Homebrew issues:"
    zsh_setup::core::logger::info "   1. Verify Homebrew installation:"
    zsh_setup::core::logger::info "      brew --version"
    zsh_setup::core::logger::info "   2. Update Homebrew:"
    zsh_setup::core::logger::info "      brew update"
    zsh_setup::core::logger::info "   3. Check Homebrew status:"
    zsh_setup::core::logger::info "      brew doctor"
    zsh_setup::core::logger::info "   4. Check if you have write permissions:"
    zsh_setup::core::logger::info "      ls -ld $(brew --prefix)"
    zsh_setup::core::logger::info ""
    zsh_setup::core::logger::info "   If you don't have sudo privileges, Homebrew may be limited."
    zsh_setup::core::logger::info "   Run with --no-privileges to skip system package installations."
}

zsh_setup::core::errors::_show_config_troubleshooting() {
    echo ""
    zsh_setup::core::logger::info "🔧 Troubleshooting Configuration issues:"
    zsh_setup::core::logger::info "   1. Validate configuration files:"
    zsh_setup::core::logger::info "      zsh-setup help"
    zsh_setup::core::logger::info "   2. Check plugins.conf format:"
    zsh_setup::core::logger::info "      Each line should be: plugin_name|type|url|description"
    zsh_setup::core::logger::info "   3. Check plugin_dependencies.conf format:"
    zsh_setup::core::logger::info "      Each line should be: plugin_name=dependency1,dependency2"
    zsh_setup::core::logger::info "   4. Review the configuration files:"
    zsh_setup::core::logger::info "      cat $ZSH_SETUP_ROOT/plugins.conf"
    zsh_setup::core::logger::info "      cat $ZSH_SETUP_ROOT/plugin_dependencies.conf"
}

zsh_setup::core::errors::_show_shell_troubleshooting() {
    echo ""
    zsh_setup::core::logger::info "🔧 Troubleshooting Shell change issues:"
    zsh_setup::core::logger::info "   1. Verify Zsh is installed:"
    zsh_setup::core::logger::info "      which zsh"
    zsh_setup::core::logger::info "   2. Check if Zsh is in /etc/shells:"
    zsh_setup::core::logger::info "      grep zsh /etc/shells"
    zsh_setup::core::logger::info "   3. If not, add it (requires sudo):"
    zsh_setup::core::logger::info "      sudo sh -c 'echo $(which zsh) >> /etc/shells'"
    zsh_setup::core::logger::info "   4. Change shell manually:"
    zsh_setup::core::logger::info "      chsh -s $(which zsh)"
    zsh_setup::core::logger::info ""
    zsh_setup::core::logger::info "   If you don't have sudo privileges, you can:"
    zsh_setup::core::logger::info "   - Use Zsh manually: type 'zsh' in your terminal"
    zsh_setup::core::logger::info "   - Add 'exec zsh' to your .bashrc or .profile"
    zsh_setup::core::logger::info "   - Run with --no-shell-change flag"
}

# Set up error trap
zsh_setup::core::errors::setup_trap() {
    local context="${1:-script execution}"
    trap "zsh_setup::core::errors::handle \$? '$context' 'Check the log file for details: $(zsh_setup::core::config::get log_file)'" ERR
}

