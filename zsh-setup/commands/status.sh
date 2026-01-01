#!/usr/bin/env bash

#==============================================================================
# status.sh - Status Command
#
# Shows current installation status
#==============================================================================

# Load required modules
zsh_setup::core::bootstrap::load_modules \
    core::config \
    core::logger \
    core::state || exit 1

zsh_setup::commands::status::execute() {
    zsh_setup::core::logger::section "Zsh Setup Status"
    
    # Check Oh My Zsh
    local ohmyzsh_dir=$(zsh_setup::core::config::get oh_my_zsh_dir)
    if [[ -d "$ohmyzsh_dir" ]]; then
        zsh_setup::core::logger::info "✓ Oh My Zsh: Installed at $ohmyzsh_dir"
    else
        zsh_setup::core::logger::warn "✗ Oh My Zsh: Not installed"
    fi
    
    # Check .zshrc
    local zshrc_path=$(zsh_setup::core::config::get zshrc_path)
    if [[ -f "$zshrc_path" ]]; then
        zsh_setup::core::logger::info "✓ .zshrc: Exists at $zshrc_path"
    else
        zsh_setup::core::logger::warn "✗ .zshrc: Not found"
    fi
    
    # List installed plugins
    echo ""
    echo "Installed Plugins:"
    local count=0
    while IFS= read -r plugin; do
        [[ -n "$plugin" ]] && {
            echo "  - $plugin"
            ((count++))
        }
    done < <(zsh_setup::state::store::get_installed_plugins 2>/dev/null)
    
    if [[ $count -eq 0 ]]; then
        echo "  (none)"
    else
        echo ""
        echo "Total: $count plugins"
    fi
}
