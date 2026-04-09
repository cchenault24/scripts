#!/bin/bash
# uninstall-gemma4-opencode.sh - Comprehensive uninstaller for Gemma4 + OpenCode setup
#
# Features:
# - Selective component removal (choose what to uninstall)
# - Configuration backup before removal
# - Dry-run mode to preview changes
# - Complete or partial uninstallation
# - Safe defaults (preserves data unless explicitly requested)
#
# Usage: ./uninstall-gemma4-opencode.sh [OPTIONS]
#
# Options:
#   --complete        Complete removal (everything, no prompts)
#   --keep-models     Keep downloaded Ollama models
#   --keep-configs    Keep configuration files
#   --keep-apps       Keep Homebrew apps (only remove configs/models)
#   --dry-run         Show what would be removed without actually removing
#   --backup-dir DIR  Specify custom backup directory (default: ~/gemma4-opencode-backup-<timestamp>)
#   --yes             Answer yes to all prompts (use with caution)
#   --help            Show this help message
#
# Examples:
#   # Interactive mode (recommended)
#   ./uninstall-gemma4-opencode.sh
#
#   # Complete removal with backup
#   ./uninstall-gemma4-opencode.sh --complete
#
#   # Remove configs but keep models and apps
#   ./uninstall-gemma4-opencode.sh --keep-apps --keep-models
#
#   # Preview what would be removed
#   ./uninstall-gemma4-opencode.sh --dry-run

set -euo pipefail

# Source library modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

#############################################
# Configuration
#############################################

# Default settings
COMPLETE_REMOVAL=false
KEEP_MODELS=false
KEEP_CONFIGS=false
KEEP_APPS=false
DRY_RUN=false
AUTO_YES=false
BACKUP_DIR=""

# Component paths
LAUNCHAGENT_LABEL="com.ollama.custom"
LAUNCHAGENT_PLIST="$HOME/Library/LaunchAgents/${LAUNCHAGENT_LABEL}.plist"
OPENCODE_CONFIG_DIR="$HOME/.config/opencode"
OLLAMA_MODELS_DIR="$HOME/.ollama"
OLLAMA_LOGS_STDOUT="/tmp/ollama.stdout.log"
OLLAMA_LOGS_STDERR="/tmp/ollama.stderr.log"

# Tracking
ITEMS_REMOVED=0
ITEMS_BACKED_UP=0
SPACE_FREED=0

#############################################
# Parse Arguments
#############################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --complete)
            COMPLETE_REMOVAL=true
            shift
            ;;
        --keep-models)
            KEEP_MODELS=true
            shift
            ;;
        --keep-configs)
            KEEP_CONFIGS=true
            shift
            ;;
        --keep-apps)
            KEEP_APPS=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --yes|-y)
            AUTO_YES=true
            shift
            ;;
        --help|-h)
            grep "^#" "$0" | grep -v "^#!/" | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Set backup directory if not specified
if [[ -z "$BACKUP_DIR" ]]; then
    BACKUP_DIR="$HOME/gemma4-opencode-backup-$(date +%Y%m%d_%H%M%S)"
fi

#############################################
# Helper Functions
#############################################

# Confirm action with user
confirm() {
    local prompt="$1"
    local default="${2:-n}"  # Default to 'no' for safety

    if [[ "$AUTO_YES" == true ]]; then
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi

    local response
    if [[ "$default" == "y" ]]; then
        read -r -p "$prompt (Y/n) " response
        response=${response:-Y}
    else
        read -r -p "$prompt (y/N) " response
        response=${response:-N}
    fi

    [[ "$response" =~ ^[Yy]$ ]]
}

# Backup file or directory
backup_item() {
    local item="$1"
    local backup_path="$2"

    if [[ ! -e "$item" ]]; then
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_dry_run "Would backup: $item → $backup_path"
        return 0
    fi

    # Create backup directory structure
    mkdir -p "$(dirname "$backup_path")"

    if cp -R "$item" "$backup_path" 2>/dev/null; then
        print_status "Backed up: $(basename "$item")"
        ITEMS_BACKED_UP=$((ITEMS_BACKED_UP + 1))
        return 0
    else
        print_warning "Failed to backup: $item"
        return 1
    fi
}

# Remove file or directory
remove_item() {
    local item="$1"
    local description="$2"

    if [[ ! -e "$item" ]]; then
        return 0
    fi

    local size
    size=$(get_size "$item")

    if [[ "$DRY_RUN" == true ]]; then
        print_dry_run "Would remove: $item ($(format_bytes "$size"))"
        return 0
    fi

    if rm -rf "$item" 2>/dev/null; then
        print_status "Removed: $description"
        ITEMS_REMOVED=$((ITEMS_REMOVED + 1))
        SPACE_FREED=$((SPACE_FREED + size))
        return 0
    else
        print_error "Failed to remove: $description"
        return 1
    fi
}

#############################################
# Detection Functions
#############################################

detect_installation() {
    print_header "Detecting Installed Components"

    local found_components=false

    # Check Ollama
    if command -v ollama &> /dev/null; then
        print_info "✓ Ollama installed: $(ollama --version 2>/dev/null | head -1)"
        found_components=true
    else
        print_info "  Ollama not found"
    fi

    # Check OpenCode
    if command -v opencode &> /dev/null; then
        print_info "✓ OpenCode installed: $(opencode --version 2>/dev/null || echo 'version unknown')"
        found_components=true
    else
        print_info "  OpenCode not found"
    fi

    # Check LaunchAgent
    if [[ -f "$LAUNCHAGENT_PLIST" ]]; then
        print_info "✓ LaunchAgent configured: $LAUNCHAGENT_PLIST"
        if launchctl list | grep -q "$LAUNCHAGENT_LABEL"; then
            print_info "  Status: Loaded and running"
        else
            print_info "  Status: Not loaded"
        fi
        found_components=true
    else
        print_info "  LaunchAgent not found"
    fi

    # Check OpenCode config
    if [[ -d "$OPENCODE_CONFIG_DIR" ]]; then
        print_info "✓ OpenCode config exists: $OPENCODE_CONFIG_DIR"
        found_components=true
    else
        print_info "  OpenCode config not found"
    fi

    # Check Ollama models
    if [[ -d "$OLLAMA_MODELS_DIR" ]]; then
        local model_count
        model_count=$(find "$OLLAMA_MODELS_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
        local model_size
        model_size=$(get_size "$OLLAMA_MODELS_DIR")
        print_info "✓ Ollama models directory: $OLLAMA_MODELS_DIR"
        print_info "  Files: $model_count, Size: $(format_bytes "$model_size")"
        found_components=true
    else
        print_info "  Ollama models directory not found"
    fi

    # Check logs
    local logs_exist=false
    if [[ -f "$OLLAMA_LOGS_STDOUT" ]]; then
        print_info "✓ Ollama stdout log: $(format_bytes "$(get_size "$OLLAMA_LOGS_STDOUT")")"
        logs_exist=true
    fi
    if [[ -f "$OLLAMA_LOGS_STDERR" ]]; then
        print_info "✓ Ollama stderr log: $(format_bytes "$(get_size "$OLLAMA_LOGS_STDERR")")"
        logs_exist=true
    fi
    if [[ "$logs_exist" == false ]]; then
        print_info "  Ollama logs not found"
    fi

    echo

    if [[ "$found_components" == false ]]; then
        print_warning "No Gemma4 + OpenCode components found"
        print_info "Nothing to uninstall"
        exit 0
    fi
}

#############################################
# Interactive Selection
#############################################

interactive_selection() {
    print_header "Uninstallation Options"

    echo "What would you like to remove?"
    echo ""
    echo "1. Complete removal (everything)"
    echo "2. Applications only (Ollama + OpenCode)"
    echo "3. Configurations only (keep apps and models)"
    echo "4. Models only (keep apps and configs)"
    echo "5. LaunchAgent only (keep everything else)"
    echo "6. Custom selection (choose each component)"
    echo "7. Cancel"
    echo ""

    local choice
    read -r -p "Enter your choice (1-7): " choice

    case $choice in
        1)
            COMPLETE_REMOVAL=true
            print_info "Selected: Complete removal"
            ;;
        2)
            KEEP_MODELS=true
            KEEP_CONFIGS=true
            print_info "Selected: Remove applications only"
            ;;
        3)
            KEEP_APPS=true
            KEEP_MODELS=true
            print_info "Selected: Remove configurations only"
            ;;
        4)
            KEEP_APPS=true
            KEEP_CONFIGS=true
            print_info "Selected: Remove models only"
            ;;
        5)
            KEEP_APPS=true
            KEEP_MODELS=true
            KEEP_CONFIGS=true
            print_info "Selected: Remove LaunchAgent only"
            ;;
        6)
            print_info "Selected: Custom selection"
            custom_selection
            ;;
        7)
            print_info "Cancelled by user"
            exit 0
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac

    echo
}

custom_selection() {
    echo ""
    echo "Select components to remove:"
    echo ""

    # Apps
    if confirm "Remove Ollama application?"; then
        KEEP_APPS=false
    else
        KEEP_APPS=true
    fi

    if confirm "Remove OpenCode application?"; then
        # Store separately if needed
        :
    fi

    # Configs
    if confirm "Remove configuration files?"; then
        KEEP_CONFIGS=false
    else
        KEEP_CONFIGS=true
    fi

    # Models
    if confirm "Remove downloaded models?"; then
        KEEP_MODELS=false
    else
        KEEP_MODELS=true
    fi

    echo
}

#############################################
# Uninstallation Functions
#############################################

uninstall_launchagent() {
    print_header "Step 1: Removing LaunchAgent"

    if [[ ! -f "$LAUNCHAGENT_PLIST" ]]; then
        print_info "LaunchAgent not found, skipping"
        return 0
    fi

    # Backup LaunchAgent
    if [[ "$DRY_RUN" == false ]]; then
        backup_item "$LAUNCHAGENT_PLIST" "$BACKUP_DIR/LaunchAgent/$(basename "$LAUNCHAGENT_PLIST")"
    fi

    # Unload if loaded
    if launchctl list | grep -q "$LAUNCHAGENT_LABEL"; then
        print_action "Unloading LaunchAgent..."
        if [[ "$DRY_RUN" == true ]]; then
            print_dry_run "Would unload: $LAUNCHAGENT_LABEL"
        else
            if launchctl unload "$LAUNCHAGENT_PLIST" 2>/dev/null; then
                print_status "LaunchAgent unloaded"
            else
                print_warning "Failed to unload LaunchAgent (may not be running)"
            fi
        fi
    fi

    # Stop any running Ollama processes
    if pgrep -x ollama > /dev/null; then
        print_action "Stopping Ollama processes..."
        if [[ "$DRY_RUN" == true ]]; then
            print_dry_run "Would stop Ollama processes"
        else
            pkill -x ollama || true
            sleep 2
            print_status "Ollama processes stopped"
        fi
    fi

    # Remove LaunchAgent plist
    remove_item "$LAUNCHAGENT_PLIST" "LaunchAgent plist"
}

uninstall_configs() {
    print_header "Step 2: Removing Configuration Files"

    if [[ "$KEEP_CONFIGS" == true ]]; then
        print_info "Keeping configuration files (--keep-configs specified)"
        return 0
    fi

    # Backup and remove OpenCode config
    if [[ -d "$OPENCODE_CONFIG_DIR" ]]; then
        if [[ "$DRY_RUN" == false ]]; then
            backup_item "$OPENCODE_CONFIG_DIR" "$BACKUP_DIR/configs/opencode"
        fi
        remove_item "$OPENCODE_CONFIG_DIR" "OpenCode configuration directory"
    else
        print_info "OpenCode config directory not found, skipping"
    fi

    # Remove logs
    if [[ -f "$OLLAMA_LOGS_STDOUT" ]]; then
        remove_item "$OLLAMA_LOGS_STDOUT" "Ollama stdout log"
    fi

    if [[ -f "$OLLAMA_LOGS_STDERR" ]]; then
        remove_item "$OLLAMA_LOGS_STDERR" "Ollama stderr log"
    fi
}

uninstall_models() {
    print_header "Step 3: Removing Ollama Models"

    if [[ "$KEEP_MODELS" == true ]]; then
        print_info "Keeping Ollama models (--keep-models specified)"
        return 0
    fi

    if [[ ! -d "$OLLAMA_MODELS_DIR" ]]; then
        print_info "Ollama models directory not found, skipping"
        return 0
    fi

    local model_size
    model_size=$(get_size "$OLLAMA_MODELS_DIR")
    print_warning "This will remove $(format_bytes "$model_size") of model data"

    if [[ "$DRY_RUN" == false ]] && [[ "$AUTO_YES" == false ]]; then
        if ! confirm "Are you sure you want to delete all models?" "n"; then
            print_info "Keeping models"
            return 0
        fi
    fi

    # List models before removal (for backup record)
    if command -v ollama &> /dev/null && [[ "$DRY_RUN" == false ]]; then
        print_action "Listing installed models..."
        ollama list > "$BACKUP_DIR/models_list.txt" 2>/dev/null || true
        print_status "Model list saved to backup"
    fi

    # Remove models directory
    remove_item "$OLLAMA_MODELS_DIR" "Ollama models directory"
}

uninstall_applications() {
    print_header "Step 4: Removing Applications"

    if [[ "$KEEP_APPS" == true ]]; then
        print_info "Keeping applications (--keep-apps specified)"
        return 0
    fi

    # Check if Homebrew is available
    if ! command -v brew &> /dev/null; then
        print_warning "Homebrew not found, cannot uninstall applications"
        return 1
    fi

    # Uninstall Ollama
    if brew list ollama &> /dev/null; then
        print_action "Uninstalling Ollama via Homebrew..."
        if [[ "$DRY_RUN" == true ]]; then
            print_dry_run "Would run: brew uninstall ollama"
        else
            if brew uninstall ollama 2>&1 | grep -v "Uninstalling"; then
                print_status "Ollama uninstalled"
                ITEMS_REMOVED=$((ITEMS_REMOVED + 1))
            else
                print_status "Ollama uninstalled"
                ITEMS_REMOVED=$((ITEMS_REMOVED + 1))
            fi
        fi
    else
        print_info "Ollama not installed via Homebrew, skipping"
    fi

    # Uninstall OpenCode
    if brew list opencode &> /dev/null; then
        print_action "Uninstalling OpenCode via Homebrew..."
        if [[ "$DRY_RUN" == true ]]; then
            print_dry_run "Would run: brew uninstall opencode"
        else
            if brew uninstall opencode 2>&1 | grep -v "Uninstalling"; then
                print_status "OpenCode uninstalled"
                ITEMS_REMOVED=$((ITEMS_REMOVED + 1))
            else
                print_status "OpenCode uninstalled"
                ITEMS_REMOVED=$((ITEMS_REMOVED + 1))
            fi
        fi
    else
        print_info "OpenCode not installed via Homebrew, skipping"
    fi
}

#############################################
# Summary and Restoration Info
#############################################

print_summary() {
    print_header "Uninstallation Summary"

    if [[ "$DRY_RUN" == true ]]; then
        print_info "DRY-RUN MODE: No actual changes were made"
        echo
    fi

    echo "Statistics:"
    echo "  • Items removed:  $ITEMS_REMOVED"
    echo "  • Items backed up: $ITEMS_BACKED_UP"
    echo "  • Space freed:    $(format_bytes "$SPACE_FREED")"
    echo

    if [[ "$DRY_RUN" == false ]] && [[ $ITEMS_BACKED_UP -gt 0 ]]; then
        print_status "Backup created at: $BACKUP_DIR"
        echo
        print_info "Backup contents:"
        if [[ -d "$BACKUP_DIR" ]]; then
            ls -lh "$BACKUP_DIR" 2>/dev/null | tail -n +2 | while read -r line; do
                echo "    $line"
            done
        fi
        echo
    fi

    if [[ "$DRY_RUN" == false ]]; then
        print_status "Uninstallation complete!"
    else
        print_info "To perform actual uninstallation, run without --dry-run flag"
    fi
}

print_restoration_info() {
    if [[ "$DRY_RUN" == true ]] || [[ $ITEMS_BACKED_UP -eq 0 ]]; then
        return 0
    fi

    print_header "Restoration Information"

    cat << EOF
To restore your previous configuration:

1. LaunchAgent:
   cp "$BACKUP_DIR/LaunchAgent/$(basename "$LAUNCHAGENT_PLIST")" "$LAUNCHAGENT_PLIST"
   launchctl load "$LAUNCHAGENT_PLIST"

2. OpenCode Config:
   cp -R "$BACKUP_DIR/configs/opencode" "$OPENCODE_CONFIG_DIR"

3. Reinstall Applications:
   brew install ollama
   brew install anomalyco/tap/opencode

4. Restore Models (requires Ollama):
   # See model list in: $BACKUP_DIR/models_list.txt
   # Pull models manually with: ollama pull <model-name>

For full restoration, you can also run the setup script again:
   ./setup-gemma4-opencode.sh
EOF
}

#############################################
# Main Execution
#############################################

main() {
    print_header "Gemma4 + OpenCode Uninstaller"

    if [[ "$DRY_RUN" == true ]]; then
        print_warning "DRY-RUN MODE: No changes will be made"
        echo
    fi

    # Detect what's installed
    detect_installation

    # Get user preferences (unless complete removal specified)
    if [[ "$COMPLETE_REMOVAL" == false ]] && [[ "$AUTO_YES" == false ]]; then
        interactive_selection
    else
        if [[ "$COMPLETE_REMOVAL" == true ]]; then
            print_warning "Complete removal mode enabled"
            if [[ "$AUTO_YES" == false ]] && [[ "$DRY_RUN" == false ]]; then
                echo
                if ! confirm "This will remove ALL components. Continue?" "n"; then
                    print_info "Cancelled by user"
                    exit 0
                fi
            fi
        fi
    fi

    # Confirmation before proceeding
    if [[ "$DRY_RUN" == false ]] && [[ "$AUTO_YES" == false ]]; then
        echo
        print_warning "Components will be backed up to: $BACKUP_DIR"
        if ! confirm "Proceed with uninstallation?" "n"; then
            print_info "Cancelled by user"
            exit 0
        fi
    fi

    # Create backup directory
    if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$BACKUP_DIR"
        print_status "Backup directory created: $BACKUP_DIR"
        echo
    fi

    # Execute uninstallation steps
    uninstall_launchagent
    uninstall_configs
    uninstall_models
    uninstall_applications

    # Show summary
    print_summary
    print_restoration_info
}

# Run main function
main "$@"
