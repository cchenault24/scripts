#!/usr/bin/env bash

#==============================================================================
# config.sh - Configuration Management
#
# Centralized configuration with environment variable override support
#==============================================================================

# Configuration storage
declare -A ZSH_SETUP_CONFIG=()

#------------------------------------------------------------------------------
# Configuration Loading
#------------------------------------------------------------------------------

# Load configuration from files, environment, and defaults
zsh_setup::core::config::load() {
    local root="${ZSH_SETUP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    
    # Set defaults
    zsh_setup::core::config::_set_defaults
    
    # Load from config files
    if [[ -f "$root/config/defaults.conf" ]]; then
        zsh_setup::core::config::_load_file "$root/config/defaults.conf"
    fi
    
    # Override with environment variables
    zsh_setup::core::config::_load_env
    
    # Load from legacy config.sh if exists (for migration)
    if [[ -f "$root/config.sh" ]]; then
        source "$root/config.sh"
        # Map legacy variables to new config
        zsh_setup::core::config::_map_legacy
    fi
}

# Set default configuration values
zsh_setup::core::config::_set_defaults() {
    ZSH_SETUP_CONFIG[version]="2.0.0"
    ZSH_SETUP_CONFIG[oh_my_zsh_dir]="$HOME/.oh-my-zsh"
    ZSH_SETUP_CONFIG[custom_plugins_dir]="$HOME/.oh-my-zsh/custom/plugins"
    ZSH_SETUP_CONFIG[custom_themes_dir]="$HOME/.oh-my-zsh/custom/themes"
    ZSH_SETUP_CONFIG[zshrc_path]="$HOME/.zshrc"
    ZSH_SETUP_CONFIG[backup_dir]="$HOME/.zsh_backup"
    ZSH_SETUP_CONFIG[state_file]="${ZSH_SETUP_STATE_FILE:-/tmp/zsh_setup_state.json}"
    ZSH_SETUP_CONFIG[log_file]="${LOG_FILE:-/tmp/zsh_setup.log}"
    ZSH_SETUP_CONFIG[installation_log]="${INSTALLATION_LOG:-/tmp/zsh_plugin_installation.log}"
    ZSH_SETUP_CONFIG[max_parallel_installs]="${MAX_PARALLEL_INSTALLS:-3}"
    ZSH_SETUP_CONFIG[max_retries]="${MAX_RETRIES:-3}"
    ZSH_SETUP_CONFIG[retry_delay]="${RETRY_DELAY:-2}"
    ZSH_SETUP_CONFIG[retry_backoff_multiplier]="${RETRY_BACKOFF_MULTIPLIER:-2}"
    ZSH_SETUP_CONFIG[rollback_on_failure]="${ROLLBACK_ON_FAILURE:-true}"
    ZSH_SETUP_CONFIG[default_theme]="robbyrussell"
    ZSH_SETUP_CONFIG[max_dependency_depth]="10"
    ZSH_SETUP_CONFIG[min_zsh_version]="4.0"
    ZSH_SETUP_CONFIG[verbose]="${VERBOSE:-true}"
    ZSH_SETUP_CONFIG[dry_run]="${DRY_RUN:-false}"
}

# Load configuration from file
zsh_setup::core::config::_load_file() {
    local file="$1"
    while IFS='=' read -r key value; do
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        ZSH_SETUP_CONFIG[$key]="$value"
    done < "$file" 2>/dev/null || true
}

# Load from environment variables
zsh_setup::core::config::_load_env() {
    # Map common environment variables
    [[ -n "${ZSH_SETUP_STATE_FILE:-}" ]] && ZSH_SETUP_CONFIG[state_file]="$ZSH_SETUP_STATE_FILE"
    [[ -n "${LOG_FILE:-}" ]] && ZSH_SETUP_CONFIG[log_file]="$LOG_FILE"
    [[ -n "${VERBOSE:-}" ]] && ZSH_SETUP_CONFIG[verbose]="$VERBOSE"
    [[ -n "${DRY_RUN:-}" ]] && ZSH_SETUP_CONFIG[dry_run]="$DRY_RUN"
    [[ -n "${MAX_PARALLEL_INSTALLS:-}" ]] && ZSH_SETUP_CONFIG[max_parallel_installs]="$MAX_PARALLEL_INSTALLS"
}

# Map legacy variables to new config
zsh_setup::core::config::_map_legacy() {
    [[ -n "${OH_MY_ZSH_DIR:-}" ]] && ZSH_SETUP_CONFIG[oh_my_zsh_dir]="$OH_MY_ZSH_DIR"
    [[ -n "${CUSTOM_PLUGINS_DIR:-}" ]] && ZSH_SETUP_CONFIG[custom_plugins_dir]="$CUSTOM_PLUGINS_DIR"
    [[ -n "${CUSTOM_THEMES_DIR:-}" ]] && ZSH_SETUP_CONFIG[custom_themes_dir]="$CUSTOM_THEMES_DIR"
    [[ -n "${ZSHRC_PATH:-}" ]] && ZSH_SETUP_CONFIG[zshrc_path]="$ZSHRC_PATH"
    [[ -n "${BACKUP_DIR:-}" ]] && ZSH_SETUP_CONFIG[backup_dir]="$BACKUP_DIR"
    [[ -n "${DEFAULT_THEME:-}" ]] && ZSH_SETUP_CONFIG[default_theme]="$DEFAULT_THEME"
}

#------------------------------------------------------------------------------
# Configuration Access
#------------------------------------------------------------------------------

# Get a configuration value
zsh_setup::core::config::get() {
    local key="$1"
    local default="${2:-}"
    echo "${ZSH_SETUP_CONFIG[$key]:-$default}"
}

# Set a configuration value
zsh_setup::core::config::set() {
    local key="$1"
    local value="$2"
    ZSH_SETUP_CONFIG[$key]="$value"
}

# Check if a configuration key exists
zsh_setup::core::config::has() {
    local key="$1"
    [[ -n "${ZSH_SETUP_CONFIG[$key]:-}" ]]
}

# Get all configuration keys
zsh_setup::core::config::keys() {
    printf '%s\n' "${!ZSH_SETUP_CONFIG[@]}" | sort
}

# Export configuration as environment variables (for backward compatibility)
zsh_setup::core::config::export() {
    export OH_MY_ZSH_DIR="${ZSH_SETUP_CONFIG[oh_my_zsh_dir]}"
    export CUSTOM_PLUGINS_DIR="${ZSH_SETUP_CONFIG[custom_plugins_dir]}"
    export CUSTOM_THEMES_DIR="${ZSH_SETUP_CONFIG[custom_themes_dir]}"
    export ZSHRC_PATH="${ZSH_SETUP_CONFIG[zshrc_path]}"
    export BACKUP_DIR="${ZSH_SETUP_CONFIG[backup_dir]}"
    export STATE_FILE="${ZSH_SETUP_CONFIG[state_file]}"
    export LOG_FILE="${ZSH_SETUP_CONFIG[log_file]}"
    export INSTALLATION_LOG="${ZSH_SETUP_CONFIG[installation_log]}"
    export MAX_PARALLEL_INSTALLS="${ZSH_SETUP_CONFIG[max_parallel_installs]}"
    export MAX_RETRIES="${ZSH_SETUP_CONFIG[max_retries]}"
    export RETRY_DELAY="${ZSH_SETUP_CONFIG[retry_delay]}"
    export RETRY_BACKOFF_MULTIPLIER="${ZSH_SETUP_CONFIG[retry_backoff_multiplier]}"
    export ROLLBACK_ON_FAILURE="${ZSH_SETUP_CONFIG[rollback_on_failure]}"
    export DEFAULT_THEME="${ZSH_SETUP_CONFIG[default_theme]}"
    export VERBOSE="${ZSH_SETUP_CONFIG[verbose]}"
    export DRY_RUN="${ZSH_SETUP_CONFIG[dry_run]}"
}
