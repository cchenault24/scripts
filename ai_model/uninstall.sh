#!/usr/bin/env bash
set -euo pipefail

# Comprehensive LLM Setup Uninstaller
# Removes Ollama, models, configs, and related components

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR=""
NO_BACKUP=false

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all)
                AUTO_MODE="all"
                shift
                ;;
            --models-only)
                AUTO_MODE="models"
                shift
                ;;
            --no-backup)
                NO_BACKUP=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
Usage: ./uninstall.sh [OPTIONS]

Comprehensive uninstaller for LLM setup components.

OPTIONS:
    --all           Remove everything without prompts
    --models-only   Remove only models without prompts
    --no-backup     Skip backup of configurations
    -h, --help      Show this help message

Interactive mode (default): Prompts for each component removal.

EOF
}

# Backup configurations before removal
backup_configs() {
    if [[ "$NO_BACKUP" == true ]]; then
        log_warn "Skipping backup (--no-backup flag set)"
        return
    fi

    BACKUP_DIR="$HOME/.llm-setup-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    local backed_up=false

    # Backup Continue.dev config
    if [[ -f "$HOME/.continue/config.json" ]]; then
        mkdir -p "$BACKUP_DIR/continue"
        cp "$HOME/.continue/config.json" "$BACKUP_DIR/continue/"
        backed_up=true
    fi

    # Backup OpenCode config
    if [[ -d "$HOME/.config/opencode" ]]; then
        cp -r "$HOME/.config/opencode" "$BACKUP_DIR/"
        backed_up=true
    fi

    # Backup model list
    if [[ -d "$HOME/.ollama/models" ]]; then
        if command -v ollama &> /dev/null; then
            ollama list > "$BACKUP_DIR/models-list.txt" 2>/dev/null || true
            backed_up=true
        fi
    fi

    if [[ "$backed_up" == true ]]; then
        log_info "Configs backed up to: $BACKUP_DIR"
    else
        log_warn "No configs found to backup"
        rmdir "$BACKUP_DIR" 2>/dev/null || true
        BACKUP_DIR=""
    fi
}

# Stop and remove Ollama server
remove_ollama_server() {
    echo ""
    echo "Stopping Ollama server..."

    # Stop using llama-control.sh if it exists
    if [[ -f "$SCRIPT_DIR/llama-control.sh" ]]; then
        "$SCRIPT_DIR/llama-control.sh" stop 2>/dev/null || true
    fi

    # Also try to kill any running ollama processes
    pkill -f "ollama serve" 2>/dev/null || true

    # Remove build directory
    if [[ -d "/tmp/ollama-build" ]]; then
        echo "Removing Ollama build directory..."
        rm -rf /tmp/ollama-build
        log_info "Ollama build removed"
    fi

    # Remove PID file
    if [[ -f "$HOME/.local/var/ollama-server.pid" ]]; then
        rm -f "$HOME/.local/var/ollama-server.pid"
    fi

    # Remove logs
    if [[ -f "$HOME/.local/var/log/ollama-server.log" ]]; then
        rm -f "$HOME/.local/var/log/ollama-server.log"
        log_info "Logs removed"
    fi

    log_info "Ollama server stopped and removed"
}

# Remove downloaded models
remove_models() {
    echo ""
    if [[ ! -d "$HOME/.ollama" ]]; then
        log_warn "No models directory found"
        return
    fi

    local size=$(du -sh "$HOME/.ollama" 2>/dev/null | awk '{print $1}')
    echo "Models directory size: ${size:-0}"

    if [[ -z "${AUTO_MODE:-}" ]]; then
        read -p "Remove $size of models? (y/N): " confirm
        [[ "$confirm" != "y" ]] && return
    fi

    rm -rf "$HOME/.ollama"
    log_info "Models removed"
}

# Remove client configurations
remove_client_configs() {
    echo ""
    echo "Removing client configurations..."

    # Continue.dev
    if [[ -f "$HOME/.continue/config.json" ]]; then
        if [[ -z "${AUTO_MODE:-}" ]]; then
            read -p "Remove Continue.dev config? (y/N): " confirm
        else
            confirm="y"
        fi

        if [[ "$confirm" == "y" ]]; then
            rm -f "$HOME/.continue/config.json"
            # Remove directory if empty
            rmdir "$HOME/.continue" 2>/dev/null || true
            log_info "Continue.dev config removed"
        fi
    fi

    # OpenCode
    if [[ -d "$HOME/.config/opencode" ]]; then
        if [[ -z "${AUTO_MODE:-}" ]]; then
            read -p "Remove OpenCode config? (y/N): " confirm
        else
            confirm="y"
        fi

        if [[ "$confirm" == "y" ]]; then
            rm -rf "$HOME/.config/opencode"
            log_info "OpenCode config removed"
        fi
    fi
}

# Remove Open WebUI Docker container
remove_open_webui() {
    echo ""
    echo "Checking for Open WebUI Docker container..."

    if ! command -v docker &> /dev/null; then
        log_warn "Docker not found, skipping Open WebUI removal"
        return
    fi

    if docker ps -a 2>/dev/null | grep -q open-webui; then
        if [[ -z "${AUTO_MODE:-}" ]]; then
            read -p "Remove Open WebUI container? (y/N): " confirm
        else
            confirm="y"
        fi

        if [[ "$confirm" == "y" ]]; then
            docker stop open-webui 2>/dev/null || true
            docker rm open-webui 2>/dev/null || true
            docker volume rm open-webui 2>/dev/null || true
            log_info "Open WebUI removed"
        fi
    else
        log_warn "No Open WebUI container found"
    fi
}

# Remove all components
remove_all() {
    backup_configs
    remove_ollama_server
    remove_models
    remove_client_configs
    remove_open_webui
}

# Remove only Ollama (keep configs)
remove_ollama() {
    backup_configs
    remove_ollama_server
    remove_models
}

# Remove only models (keep Ollama and configs)
remove_models_only() {
    backup_configs
    remove_models
}

# Remove only configs (keep Ollama and models)
remove_configs() {
    backup_configs
    remove_client_configs
}

# Custom selection
custom_removal() {
    echo ""
    echo "Custom Selection"
    echo "================"

    backup_configs

    echo ""
    read -p "Remove Ollama server? (y/N): " remove_server
    [[ "$remove_server" == "y" ]] && remove_ollama_server

    echo ""
    read -p "Remove models? (y/N): " remove_model
    [[ "$remove_model" == "y" ]] && remove_models

    echo ""
    read -p "Remove client configs? (y/N): " remove_config
    [[ "$remove_config" == "y" ]] && remove_client_configs

    echo ""
    read -p "Remove Open WebUI? (y/N): " remove_webui
    [[ "$remove_webui" == "y" ]] && remove_open_webui
}

# Show summary of what was removed
show_summary() {
    echo ""
    echo "Uninstallation Summary"
    echo "======================"
    echo ""

    local removed_items=false

    if [[ ! -d "/tmp/ollama-build" ]]; then
        log_info "Ollama build removed"
        removed_items=true
    fi

    if [[ ! -d "$HOME/.ollama" ]]; then
        log_info "Models removed"
        removed_items=true
    fi

    if [[ ! -f "$HOME/.continue/config.json" ]]; then
        log_info "Continue.dev config removed"
        removed_items=true
    fi

    if [[ ! -d "$HOME/.config/opencode" ]]; then
        log_info "OpenCode config removed"
        removed_items=true
    fi

    if ! docker ps -a 2>/dev/null | grep -q open-webui; then
        log_info "Open WebUI removed"
        removed_items=true
    fi

    if [[ "$removed_items" == false ]]; then
        log_warn "No components were removed"
    fi

    if [[ -n "$BACKUP_DIR" ]] && [[ -d "$BACKUP_DIR" ]]; then
        echo ""
        echo "Backups saved to: $BACKUP_DIR"
    fi

    echo ""
    echo "To reinstall: cd $SCRIPT_DIR && ./setup.sh"
    echo ""
}

# Interactive mode
interactive_uninstall() {
    echo "Comprehensive LLM Setup Uninstaller"
    echo "===================================="
    echo ""

    # Show what can be removed
    echo "This script can remove:"
    echo "  - Ollama server and build (/tmp/ollama-build)"
    echo "  - Downloaded models (~/.ollama/)"
    echo "  - Client configurations (Continue.dev, OpenCode)"
    echo "  - Logs and PID files"
    echo "  - Open WebUI Docker container"
    echo ""

    read -p "Continue? (y/N): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Uninstallation cancelled."
        exit 0
    fi

    # Selective removal menu
    echo ""
    echo "Select what to remove:"
    echo "  1) Everything (complete removal)"
    echo "  2) Ollama only (keep configs)"
    echo "  3) Models only (keep Ollama and configs)"
    echo "  4) Configs only (keep Ollama and models)"
    echo "  5) Custom selection"
    echo ""

    read -p "Choice (1-5): " choice

    case "$choice" in
        1)
            echo ""
            echo "Removing everything..."
            remove_all
            ;;
        2)
            echo ""
            echo "Removing Ollama (keeping configs)..."
            remove_ollama
            ;;
        3)
            echo ""
            echo "Removing models only..."
            remove_models_only
            ;;
        4)
            echo ""
            echo "Removing configs only..."
            remove_configs
            ;;
        5)
            custom_removal
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
}

# Main execution
main() {
    parse_args "$@"

    if [[ -n "${AUTO_MODE:-}" ]]; then
        echo "Comprehensive LLM Setup Uninstaller"
        echo "===================================="
        echo ""

        case "$AUTO_MODE" in
            all)
                echo "Removing everything..."
                remove_all
                ;;
            models)
                echo "Removing models only..."
                remove_models_only
                ;;
        esac
    else
        interactive_uninstall
    fi

    show_summary
}

main "$@"
