#!/bin/bash
# lib/model-setup.sh - Gemma4 model download and custom model creation
#
# Provides:
# - Model pulling from Ollama registry
# - Custom model creation with Modelfile
# - Model verification

set -euo pipefail

# Pull Gemma4 model from Ollama registry
#
# Globals read:
#   - GEMMA_MODEL: Model name (e.g., "gemma4:31b")
#   - DETECTED_RAM_GB: Detected RAM for validation
pull_model() {
    print_step "4/6" "Pulling Gemma4 Model"

    # Check if model already exists (using cached list)
    if get_ollama_list | grep -q "^${GEMMA_MODEL}"; then
        print_status "$GEMMA_MODEL (already downloaded)"
        return 0
    fi

    # Get model specifications from data structure
    local model_variant="${GEMMA_MODEL#*:}"
    local specs
    specs=$(get_model_specs "$model_variant")

    if [[ -n "$specs" ]]; then
        # Parse specifications
        read -r size_gb context_k min_ram_gb <<< "$specs"

        if [[ $VERBOSITY_LEVEL -ge 2 ]]; then
            print_verbose "Model: ${GEMMA_MODEL} (${size_gb}GB download, ${context_k}K context)"
            print_verbose "Recommended RAM: ${min_ram_gb}GB+"
            if [[ $DETECTED_RAM_GB -lt $min_ram_gb ]]; then
                print_warning "Your system has ${DETECTED_RAM_GB}GB RAM - ${min_ram_gb}GB+ recommended"
            fi
        else
            print_info "Downloading ${GEMMA_MODEL} (${size_gb}GB)..."
        fi
    else
        print_info "Downloading ${GEMMA_MODEL}..."
    fi

    # Use spinner for download
    if [[ $VERBOSITY_LEVEL -eq 1 ]]; then
        start_spinner "Downloading ${GEMMA_MODEL}..."
        if ollama pull "$GEMMA_MODEL" > /dev/null 2>&1; then
            stop_spinner
            print_status "$GEMMA_MODEL downloaded"
            clear_ollama_cache
        else
            stop_spinner
            print_error "Failed to pull model $GEMMA_MODEL"
            draw_error_box \
                "Model Download Failed" \
                "Failed to download $GEMMA_MODEL from Ollama registry.

Possible causes:
  • Network connection issues
  • Insufficient disk space
  • Ollama service not running

Check logs for details." \
                "Retry download|Check disk space|View logs|Skip this model"

            read -p "Select action [1-4]: " -r error_choice
            case "$error_choice" in
                1) # Retry
                    pull_model
                    ;;
                2) # Check disk
                    df -h /
                    read -p "Press Enter to continue..."
                    exit 1
                    ;;
                3) # View logs
                    if [[ -f "$HOME/.ollama/logs/server.log" ]]; then
                        tail -50 "$HOME/.ollama/logs/server.log"
                    fi
                    exit 1
                    ;;
                *)
                    exit 1
                    ;;
            esac
        fi
    else
        # Verbose mode: show full output
        if ollama pull "$GEMMA_MODEL" 2>&1 | grep -E "pulling|success" || true; then
            print_status "$GEMMA_MODEL downloaded"
            clear_ollama_cache
        else
            print_error "Failed to pull model $GEMMA_MODEL"
            exit 1
        fi
    fi
}

# Create custom model with optimized context window
#
# Globals read:
#   - CUSTOM_MODEL_NAME: Name for custom model
#   - GEMMA_MODEL: Base model name
#   - NUM_CTX: Context length
#   - DETECTED_RAM_GB: Detected RAM
#   - AUTO_MODE: Whether in auto mode
create_custom_model() {
    print_step "5/6" "Creating Custom Model"

    # Check if custom model already exists (using cached list)
    if get_ollama_list | grep -q "^${CUSTOM_MODEL_NAME}"; then
        print_status "Custom model $CUSTOM_MODEL_NAME already exists"

        # Ask if user wants to recreate it (skip in auto mode)
        if [[ "$AUTO_MODE" != true ]]; then
            read -p "Recreate $CUSTOM_MODEL_NAME with latest settings? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                return 0
            fi
        else
            print_info "Auto mode: skipping recreation of existing model"
            return 0
        fi

        print_info "Removing existing $CUSTOM_MODEL_NAME..."
        ollama rm "$CUSTOM_MODEL_NAME" 2>/dev/null || true
        clear_ollama_cache  # Invalidate cache after removing model
    fi

    # Format context window for display
    local context_display
    context_display=$(format_context_display "$NUM_CTX")

    print_info "Creating $CUSTOM_MODEL_NAME with ${context_display} token context window..."
    print_info "Configuration optimized for ${DETECTED_RAM_GB}GB RAM"

    # Create temporary Modelfile
    local modelfile_path
    modelfile_path=$(mktemp "/tmp/Modelfile.XXXXXX") || {
        print_error "Failed to create temporary file"
        exit 1
    }
    cat > "$modelfile_path" << EOF
FROM ${GEMMA_MODEL}

# Set context window optimized for ${DETECTED_RAM_GB}GB RAM
PARAMETER num_ctx ${NUM_CTX}

# Optimize for code generation
PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER top_k 40

# System prompt optimized for coding
SYSTEM """
You are a helpful AI coding assistant. You provide clear, accurate, and well-documented code solutions.
Focus on code quality, best practices, and security.
"""
EOF

    # Create the custom model
    if ollama create "$CUSTOM_MODEL_NAME" -f "$modelfile_path"; then
        print_status "Custom model $CUSTOM_MODEL_NAME created successfully"
        print_status "Context: ${context_display} tokens (optimized for your ${DETECTED_RAM_GB}GB RAM)"
        rm "$modelfile_path"
        clear_ollama_cache  # Invalidate cache after creating new model
    else
        print_error "Failed to create custom model $CUSTOM_MODEL_NAME"
        rm "$modelfile_path"
        exit 1
    fi

    # Verify the model
    verify_custom_model
}

# Pull CodeGemma model for JetBrains AI Assistant (FIM support)
#
# Globals read:
#   - CODEGEMMA_MODEL: CodeGemma model name (e.g., "codegemma:7b")
#   - DETECTED_RAM_GB: Detected RAM for validation
pull_codegemma() {
    # Check if CodeGemma model variable is set
    if [[ -z "$CODEGEMMA_MODEL" ]]; then
        return 0
    fi

    print_step "5.5/6" "Pulling CodeGemma (FIM)"

    # Check if model already exists
    if get_ollama_list | grep -q "^${CODEGEMMA_MODEL}"; then
        print_status "$CODEGEMMA_MODEL (already downloaded)"
        return 0
    fi

    # Get model size info
    local model_variant="${CODEGEMMA_MODEL#*:}"
    local size_info=""
    case "$model_variant" in
        2b)
            size_info="1.6GB"
            ;;
        7b)
            size_info="5.0GB"
            ;;
    esac

    if [[ $VERBOSITY_LEVEL -eq 1 ]]; then
        start_spinner "Downloading ${CODEGEMMA_MODEL} (${size_info})..."
        if ollama pull "$CODEGEMMA_MODEL" > /dev/null 2>&1; then
            stop_spinner
            print_status "$CODEGEMMA_MODEL downloaded"
            clear_ollama_cache
        else
            stop_spinner
            print_error "Failed to pull model $CODEGEMMA_MODEL"
            exit 1
        fi
    else
        print_info "Downloading ${CODEGEMMA_MODEL} (${size_info})..."
        if ollama pull "$CODEGEMMA_MODEL" 2>&1 | grep -E "pulling|success" || true; then
            print_status "$CODEGEMMA_MODEL downloaded"
            clear_ollama_cache
        else
            print_error "Failed to pull model $CODEGEMMA_MODEL"
            exit 1
        fi
    fi
}

# Verify custom model exists and is accessible
#
# Globals read:
#   - CUSTOM_MODEL_NAME: Name of custom model to verify
verify_custom_model() {
    print_info "Verifying model configuration..."
    if ollama show "$CUSTOM_MODEL_NAME" &> /dev/null; then
        print_status "Model verified: $CUSTOM_MODEL_NAME"
    else
        print_error "Model verification failed"
        exit 1
    fi
}
