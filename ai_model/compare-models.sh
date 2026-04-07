#!/bin/bash
# compare-models.sh - Display installed Ollama models in table format
# Shows model metadata including family, size, RAM requirements, and quantization

# Get script directory for sourcing libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/model-families.sh"
source "$SCRIPT_DIR/lib/ollama-setup.sh"

#############################################
# Helper Functions
#############################################

# Extract family name from model name
get_family_from_model() {
    local model="$1"

    if [[ "$model" =~ ^llama ]]; then
        echo "Llama"
    elif [[ "$model" =~ ^codestral ]]; then
        echo "Mistral"
    elif [[ "$model" =~ ^mistral ]]; then
        echo "Mistral"
    elif [[ "$model" =~ ^phi ]]; then
        echo "Phi"
    elif [[ "$model" =~ ^gemma ]]; then
        echo "Gemma"
    else
        echo "Other"
    fi
}

# Extract quantization from model name
get_quantization_from_model() {
    local model="$1"

    if [[ "$model" =~ q4_K_M|Q4_K_M ]]; then
        echo "Q4_K_M"
    elif [[ "$model" =~ q8_0|Q8_0 ]]; then
        echo "Q8_0"
    elif [[ "$model" =~ q4_0|Q4_0 ]]; then
        echo "Q4_0"
    elif [[ "$model" =~ q5_K_M|Q5_K_M ]]; then
        echo "Q5_K_M"
    elif [[ "$model" =~ q6_K|Q6_K ]]; then
        echo "Q6_K"
    else
        echo "-"
    fi
}

# Get model metadata from model-families.sh
get_metadata_from_families() {
    local model="$1"
    local field="$2"

    # Search through all model families
    local -a all_models=()
    all_models+=("${LLAMA_MODELS[@]}")
    all_models+=("${MISTRAL_MODELS[@]}")
    all_models+=("${PHI_MODELS[@]}")
    all_models+=("${GEMMA_MODELS[@]}")

    for model_line in "${all_models[@]}"; do
        local model_name
        model_name=$(get_model_info "$model_line" "name")

        # Match model name (case insensitive, handle variations)
        local model_lower model_name_lower
        model_lower=$(echo "$model" | tr '[:upper:]' '[:lower:]')
        model_name_lower=$(echo "$model_name" | tr '[:upper:]' '[:lower:]')
        if [[ "$model_lower" == "$model_name_lower" ]]; then
            get_model_info "$model_line" "$field"
            return 0
        fi
    done

    # Return default if not found
    echo "-"
}

# Check if model is currently active (loaded in memory)
is_model_active() {
    local model="$1"

    # Check if server is running
    if [[ ! -f "$OLLAMA_PID_FILE" ]] || ! ps -p "$(cat "$OLLAMA_PID_FILE" 2>/dev/null)" > /dev/null 2>&1; then
        echo ""
        return
    fi

    # Try to get running models from API
    local running_models
    running_models=$(curl -s "http://127.0.0.1:$PORT/api/ps" 2>/dev/null | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | head -1)

    if [[ -n "$running_models" ]] && [[ "$running_models" == *"$model"* ]]; then
        echo "✓"
    else
        echo ""
    fi
}

#############################################
# Main Function
#############################################

compare_models() {
    print_header "Installed Models Comparison"

    # Check if Ollama server is running
    if [[ ! -f "$OLLAMA_PID_FILE" ]] || ! ps -p "$(cat "$OLLAMA_PID_FILE" 2>/dev/null)" > /dev/null 2>&1; then
        print_warning "Ollama server is not running. Start it with: start_ollama_server"
        echo ""
    fi

    # Check if Ollama binary exists
    if [[ ! -f "$OLLAMA_BUILD_DIR/ollama" ]]; then
        print_error "Ollama binary not found at $OLLAMA_BUILD_DIR/ollama"
        print_info "Run build_ollama first to build Ollama"
        return 1
    fi

    # Get installed models
    local models_output
    models_output=$("$OLLAMA_BUILD_DIR/ollama" list 2>/dev/null)

    if [[ -z "$models_output" ]]; then
        print_warning "No models found or Ollama server is not accessible"
        print_info "Pull models with: pull_model <model_name>"
        return 0
    fi

    # Parse model names (skip header line)
    local models
    models=$(echo "$models_output" | tail -n +2 | awk '{print $1}')

    if [[ -z "$models" ]]; then
        print_warning "No models installed"
        print_info "Pull models with: pull_model <model_name>"
        return 0
    fi

    # Display table header
    printf "┌─────────────────────────────┬────────┬─────────┬────────┬──────────┬────────┐\n"
    printf "│ %-27s │ %-6s │ %-7s │ %-6s │ %-8s │ %-6s │\n" \
        "Model" "Family" "Size" "RAM" "Quant" "Active"
    printf "├─────────────────────────────┼────────┼─────────┼────────┼──────────┼────────┤\n"

    # Process each model
    while IFS= read -r model; do
        [[ -z "$model" ]] && continue

        # Extract metadata
        local family
        family=$(get_family_from_model "$model")

        local quant
        quant=$(get_quantization_from_model "$model")

        # Try to get size and RAM from model families
        local size ram
        size=$(get_metadata_from_families "$model" "size")
        ram=$(get_metadata_from_families "$model" "min_ram")

        # Format size and ram with GB suffix if numeric
        if [[ "$size" != "-" ]] && [[ "$size" =~ ^[0-9]+$ ]]; then
            size="${size}GB"
        fi
        if [[ "$ram" != "-" ]] && [[ "$ram" =~ ^[0-9]+$ ]]; then
            ram="${ram}GB"
        fi

        # Check if active
        local active
        active=$(is_model_active "$model")

        # Truncate model name if too long
        local display_model="$model"
        if [[ ${#display_model} -gt 27 ]]; then
            display_model="${display_model:0:24}..."
        fi

        # Print row
        printf "│ %-27s │ %-6s │ %-7s │ %-6s │ %-8s │ %-6s │\n" \
            "$display_model" "$family" "$size" "$ram" "$quant" "$active"
    done <<< "$models"

    # Display table footer
    printf "└─────────────────────────────┴────────┴─────────┴────────┴──────────┴────────┘\n"

    # Show quantization guide
    echo ""
    print_info "Quantization Guide:"
    echo "  Q4_K_M: Smaller files, 95-98% quality, faster inference"
    echo "  Q8_0:   Larger files, 99%+ quality, best accuracy"
    echo "  Q4_0:   Basic quantization, smaller than Q4_K_M"
    echo "  Q5_K_M: Medium quality, balanced"
    echo "  Q6_K:   High quality, close to Q8_0"

    # Show system info
    echo ""
    print_info "System Information:"
    echo "  Chip: $M_CHIP"
    echo "  GPU Cores: $GPU_CORES"
    echo "  Total RAM: ${TOTAL_RAM_GB}GB (Tier: $RAM_TIER)"
}

#############################################
# Script Execution
#############################################

# If script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    compare_models "$@"
fi
