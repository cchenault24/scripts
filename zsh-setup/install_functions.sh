#!/usr/bin/env bash

#==============================================================================
# install_functions.sh - Helper functions for installing plugins and packages
#
# This script provides utilities for managing Zsh plugins through various
# installation methods (git, Homebrew, npm, Oh My Zsh).
#==============================================================================

#------------------------------------------------------------------------------
# Global Variables
#------------------------------------------------------------------------------

# Configuration files
PLUGINS_CONF="${SCRIPT_DIR:-$(dirname "$0")}/plugins.conf"
DEPENDENCIES_CONF="${SCRIPT_DIR:-$(dirname "$0")}/plugin_dependencies.conf"

# Arrays for tracking installation results
INSTALLED_PLUGINS=()
FAILED_PLUGINS=()

# Default log file
LOG_FILE="${LOG_FILE:-/tmp/zsh_setup.log}"

#------------------------------------------------------------------------------
# Utility Functions
#------------------------------------------------------------------------------

# Determine which selection tool to use based on available commands
get_selection_tool() {
    command -v gum &>/dev/null && echo "gum" && return
    command -v fzf &>/dev/null && echo "fzf" && return
    echo "fallback"
}

# Execute a command silently with a spinner animation to show progress
install_silently_with_spinner() {
    local name="$1"
    local check_cmd="$2"
    local install_cmd="$3"
    local log_file="/tmp/install_${name// /_}.log" # Replace spaces with underscores

    echo -n "⏳ Installing $name... "

    # Check if already installed
    if eval "$check_cmd" &>/dev/null; then
        echo "✅ Already installed."
        return 0
    fi

    # Create log file directory
    mkdir -p "$(dirname "$log_file")" 2>/dev/null

    # Run installation in background
    eval "$install_cmd" &>"$log_file" &
    local pid=$!

    # Display spinner while installation is running
    local spin='-\|/'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(((i + 1) % 4))
        echo -ne "\r⏳ Installing $name... ${spin:$i:1} "
        sleep 0.2
    done

    # Check installation result
    wait "$pid"
    local exit_status=$?

    if [ "$exit_status" -eq 0 ]; then
        echo -e "\r✅ $name installed successfully."
    else
        echo -e "\r❌ Installation of $name failed. Check log: $log_file"
    fi

    return "$exit_status"
}

# Check if element exists in array
contains_element() {
    local element="$1"
    shift
    for e in "$@"; do
        [[ "$e" == "$element" ]] && return 0
    done
    return 1
}

# Retrieve dependencies for a given plugin from config file
get_plugin_dependencies() {
    local plugin_name="$1"

    # Check if dependency file exists
    [ ! -f "$DEPENDENCIES_CONF" ] && return 0

    # Read dependencies from file
    while IFS='=' read -r name deps; do
        [ "$name" = "$plugin_name" ] && echo "$deps" | tr ',' ' ' && return 0
    done <"$DEPENDENCIES_CONF"

    echo "" # Return empty string if no dependencies found
}

#------------------------------------------------------------------------------
# Plugin Configuration Functions
#------------------------------------------------------------------------------

# Parse the plugins configuration file
parse_plugins_config() {
    local plugins=()

    # Check if config file exists
    if [ ! -f "$PLUGINS_CONF" ]; then
        log_error "Plugins configuration file not found: $PLUGINS_CONF"
        return 1
    fi

    # Read plugins from file
    while IFS='|' read -r name type url description; do
        # Skip comments and empty lines
        [[ "$name" =~ ^# ]] || [ -z "$name" ] && continue
        plugins+=("$name|$type|$url|$description")
    done <"$PLUGINS_CONF"

    echo "${plugins[@]}"
}

# Display and select plugins using the best available selection tool
select_plugins() {
    local plugins=("$@")
    local selected_plugins=()
    local selection_tool=$(get_selection_tool)

    case "$selection_tool" in
    "gum")
        # Use gum for interactive selection
        local plugin_names=()
        for plugin in "${plugins[@]}"; do
            IFS='|' read -r name _ _ description <<<"$plugin"
            plugin_names+=("$name - $description")
        done

        # Display plugin selection with gum
        local selected_indices=$(gum choose --no-limit "${plugin_names[@]}" | cut -d ' ' -f1)

        # Process selected plugins
        for index in $selected_indices; do
            selected_plugins+=("${plugins[$index]}")
        done
        ;;
    "fzf")
        # Use fzf for interactive selection
        local plugin_names=()
        for plugin in "${plugins[@]}"; do
            IFS='|' read -r name _ _ description <<<"$plugin"
            plugin_names+=("$name - $description")
        done

        # Display plugin selection with fzf
        local selected_names=$(printf '%s\n' "${plugin_names[@]}" | fzf --multi)

        # Process selected plugins
        for name in $selected_names; do
            local plugin_name=$(echo "$name" | cut -d ' ' -f1)
            for plugin in "${plugins[@]}"; do
                IFS='|' read -r p_name _ _ _ <<<"$plugin"
                if [ "$p_name" = "$plugin_name" ]; then
                    selected_plugins+=("$plugin")
                    break
                fi
            done
        done
        ;;
    "fallback")
        # Use simple text-based interface
        echo "Available plugins:"
        local i=1
        for plugin in "${plugins[@]}"; do
            IFS='|' read -r name _ _ description <<<"$plugin"
            echo "$i) $name - $description"
            i=$((i + 1))
        done

        echo "Enter the numbers of plugins to install (separated by spaces):"
        read -r selections

        # Process selected plugins
        for selection in $selections; do
            if [[ "$selection" =~ ^[0-9]+$ ]] &&
                [ "$selection" -le "${#plugins[@]}" ] &&
                [ "$selection" -gt 0 ]; then
                selected_plugins+=("${plugins[$((selection - 1))]}")
            fi
        done
        ;;
    esac

    echo "${selected_plugins[@]}"
}

#------------------------------------------------------------------------------
# Plugin Installation Functions
#------------------------------------------------------------------------------

# Install a plugin from git repository
install_git_plugin() {
    local plugin_name="$1"
    local plugin_url="$2"
    local plugin_type="${3:-plugin}" # Default to "plugin" if not specified

    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null

    # Determine installation path
    local plugin_path
    if [ "$plugin_type" = "theme" ]; then
        plugin_path="$HOME/.oh-my-zsh/custom/themes/$plugin_name"
    else
        plugin_path="$HOME/.oh-my-zsh/custom/plugins/$plugin_name"
    fi

    log_message "Installing ${plugin_type}: $plugin_name"

    # Set default URL if not provided
    if [ -z "$plugin_url" ]; then
        case "$plugin_name" in
        "powerlevel10k")
            plugin_url="https://github.com/romkatv/powerlevel10k.git"
            ;;
        "nvm")
            plugin_url="https://github.com/nvm-sh/nvm.git"
            ;;
        "zsh-defer")
            plugin_url="https://github.com/romkatv/zsh-defer.git"
            ;;
        *)
            # Default plugin locations
            plugin_url="https://github.com/zsh-users/$plugin_name.git"
            ;;
        esac
    fi

    # Create directory structure
    mkdir -p "$(dirname "$plugin_path")"

    # Clone the repository
    log_message "Cloning from: $plugin_url to $plugin_path"
    if git clone --depth=1 "$plugin_url" "$plugin_path" 2>>"$LOG_FILE"; then
        log_message "✅ ${plugin_type} $plugin_name installed successfully"
        INSTALLED_PLUGINS+=("$plugin_name")

        # For powerlevel10k theme, create symlink if needed
        if [ "$plugin_name" = "powerlevel10k" ] && [ "$plugin_type" = "plugin" ]; then
            log_message "Creating symlink for powerlevel10k theme"
            local theme_path="$HOME/.oh-my-zsh/custom/themes/$plugin_name"
            mkdir -p "$(dirname "$theme_path")"
            [ ! -e "$theme_path" ] && ln -sf "$plugin_path" "$theme_path"
        fi

        return 0
    else
        log_error "❌ Failed to install ${plugin_type}: $plugin_name from $plugin_url"
        FAILED_PLUGINS+=("$plugin_name")
        return 1
    fi
}

# Install a plugin via Homebrew
install_brew_plugin() {
    local plugin_name="$1"
    local package_name="$2"

    log_message "📦 Installing plugin: $plugin_name via Homebrew..."

    # Check if Homebrew is installed
    if ! command -v brew &>/dev/null; then
        log_error "❌ Homebrew is not installed. Cannot install $plugin_name."
        FAILED_PLUGINS+=("$plugin_name")
        return 1
    fi

    # Handle deprecated packages
    if [ "$package_name" = "exa" ]; then
        package_name="eza" # Use eza instead (exa is deprecated)
    fi

    # Check if already installed
    if brew list --formula 2>/dev/null | grep -qx "$package_name"; then
        log_message "✅ $plugin_name is already installed."
        INSTALLED_PLUGINS+=("$plugin_name")
        return 0
    fi

    # Install the package
    if brew install "$package_name"; then
        log_message "✅ Successfully installed $plugin_name via Homebrew."
        INSTALLED_PLUGINS+=("$plugin_name")
        return 0
    else
        log_error "❌ Failed to install plugin: $plugin_name"
        FAILED_PLUGINS+=("$plugin_name")
        return 1
    fi
}

# Install a plugin from Oh My Zsh
install_omz_plugin() {
    local plugin_name="$1"

    log_message "Adding Oh My Zsh plugin: $plugin_name"

    # Check if the plugin exists in Oh My Zsh
    if [ -d "$HOME/.oh-my-zsh/plugins/$plugin_name" ]; then
        log_message "Plugin $plugin_name is available in Oh My Zsh."
        INSTALLED_PLUGINS+=("$plugin_name")
        return 0
    else
        log_error "Plugin $plugin_name is not available in Oh My Zsh."
        FAILED_PLUGINS+=("$plugin_name")
        return 1
    fi
}

# Install a plugin from npm
install_npm_plugin() {
    local plugin_name="$1"
    local package_name="$2"
    local global_flag="${3:-local}" # Default to local if not specified

    log_message "Installing plugin: $plugin_name via npm"

    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null

    # Check if npm is installed
    if ! command -v npm &>/dev/null; then
        log_error "npm is not installed. Cannot install $plugin_name."
        FAILED_PLUGINS+=("$plugin_name")
        return 1
    fi

    # Install with appropriate scope
    local install_cmd
    if [ "$global_flag" = "global" ]; then
        install_cmd="npm install -g $package_name"
    else
        install_cmd="npm install $package_name"
    fi

    if $install_cmd 2>>"$LOG_FILE"; then
        log_message "✅ Plugin $plugin_name installed successfully."
        INSTALLED_PLUGINS+=("$plugin_name")
        return 0
    else
        log_error "❌ Failed to install plugin: $plugin_name"
        FAILED_PLUGINS+=("$plugin_name")
        return 1
    fi
}

# Dispatch plugin installation based on type
install_plugin() {
    local plugin="$1"
    IFS='|' read -r name type url _ <<<"$plugin"

    case "$type" in
    "git")
        # For powerlevel10k, install as a theme
        if [ "$name" = "powerlevel10k" ]; then
            install_git_plugin "$name" "$url" "theme"
        else
            install_git_plugin "$name" "$url" "plugin"
        fi
        ;;
    "brew")
        install_brew_plugin "$name" "$url"
        ;;
    "omz")
        install_omz_plugin "$name"
        ;;
    "npm")
        install_npm_plugin "$name" "$url" "global"
        ;;
    *)
        log_error "Unknown plugin type: $type"
        return 1
        ;;
    esac
}

#------------------------------------------------------------------------------
# Plugin Verification Functions
#------------------------------------------------------------------------------

# Verify successful installation of all plugins
verify_plugins() {
    log_message "Verifying plugin installation..."

    # Check if INSTALLED_PLUGINS is defined
    if [ ${#INSTALLED_PLUGINS[@]} -eq 0 ]; then
        log_message "No plugins to verify."
        return 0
    fi

    local issues=0

    for plugin in "${INSTALLED_PLUGINS[@]}"; do
        # Extract plugin name if it contains a description
        local plugin_name="${plugin%% - *}"

        # Handle special cases
        case "$plugin_name" in
        "oh-my-zsh")
            _verify_oh_my_zsh || ((issues++))
            ;;
        "zsh")
            _verify_zsh || ((issues++))
            ;;
        "powerlevel10k")
            _verify_powerlevel10k || ((issues++))
            ;;
        "autojump" | "fzf" | "zoxide" | "bat" | "exa" | "fd" | "ripgrep" | "gum")
            _verify_brew_package "$plugin_name" || ((issues++))
            ;;
        *)
            _verify_standard_plugin "$plugin_name" || ((issues++))
            ;;
        esac
    done

    if [ $issues -eq 0 ]; then
        log_message "✅ Plugin verification passed. All plugins appear to be installed correctly."
        return 0
    else
        log_message "⚠️ Plugin verification completed with $issues issues."
        log_message "You can still proceed with Zsh, but some plugins might not work as expected."
        return 1
    fi
}

# Verify Oh My Zsh installation
_verify_oh_my_zsh() {
    if [ -d "$HOME/.oh-my-zsh" ]; then
        log_message "Oh My Zsh is correctly installed."
        return 0
    else
        log_error "Oh My Zsh does not appear to be installed correctly."
        return 1
    fi
}

# Verify Zsh installation
_verify_zsh() {
    if command -v zsh &>/dev/null; then
        log_message "Zsh is correctly installed: $(zsh --version 2>/dev/null || echo 'version unknown')"
        return 0
    else
        log_error "Zsh does not appear to be installed correctly."
        return 1
    fi
}

# Verify Powerlevel10k installation
_verify_powerlevel10k() {
    log_message "Checking Powerlevel10k installation..."

    # Possible locations for powerlevel10k
    local p10k_locations=(
        "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
        "$HOME/.oh-my-zsh/themes/powerlevel10k"
        "$HOME/.oh-my-zsh/custom/plugins/powerlevel10k"
        "$HOME/.zsh/themes/powerlevel10k"
        "$HOME/.zsh_plugins/powerlevel10k"
    )

    # Check all possible locations
    for location in "${p10k_locations[@]}"; do
        if [ -d "$location" ]; then
            log_message "✅ Powerlevel10k found at: $location"
            return 0
        fi
    done

    # If not found in themes but exists in plugins, create symlink
    if [ -d "$HOME/.oh-my-zsh/custom/plugins/powerlevel10k" ]; then
        mkdir -p "$HOME/.oh-my-zsh/custom/themes"
        ln -sf "$HOME/.oh-my-zsh/custom/plugins/powerlevel10k" "$HOME/.oh-my-zsh/custom/themes/"
        log_message "Created symlink for powerlevel10k theme."
        return 0
    else
        log_error "❌ Could not find powerlevel10k in any standard location."
        return 1
    fi
}

# Verify Homebrew package installation
_verify_brew_package() {
    local package_name="$1"

    # Handle special case for exa -> eza replacement
    local check_name="$package_name"
    [ "$package_name" = "exa" ] && check_name="eza"

    if brew list --formula 2>/dev/null | grep -q "^$check_name$"; then
        log_message "✅ Brew package $package_name is correctly installed."
        return 0
    else
        log_error "❌ Brew package $package_name does not appear to be installed correctly."
        return 1
    fi
}

# Verify standard plugin installation
_verify_standard_plugin() {
    local plugin_name="$1"

    # Check various possible locations
    if [ -d "$HOME/.oh-my-zsh/custom/plugins/$plugin_name" ]; then
        log_message "✅ Plugin $plugin_name found in custom plugins directory."
        return 0
    elif [ -d "$HOME/.oh-my-zsh/plugins/$plugin_name" ]; then
        log_message "✅ Plugin $plugin_name found in built-in Oh My Zsh plugins directory."
        return 0
    elif [ -d "$HOME/.zsh_plugins/$plugin_name" ]; then
        log_message "✅ Plugin $plugin_name found in .zsh_plugins directory."
        return 0
    else
        log_error "❌ Plugin $plugin_name does not appear to be installed correctly."
        return 1
    fi
}
