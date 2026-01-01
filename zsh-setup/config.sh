#!/usr/bin/env bash

#==============================================================================
# config.sh - Shared Configuration Constants
#
# Centralized configuration for all zsh-setup scripts
#==============================================================================

#------------------------------------------------------------------------------
# Version Information
#------------------------------------------------------------------------------

ZSH_SETUP_VERSION="2.0.0"

#------------------------------------------------------------------------------
# Paths and Directories
#------------------------------------------------------------------------------

# Default directories
OH_MY_ZSH_DIR="$HOME/.oh-my-zsh"
CUSTOM_PLUGINS_DIR="$OH_MY_ZSH_DIR/custom/plugins"
CUSTOM_THEMES_DIR="$OH_MY_ZSH_DIR/custom/themes"
ZSHRC_PATH="$HOME/.zshrc"
BACKUP_DIR="$HOME/.zsh_backup"

# State and log files
STATE_FILE="${ZSH_SETUP_STATE_FILE:-/tmp/zsh_setup_state.json}"
LOG_FILE="${LOG_FILE:-/tmp/zsh_setup.log}"
INSTALLATION_LOG="${INSTALLATION_LOG:-/tmp/zsh_plugin_installation.log}"

#------------------------------------------------------------------------------
# Installation Settings
#------------------------------------------------------------------------------

# Parallel installation settings
MAX_PARALLEL_INSTALLS="${MAX_PARALLEL_INSTALLS:-3}"

# Retry settings
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-2}"
RETRY_BACKOFF_MULTIPLIER="${RETRY_BACKOFF_MULTIPLIER:-2}"

# Rollback settings
ROLLBACK_ON_FAILURE="${ROLLBACK_ON_FAILURE:-true}"

#------------------------------------------------------------------------------
# Theme and Plugin Defaults
#------------------------------------------------------------------------------

DEFAULT_THEME="robbyrussell"
STANDARD_PLUGINS=("git")

#------------------------------------------------------------------------------
# System Paths (macOS)
#------------------------------------------------------------------------------

# Common system paths
SYSTEM_PATHS=(
    "/System/Cryptexes/App/usr/bin"
    "/usr/local/bin"
    "/usr/local/sbin"
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
    "/Library/Apple/usr/bin"
)

# Homebrew paths (detected dynamically)
HOMEBREW_PATHS_APPLE_SILICON=(
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
)

HOMEBREW_PATHS_INTEL=(
    "/usr/local/bin"
    "/usr/local/sbin"
)

#------------------------------------------------------------------------------
# Network Settings
#------------------------------------------------------------------------------

# Connectivity test hosts
CONNECTIVITY_TEST_HOSTS=("8.8.8.8" "1.1.1.1" "github.com")

#------------------------------------------------------------------------------
# URLs
#------------------------------------------------------------------------------

OH_MY_ZSH_INSTALL_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"

# Common plugin repositories
PLUGIN_REPO_ZSH_USERS="https://github.com/zsh-users"
PLUGIN_REPO_ROMKATV="https://github.com/romkatv"
PLUGIN_REPO_NVM="https://github.com/nvm-sh"

#------------------------------------------------------------------------------
# File Patterns
#------------------------------------------------------------------------------

# Files to backup
CONFIG_FILES_TO_BACKUP=(
    ".zshrc"
    ".zshenv"
    ".zprofile"
    ".zlogin"
    ".zlogout"
)

# Files to remove during uninstall
CONFIG_FILES_TO_REMOVE=(
    ".zshrc"
    ".zshrc.pre-oh-my-zsh"
    ".zshenv"
    ".zprofile"
    ".zlogin"
    ".zlogout"
    ".zcompdump"
    ".zsh_history"
    ".p10k.zsh"
    ".fzf.zsh"
    ".zsh_plugins.txt"
)

#------------------------------------------------------------------------------
# Validation Settings
#------------------------------------------------------------------------------

# Maximum dependency resolution depth
MAX_DEPENDENCY_DEPTH=10

# Minimum Zsh version
MIN_ZSH_VERSION="4.0"

#------------------------------------------------------------------------------
# Display Settings
#------------------------------------------------------------------------------

# Progress indicator characters
SPINNER_CHARS='-\|/'

#------------------------------------------------------------------------------
# Export all variables for use in other scripts
#------------------------------------------------------------------------------

export ZSH_SETUP_VERSION
export OH_MY_ZSH_DIR
export CUSTOM_PLUGINS_DIR
export CUSTOM_THEMES_DIR
export ZSHRC_PATH
export BACKUP_DIR
export STATE_FILE
export LOG_FILE
export INSTALLATION_LOG
export MAX_PARALLEL_INSTALLS
export MAX_RETRIES
export RETRY_DELAY
export RETRY_BACKOFF_MULTIPLIER
export ROLLBACK_ON_FAILURE
export DEFAULT_THEME
export MAX_DEPENDENCY_DEPTH
export MIN_ZSH_VERSION
