#!/usr/bin/env bash

#==============================================================================
# registry.sh - Plugin Registry
#
# Manages plugin definitions and configuration loading
#==============================================================================

# Load dependencies
if [[ -n "${ZSH_SETUP_ROOT:-}" ]]; then
    source "$ZSH_SETUP_ROOT/lib/core/config.sh"
    source "$ZSH_SETUP_ROOT/lib/core/logger.sh"
fi

# Plugin registry storage
declare -A ZSH_SETUP_PLUGIN_REGISTRY=()
declare -A ZSH_SETUP_PLUGIN_DEPS=()

#------------------------------------------------------------------------------
# Plugin Loading
#------------------------------------------------------------------------------

# Load plugin configurations
zsh_setup::plugins::registry::load() {
    local root="${ZSH_SETUP_ROOT:-}"
    local plugins_file="${root}/plugins.conf"
    local deps_file="${root}/plugin_dependencies.conf"
    
    # Clear existing registry
    ZSH_SETUP_PLUGIN_REGISTRY=()
    ZSH_SETUP_PLUGIN_DEPS=()
    
    # Load plugins
    if [[ -f "$plugins_file" ]]; then
        zsh_setup::core::logger::info "Loading plugin configurations from $plugins_file"
        while IFS='|' read -r name type url description; do
            [[ -z "$name" || "$name" =~ ^# ]] && continue
            name=$(echo "$name" | xargs)
            type=$(echo "$type" | xargs)
            url=$(echo "$url" | xargs)
            description=$(echo "$description" | xargs)
            
            ZSH_SETUP_PLUGIN_REGISTRY[$name]="$type|$url|$description"
        done < "$plugins_file"
    else
        zsh_setup::core::logger::warn "Plugin configuration file not found: $plugins_file"
    fi
    
    # Load dependencies
    if [[ -f "$deps_file" ]]; then
        zsh_setup::core::logger::info "Loading plugin dependencies from $deps_file"
        while IFS='=' read -r plugin_name deps; do
            [[ -z "$plugin_name" || "$plugin_name" =~ ^# ]] && continue
            plugin_name=$(echo "$plugin_name" | xargs)
            deps=$(echo "$deps" | xargs)
            ZSH_SETUP_PLUGIN_DEPS[$plugin_name]="$deps"
        done < "$deps_file"
    fi
}

# Get plugin info
zsh_setup::plugins::registry::get() {
    local plugin_name="$1"
    local field="${2:-all}"  # all, type, url, description
    
    if [[ -z "${ZSH_SETUP_PLUGIN_REGISTRY[$plugin_name]:-}" ]]; then
        return 1
    fi
    
    IFS='|' read -r type url description <<<"${ZSH_SETUP_PLUGIN_REGISTRY[$plugin_name]}"
    
    case "$field" in
        type) echo "$type" ;;
        url) echo "$url" ;;
        description) echo "$description" ;;
        all) echo "$type|$url|$description" ;;
    esac
}

# Get plugin dependencies
zsh_setup::plugins::registry::get_dependencies() {
    local plugin_name="$1"
    echo "${ZSH_SETUP_PLUGIN_DEPS[$plugin_name]:-}"
}

# List all available plugins
zsh_setup::plugins::registry::list() {
    printf '%s\n' "${!ZSH_SETUP_PLUGIN_REGISTRY[@]}" | sort
}

# Check if plugin exists
zsh_setup::plugins::registry::exists() {
    local plugin_name="$1"
    [[ -n "${ZSH_SETUP_PLUGIN_REGISTRY[$plugin_name]:-}" ]]
}
