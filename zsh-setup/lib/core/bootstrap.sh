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

# Check if module is loaded (bash 3.2 compatible)
zsh_setup::core::bootstrap::is_loaded() {
    local module="$1"
    case ":$ZSH_SETUP_LOADED_MODULES:" in
        *":$module:"*) return 0 ;;
        *) return 1 ;;
    esac
}

# Mark module as loaded (bash 3.2 compatible)
zsh_setup::core::bootstrap::mark_loaded() {
    local module="$1"
    if ! zsh_setup::core::bootstrap::is_loaded "$module"; then
        ZSH_SETUP_LOADED_MODULES="${ZSH_SETUP_LOADED_MODULES}:${module}"
    fi
}

#------------------------------------------------------------------------------
# Module Loading
#------------------------------------------------------------------------------

# Load a module by name
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
        plugins::registry)
            module_path="$ZSH_SETUP_ROOT/lib/plugins/registry.sh"
            ;;
        plugins::installer)
            module_path="$ZSH_SETUP_ROOT/lib/plugins/installer.sh"
            ;;
        plugins::resolver)
            module_path="$ZSH_SETUP_ROOT/lib/plugins/resolver.sh"
            ;;
        plugins::manager)
            module_path="$ZSH_SETUP_ROOT/lib/plugins/manager.sh"
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

# Load multiple modules
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

# Initialize the zsh-setup environment
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
