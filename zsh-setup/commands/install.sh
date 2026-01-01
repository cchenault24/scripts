#!/usr/bin/env bash

#==============================================================================
# install.sh - Install Command
#
# Handles the main installation workflow
#==============================================================================

# Load required modules
zsh_setup::core::bootstrap::load_modules \
    core::config \
    core::logger \
    core::errors \
    core::state \
    system::validation \
    system::shell \
    system::package_manager || exit 1

# Export config for backward compatibility
zsh_setup::core::config::export

#------------------------------------------------------------------------------
# Command Implementation
#------------------------------------------------------------------------------

zsh_setup::commands::install::execute() {
    local options=("$@")
    local backup_zshrc=true
    local install_ohmyzsh=true
    local install_plugins=true
    local change_shell=true
    local dry_run=false
    
    # Parse options
    for opt in "${options[@]}"; do
        case "$opt" in
            --no-backup)
                backup_zshrc=false
                ;;
            --skip-ohmyzsh)
                install_ohmyzsh=false
                ;;
            --skip-plugins)
                install_plugins=false
                ;;
            --no-shell-change)
                change_shell=false
                ;;
            --dry-run)
                dry_run=true
                zsh_setup::core::config::set dry_run "true"
                ;;
            --quiet)
                zsh_setup::core::config::set verbose "false"
                ;;
        esac
    done
    
    zsh_setup::core::logger::section "Zsh Setup Installation"
    
    if [[ "$dry_run" == "true" ]]; then
        zsh_setup::core::logger::info "🔍 Running in DRY-RUN mode - no changes will be made"
        echo ""
    fi
    
    # Validate configuration
    zsh_setup::core::bootstrap::load_module config::validator
    if ! zsh_setup::config::validator::validate_all "$ZSH_SETUP_ROOT"; then
        zsh_setup::core::logger::error "Configuration validation failed. Please fix errors before proceeding."
        if [[ "$dry_run" != "true" ]]; then
            exit 1
        fi
    fi
    
    # Check system requirements
    zsh_setup::system::validation::check_requirements || exit 1
    
    # Initialize state
    local state_file=$(zsh_setup::state::store::_get_state_file)
    if [[ ! -f "$state_file" ]]; then
        zsh_setup::state::store::init "$ZSH_SETUP_ROOT"
    fi
    
    # Run installation steps
    local steps=()
    
    if [[ "$backup_zshrc" == "true" ]]; then
        steps+=("backup")
    fi
    
    if [[ "$install_ohmyzsh" == "true" ]]; then
        steps+=("ohmyzsh")
    fi
    
    if [[ "$install_plugins" == "true" ]]; then
        steps+=("plugins")
    fi
    
    steps+=("config")  # Always generate config
    
    if [[ "$change_shell" == "true" ]]; then
        steps+=("shell")
    fi
    
    # Execute steps
    for step in "${steps[@]}"; do
        case "$step" in
            backup)
                zsh_setup::commands::install::_backup_config
                ;;
            ohmyzsh)
                zsh_setup::commands::install::_install_ohmyzsh
                ;;
            plugins)
                zsh_setup::commands::install::_install_plugins
                ;;
            config)
                zsh_setup::commands::install::_generate_config
                ;;
            shell)
                zsh_setup::commands::install::_change_shell
                ;;
        esac
    done
    
    # Verify installation
    zsh_setup::commands::install::_verify_installation
    
    # Show summary
    zsh_setup::commands::install::_show_summary
    
    zsh_setup::core::logger::success "Zsh setup completed successfully!"
    echo "====================================================="
    echo "✅ Setup complete! Please restart your terminal or run 'source ~/.zshrc' to apply changes."
    echo "====================================================="
}

# Backup configuration
zsh_setup::commands::install::_backup_config() {
    zsh_setup::core::bootstrap::load_module config::backup
    zsh_setup::config::backup::backup_zshrc
}

# Install Oh My Zsh
zsh_setup::commands::install::_install_ohmyzsh() {
    zsh_setup::core::bootstrap::load_module utils::network
    zsh_setup::core::logger::info "Installing Oh My Zsh..."
    
    local ohmyzsh_dir=$(zsh_setup::core::config::get oh_my_zsh_dir)
    
    if [[ -d "$ohmyzsh_dir" ]]; then
        zsh_setup::core::logger::info "Oh My Zsh is already installed. Skipping installation."
        return 0
    fi
    
    local install_script="/tmp/install_ohmyzsh.sh"
    local install_url=$(zsh_setup::core::config::get oh_my_zsh_install_url "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh")
    
    zsh_setup::core::logger::info "Downloading Oh My Zsh installer..."
    if zsh_setup::utils::network::download_with_retry "$install_url" "$install_script" "Downloading Oh My Zsh installer"; then
        # Modify installer
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' 's/exec zsh -l/exit 0/g' "$install_script"
        else
            sed -i 's/exec zsh -l/exit 0/g' "$install_script"
        fi
        
        # Run installer
        zsh_setup::core::logger::info "Running Oh My Zsh installer..."
        if zsh_setup::core::errors::execute_with_retry "Installing Oh My Zsh" sh "$install_script" --unattended; then
            if [[ -d "$ohmyzsh_dir" ]]; then
                zsh_setup::core::logger::success "Oh My Zsh installed successfully."
                rm -f "$install_script" "${install_script}.bak"
                return 0
            fi
        fi
    fi
    
    zsh_setup::core::logger::error "Oh My Zsh installation failed."
    rm -f "$install_script" "${install_script}.bak"
    return 1
}

# Install plugins
zsh_setup::commands::install::_install_plugins() {
    zsh_setup::core::bootstrap::load_module plugins::manager
    zsh_setup::plugins::manager::install_interactive
}

# Generate configuration
zsh_setup::commands::install::_generate_config() {
    zsh_setup::core::bootstrap::load_module config::generator
    zsh_setup::config::generator::generate
}

# Change shell
zsh_setup::commands::install::_change_shell() {
    zsh_setup::system::shell::change_default
}

# Verify installation
zsh_setup::commands::install::_verify_installation() {
    zsh_setup::core::logger::info "Verifying installation..."
    
    local ohmyzsh_dir=$(zsh_setup::core::config::get oh_my_zsh_dir)
    local zshrc_path=$(zsh_setup::core::config::get zshrc_path)
    
    if [[ -d "$ohmyzsh_dir" ]]; then
        zsh_setup::core::logger::info "✓ Oh My Zsh is correctly installed."
    else
        zsh_setup::core::logger::warn "Oh My Zsh directory not found at $ohmyzsh_dir"
    fi
    
    if [[ -f "$zshrc_path" ]]; then
        zsh_setup::core::logger::info "✓ .zshrc configuration file exists."
    else
        zsh_setup::core::logger::warn ".zshrc configuration file not found."
    fi
}

# Show summary
zsh_setup::commands::install::_show_summary() {
    local installed_count=0
    while IFS= read -r plugin; do
        [[ -n "$plugin" ]] && ((installed_count++))
    done < <(zsh_setup::state::store::get_installed_plugins 2>/dev/null)
    
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║           Zsh Setup Summary            ║"
    echo "╠════════════════════════════════════════╣"
    echo "║ Oh My Zsh      : ✅ Installed          ║"
    echo "║ Plugins        : ✅ $installed_count installed"
    printf "║%*s║\n" $((41 - ${#installed_count})) ""
    echo "╚════════════════════════════════════════╝"
    echo ""
}

# Show help
zsh_setup::commands::install::help() {
    cat <<EOF
zsh-setup install - Install Zsh, Oh My Zsh, and plugins

Usage: zsh-setup install [options]

Options:
  --no-backup         Skip backup of existing .zshrc
  --skip-ohmyzsh      Skip Oh My Zsh installation
  --skip-plugins      Skip plugin installation
  --no-shell-change   Do not change the default shell to Zsh
  --quiet             Suppress verbose output
  --dry-run           Preview changes without executing

Examples:
  zsh-setup install
  zsh-setup install --skip-plugins
  zsh-setup install --dry-run
EOF
}
