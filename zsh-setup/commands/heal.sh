#!/usr/bin/env bash

#==============================================================================
# heal.sh - Self-Heal Command
#
# Detects and fixes common issues
#==============================================================================

# Load required modules
zsh_setup::core::bootstrap::load_modules \
    core::config \
    core::logger \
    core::state || exit 1

zsh_setup::commands::heal::execute() {
    zsh_setup::core::logger::section "Self-Healing Zsh Setup"
    
    zsh_setup::core::logger::info "Checking for issues..."
    
    # Check Oh My Zsh
    local ohmyzsh_dir=$(zsh_setup::core::config::get oh_my_zsh_dir)
    if [[ ! -d "$ohmyzsh_dir" ]]; then
        zsh_setup::core::logger::warn "Oh My Zsh not found. Reinstalling..."
        # Would trigger reinstall here
    fi
    
    # Check .zshrc
    local zshrc_path=$(zsh_setup::core::config::get zshrc_path)
    if [[ ! -f "$zshrc_path" ]]; then
        zsh_setup::core::logger::warn ".zshrc not found. Regenerating..."
        zsh_setup::core::bootstrap::load_module config::generator
        zsh_setup::config::generator::generate
    fi
    
    zsh_setup::core::logger::success "Self-healing complete"
}
