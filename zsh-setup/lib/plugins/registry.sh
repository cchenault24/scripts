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

# Plugin registry storage (bash 3.2 compatible - using prefix-based variables)
# Keys are stored as ZSH_SETUP_PLUGIN_REGISTRY_key variables
ZSH_SETUP_PLUGIN_REGISTRY_KEYS=""
ZSH_SETUP_PLUGIN_DEPS_KEYS=""

# Helper function to sanitize key names for variable names
zsh_setup::plugins::registry::_sanitize_key() {
    local key="$1"
    echo "$key" | sed 's/[^a-zA-Z0-9_]/_/g'
}

# Helper function to get variable name for a registry key
zsh_setup::plugins::registry::_get_registry_var_name() {
    local key="$1"
    local sanitized=$(zsh_setup::plugins::registry::_sanitize_key "$key")
    echo "ZSH_SETUP_PLUGIN_REGISTRY_${sanitized}"
}

# Helper function to get variable name for a deps key
zsh_setup::plugins::registry::_get_deps_var_name() {
    local key="$1"
    local sanitized=$(zsh_setup::plugins::registry::_sanitize_key "$key")
    echo "ZSH_SETUP_PLUGIN_DEPS_${sanitized}"
}

# Cache tracking
ZSH_SETUP_REGISTRY_LOADED=false
ZSH_SETUP_REGISTRY_CACHE_ROOT=""

#------------------------------------------------------------------------------
# Plugin Loading
#------------------------------------------------------------------------------

# Load plugin configurations (with caching)
zsh_setup::plugins::registry::load() {
    local root="${ZSH_SETUP_ROOT:-}"
    local plugins_file="${root}/plugins.conf"
    local deps_file="${root}/plugin_dependencies.conf"
    
    # Check if already loaded for this root
    if [[ "$ZSH_SETUP_REGISTRY_LOADED" == "true" && "$ZSH_SETUP_REGISTRY_CACHE_ROOT" == "$root" ]]; then
        zsh_setup::core::logger::debug "Using cached plugin registry"
        return 0
    fi
    
    # Clear existing registry
    # Unset all registry variables
    for key in $(echo "$ZSH_SETUP_PLUGIN_REGISTRY_KEYS" | tr ':' '\n' | grep -v '^$'); do
        local var_name=$(zsh_setup::plugins::registry::_get_registry_var_name "$key")
        unset "$var_name"
    done
    for key in $(echo "$ZSH_SETUP_PLUGIN_DEPS_KEYS" | tr ':' '\n' | grep -v '^$'); do
        local var_name=$(zsh_setup::plugins::registry::_get_deps_var_name "$key")
        unset "$var_name"
    done
    ZSH_SETUP_PLUGIN_REGISTRY_KEYS=""
    ZSH_SETUP_PLUGIN_DEPS_KEYS=""
    
    # Load plugins
    if [[ -f "$plugins_file" ]]; then
        zsh_setup::core::logger::info "Loading plugin configurations from $plugins_file"
        while IFS='|' read -r name type url description; do
            [[ -z "$name" || "$name" =~ ^# ]] && continue
            name=$(echo "$name" | xargs)
            type=$(echo "$type" | xargs)
            url=$(echo "$url" | xargs)
            description=$(echo "$description" | xargs)
            
            local var_name=$(zsh_setup::plugins::registry::_get_registry_var_name "$name")
            local value="${type}|${url}|${description}"
            local escaped_value=$(printf '%q' "$value")
            eval "${var_name}=${escaped_value}"
            if [[ "$ZSH_SETUP_PLUGIN_REGISTRY_KEYS" != *":$name:"* ]]; then
                ZSH_SETUP_PLUGIN_REGISTRY_KEYS="${ZSH_SETUP_PLUGIN_REGISTRY_KEYS}:$name:"
            fi
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
            local var_name=$(zsh_setup::plugins::registry::_get_deps_var_name "$plugin_name")
            local escaped_value=$(printf '%q' "$deps")
            eval "${var_name}=${escaped_value}"
            if [[ "$ZSH_SETUP_PLUGIN_DEPS_KEYS" != *":$plugin_name:"* ]]; then
                ZSH_SETUP_PLUGIN_DEPS_KEYS="${ZSH_SETUP_PLUGIN_DEPS_KEYS}:$plugin_name:"
            fi
        done < "$deps_file"
    fi
    
    # Mark as loaded
    ZSH_SETUP_REGISTRY_LOADED=true
    ZSH_SETUP_REGISTRY_CACHE_ROOT="$root"
    zsh_setup::core::logger::debug "Plugin registry loaded and cached"
}

# Clear registry cache (useful for testing or reloading)
zsh_setup::plugins::registry::clear_cache() {
    # Unset all registry variables
    for key in $(echo "$ZSH_SETUP_PLUGIN_REGISTRY_KEYS" | tr ':' '\n' | grep -v '^$'); do
        local var_name=$(zsh_setup::plugins::registry::_get_registry_var_name "$key")
        unset "$var_name"
    done
    for key in $(echo "$ZSH_SETUP_PLUGIN_DEPS_KEYS" | tr ':' '\n' | grep -v '^$'); do
        local var_name=$(zsh_setup::plugins::registry::_get_deps_var_name "$key")
        unset "$var_name"
    done
    ZSH_SETUP_PLUGIN_REGISTRY_KEYS=""
    ZSH_SETUP_PLUGIN_DEPS_KEYS=""
    ZSH_SETUP_REGISTRY_LOADED=false
    ZSH_SETUP_REGISTRY_CACHE_ROOT=""
}

# Get plugin info
zsh_setup::plugins::registry::get() {
    local plugin_name="$1"
    local field="${2:-all}"  # all, type, url, description
    
    local var_name=$(zsh_setup::plugins::registry::_get_registry_var_name "$plugin_name")
    local value=$(eval "echo \${${var_name}:-}")
    
    if [[ -z "$value" ]]; then
        return 1
    fi
    
    IFS='|' read -r type url description <<<"$value"
    
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
    local var_name=$(zsh_setup::plugins::registry::_get_deps_var_name "$plugin_name")
    local value=$(eval "echo \${${var_name}:-}")
    echo "$value"
}

# List all available plugins
zsh_setup::plugins::registry::list() {
    echo "$ZSH_SETUP_PLUGIN_REGISTRY_KEYS" | tr ':' '\n' | grep -v '^$' | sort
}

# Check if plugin exists
zsh_setup::plugins::registry::exists() {
    local plugin_name="$1"
    local var_name=$(zsh_setup::plugins::registry::_get_registry_var_name "$plugin_name")
    local value=$(eval "echo \${${var_name}:-}")
    [[ -n "$value" ]]
}
