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
    # Load package manager for system dependency installation
    if [[ -f "$ZSH_SETUP_ROOT/lib/system/package_manager.sh" ]]; then
        source "$ZSH_SETUP_ROOT/lib/system/package_manager.sh"
    fi
fi

# Track resolved dependencies (bash 3.2 compatible)
ZSH_SETUP_RESOLVED_DEPS_KEYS=""

# Helper function to sanitize key names for variable names
zsh_setup::plugins::resolver::_sanitize_key() {
    local key="$1"
    echo "$key" | sed 's/[^a-zA-Z0-9_]/_/g'
}

# Helper function to get variable name for a resolved deps key
zsh_setup::plugins::resolver::_get_var_name() {
    local key="$1"
    local sanitized=$(zsh_setup::plugins::resolver::_sanitize_key "$key")
    echo "ZSH_SETUP_RESOLVED_DEPS_${sanitized}"
}

# Helper function to check if a dependency is resolved
zsh_setup::plugins::resolver::_is_resolved() {
    local plugin="$1"
    local var_name=$(zsh_setup::plugins::resolver::_get_var_name "$plugin")
    local value=$(eval "echo \${${var_name}:-}")
    [[ -n "$value" ]]
}

# Helper function to mark a dependency as resolved
zsh_setup::plugins::resolver::_mark_resolved() {
    local plugin="$1"
    local var_name=$(zsh_setup::plugins::resolver::_get_var_name "$plugin")
    eval "${var_name}=1"
    if [[ "$ZSH_SETUP_RESOLVED_DEPS_KEYS" != *":$plugin:"* ]]; then
        ZSH_SETUP_RESOLVED_DEPS_KEYS="${ZSH_SETUP_RESOLVED_DEPS_KEYS}:$plugin:"
    fi
}

# Helper function to clear resolved dependencies
zsh_setup::plugins::resolver::_clear_resolved() {
    # Unset all resolved deps variables
    for key in $(echo "$ZSH_SETUP_RESOLVED_DEPS_KEYS" | tr ':' '\n' | grep -v '^$'); do
        local var_name=$(zsh_setup::plugins::resolver::_get_var_name "$key")
        unset "$var_name"
    done
    ZSH_SETUP_RESOLVED_DEPS_KEYS=""
}

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
    if zsh_setup::plugins::resolver::_is_resolved "$plugin"; then
        zsh_setup::core::logger::warn "Circular dependency detected involving $plugin. Skipping."
        return 0
    fi
    
    # Mark as being resolved
    zsh_setup::plugins::resolver::_mark_resolved "$plugin"
    
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
        elif command -v "$dep" &>/dev/null; then
            # System dependency (command exists) - silently skip, no need to install as plugin
            zsh_setup::core::logger::debug "Dependency '$dep' for plugin '$plugin' is a system command (already available)"
        else
            # System dependency not found - try to install it
            if declare -f zsh_setup::system::package_manager::install &>/dev/null; then
                zsh_setup::core::logger::info "System dependency '$dep' required for plugin '$plugin' is not installed. Attempting to install..."
                if zsh_setup::system::package_manager::install "$dep" "Installing system dependency '$dep' for plugin '$plugin'"; then
                    zsh_setup::core::logger::success "System dependency '$dep' installed successfully"
                else
                    zsh_setup::core::logger::warn "Failed to install system dependency '$dep' for plugin '$plugin'. Plugin installation may fail."
                fi
            else
                # Neither a plugin nor a system command, and can't install it
                zsh_setup::core::logger::warn "Dependency '$dep' for plugin '$plugin' not found in registry and not available as system command"
            fi
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
    zsh_setup::plugins::resolver::_clear_resolved
    
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

