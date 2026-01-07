#!/usr/bin/env bash

#==============================================================================
# bootstrap.sh - Module Bootstrap and Dependency Loader
#
# Initializes the zsh-setup environment and loads required modules
#==============================================================================

# Determine root directory
if [[ -z "${ZSH_SETUP_ROOT:-}" ]]; then
    if [[ -n "${BASH_SOURCE[0]}" ]]; then
        ZSH_SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    else
        ZSH_SETUP_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
    fi
fi

export ZSH_SETUP_ROOT

# Track loaded modules to prevent circular dependencies (bash 3.2 compatible)
ZSH_SETUP_LOADED_MODULES=""

#------------------------------------------------------------------------------
# Function: zsh_setup::core::bootstrap::is_loaded
# Description: Check if a module has already been loaded
# Arguments:
#   $1 - Module name (e.g., "core::config")
# Returns: 0 if loaded, 1 if not loaded
#------------------------------------------------------------------------------
zsh_setup::core::bootstrap::is_loaded() {
    local module="$1"
    case ":$ZSH_SETUP_LOADED_MODULES:" in
        *":$module:"*) return 0 ;;
        *) return 1 ;;
    esac
}

#------------------------------------------------------------------------------
# Function: zsh_setup::core::bootstrap::mark_loaded
# Description: Mark a module as loaded to prevent duplicate loading
# Arguments:
#   $1 - Module name (e.g., "core::config")
# Returns: 0 on success
#------------------------------------------------------------------------------
zsh_setup::core::bootstrap::mark_loaded() {
    local module="$1"
    if ! zsh_setup::core::bootstrap::is_loaded "$module"; then
        ZSH_SETUP_LOADED_MODULES="${ZSH_SETUP_LOADED_MODULES}:${module}"
    fi
}

#------------------------------------------------------------------------------
# Module Loading
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Function: zsh_setup::core::bootstrap::load_module
# Description: Load a module by name, handling dependencies and preventing duplicates
# Arguments:
#   $1 - Module name (e.g., "core::config", "plugins::manager")
# Returns: 0 on success, 1 on failure
# Notes: Modules are loaded only once, even if called multiple times
#------------------------------------------------------------------------------
zsh_setup::core::bootstrap::load_module() {
    local module="$1"
    local module_path=""
    
    # Check if already loaded
    if zsh_setup::core::bootstrap::is_loaded "$module"; then
        return 0
    fi
    
    # Determine module path
    case "$module" in
        core::config)
            module_path="$ZSH_SETUP_ROOT/lib/core/config.sh"
            ;;
        core::logger)
            module_path="$ZSH_SETUP_ROOT/lib/core/logger.sh"
            ;;
        core::errors)
            module_path="$ZSH_SETUP_ROOT/lib/core/errors.sh"
            ;;
        core::progress)
            module_path="$ZSH_SETUP_ROOT/lib/core/progress.sh"
            ;;
        core::state)
            module_path="$ZSH_SETUP_ROOT/lib/state/store.sh"
            ;;
        system::package_manager)
            module_path="$ZSH_SETUP_ROOT/lib/system/package_manager.sh"
            ;;
        system::shell)
            module_path="$ZSH_SETUP_ROOT/lib/system/shell.sh"
            ;;
        system::validation)
            module_path="$ZSH_SETUP_ROOT/lib/system/validation.sh"
            ;;
        plugins::registry)
            module_path="$ZSH_SETUP_ROOT/lib/plugins/registry.sh"
            ;;
        plugins::manager)
            module_path="$ZSH_SETUP_ROOT/lib/plugins/manager.sh"
            ;;
        plugins::installer)
            module_path="$ZSH_SETUP_ROOT/lib/plugins/installer.sh"
            ;;
        plugins::resolver)
            module_path="$ZSH_SETUP_ROOT/lib/plugins/resolver.sh"
            ;;
        config::generator)
            module_path="$ZSH_SETUP_ROOT/lib/config/generator.sh"
            ;;
        config::validator)
            module_path="$ZSH_SETUP_ROOT/lib/config/validator.sh"
            ;;
        config::backup)
            module_path="$ZSH_SETUP_ROOT/lib/config/backup.sh"
            ;;
        utils::network)
            module_path="$ZSH_SETUP_ROOT/lib/utils/network.sh"
            ;;
        utils::filesystem)
            module_path="$ZSH_SETUP_ROOT/lib/utils/filesystem.sh"
            ;;
        *)
            echo "Unknown module: $module" >&2
            return 1
            ;;
    esac
    
    if [[ ! -f "$module_path" ]]; then
        echo "Module not found: $module_path" >&2
        return 1
    fi
    
    # Load the module
    source "$module_path"
    zsh_setup::core::bootstrap::mark_loaded "$module"
    
    return 0
}

#------------------------------------------------------------------------------
# Function: zsh_setup::core::bootstrap::load_modules
# Description: Load multiple modules in sequence
# Arguments:
#   $@ - Module names to load
# Returns: 0 if all modules loaded successfully, 1 on first failure
#------------------------------------------------------------------------------
zsh_setup::core::bootstrap::load_modules() {
    local modules=("$@")
    for module in "${modules[@]}"; do
        zsh_setup::core::bootstrap::load_module "$module" || return 1
    done
    return 0
}

#------------------------------------------------------------------------------
# Initialization
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Function: zsh_setup::core::bootstrap::init
# Description: Initialize the zsh-setup environment, loading core modules
# Arguments:
#   $1 - Optional initialization options (currently unused)
# Returns: 0 on success, 1 on failure
# Notes: Must be called before using any zsh-setup functions
#------------------------------------------------------------------------------
zsh_setup::core::bootstrap::init() {
    local options="${1:-}"
    
    # Load core modules first (they have no dependencies)
    zsh_setup::core::bootstrap::load_modules \
        core::config \
        core::logger \
        core::errors || return 1
    
    # Initialize configuration
    zsh_setup::core::config::load
    
    # Initialize logging
    zsh_setup::core::logger::init "${ZSH_SETUP_VERSION:-2.0.0}"
    
    # Set up error handling
    zsh_setup::core::errors::setup_trap
    
    return 0
}

# Get a module's functions (for dependency injection)
zsh_setup::core::bootstrap::get_module() {
    local module="$1"
    zsh_setup::core::bootstrap::load_module "$module" || return 1
    echo "$module"
}

# Helper function for modules to load their dependencies
# This can be called from within modules to load dependencies
zsh_setup::core::bootstrap::load_dependency() {
    local module="$1"
    # If bootstrap is available, use it; otherwise fall back to direct source
    if declare -f zsh_setup::core::bootstrap::load_module &>/dev/null; then
        zsh_setup::core::bootstrap::load_module "$module"
    else
        # Fallback: try to determine path and source directly
        local module_path=""
        case "$module" in
            core::config)
                module_path="${ZSH_SETUP_ROOT:-}/lib/core/config.sh"
                ;;
            core::logger)
                module_path="${ZSH_SETUP_ROOT:-}/lib/core/logger.sh"
                ;;
            core::errors)
                module_path="${ZSH_SETUP_ROOT:-}/lib/core/errors.sh"
                ;;
            *)
                # Try to construct path from module name
                module_path="${ZSH_SETUP_ROOT:-}/lib/${module//::/\/}.sh"
                ;;
        esac
        if [[ -f "$module_path" ]]; then
            source "$module_path"
        else
            echo "Cannot load dependency $module: path not found" >&2
            return 1
        fi
    fi
}
