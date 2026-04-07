#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Source common utilities first
source "$LIB_DIR/common.sh"

# Source all other libraries (they will use the already-sourced common.sh)
source "$LIB_DIR/model-families.sh"
source "$LIB_DIR/model-selection.sh"
source "$LIB_DIR/ollama-setup.sh"
source "$LIB_DIR/continue-setup.sh"
source "$LIB_DIR/webui-setup.sh"
source "$LIB_DIR/opencode-setup.sh"

# Configuration
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
    local preset_file="$SCRIPT_DIR/presets/${preset_name}.env"

    if [[ ! -f "$preset_file" ]]; then
        print_error "Preset not found: $preset_name"
        print_info "Available presets:"
        if [[ -d "$SCRIPT_DIR/presets" ]]; then
            ls -1 "$SCRIPT_DIR/presets"/*.env 2>/dev/null | xargs -n1 basename | sed 's/.env$//' || echo "  (none)"
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

    local missing=()

    # Check for required tools
    command -v git >/dev/null 2>&1 || missing+=("git")
    command -v go >/dev/null 2>&1 || missing+=("go")
    command -v cmake >/dev/null 2>&1 || missing+=("cmake")

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing required tools: ${missing[*]}"
        print_info "Install with: brew install ${missing[*]}"
        exit 1
    fi

    # Check Go version
    local go_version
    go_version=$(go version | awk '{print $3}' | sed 's/go//')
    if [[ "$(printf '%s\n' "1.22" "$go_version" | sort -V | head -n1)" != "1.22" ]]; then
        print_error "Go 1.22+ required (found: $go_version)"
        exit 1
    fi

    print_status "All prerequisites met"
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
    echo "✓ Ollama Server: Running on port ${PORT:-11434}"
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
        echo "   opencode chat"
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

    # IDEMPOTENCY: Check if Ollama is already built
    if [[ -f /tmp/ollama-build/ollama ]]; then
        print_status "Ollama binary already built at /tmp/ollama-build/ollama"
        if [[ "$UNATTENDED" == "false" ]]; then
            read -p "Rebuild Ollama? (y/N): " rebuild
            if [[ "$rebuild" != "y" && "$rebuild" != "Y" ]]; then
                export SKIP_BUILD=true
                print_info "Skipping Ollama build"
            fi
        else
            export SKIP_BUILD=true
            print_info "Unattended mode: Skipping rebuild"
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

    # Step 2: Build Ollama (if not skipped)
    if [[ "${SKIP_BUILD:-false}" != "true" ]]; then
        build_ollama
    else
        print_info "Using existing Ollama build"
    fi

    # Step 3: Start server (if not already running)
    if [[ "${OLLAMA_ALREADY_RUNNING:-false}" != "true" ]]; then
        start_ollama_server
    else
        print_info "Using existing Ollama server"
    fi

    # Step 4: Model selection (unless preset specifies one)
    if [[ -z "${OLLAMA_MODEL:-}" ]]; then
        if [[ "$UNATTENDED" == "true" ]]; then
            print_error "Unattended mode requires OLLAMA_MODEL to be set"
            exit 1
        fi
        select_model  # From lib/model-selection.sh
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
