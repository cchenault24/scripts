#!/usr/bin/env bash

#==============================================================================
# dry_run.sh - Interactive Dry-Run Mode
#
# Previews all operations without executing them
#==============================================================================

# Load required utilities
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

if [ -f "$SCRIPT_DIR/logger.sh" ]; then
    source "$SCRIPT_DIR/logger.sh"
fi

if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
fi

# Dry-run mode flag
DRY_RUN_MODE=false

#------------------------------------------------------------------------------
# Dry-Run Functions
#------------------------------------------------------------------------------

# Enable dry-run mode
enable_dry_run() {
    DRY_RUN_MODE=true
    export DRY_RUN_MODE
    log_info "🔍 DRY-RUN MODE ENABLED - No changes will be made"
}

# Check if dry-run mode is enabled
is_dry_run() {
    [[ "$DRY_RUN_MODE" == "true" ]]
}

# Preview file operation
preview_file_operation() {
    local operation="$1"  # create, modify, delete, backup
    local file_path="$2"
    local description="${3:-}"
    
    if is_dry_run; then
        case "$operation" in
            create)
                echo "  [CREATE] $file_path"
                [[ -n "$description" ]] && echo "           → $description"
                ;;
            modify)
                echo "  [MODIFY] $file_path"
                [[ -n "$description" ]] && echo "           → $description"
                ;;
            delete)
                echo "  [DELETE] $file_path"
                [[ -n "$description" ]] && echo "           → $description"
                ;;
            backup)
                echo "  [BACKUP] $file_path"
                [[ -n "$description" ]] && echo "           → $description"
                ;;
        esac
    fi
}

# Preview command execution
preview_command() {
    local description="$1"
    local command="$2"
    
    if is_dry_run; then
        echo "  [COMMAND] $description"
        echo "           → $command"
    fi
}

# Preview plugin installation
preview_plugin_install() {
    local plugin_name="$1"
    local method="$2"
    local url="${3:-}"
    
    if is_dry_run; then
        echo "  [INSTALL] $plugin_name (via $method)"
        [[ -n "$url" ]] && echo "           → $url"
    fi
}

# Show dry-run summary
show_dry_run_summary() {
    if ! is_dry_run; then
        return 0
    fi
    
    echo ""
    log_section "Dry-Run Summary"
    echo ""
    echo "The following operations would be performed:"
    echo ""
    echo "📦 Components to Install:"
    echo "  - Oh My Zsh framework"
    echo "  - Selected plugins (see details above)"
    echo ""
    echo "📝 Configuration Changes:"
    echo "  - Generate new .zshrc file"
    echo "  - Configure theme and plugins"
    echo "  - Set up environment variables"
    echo ""
    echo "💾 Backup Operations:"
    echo "  - Backup existing .zshrc to $BACKUP_DIR"
    echo ""
    echo "🔧 System Changes:"
    echo "  - Change default shell to Zsh (if requested)"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Interactive confirmation for dry-run
confirm_dry_run_operations() {
    if ! is_dry_run; then
        return 0
    fi
    
    echo ""
    read -p "Would you like to proceed with these changes? (y/n): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Dry-run cancelled by user"
        return 1
    fi
    
    return 0
}

# Show what would be changed in .zshrc
preview_zshrc_changes() {
    local current_zshrc="$HOME/.zshrc"
    local temp_zshrc=$(mktemp)
    
    if is_dry_run; then
        log_section "Preview: .zshrc Changes"
        
        if [[ -f "$current_zshrc" ]]; then
            echo ""
            echo "Current .zshrc exists. Here's what would change:"
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "NEW CONFIGURATION PREVIEW:"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            
            # Generate preview (this would call generate_zsh_config in dry-run mode)
            # For now, show a summary
            echo "  - Theme: ${ZSH_THEME:-$DEFAULT_THEME}"
            echo "  - Plugins: (see installation list above)"
            echo "  - Environment variables: PATH, EDITOR, etc."
            echo "  - Custom aliases and functions"
            echo ""
            
            if [[ -f "$current_zshrc" ]]; then
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "CURRENT .zshrc will be backed up to:"
                echo "  $BACKUP_DIR/.zshrc.$(date +%Y%m%d_%H%M%S)"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            fi
        else
            echo "  - New .zshrc file will be created"
        fi
        
        echo ""
    fi
    
    rm -f "$temp_zshrc"
}

# Export functions
export -f enable_dry_run
export -f is_dry_run
export -f preview_file_operation
export -f preview_command
export -f preview_plugin_install
export -f show_dry_run_summary
export -f confirm_dry_run_operations
export -f preview_zshrc_changes
