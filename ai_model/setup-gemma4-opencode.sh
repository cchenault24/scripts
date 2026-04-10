#!/bin/bash
# setup-gemma4-opencode.sh - Idempotent setup for Gemma4 + IDE tools via Ollama (Homebrew)
#
# One-stop shop for team deployment:
# - Installs Ollama and OpenCode via Homebrew
# - Dynamically optimizes configuration based on detected hardware
# - Pulls and configures Gemma4 models with native context windows
# - Sets up IDE tool integration (OpenCode and/or JetBrains AI Assistant)
# - For JetBrains: Includes CodeGemma for FIM (Fill-In-Middle) code completion
#
# Safe to run multiple times - idempotent design
#
# Available Gemma4 Models (https://ollama.com/library/gemma4/tags):
# ┌──────────────┬────────┬─────────┬──────────────┬──────────────┐
# │ Model        │ Size   │ Context │ RAM Required │ Best For     │
# ├──────────────┼────────┼─────────┼──────────────┼──────────────┤
# │ gemma4:e2b   │ 7.2GB  │ 128K    │ 12GB+        │ Minimal RAM  │
# │ gemma4:latest│ 9.6GB  │ 128K    │ 16GB+        │ Balanced     │
# │ gemma4:26b   │ 18GB   │ 256K    │ 32GB+        │ Large Context│
# │ gemma4:31b   │ 20GB   │ 256K    │ 48GB+        │ Best Quality │
# └──────────────┴────────┴─────────┴──────────────┴──────────────┘
#
# Usage: ./setup-gemma4-opencode.sh [OPTIONS]
#
# Options:
#   --model MODEL    Specify Gemma4 variant (auto-detected by default)
#                    Available: gemma4:e2b, gemma4:latest, gemma4:26b, gemma4:31b
#                    See: https://ollama.com/library/gemma4/tags
#   --auto           Skip all interactive prompts, use auto-detected defaults
#   -v, --verbose    Show detailed output (all steps and debug info)
#   -q, --quiet      Minimal output (only errors and final summary)
#
# Requirements:
#   - macOS 10.14+ (Mojave or later)
#   - Apple Silicon (M1/M2/M3/M4/M5 recommended, Intel supported but slower)
#   - Homebrew installed
#   - Minimum 12GB RAM (16GB+ recommended)
#   - RAM varies by model:
#       e2b: 12GB+ (7.2GB model, 128K context)
#       latest/e4b: 16GB+ (9.6GB model, 128K context)
#       26b: 32GB+ (18GB model, 256K context)
#       31b: 48GB+ (20GB model, 256K context)

set -euo pipefail

# Cleanup function for trap
cleanup() {
    local exit_code=$?
    # Remove temporary modelfile if it exists
    [[ -n "${modelfile_path:-}" && -f "$modelfile_path" ]] && rm -f "$modelfile_path"
    exit "$exit_code"
}
trap cleanup EXIT INT TERM

#############################################
# Source Library Modules
#############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/tui-advanced.sh"
source "$SCRIPT_DIR/lib/hardware-config.sh"
source "$SCRIPT_DIR/lib/interactive.sh"
source "$SCRIPT_DIR/lib/validation.sh"
source "$SCRIPT_DIR/lib/installation.sh"
source "$SCRIPT_DIR/lib/launchagent.sh"
source "$SCRIPT_DIR/lib/model-setup.sh"
source "$SCRIPT_DIR/lib/opencode-config.sh"
source "$SCRIPT_DIR/lib/jetbrains-config.sh"
source "$SCRIPT_DIR/lib/verification.sh"

#############################################
# Configuration
#############################################

# Detect hardware (batched for efficiency - single subprocess call)
read -r DETECTED_M_CHIP DETECTED_RAM_GB DETECTED_CPU_CORES <<< "$(detect_hardware_profile)"

# Model configuration (can be overridden via --model flag)
RECOMMENDED_MODEL=$(recommend_model "$DETECTED_RAM_GB")
GEMMA_MODEL="${GEMMA_MODEL:-}"  # Will be set after arg parsing
AUTO_MODE=false

# LaunchAgent configuration
LAUNCHAGENT_LABEL="com.ollama.custom"
LAUNCHAGENT_PLIST="$HOME/Library/LaunchAgents/${LAUNCHAGENT_LABEL}.plist"

# Custom model name will be set after model selection
CUSTOM_MODEL_NAME=""

# IDE tool selection (will be set after user selection)
IDE_TOOLS=()

# Ollama configuration
OLLAMA_HOST="http://localhost:11434"

#############################################
# Parse Arguments
#############################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            echo "Gemma4 + OpenCode Setup Script"
            echo "Version: 2.1.0 (modular architecture with improved UI)"
            echo "Compatible models: gemma4:e2b, gemma4:latest, gemma4:26b, gemma4:31b"
            echo "Requirements: macOS 10.14+, Homebrew, 12GB+ RAM"
            exit 0
            ;;
        --model)
            validate_model_name "$2" || exit 1
            GEMMA_MODEL="$2"
            shift 2
            ;;
        --auto)
            AUTO_MODE=true
            shift
            ;;
        -v|--verbose)
            export VERBOSITY_LEVEL=2
            shift
            ;;
        -q|--quiet)
            export VERBOSITY_LEVEL=0
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

#############################################
# IDE Tool Selection (Must happen FIRST)
#############################################

# Ask which IDE tool(s) to configure (skip in auto mode - default to OpenCode only)
if [[ "$AUTO_MODE" != true ]]; then
    select_ide_tools
else
    IDE_TOOLS=("opencode")  # Default to OpenCode in auto mode
fi

#############################################
# Interactive Model Selection
#############################################

# Set model if not specified
if [[ -z "$GEMMA_MODEL" ]]; then
    if [[ "$AUTO_MODE" != true ]]; then
        # Interactive mode: show hardware and let user select
        display_hardware_and_recommendation
        select_model_interactive "true"  # Pass true to show default
    else
        # Auto mode: use recommended model
        GEMMA_MODEL="$RECOMMENDED_MODEL"
    fi
fi

# Extract model size for dynamic configuration
MODEL_SIZE=$(get_model_size "$GEMMA_MODEL")

#############################################
# CodeGemma Selection (for JetBrains FIM)
#############################################

# If JetBrains is selected, also need a FIM model for code completion
CODEGEMMA_MODEL=""
if [[ " ${IDE_TOOLS[*]} " =~ " jetbrains " ]]; then
    if [[ "$AUTO_MODE" != true ]]; then
        select_codegemma_interactive
    else
        # Auto mode: use recommended CodeGemma based on RAM
        CODEGEMMA_MODEL=$(recommend_codegemma "$DETECTED_RAM_GB")
    fi
fi

#############################################
# Calculate Hardware-Optimized Settings
#############################################

METAL_MEMORY=$(calculate_metal_memory "$DETECTED_RAM_GB")
NUM_PARALLEL=$(calculate_num_parallel "$DETECTED_RAM_GB")
RECOMMENDED_CONTEXT=$(calculate_context_length "$DETECTED_RAM_GB" "$MODEL_SIZE")
CONTEXT_LENGTH=$RECOMMENDED_CONTEXT  # Default to recommended

#############################################
# Interactive Context & Naming
#############################################

# Ask about context window (skip in auto mode)
if [[ "$AUTO_MODE" != true ]]; then
    select_context_window
fi

NUM_CTX=$CONTEXT_LENGTH  # Ollama uses num_ctx parameter name

# Ask about custom model name (skip in auto mode)
if [[ "$AUTO_MODE" != true ]]; then
    select_custom_name
else
    # Auto mode: use default naming with context
    CUSTOM_MODEL_NAME=$(generate_custom_model_name "$MODEL_SIZE" "$CONTEXT_LENGTH")
fi

#############################################
# Validate GPU Compatibility
#############################################

validate_and_prompt_gpu_fit

#############################################
# Main Installation Flow
#############################################

main() {
    #############################################
    # Configuration Preview
    #############################################

    if [[ "$AUTO_MODE" != true ]] && [[ $VERBOSITY_LEVEL -ge 1 ]]; then
        # Format IDE tools for display
        local ide_display=""
        if [[ " ${IDE_TOOLS[*]} " =~ " opencode " ]] && [[ " ${IDE_TOOLS[*]} " =~ " jetbrains " ]]; then
            ide_display="OpenCode + JetBrains"
        elif [[ " ${IDE_TOOLS[*]} " =~ " opencode " ]]; then
            ide_display="OpenCode"
        elif [[ " ${IDE_TOOLS[*]} " =~ " jetbrains " ]]; then
            ide_display="JetBrains AI Assistant"
        else
            ide_display="None"
        fi

        # Get model sizes
        local gemma_size
        gemma_size=$(get_model_specs "$MODEL_SIZE" | awk '{print $1}')

        local codegemma_size=""
        if [[ -n "$CODEGEMMA_MODEL" ]]; then
            # Use registry lookup for FIM model size (supports all FIM models)
            codegemma_size=$(get_fim_model_weight_gb "$CODEGEMMA_MODEL")
        fi

        # Show preview
        show_config_preview \
            "$DETECTED_M_CHIP" \
            "$DETECTED_RAM_GB" \
            "$DETECTED_CPU_CORES" \
            "$GEMMA_MODEL" \
            "$gemma_size" \
            "${CODEGEMMA_MODEL:-}" \
            "${codegemma_size:-}" \
            "$ide_display"

        # Get confirmation
        while true; do
            read -p "Your choice [C/E/Q]: " -n 1 -r choice
            echo ""
            case "$choice" in
                [Cc])
                    break
                    ;;
                [Ee])
                    echo "Configuration editing not yet implemented. Please restart the script."
                    exit 0
                    ;;
                [Qq])
                    echo "Setup cancelled."
                    exit 0
                    ;;
                *)
                    echo "Invalid choice. Press C to continue, E to edit, or Q to quit."
                    ;;
            esac
        done
    fi

    #############################################
    # Installation Header
    #############################################

    if [[ $VERBOSITY_LEVEL -ge 2 ]]; then
        # Verbose: show traditional header
        print_header "Gemma4 + OpenCode Setup for Teams"
        print_info "Hardware-optimized setup with dynamic configuration"
        print_info "This script is idempotent - safe to run multiple times"
        echo
    fi
    # Normal/Quiet: no header (config preview already shown)

    # Platform validation (silent unless errors)
    check_macos > /dev/null 2>&1 || check_macos
    check_apple_silicon > /dev/null 2>&1 || check_apple_silicon
    check_homebrew > /dev/null 2>&1 || check_homebrew

    # Installation
    install_ollama
    install_opencode

    # Configuration (uses dynamic values based on hardware)
    create_launchagent

    # Model setup
    pull_model
    create_custom_model

    # Pull CodeGemma if JetBrains is selected
    if [[ " ${IDE_TOOLS[*]} " =~ " jetbrains " ]]; then
        pull_codegemma
    fi

    # IDE tool setup
    for tool in "${IDE_TOOLS[@]}"; do
        case "$tool" in
            opencode)
                configure_opencode
                ;;
            jetbrains)
                configure_jetbrains
                ;;
            *)
                print_warning "Unknown IDE tool: $tool (skipping)"
                ;;
        esac
    done

    # Verification and instructions
    verify_setup
    print_usage_instructions

    # Interactive final menu (only in interactive mode)
    if [[ "$AUTO_MODE" != true ]] && [[ $VERBOSITY_LEVEL -ge 1 ]]; then
        # Format IDE tools for display
        local ide_display=""
        if [[ " ${IDE_TOOLS[*]} " =~ " opencode " ]] && [[ " ${IDE_TOOLS[*]} " =~ " jetbrains " ]]; then
            ide_display="OpenCode + JetBrains"
        elif [[ " ${IDE_TOOLS[*]} " =~ " opencode " ]]; then
            ide_display="OpenCode"
        elif [[ " ${IDE_TOOLS[*]} " =~ " jetbrains " ]]; then
            ide_display="JetBrains"
        else
            ide_display="None"
        fi

        show_final_menu "$CUSTOM_MODEL_NAME" "$ide_display"
    fi
}

# Run main function
main "$@"
