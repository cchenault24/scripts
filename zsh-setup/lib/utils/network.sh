#!/usr/bin/env bash

#==============================================================================
# network.sh - Network Utilities
#
# Provides network operation functions
#==============================================================================

# Load dependencies
if [[ -n "${ZSH_SETUP_ROOT:-}" ]]; then
    source "$ZSH_SETUP_ROOT/lib/core/config.sh"
    source "$ZSH_SETUP_ROOT/lib/core/logger.sh"
    source "$ZSH_SETUP_ROOT/lib/core/errors.sh"
fi

#------------------------------------------------------------------------------
# Network Operations
#------------------------------------------------------------------------------

# Download file with retry
zsh_setup::utils::network::download_with_retry() {
    local url="$1"
    local output="$2"
    local description="${3:-Downloading $url}"
    
    if ! zsh_setup::core::errors::validate_url "$url"; then
        zsh_setup::core::logger::error "Invalid URL: $url"
        return 1
    fi
    
    zsh_setup::core::errors::execute_network_with_retry "$description" \
        curl -fsSL "$url" -o "$output"
}

# Git clone with retry
zsh_setup::utils::network::git_clone_with_retry() {
    local repo_url="$1"
    local destination="$2"
    local description="${3:-Cloning $repo_url}"
    
    if ! zsh_setup::core::errors::validate_url "$repo_url"; then
        zsh_setup::core::logger::error "Invalid repository URL: $repo_url"
        return 1
    fi
    
    zsh_setup::core::errors::execute_network_with_retry "$description" \
        git clone --depth=1 "$repo_url" "$destination"
}

# Backward compatibility
curl_download_with_retry() {
    zsh_setup::utils::network::download_with_retry "$@"
}

git_clone_with_retry() {
    zsh_setup::utils::network::git_clone_with_retry "$@"
}
