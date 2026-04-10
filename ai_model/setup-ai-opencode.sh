#!/bin/bash
# setup-ai-opencode.sh - Idempotent setup for AI Models + IDE tools via Ollama (Homebrew)
#
# One-stop shop for team deployment:
# - Installs Ollama and OpenCode via Homebrew
# - Dynamically optimizes configuration based on detected hardware
# - Pulls and configures AI models (Gemma4, Phi-4, Llama 3.1, Mistral, Granite) with native context windows
# - Sets up IDE tool integration (OpenCode and/or JetBrains AI Assistant)
# - For JetBrains: Includes CodeGemma for FIM (Fill-In-Middle) code completion
#
# Safe to run multiple times - idempotent design
#
# Available Models:
# - See lib/model-registry.sh for complete list of supported models
# - Includes: Gemma4, Phi-4, Llama 3.1, Mistral, CodeGemma, IBM Granite Code
# - Run with --model flag to specify a model, or use interactive selection
#
# Usage: ./setup-ai-opencode.sh [OPTIONS]
#
# Options:
#   --model MODEL    Specify model (auto-detected by default)
#                    Format: family:variant (e.g., "gemma4:31b", "phi4-reasoning:latest")
#                    See: lib/model-registry.sh for full list of available models
#   --auto           Skip all interactive prompts, use auto-detected defaults
#   -v, --verbose    Show detailed output (all steps and debug info)
#   -q, --quiet      Minimal output (only errors and final summary)
#
# Requirements:
#   - macOS 10.14+ (Mojave or later)
#   - Apple Silicon (M1/M2/M3/M4/M5 recommended, Intel supported but slower)
#   - Homebrew installed
#   - Minimum RAM varies by model (8GB-48GB+, script will recommend best fit)

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
source "$SCRIPT_DIR/lib/model-registry.sh"
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
SELECTED_MODEL="${SELECTED_MODEL:-}"  # Will be set after arg parsing
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
            echo "AI Model + OpenCode Setup Script"
            echo "Version: 3.0.0 (multi-model support with registry)"
            echo "Supported models: Gemma4, Phi-4, Llama 3.1, Mistral, CodeGemma, IBM Granite"
            echo "See: lib/model-registry.sh for full list"
            echo "Requirements: macOS 10.14+, Homebrew, 8GB+ RAM"
            exit 0
            ;;
        --model)
            validate_model_name "$2" || exit 1
            SELECTED_MODEL="$2"
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
if [[ -z "$SELECTED_MODEL" ]]; then
    if [[ "$AUTO_MODE" != true ]]; then
        # Interactive mode: show hardware and let user select
        display_hardware_and_recommendation
        select_model_interactive "true"  # Pass true to show default
    else
        # Auto mode: use recommended model
        SELECTED_MODEL="$RECOMMENDED_MODEL"
    fi
fi

# Extract model size for dynamic configuration
MODEL_VARIANT=$(get_model_variant "$SELECTED_MODEL")

#############################################
# FIM Model Selection (for JetBrains)
#############################################

# If JetBrains is selected, also need a FIM model for code completion
CODESELECTED_MODEL=""
if [[ " ${IDE_TOOLS[*]} " =~ " jetbrains " ]]; then
    if [[ "$AUTO_MODE" != true ]]; then
        select_fim_model_interactive
    else
        # Auto mode: use recommended FIM model based on RAM
        CODESELECTED_MODEL=$(recommend_fim_model "$DETECTED_RAM_GB")
    fi
fi

#############################################
# Calculate Hardware-Optimized Settings
#############################################

METAL_MEMORY=$(calculate_metal_memory "$DETECTED_RAM_GB")
NUM_PARALLEL=$(calculate_num_parallel "$DETECTED_RAM_GB")
RECOMMENDED_CONTEXT=$(calculate_context_length "$DETECTED_RAM_GB" "$SELECTED_MODEL")
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
    CUSTOM_MODEL_NAME=$(generate_custom_model_name "$SELECTED_MODEL" "$CONTEXT_LENGTH")
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
        gemma_size=$(get_registry_model_weight_gb "$SELECTED_MODEL")

        local codegemma_size=""
        if [[ -n "$CODESELECTED_MODEL" ]]; then
            # Use registry lookup for FIM model size (supports all FIM models)
            codegemma_size=$(get_fim_model_weight_gb "$CODESELECTED_MODEL")
        fi

        # Show preview
        show_config_preview \
            "$DETECTED_M_CHIP" \
            "$DETECTED_RAM_GB" \
            "$DETECTED_CPU_CORES" \
            "$SELECTED_MODEL" \
            "$gemma_size" \
            "${CODESELECTED_MODEL:-}" \
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

    # Pre-load model into GPU memory for instant first response
    # Check if model is already loaded to avoid redundant warmup
    if ollama ps 2>/dev/null | grep -q "^${CUSTOM_MODEL_NAME}[[:space:]]"; then
        print_status "Model already loaded in GPU memory"
    else
        # In interactive mode, ask user; in auto mode, always warmup
        local should_warmup=true
        if [[ "$AUTO_MODE" != true ]]; then
            read -p "Pre-load model into GPU memory now for instant first response? (Y/n) " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                should_warmup=false
                print_info "Skipping warmup - model will load on first request (~5-10s delay)"
            fi
        fi

        if [[ "$should_warmup" == true ]]; then
            warmup_model
        fi
    fi

    # Pull FIM model if JetBrains is selected
    if [[ " ${IDE_TOOLS[*]} " =~ " jetbrains " ]]; then
        pull_fim_model
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
