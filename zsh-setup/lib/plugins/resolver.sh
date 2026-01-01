#!/usr/bin/env bash

#==============================================================================
# resolver.sh - Dependency Resolution
#
# Handles plugin dependency resolution with circular dependency detection
#==============================================================================

# Load dependencies
if [[ -n "${ZSH_SETUP_ROOT:-}" ]]; then
    source "$ZSH_SETUP_ROOT/lib/core/config.sh"
    source "$ZSH_SETUP_ROOT/lib/core/logger.sh"
    source "$ZSH_SETUP_ROOT/lib/plugins/registry.sh"
fi

# Track resolved dependencies
declare -A ZSH_SETUP_RESOLVED_DEPS=()

#------------------------------------------------------------------------------
# Dependency Resolution
#------------------------------------------------------------------------------

# Resolve dependencies for a plugin
zsh_setup::plugins::resolver::resolve() {
    local plugin="$1"
    local depth="${2:-0}"
    local max_depth=$(zsh_setup::core::config::get max_dependency_depth "10")
    local resolved=()
    
    # Prevent infinite recursion
    if [[ $depth -gt $max_depth ]]; then
        zsh_setup::core::logger::warn "Maximum dependency depth reached for $plugin. Possible circular dependency."
        return 1
    fi
    
    # Check for circular dependencies
    if [[ -n "${ZSH_SETUP_RESOLVED_DEPS[$plugin]}" ]]; then
        zsh_setup::core::logger::warn "Circular dependency detected involving $plugin. Skipping."
        return 0
    fi
    
    # Mark as being resolved
    ZSH_SETUP_RESOLVED_DEPS[$plugin]=1
    
    # Get dependencies
    local deps=$(zsh_setup::plugins::registry::get_dependencies "$plugin")
    [[ -z "$deps" ]] && return 0
    
    # Split dependencies
    local deps_array=()
    if [[ "$deps" == *","* ]]; then
        IFS=',' read -ra deps_array <<<"$deps"
    else
        read -ra deps_array <<<"$deps"
    fi
    
    # Resolve each dependency
    for dep in "${deps_array[@]}"; do
        dep=$(echo "$dep" | xargs)
        [[ -z "$dep" ]] && continue
        
        # Check if dependency is a valid plugin
        if zsh_setup::plugins::registry::exists "$dep"; then
            resolved+=("$dep")
            # Recursively resolve dependencies
            zsh_setup::plugins::resolver::resolve "$dep" $((depth + 1))
        else
            zsh_setup::core::logger::warn "Dependency '$dep' for plugin '$plugin' not found in registry"
        fi
    done
    
    # Output resolved dependencies
    if [[ ${#resolved[@]} -gt 0 ]]; then
        printf '%s\n' "${resolved[@]}"
    fi
    
    return 0
}

# Resolve all dependencies for a list of plugins
zsh_setup::plugins::resolver::resolve_all() {
    local plugins=("$@")
    local all_deps=()
    local resolved_plugins=()
    
    # Clear resolution tracking
    ZSH_SETUP_RESOLVED_DEPS=()
    
    # Resolve dependencies for each plugin
    for plugin in "${plugins[@]}"; do
        # Add plugin itself
        resolved_plugins+=("$plugin")
        
        # Resolve dependencies
        local deps=()
        while IFS= read -r dep; do
            [[ -n "$dep" ]] && deps+=("$dep")
        done < <(zsh_setup::plugins::resolver::resolve "$plugin")
        
        # Add dependencies
        for dep in "${deps[@]}"; do
            if ! printf '%s\n' "${resolved_plugins[@]}" | grep -q "^${dep}$"; then
                resolved_plugins+=("$dep")
            fi
        done
    done
    
    # Return resolved list
    printf '%s\n' "${resolved_plugins[@]}"
}

# Backward compatibility
resolve_dependencies() {
    zsh_setup::plugins::resolver::resolve "$@"
}

get_plugin_dependencies() {
    zsh_setup::plugins::registry::get_dependencies "$@"
}
