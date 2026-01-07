#!/usr/bin/env bash

#==============================================================================
# config.sh - Configuration Management
#
# Centralized configuration with environment variable override support
#==============================================================================

# Configuration storage (bash 3.2 compatible - using prefix-based variables)
# Keys are stored as ZSH_SETUP_CONFIG_key variables
ZSH_SETUP_CONFIG_KEYS=""

# Helper function to sanitize key names for variable names
zsh_setup::core::config::_sanitize_key() {
    local key="$1"
    # Replace special characters with underscores
    echo "$key" | sed 's/[^a-zA-Z0-9_]/_/g'
}

# Helper function to get variable name for a key
zsh_setup::core::config::_get_var_name() {
    local key="$1"
    local sanitized=$(zsh_setup::core::config::_sanitize_key "$key")
    echo "ZSH_SETUP_CONFIG_${sanitized}"
}

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
}

# Set default configuration values
zsh_setup::core::config::_set_defaults() {
    zsh_setup::core::config::set "version" "2.0.0"
    zsh_setup::core::config::set "oh_my_zsh_dir" "$HOME/.oh-my-zsh"
    zsh_setup::core::config::set "custom_plugins_dir" "$HOME/.oh-my-zsh/custom/plugins"
    zsh_setup::core::config::set "custom_themes_dir" "$HOME/.oh-my-zsh/custom/themes"
    zsh_setup::core::config::set "zshrc_path" "$HOME/.zshrc"
    zsh_setup::core::config::set "backup_dir" "$HOME/.zsh_backup"
    zsh_setup::core::config::set "state_file" "${ZSH_SETUP_STATE_FILE:-/tmp/zsh_setup_state.json}"
    zsh_setup::core::config::set "log_file" "${LOG_FILE:-/tmp/zsh_setup.log}"
    zsh_setup::core::config::set "installation_log" "${INSTALLATION_LOG:-/tmp/zsh_plugin_installation.log}"
    zsh_setup::core::config::set "max_parallel_installs" "${MAX_PARALLEL_INSTALLS:-3}"
    zsh_setup::core::config::set "max_retries" "${MAX_RETRIES:-3}"
    zsh_setup::core::config::set "retry_delay" "${RETRY_DELAY:-2}"
    zsh_setup::core::config::set "retry_backoff_multiplier" "${RETRY_BACKOFF_MULTIPLIER:-2}"
    zsh_setup::core::config::set "rollback_on_failure" "${ROLLBACK_ON_FAILURE:-true}"
    zsh_setup::core::config::set "default_theme" "robbyrussell"
    zsh_setup::core::config::set "max_dependency_depth" "10"
    zsh_setup::core::config::set "min_zsh_version" "4.0"
    zsh_setup::core::config::set "verbose" "${VERBOSE:-true}"
    zsh_setup::core::config::set "dry_run" "${DRY_RUN:-false}"
}

# Load configuration from file
zsh_setup::core::config::_load_file() {
    local file="$1"
    while IFS='=' read -r key value; do
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        zsh_setup::core::config::set "$key" "$value"
    done < "$file" 2>/dev/null || true
}

# Load from environment variables
zsh_setup::core::config::_load_env() {
    # Map common environment variables
    [[ -n "${ZSH_SETUP_STATE_FILE:-}" ]] && zsh_setup::core::config::set "state_file" "$ZSH_SETUP_STATE_FILE"
    [[ -n "${LOG_FILE:-}" ]] && zsh_setup::core::config::set "log_file" "$LOG_FILE"
    [[ -n "${VERBOSE:-}" ]] && zsh_setup::core::config::set "verbose" "$VERBOSE"
    [[ -n "${DRY_RUN:-}" ]] && zsh_setup::core::config::set "dry_run" "$DRY_RUN"
    [[ -n "${MAX_PARALLEL_INSTALLS:-}" ]] && zsh_setup::core::config::set "max_parallel_installs" "$MAX_PARALLEL_INSTALLS"
}


#------------------------------------------------------------------------------
# Configuration Access
#------------------------------------------------------------------------------

# Get a configuration value
zsh_setup::core::config::get() {
    local key="$1"
    local default="${2:-}"
    local var_name=$(zsh_setup::core::config::_get_var_name "$key")
    local value=$(eval "echo \${${var_name}:-}")
    if [[ -z "$value" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Set a configuration value
zsh_setup::core::config::set() {
    local key="$1"
    local value="$2"
    local var_name=$(zsh_setup::core::config::_get_var_name "$key")
    # Use printf %q to safely escape the value
    local escaped_value=$(printf '%q' "$value")
    eval "${var_name}=${escaped_value}"
    # Track keys
    if [[ "$ZSH_SETUP_CONFIG_KEYS" != *":$key:"* ]]; then
        ZSH_SETUP_CONFIG_KEYS="${ZSH_SETUP_CONFIG_KEYS}:$key:"
    fi
}

# Check if a configuration key exists
zsh_setup::core::config::has() {
    local key="$1"
    local var_name=$(zsh_setup::core::config::_get_var_name "$key")
    local value=$(eval "echo \${${var_name}:-}")
    [[ -n "$value" ]]
}

# Get all configuration keys
zsh_setup::core::config::keys() {
    echo "$ZSH_SETUP_CONFIG_KEYS" | tr ':' '\n' | grep -v '^$' | sort
}

# Export configuration as environment variables
zsh_setup::core::config::export() {
    export OH_MY_ZSH_DIR="$(zsh_setup::core::config::get oh_my_zsh_dir)"
    export CUSTOM_PLUGINS_DIR="$(zsh_setup::core::config::get custom_plugins_dir)"
    export CUSTOM_THEMES_DIR="$(zsh_setup::core::config::get custom_themes_dir)"
    export ZSHRC_PATH="$(zsh_setup::core::config::get zshrc_path)"
    export BACKUP_DIR="$(zsh_setup::core::config::get backup_dir)"
    export STATE_FILE="$(zsh_setup::core::config::get state_file)"
    export LOG_FILE="$(zsh_setup::core::config::get log_file)"
    export INSTALLATION_LOG="$(zsh_setup::core::config::get installation_log)"
    export MAX_PARALLEL_INSTALLS="$(zsh_setup::core::config::get max_parallel_installs)"
    export MAX_RETRIES="$(zsh_setup::core::config::get max_retries)"
    export RETRY_DELAY="$(zsh_setup::core::config::get retry_delay)"
    export RETRY_BACKOFF_MULTIPLIER="$(zsh_setup::core::config::get retry_backoff_multiplier)"
    export ROLLBACK_ON_FAILURE="$(zsh_setup::core::config::get rollback_on_failure)"
    export DEFAULT_THEME="$(zsh_setup::core::config::get default_theme)"
    export VERBOSE="$(zsh_setup::core::config::get verbose)"
    export DRY_RUN="$(zsh_setup::core::config::get dry_run)"
}
