#!/bin/bash
# setup-gemma4-opencode.sh - Idempotent setup for Gemma4 + OpenCode via Ollama (Homebrew)
#
# One-stop shop for team deployment:
# - Installs Ollama and OpenCode via Homebrew
# - Dynamically optimizes configuration based on detected hardware
# - Pulls and configures Gemma4 models with native context windows
# - Sets up OpenCode integration
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
# Usage: ./setup-gemma4-opencode.sh [--model MODEL] [--auto]
#
# Options:
#   --model MODEL    Specify Gemma4 variant (auto-detected by default)
#                    Available: gemma4:e2b, gemma4:latest, gemma4:26b, gemma4:31b
#                    See: https://ollama.com/library/gemma4/tags
#   --auto           Skip all interactive prompts, use auto-detected defaults
#
# Requirements:
#   - macOS with Apple Silicon (M1 or later recommended)
#   - Homebrew installed
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
source "$SCRIPT_DIR/lib/hardware-config.sh"
source "$SCRIPT_DIR/lib/interactive.sh"
source "$SCRIPT_DIR/lib/validation.sh"
source "$SCRIPT_DIR/lib/installation.sh"
source "$SCRIPT_DIR/lib/launchagent.sh"
source "$SCRIPT_DIR/lib/model-setup.sh"
source "$SCRIPT_DIR/lib/opencode-config.sh"
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

# Ollama configuration
OLLAMA_HOST="http://localhost:11434"

#############################################
# Parse Arguments
#############################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --model)
            validate_model_name "$2" || exit 1
            GEMMA_MODEL="$2"
            shift 2
            ;;
        --auto)
            AUTO_MODE=true
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
# Interactive Model Selection
#############################################

# Set model if not specified
if [[ -z "$GEMMA_MODEL" ]]; then
    GEMMA_MODEL="$RECOMMENDED_MODEL"

    # Show recommendation to user (unless --auto mode)
    if [[ "$AUTO_MODE" != true ]]; then
        display_hardware_and_recommendation

        read -p "Use recommended model $RECOMMENDED_MODEL? (Y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            echo ""
            select_model_interactive
        fi
    fi
fi

# Extract model size for dynamic configuration
MODEL_SIZE=$(get_model_size "$GEMMA_MODEL")

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
    print_header "Gemma4 + OpenCode Setup for Teams"
    print_info "Hardware-optimized setup with dynamic configuration"
    print_info "This script is idempotent - safe to run multiple times"
    echo

    # Platform validation
    check_macos
    check_apple_silicon
    check_homebrew

    # Installation
    install_ollama
    install_opencode

    # Configuration (uses dynamic values based on hardware)
    create_launchagent

    # Model setup
    pull_model
    create_custom_model

    # OpenCode setup
    configure_opencode

    # Verification and instructions
    verify_setup
    print_usage_instructions
}

# Run main function
main "$@"
