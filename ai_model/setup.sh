#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Protect SCRIPT_DIR from being overwritten by sourced libraries
SETUP_SCRIPT_DIR="$SCRIPT_DIR"
export SETUP_SCRIPT_DIR

# Source common utilities first
source "$LIB_DIR/common.sh"

# Source all other libraries (they will use the already-sourced common.sh)
source "$LIB_DIR/model-families.sh"
source "$LIB_DIR/model-selection.sh"
source "$LIB_DIR/ollama-setup.sh"
source "$LIB_DIR/continue-setup.sh"
source "$LIB_DIR/webui-setup.sh"
source "$LIB_DIR/opencode-setup.sh"

# Configuration - ensure OLLAMA_PORT is set before anything else
export OLLAMA_PORT="${OLLAMA_PORT:-11434}"
export AUTO_START="${AUTO_START:-true}"
export SETUP_CLIENTS="${SETUP_CLIENTS:-all}"
export INSTALL_EMBEDDING_MODEL="${INSTALL_EMBEDDING_MODEL:-false}"

# Parse flags
UNATTENDED=false
PRESET=""

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Comprehensive Local LLM Setup - Main Orchestrator

OPTIONS:
    --unattended        Run without user interaction
    --preset NAME       Load configuration from presets/NAME.env
    --help              Show this help message

ENVIRONMENT VARIABLES:
    OLLAMA_MODEL_FAMILY         Model family (llama, gemma, qwen, deepseek)
    OLLAMA_MODEL                Specific model to install
    SETUP_CLIENTS               Clients to setup (all|continue|webui|opencode|none)
    AUTO_START                  Auto-start Ollama server (true|false)
    INSTALL_EMBEDDING_MODEL     Install embedding model (true|false)

EXAMPLES:
    # Interactive setup
    ./setup.sh

    # Unattended with preset
    ./setup.sh --preset developer --unattended

    # Custom model
    OLLAMA_MODEL=gemma4:31b-it-q8_0 ./setup.sh

    # Only specific clients
    SETUP_CLIENTS=continue,opencode ./setup.sh

DOCUMENTATION:
    See docs/ directory for detailed guides
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --unattended) UNATTENDED=true; shift ;;
        --preset) PRESET="$2"; shift 2 ;;
        --help) show_help; exit 0 ;;
        *) echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

load_preset() {
    local preset_name="$1"
    local preset_file="$SETUP_SCRIPT_DIR/presets/${preset_name}.env"

    if [[ ! -f "$preset_file" ]]; then
        print_error "Preset not found: $preset_name"
        print_info "Available presets:"
        if [[ -d "$SETUP_SCRIPT_DIR/presets" ]]; then
            find "$SETUP_SCRIPT_DIR/presets" -maxdepth 1 -name "*.env" -print0 2>/dev/null | \
                xargs -0 -n1 basename | \
                sed 's/.env$//' || echo "  (none)"
        else
            echo "  (presets/ directory not found)"
        fi
        exit 1
    fi

    source "$preset_file"
    print_info "Loaded preset: $preset_name"
}

check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check for Homebrew (required for installing Ollama)
    if ! command -v brew >/dev/null 2>&1; then
        print_error "Homebrew is not installed"
        print_info "Install Homebrew from: https://brew.sh"
        print_info "Then run: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi

    print_status "Homebrew found: $(brew --version | head -1)"
    print_status "All prerequisites met"
}

configure_shell_environment() {
    print_header "Configuring Shell Environment"

    local shell_config=""
    local current_shell="${SHELL##*/}"

    # Detect shell configuration file
    case "$current_shell" in
        zsh)
            shell_config="$HOME/.zshrc"
            ;;
        bash)
            # macOS uses .bash_profile, Linux uses .bashrc
            if [[ "$OSTYPE" == "darwin"* ]]; then
                shell_config="$HOME/.bash_profile"
            else
                shell_config="$HOME/.bashrc"
            fi
            ;;
        *)
            print_warning "Unknown shell: $current_shell"
            print_info "Please manually add: export OLLAMA_HOST=\"127.0.0.1:$OLLAMA_PORT\""
            return 0
            ;;
    esac

    print_info "Shell: $current_shell"
    print_info "Config file: $shell_config"

    # Check if OLLAMA_PORT is already configured
    if ! grep -q "export OLLAMA_PORT=" "$shell_config" 2>/dev/null; then
        print_info "Adding OLLAMA_PORT to $shell_config..."
        cat >> "$shell_config" <<EOF

# Ollama custom port (added by ai_model setup)
export OLLAMA_PORT="$OLLAMA_PORT"
EOF
        print_status "Added OLLAMA_PORT=$OLLAMA_PORT"
    fi

    # Check if OLLAMA_HOST is already configured
    if grep -q "export OLLAMA_HOST=" "$shell_config" 2>/dev/null; then
        # Check if it has the correct value
        if grep -q "export OLLAMA_HOST=\"127.0.0.1:$OLLAMA_PORT\"" "$shell_config"; then
            print_status "OLLAMA_HOST already configured correctly"
        else
            print_warning "OLLAMA_HOST exists with different value"
            # Update the existing line
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s|export OLLAMA_HOST=.*|export OLLAMA_HOST=\"127.0.0.1:$OLLAMA_PORT\"|" "$shell_config"
            else
                sed -i "s|export OLLAMA_HOST=.*|export OLLAMA_HOST=\"127.0.0.1:$OLLAMA_PORT\"|" "$shell_config"
            fi
            print_status "Updated OLLAMA_HOST to: 127.0.0.1:$OLLAMA_PORT"
        fi
    else
        # Add OLLAMA_HOST configuration
        print_info "Adding OLLAMA_HOST to $shell_config..."
        cat >> "$shell_config" <<EOF

# Ollama custom port configuration (added by ai_model setup)
export OLLAMA_HOST="127.0.0.1:$OLLAMA_PORT"
EOF
        print_status "Added OLLAMA_HOST=127.0.0.1:$OLLAMA_PORT"
    fi

    # Export for current session
    export OLLAMA_PORT="$OLLAMA_PORT"
    export OLLAMA_HOST="127.0.0.1:$OLLAMA_PORT"

    # Note: New terminal sessions will automatically load OLLAMA_HOST
    # Current session already has OLLAMA_HOST exported above

    print_status "Environment configured: OLLAMA_PORT=$OLLAMA_PORT, OLLAMA_HOST=127.0.0.1:$OLLAMA_PORT"
    print_info "Future terminals will automatically have these settings"
}

setup_clients() {
    local clients="$1"

    case "$clients" in
        all)
            setup_continue
            setup_webui
            setup_opencode
            ;;
        continue)
            setup_continue
            ;;
        webui)
            setup_webui
            ;;
        opencode)
            setup_opencode
            ;;
        none)
            print_info "Skipping client setup"
            ;;
        *)
            # Parse comma-separated list
            IFS=',' read -ra CLIENT_ARRAY <<< "$clients"
            for client in "${CLIENT_ARRAY[@]}"; do
                case "$client" in
                    continue) setup_continue ;;
                    webui) setup_webui ;;
                    opencode) setup_opencode ;;
                    *) print_error "Unknown client: $client"; exit 1 ;;
                esac
            done
            ;;
    esac
}

show_final_summary() {
    print_header "Setup Complete!"

    echo ""
    echo "INSTALLED COMPONENTS:"
    echo "====================="
    echo ""
    echo "✓ Ollama Server: Running on port ${OLLAMA_PORT:-11434}"
    echo "✓ Model: ${OLLAMA_MODEL:-$(cat ~/.ollama-model 2>/dev/null || echo 'N/A')}"
    echo ""

    # Show installed clients
    local clients_installed=false
    echo "✓ Clients:"

    if [[ "$SETUP_CLIENTS" =~ "continue" ]] || [[ "$SETUP_CLIENTS" == "all" ]]; then
        echo "  - Continue.dev (VS Code/Cursor IDE)"
        echo "    Config: ~/.continue/config.json"
        clients_installed=true
    fi

    if [[ "$SETUP_CLIENTS" =~ "webui" ]] || [[ "$SETUP_CLIENTS" == "all" ]]; then
        echo "  - Open WebUI"
        echo "    URL: http://localhost:38080"
        echo "    Control: docker ps | grep open-webui"
        clients_installed=true
    fi

    if [[ "$SETUP_CLIENTS" =~ "opencode" ]] || [[ "$SETUP_CLIENTS" == "all" ]]; then
        echo "  - OpenCode CLI"
        echo "    Binary: ~/go/bin/opencode"
        echo "    Usage: opencode chat"
        clients_installed=true
    fi

    if [[ "$clients_installed" == "false" ]]; then
        echo "  (none installed)"
    fi

    echo ""
    echo "UTILITY SCRIPTS:"
    echo "================"
    echo ""
    echo "Server Management:"
    echo "  ./llama-control.sh {start|stop|status|health|metrics}"
    echo ""
    echo "Model Operations:"
    echo "  ./switch-model.sh <model>        - Switch active model"
    echo "  ./compare-models.sh              - Compare model performance"
    echo "  ./benchmark.sh <model>           - Benchmark specific model"
    echo ""
    echo "Troubleshooting:"
    echo "  ./diagnose.sh                    - System diagnostics"
    echo ""
    echo "DOCUMENTATION:"
    echo "=============="
    echo ""
    echo "  docs/USAGE.md                    - Quick start guide"
    echo "  docs/MODELS.md                   - Model selection guide"
    echo "  docs/TROUBLESHOOTING.md          - Common issues"
    echo ""

    # Show next steps
    print_header "Next Steps"
    echo ""

    # Detect shell config file for user instruction
    local shell_config=""
    case "${SHELL##*/}" in
        zsh) shell_config="~/.zshrc" ;;
        bash) shell_config="~/.bash_profile" ;;
        *) shell_config="your shell config" ;;
    esac

    echo "1. Test your installation:"
    echo "   ollama run ${OLLAMA_MODEL:-$(cat ~/.ollama-model 2>/dev/null || echo 'llama3.3:70b')}"
    echo ""
    echo "2. Check server status:"
    echo "   ./llama-control.sh status"
    echo ""

    if [[ "$SETUP_CLIENTS" =~ "webui" ]] || [[ "$SETUP_CLIENTS" == "all" ]]; then
        echo "3. Access Open WebUI:"
        echo "   Open http://localhost:38080 in your browser"
        echo ""
    fi

    if [[ "$SETUP_CLIENTS" =~ "opencode" ]] || [[ "$SETUP_CLIENTS" == "all" ]]; then
        echo "4. Try OpenCode CLI:"
        echo "   opencode        # Start TUI"
        echo "   opencode run \"your message here\""
        echo ""
    fi
}

main() {
    print_header "Comprehensive Local LLM Setup"
    echo ""
    echo "This script will set up a complete local LLM environment with:"
    echo "  - Ollama server (custom build with Metal acceleration)"
    echo "  - AI model tailored to your hardware"
    echo "  - Client applications (Continue.dev, Open WebUI, OpenCode)"
    echo ""

    # Show detected hardware
    print_info "Detected Hardware:"
    echo "  Chip: $M_CHIP"
    echo "  RAM: ${TOTAL_RAM_GB}GB (Tier: $RAM_TIER)"
    echo "  GPU Cores: ${GPU_CORES:-Unknown}"
    echo ""

    # IDEMPOTENCY: Check if Ollama is already installed
    if command -v ollama &> /dev/null; then
        print_status "Ollama already installed: $(ollama --version 2>&1 | head -1)"
        if [[ "$UNATTENDED" == "false" ]]; then
            read -p "Reinstall/upgrade Ollama? (y/N): " reinstall
            if [[ "$reinstall" != "y" && "$reinstall" != "Y" ]]; then
                export SKIP_INSTALL=true
                print_info "Skipping Ollama installation"
            fi
        else
            export SKIP_INSTALL=true
            print_info "Unattended mode: Skipping reinstall"
        fi
    fi

    # IDEMPOTENCY: Check if Ollama server is running
    if pgrep -x "ollama" > /dev/null; then
        print_status "Ollama server is already running"
        export OLLAMA_ALREADY_RUNNING=true
    fi

    # Load preset if specified
    if [[ -n "$PRESET" ]]; then
        load_preset "$PRESET"
    fi

    # Step 1: Prerequisites
    check_prerequisites

    # Step 2: Install Ollama (if not skipped)
    if [[ "${SKIP_INSTALL:-false}" != "true" ]]; then
        install_ollama
    else
        print_info "Using existing Ollama installation"
    fi

    # Step 3: Start server (if not already running)
    if [[ "${OLLAMA_ALREADY_RUNNING:-false}" != "true" ]]; then
        start_ollama_server
    else
        print_info "Using existing Ollama server"
    fi

    # Step 3.5: Configure shell environment
    configure_shell_environment

    # Step 4: Model selection (unless preset specifies one)
    if [[ -z "${OLLAMA_MODEL:-}" ]]; then
        if [[ "$UNATTENDED" == "true" ]]; then
            print_error "Unattended mode requires OLLAMA_MODEL to be set"
            exit 1
        fi
        run_model_selection  # From lib/model-selection.sh
        # Export selected model to OLLAMA_MODEL
        export OLLAMA_MODEL="$SELECTED_MODEL"
    else
        print_info "Using model: $OLLAMA_MODEL"
    fi

    # Step 5: Pull model (check if already installed)
    if ollama list 2>/dev/null | grep -q "^${OLLAMA_MODEL%%:*}"; then
        print_status "Model $OLLAMA_MODEL already installed"
        if [[ "$UNATTENDED" == "false" ]]; then
            read -p "Re-pull model? (y/N): " repull
            if [[ "$repull" == "y" || "$repull" == "Y" ]]; then
                pull_model "$OLLAMA_MODEL"
            fi
        else
            print_info "Unattended mode: Skipping model re-pull"
        fi
    else
        pull_model "$OLLAMA_MODEL"
    fi

    # Save selected model for utilities
    echo "$OLLAMA_MODEL" > ~/.ollama-model

    # Step 6: Setup clients
    setup_clients "$SETUP_CLIENTS"

    # Step 7: Install embedding model if requested
    if [[ "$INSTALL_EMBEDDING_MODEL" == "true" ]]; then
        print_header "Installing Embedding Model"
        local embed_model="nomic-embed-text"
        if ollama list 2>/dev/null | grep -q "^${embed_model}"; then
            print_status "Embedding model already installed"
        else
            pull_model "$embed_model"
        fi
    fi

    # Step 8: Summary
    echo ""
    show_final_summary
}

# Run main function
main
