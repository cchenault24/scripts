#!/usr/bin/env bash

#==============================================================================
# uninstall.sh - Uninstall Command
#
# Removes Zsh setup completely
#==============================================================================

# Load required modules
zsh_setup::core::bootstrap::load_modules \
    core::config \
    core::logger || exit 1

zsh_setup::commands::uninstall::execute() {
    zsh_setup::core::logger::section "Uninstalling Zsh Setup"
    
    read -p "Are you sure you want to uninstall? This will remove Oh My Zsh and all plugins. (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        zsh_setup::core::logger::info "Uninstall cancelled"
        return 0
    fi
    
    # Remove Oh My Zsh
    local ohmyzsh_dir=$(zsh_setup::core::config::get oh_my_zsh_dir)
    if [[ -d "$ohmyzsh_dir" ]]; then
        rm -rf "$ohmyzsh_dir" && zsh_setup::core::logger::info "Removed Oh My Zsh"
    fi
    
    # Remove .zshrc
    local zshrc_path=$(zsh_setup::core::config::get zshrc_path)
    if [[ -f "$zshrc_path" ]]; then
        rm -f "$zshrc_path" && zsh_setup::core::logger::info "Removed .zshrc"
    fi
    
    # Clear state
    zsh_setup::state::store::clear
    
    zsh_setup::core::logger::success "Uninstall complete"
}
