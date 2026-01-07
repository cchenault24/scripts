#!/usr/bin/env bash

#==============================================================================
# installer.sh - Plugin Installation Methods
#
# Provides installation functions for different plugin types
#==============================================================================

# Load dependencies
if [[ -n "${ZSH_SETUP_ROOT:-}" ]]; then
    source "$ZSH_SETUP_ROOT/lib/core/config.sh"
    source "$ZSH_SETUP_ROOT/lib/core/logger.sh"
    source "$ZSH_SETUP_ROOT/lib/core/errors.sh"
    source "$ZSH_SETUP_ROOT/lib/state/store.sh"
    source "$ZSH_SETUP_ROOT/lib/utils/network.sh"
    source "$ZSH_SETUP_ROOT/lib/system/package_manager.sh"
fi

#------------------------------------------------------------------------------
# Installation Methods
#------------------------------------------------------------------------------

# Install git-based plugin
zsh_setup::plugins::installer::install_git() {
    local plugin_name="$1"
    local plugin_url="$2"
    local plugin_type="${3:-plugin}"
    
    local ohmyzsh_dir=$(zsh_setup::core::config::get oh_my_zsh_dir)
    local plugins_dir="$ohmyzsh_dir/custom/plugins"
    local themes_dir="$ohmyzsh_dir/custom/themes"
    
    local plugin_path
    if [[ "$plugin_type" == "theme" ]]; then
        plugin_path="$themes_dir/$plugin_name"
    else
        plugin_path="$plugins_dir/$plugin_name"
    fi
    
    zsh_setup::core::logger::info "Installing ${plugin_type}: $plugin_name"
    
    # Set default URL if not provided
    if [[ -z "$plugin_url" ]]; then
        case "$plugin_name" in
            powerlevel10k)
                plugin_url="https://github.com/romkatv/powerlevel10k.git"
                ;;
            nvm)
                plugin_url="https://github.com/nvm-sh/nvm.git"
                ;;
            zsh-defer)
                plugin_url="https://github.com/romkatv/zsh-defer.git"
                ;;
            *)
                plugin_url="https://github.com/zsh-users/$plugin_name.git"
                ;;
        esac
    fi
    
    # Create directory structure
    mkdir -p "$(dirname "$plugin_path")"
    
    # Check if plugin already exists
    if [[ -d "$plugin_path" ]]; then
        if [[ -d "$plugin_path/.git" ]]; then
            # Already a git repository - update it instead
            zsh_setup::core::logger::info "${plugin_type} $plugin_name already installed. Updating..."
            if cd "$plugin_path" && git pull --quiet 2>/dev/null; then
                local version=$(cd "$plugin_path" && git rev-parse HEAD 2>/dev/null || echo "unknown")
                zsh_setup::state::store::add_plugin "$plugin_name" "git" "$version"
                zsh_setup::core::logger::success "${plugin_type} $plugin_name updated successfully"
                return 0
            else
                zsh_setup::core::logger::warn "Failed to update ${plugin_type} $plugin_name, but it's already installed"
                # Still consider it successful since it's installed
                local version=$(cd "$plugin_path" && git rev-parse HEAD 2>/dev/null || echo "unknown")
                zsh_setup::state::store::add_plugin "$plugin_name" "git" "$version"
                return 0
            fi
        else
            # Directory exists but is not a git repo - backup and remove
            zsh_setup::core::logger::warn "Directory $plugin_path exists but is not a git repository. Backing up and removing..."
            local backup_path="${plugin_path}.backup.$(date +%s)"
            mv "$plugin_path" "$backup_path" 2>/dev/null || rm -rf "$plugin_path"
        fi
    fi
    
    # Clone repository
    if zsh_setup::utils::network::git_clone_with_retry "$plugin_url" "$plugin_path" "Installing ${plugin_type}: $plugin_name"; then
        # Get version
        local version="unknown"
        if [[ -d "$plugin_path/.git" ]]; then
            version=$(cd "$plugin_path" && git rev-parse HEAD 2>/dev/null || echo "unknown")
        fi
        
        # Update state
        zsh_setup::state::store::add_plugin "$plugin_name" "git" "$version"
        
        # Handle powerlevel10k theme symlink
        if [[ "$plugin_name" == "powerlevel10k" && "$plugin_type" == "plugin" ]]; then
            local theme_path="$themes_dir/$plugin_name"
            mkdir -p "$(dirname "$theme_path")"
            [[ ! -e "$theme_path" ]] && ln -sf "$plugin_path" "$theme_path"
        fi
        
        zsh_setup::core::logger::success "${plugin_type} $plugin_name installed successfully"
        return 0
    else
        zsh_setup::state::store::add_failed_plugin "$plugin_name" "git" "Clone failed"
        zsh_setup::core::logger::error "Failed to install ${plugin_type}: $plugin_name"
        return 1
    fi
}

# Install Homebrew package
zsh_setup::plugins::installer::install_brew() {
    local plugin_name="$1"
    local package_name="${2:-$plugin_name}"
    
    # Use package manager integration
    local mapped_package=$(zsh_setup::system::package_manager::map_plugin_to_package "$package_name")
    
    if zsh_setup::system::package_manager::install "$mapped_package" "Installing $plugin_name via Homebrew"; then
        local version=$(zsh_setup::system::package_manager::get_version "$mapped_package")
        zsh_setup::state::store::add_plugin "$plugin_name" "brew" "$version"
        zsh_setup::core::logger::success "Successfully installed $plugin_name via Homebrew"
        return 0
    else
        zsh_setup::state::store::add_failed_plugin "$plugin_name" "brew" "Installation failed"
        zsh_setup::core::logger::error "Failed to install plugin: $plugin_name"
        return 1
    fi
}

# Install Oh My Zsh built-in plugin
zsh_setup::plugins::installer::install_omz() {
    local plugin_name="$1"
    local ohmyzsh_dir=$(zsh_setup::core::config::get oh_my_zsh_dir)
    
    if [[ -d "$ohmyzsh_dir/plugins/$plugin_name" ]]; then
        zsh_setup::state::store::add_plugin "$plugin_name" "omz" "built-in"
        zsh_setup::core::logger::info "Plugin $plugin_name is available in Oh My Zsh."
        return 0
    else
        zsh_setup::state::store::add_failed_plugin "$plugin_name" "omz" "Plugin not found"
        zsh_setup::core::logger::error "Plugin $plugin_name is not available in Oh My Zsh."
        return 1
    fi
}

# Install npm package
zsh_setup::plugins::installer::install_npm() {
    local plugin_name="$1"
    local package_name="${2:-$plugin_name}"
    local global="${3:-global}"
    
    if ! command -v npm &>/dev/null; then
        zsh_setup::core::logger::error "npm is not installed. Cannot install $plugin_name."
        zsh_setup::state::store::add_failed_plugin "$plugin_name" "npm" "npm not installed"
        return 1
    fi
    
    local install_cmd
    if [[ "$global" == "global" ]]; then
        install_cmd="npm install -g $package_name"
    else
        install_cmd="npm install $package_name"
    fi
    
    if zsh_setup::core::errors::execute_with_retry "Installing $plugin_name via npm" $install_cmd; then
        zsh_setup::state::store::add_plugin "$plugin_name" "npm" "unknown"
        zsh_setup::core::logger::success "Plugin $plugin_name installed successfully."
        return 0
    else
        zsh_setup::state::store::add_failed_plugin "$plugin_name" "npm" "npm install failed"
        zsh_setup::core::logger::error "Failed to install plugin: $plugin_name"
        return 1
    fi
}

# Install plugin by type
zsh_setup::plugins::installer::install() {
    local plugin_name="$1"
    local plugin_type="$2"
    local plugin_url="$3"
    
    case "$plugin_type" in
        git)
            zsh_setup::plugins::installer::install_git "$plugin_name" "$plugin_url"
            ;;
        brew)
            zsh_setup::plugins::installer::install_brew "$plugin_name" "$plugin_url"
            ;;
        omz)
            zsh_setup::plugins::installer::install_omz "$plugin_name"
            ;;
        npm)
            zsh_setup::plugins::installer::install_npm "$plugin_name" "$plugin_url"
            ;;
        *)
            zsh_setup::core::logger::error "Unknown plugin type: $plugin_type"
            return 1
            ;;
    esac
}

# Check if plugin is already installed
zsh_setup::plugins::installer::is_installed() {
    local plugin_name="$1"
    local ohmyzsh_dir=$(zsh_setup::core::config::get oh_my_zsh_dir)
    local plugins_dir="$ohmyzsh_dir/custom/plugins"
    local themes_dir="$ohmyzsh_dir/custom/themes"
    
    [[ -d "$plugins_dir/$plugin_name" ]] || [[ -d "$themes_dir/$plugin_name" ]] || \
    [[ -d "$ohmyzsh_dir/plugins/$plugin_name" ]]
}

