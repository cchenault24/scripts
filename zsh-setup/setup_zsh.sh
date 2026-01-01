#!/usr/bin/env bash

#==============================================================================
# setup_zsh.sh - Main entry point for Zsh setup
#
# This script orchestrates the entire Zsh setup process:
# - Backing up existing configuration
# - Installing Oh My Zsh
# - Installing plugins
# - Generating a new .zshrc
# - Changing the default shell
# - Verifying the installation
#==============================================================================

set -e # Exit immediately if a command exits with a non-zero status

#------------------------------------------------------------------------------
# Global Variables
#------------------------------------------------------------------------------

# Script location and logging setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGS_DIR="/tmp"
LOG_FILE="$LOGS_DIR/zsh_setup.log"

# Default configuration flags
BACKUP_ZSHRC=true    # Whether to back up existing .zshrc
INSTALL_OHMYZSH=true # Whether to install Oh My Zsh
INSTALL_PLUGINS=true # Whether to install plugins
CHANGE_SHELL=true    # Whether to change default shell to Zsh
VERBOSE=true         # Whether to display verbose output
DRY_RUN=false        # Whether to run in dry-run mode

# Initialize INSTALLED_PLUGINS array
INSTALLED_PLUGINS=()

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------

# Print usage information for command-line help
print_usage() {
    cat <<EOF
Zsh Setup Script

Usage: $0 [options]

Options:
  --no-backup         Skip backup of existing .zshrc
  --skip-ohmyzsh      Skip Oh My Zsh installation
  --skip-plugins      Skip plugin installation
  --no-shell-change   Do not change the default shell to Zsh
  --quiet             Suppress verbose output
  --dry-run           Preview changes without executing (interactive)
  --update            Update installed plugins
  --remove <plugin>   Remove a specific plugin
  --monitor           Run monitoring and diagnostics
  --self-heal         Run self-healing to fix issues
  --help              Display this help message

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        --no-backup)
            BACKUP_ZSHRC=false
            ;;
        --skip-ohmyzsh)
            INSTALL_OHMYZSH=false
            ;;
        --skip-plugins)
            INSTALL_PLUGINS=false
            ;;
        --no-shell-change)
            CHANGE_SHELL=false
            ;;
        --quiet)
            VERBOSE=false
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        --update)
            if [ -f "$SCRIPT_DIR/update_plugins.sh" ]; then
                source "$SCRIPT_DIR/update_plugins.sh"
                main
                exit $?
            else
                log_error "update_plugins.sh not found"
                exit 1
            fi
            ;;
        --remove)
            shift
            if [ -z "$1" ]; then
                log_error "--remove requires a plugin name"
                print_usage
                exit 1
            fi
            if [ -f "$SCRIPT_DIR/remove_plugins.sh" ]; then
                source "$SCRIPT_DIR/remove_plugins.sh"
                main "$1"
                exit $?
            else
                log_error "remove_plugins.sh not found"
                exit 1
            fi
            ;;
        --monitor)
            if [ -f "$SCRIPT_DIR/monitor.sh" ]; then
                source "$SCRIPT_DIR/monitor.sh"
                main "${2:-all}"
                exit $?
            else
                log_error "monitor.sh not found"
                exit 1
            fi
            ;;
        --self-heal)
            if [ -f "$SCRIPT_DIR/self_heal.sh" ]; then
                source "$SCRIPT_DIR/self_heal.sh"
                main "${2:-false}"
                exit $?
            else
                log_error "self_heal.sh not found"
                exit 1
            fi
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit 1
            ;;
        esac
        shift
    done
}

#------------------------------------------------------------------------------
# Setup Process Functions
#------------------------------------------------------------------------------

# Run a setup step if the corresponding flag is enabled
run_step() {
    local description="$1"
    local function_name="$2"
    local enabled="$3"

    if $enabled; then
        log_message "Running step: $description"
        $function_name
    else
        log_message "Skipping step: $description"
    fi
}

# Run a plugin installation step
install_plugins_step() {
    log_message "Installing Zsh plugins..."

    # Source the install_plugins.sh script
    source "$SCRIPT_DIR/install_plugins.sh"

    # Run the main function from install_plugins.sh
    main

    # Sync arrays from state and log installed plugins
    if command -v sync_arrays_from_state &>/dev/null; then
        sync_arrays_from_state
    fi
    
    if [[ -n "${INSTALLED_PLUGINS[*]}" ]]; then
        log_message "Plugins installation complete. Installed plugins: ${#INSTALLED_PLUGINS[@]}"
    else
        log_message "No plugins were installed."
    fi
}

# Generate Zsh configuration step
generate_zshrc_step() {
    log_message "Generating new .zshrc configuration..."

    # Sync arrays from state file
    if command -v sync_arrays_from_state &>/dev/null; then
        sync_arrays_from_state
    fi
    
    # Export INSTALLED_PLUGINS for backward compatibility with generate_zshrc.sh
    export INSTALLED_PLUGINS

    # Source the generate_zshrc.sh script and call the generate function
    source "$SCRIPT_DIR/generate_zshrc.sh"
    generate_zsh_config
}

#------------------------------------------------------------------------------
# Main Setup Process
#------------------------------------------------------------------------------

# Main function that orchestrates the entire setup process
main() {
    log_section "Zsh Setup"
    
    if is_dry_run; then
        log_info "🔍 Running in DRY-RUN mode - no changes will be made"
        echo ""
    fi

    # Validate configuration files
    if [ -f "$SCRIPT_DIR/validate_config.sh" ]; then
        if ! validate_all_configs "$SCRIPT_DIR"; then
            log_error "Configuration validation failed. Please fix errors before proceeding."
            if ! is_dry_run; then
                exit 1
            fi
        fi
    fi

    # Check system requirements
    check_system_requirements

    # Define setup steps as an array of description:function:flag triplets
    local setup_steps=(
        "Backing up existing configuration:backup_zshrc:$BACKUP_ZSHRC"
        "Installing Oh My Zsh:install_oh_my_zsh:$INSTALL_OHMYZSH"
        "Installing plugins:install_plugins_step:$INSTALL_PLUGINS"
        "Generating Zsh configuration:generate_zshrc_step:true"
        "Changing default shell:change_default_shell:$CHANGE_SHELL"
    )

    # Run each step if its flag is enabled
    for step in "${setup_steps[@]}"; do
        IFS=':' read -r description function flag <<<"$step"
        run_step "$description" "$function" "$flag"
    done

    # Show dry-run summary and confirmation
    if is_dry_run; then
        show_dry_run_summary
        preview_zshrc_changes
        
        if ! confirm_dry_run_operations; then
            log_info "Dry-run cancelled. No changes made."
            exit 0
        fi
        
        log_info "Dry-run confirmed. Exiting (use without --dry-run to apply changes)."
        exit 0
    fi

    # Verify installation
    log_message "Verifying installation..."
    verify_installation

    # Display summary
    display_summary

    log_success "Zsh setup completed successfully!"
    echo "====================================================="
    echo "✅ Setup complete! Please restart your terminal or run 'source ~/.zshrc' to apply changes."
    echo "====================================================="
}

#------------------------------------------------------------------------------
# Script Entry Point
#------------------------------------------------------------------------------

# Source required helper scripts
if [ -f "$SCRIPT_DIR/setup_core.sh" ]; then
    source "$SCRIPT_DIR/setup_core.sh"
else
    echo "Error: Required script setup_core.sh not found."
    exit 1
fi

# Load config first
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
fi

# Load logger
if [ -f "$SCRIPT_DIR/logger.sh" ]; then
    source "$SCRIPT_DIR/logger.sh"
fi

# Source error handler and state manager
if [ -f "$SCRIPT_DIR/error_handler.sh" ]; then
    source "$SCRIPT_DIR/error_handler.sh"
    # Set up error trap
    setup_error_trap "Zsh setup script"
fi

if [ -f "$SCRIPT_DIR/state_manager.sh" ]; then
    source "$SCRIPT_DIR/state_manager.sh"
    # Initialize state
    init_state "$SCRIPT_DIR"
fi

# Load dry-run utilities
if [ -f "$SCRIPT_DIR/dry_run.sh" ]; then
    source "$SCRIPT_DIR/dry_run.sh"
    # Enable dry-run if requested
    if [[ "$DRY_RUN" == "true" ]]; then
        enable_dry_run
    fi
fi

# Load config validation
if [ -f "$SCRIPT_DIR/validate_config.sh" ]; then
    source "$SCRIPT_DIR/validate_config.sh"
fi

# Source installation functions
if [ -f "$SCRIPT_DIR/install_functions.sh" ]; then
    source "$SCRIPT_DIR/install_functions.sh"
else
    echo "Error: Required script install_functions.sh not found."
    exit 1
fi

# Initialize log file
mkdir -p "$LOGS_DIR"
echo "=== Zsh Setup Log - $(date) ===" >"$LOG_FILE"
echo "System: $(uname -a)" >>"$LOG_FILE"
echo "User: $(whoami)" >>"$LOG_FILE"
echo "Script version: 1.0.0" >>"$LOG_FILE"
echo "==================================" >>"$LOG_FILE"
log_message "Log file initialized at $LOG_FILE"

# Parse command line arguments
parse_arguments "$@"

# Run main function
main
