#!/usr/bin/env bash

#==============================================================================
# remove.sh - Remove Command
#
# Removes a specific plugin
#==============================================================================

# Load required modules
zsh_setup::core::bootstrap::load_modules \
    core::config \
    core::logger \
    core::state \
    plugins::registry || exit 1

zsh_setup::commands::remove::execute() {
    local plugin_name="$1"
    
    if [[ -z "$plugin_name" ]]; then
        zsh_setup::core::logger::error "Plugin name required"
        echo "Usage: zsh-setup remove <plugin-name>"
        exit 1
    fi
    
    zsh_setup::core::logger::section "Removing Plugin: $plugin_name"
    
    # Check if plugin is installed
    local installed=0
    while IFS= read -r plugin; do
        [[ "$plugin" == "$plugin_name" ]] && installed=1 && break
    done < <(zsh_setup::state::store::get_installed_plugins 2>/dev/null)
    
    if [[ $installed -eq 0 ]]; then
        zsh_setup::core::logger::warn "Plugin $plugin_name is not installed"
        return 0
    fi
    
    # Remove plugin files
    local ohmyzsh_dir=$(zsh_setup::core::config::get oh_my_zsh_dir)
    local plugin_path="$ohmyzsh_dir/custom/plugins/$plugin_name"
    local theme_path="$ohmyzsh_dir/custom/themes/$plugin_name"
    
    if [[ -d "$plugin_path" ]]; then
        rm -rf "$plugin_path" && zsh_setup::core::logger::info "Removed plugin directory: $plugin_path"
    fi
    
    if [[ -d "$theme_path" ]]; then
        rm -rf "$theme_path" && zsh_setup::core::logger::info "Removed theme directory: $theme_path"
    fi
    
    # Remove from .zshrc
    zsh_setup::commands::remove::_cleanup_zshrc "$plugin_name"
    
    # Remove from state
    # Note: State removal would require JSON manipulation - simplified for now
    zsh_setup::core::logger::success "Plugin $plugin_name removed successfully"
}

zsh_setup::commands::remove::_cleanup_zshrc() {
    local plugin="$1"
    local zshrc_path=$(zsh_setup::core::config::get zshrc_path)
    
    if [[ -f "$zshrc_path" ]]; then
        # Remove plugin from plugins array
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/ $plugin//g" "$zshrc_path"
            sed -i '' "s/$plugin //g" "$zshrc_path"
        else
            sed -i "s/ $plugin//g" "$zshrc_path"
            sed -i "s/$plugin //g" "$zshrc_path"
        fi
        
        zsh_setup::core::logger::info "Removed $plugin from .zshrc"
    fi
}
