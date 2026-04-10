#!/bin/bash
# lib/interactive.sh - Interactive user selection functions
#
# Provides:
# - Hardware detection and model recommendation display
# - Interactive model selection from available models
# - Context window selection with GPU fit visualization
# - Custom model naming with validation

set -euo pipefail

#############################################
# Hardware Detection & Model Recommendation
#############################################

# Display hardware detection and model recommendation
# Shows available models with GPU fit indicators
#
# Globals read:
#   - DETECTED_M_CHIP: Detected chip model
#   - DETECTED_RAM_GB: Detected RAM in GB
#   - DETECTED_CPU_CORES: Detected CPU cores
#   - RECOMMENDED_MODEL: Recommended model
display_hardware_and_recommendation() {
    print_header "Hardware Detection & Model Recommendation"

    if [[ $VERBOSITY_LEVEL -ge 2 ]]; then
        # Verbose: show all details
        echo -e "${BLUE}Detected Hardware:${NC}"
        echo "  • Chip:      $DETECTED_M_CHIP"
        echo "  • RAM:       ${DETECTED_RAM_GB}GB"
        echo "  • CPU Cores: $DETECTED_CPU_CORES"
        echo ""
        echo -e "${GREEN}Recommended Model: $RECOMMENDED_MODEL${NC}"
        echo ""
    else
        # Normal: compact display
        echo -e "  ${GRAY}Hardware: $DETECTED_M_CHIP / ${DETECTED_RAM_GB}GB RAM / $DETECTED_CPU_CORES cores${NC}"
        echo -e "  ${GREEN}Recommended: $RECOMMENDED_MODEL${NC}"
        echo ""
    fi

    # Show available options with GPU compatibility indicators
    if [[ $VERBOSITY_LEVEL -ge 1 ]]; then
        echo "Available Gemma4 models (✓ = 100% GPU, ⚠ = CPU/GPU split):"
        echo ""
    fi

    # Check each model's GPU fit
    local test_31b_context test_26b_context test_latest_context test_e2b_context
    test_31b_context=$(calculate_context_length "$DETECTED_RAM_GB" "31b")
    test_26b_context=$(calculate_context_length "$DETECTED_RAM_GB" "26b")
    test_latest_context=$(calculate_context_length "$DETECTED_RAM_GB" "latest")
    test_e2b_context=$(calculate_context_length "$DETECTED_RAM_GB" "e2b")

    # Display models based on RAM tiers (ascending order: smallest to largest)
    if [[ $DETECTED_RAM_GB -ge 48 ]]; then
        display_model_gpu_fit "e2b" "$test_e2b_context"
        display_model_gpu_fit "latest" "$test_latest_context"
        display_model_gpu_fit "26b" "$test_26b_context"
        display_model_gpu_fit "31b" "$test_31b_context"
    elif [[ $DETECTED_RAM_GB -ge 32 ]]; then
        display_model_gpu_fit "e2b" "$test_e2b_context"
        display_model_gpu_fit "latest" "$test_latest_context"
        display_model_gpu_fit "26b" "$test_26b_context"
    elif [[ $DETECTED_RAM_GB -ge 16 ]]; then
        display_model_gpu_fit "e2b" "$test_e2b_context"
        display_model_gpu_fit "latest" "$test_latest_context"
    else
        display_model_gpu_fit "e2b" "$test_e2b_context"
    fi
    echo ""
    print_info "Models marked with ⚠ will use CPU fallback (slower performance)"
    echo ""
}

# Helper: Display single model with GPU fit indicator
display_model_gpu_fit() {
    local model_size=$1
    local context=$2

    local model_weight
    case "$model_size" in
        31b) model_weight="19GB" ;;
        26b) model_weight="17GB" ;;
        latest) model_weight="10GB" ;;
        e2b) model_weight="7GB" ;;
        *) model_weight="unknown" ;;
    esac

    if validate_gpu_fit "$DETECTED_RAM_GB" "$model_size" "$context"; then
        echo "  ✓ gemma4:$model_size    ($model_weight model, $((context/1024))K context, 100% GPU)"
    else
        echo "  ⚠ gemma4:$model_size    ($model_weight model, $((context/1024))K context, CPU/GPU split - not recommended)"
    fi
}

#############################################
# Model Selection
#############################################

# Interactive model selection from available models
# Sets GEMMA_MODEL global based on user choice
#
# Globals read:
#   - DETECTED_RAM_GB: Detected RAM in GB
# Globals set:
#   - GEMMA_MODEL: Selected model name (e.g., "gemma4:31b")
select_model_interactive() {
    print_header "Model Selection"

    # Build arrays of available models with their specs (ascending order: smallest to largest)
    local -a models=("gemma4:e2b" "gemma4:latest" "gemma4:26b" "gemma4:31b")
    local -a model_sizes=("e2b" "latest" "26b" "31b")
    local -a model_weights=("7GB" "10GB" "17GB" "19GB")

    echo "Select a model from the list below:"
    echo ""

    # Display models with GPU fit status
    for i in "${!models[@]}"; do
        local idx=$((i + 1))
        local model="${models[$i]}"
        local size="${model_sizes[$i]}"
        local weight="${model_weights[$i]}"

        # Get context for this model at current RAM
        local context
        context=$(calculate_context_length "$DETECTED_RAM_GB" "$size")
        local context_k=$((context / 1024))

        # Check if it fits on GPU
        if validate_gpu_fit "$DETECTED_RAM_GB" "$size" "$context"; then
            echo -e "  ${GREEN}$idx) $model${NC} ($weight model, ${context_k}K context, 100% GPU)"
        else
            echo -e "  ${YELLOW}$idx) $model${NC} ($weight model, ${context_k}K context, CPU/GPU split)"
        fi
    done

    echo ""

    # Get user selection
    while true; do
        read -r -p "Enter selection (1-4): " selection

        # Validate numeric input in range 1-4
        if [[ "$selection" =~ ^[1-4]$ ]]; then
            local idx=$((selection - 1))
            GEMMA_MODEL="${models[$idx]}"
            print_status "Selected: $GEMMA_MODEL"
            break
        else
            print_error "Invalid selection. Please enter a number between 1 and 4."
        fi
    done
}

#############################################
# CodeGemma Selection (for JetBrains FIM)
#############################################

# Interactive CodeGemma model selection for JetBrains AI Assistant
# CodeGemma models support Fill-In-Middle (FIM) for code completion
#
# Globals read:
#   - DETECTED_RAM_GB: Detected RAM in GB
# Globals set:
#   - CODEGEMMA_MODEL: Selected CodeGemma model (e.g., "codegemma:7b")
select_codegemma_interactive() {
    print_header "CodeGemma Selection (for JetBrains AI Assistant)"

    echo -e "${BLUE}JetBrains AI Assistant needs a FIM-capable model for code completion${NC}"
    echo ""
    echo "CodeGemma models are optimized for:"
    echo "  • Fill-In-Middle (FIM) code completion"
    echo "  • Inline suggestions and auto-completion"
    echo "  • Code infilling and refactoring"
    echo ""

    # Build arrays of available CodeGemma models
    local -a models=("codegemma:2b" "codegemma:7b")
    local -a model_sizes=("2b" "7b")
    local -a model_weights=("1.6GB" "5.0GB")
    local -a context_sizes=("8K" "8K")
    local -a descriptions=(
        "Smallest, fastest (good for code completion)"
        "Larger, more accurate (recommended for 16GB+ RAM)"
    )

    echo "Select a CodeGemma model:"
    echo ""

    # Display models with recommendations
    for i in "${!models[@]}"; do
        local idx=$((i + 1))
        local model="${models[$i]}"
        local weight="${model_weights[$i]}"
        local context="${context_sizes[$i]}"
        local desc="${descriptions[$i]}"

        # Recommend based on RAM
        if [[ $DETECTED_RAM_GB -ge 16 && "$model" == "codegemma:7b" ]]; then
            echo -e "  ${GREEN}$idx) $model${NC} ($weight model, $context context) - $desc ${GREEN}[Recommended]${NC}"
        elif [[ $DETECTED_RAM_GB -lt 16 && "$model" == "codegemma:2b" ]]; then
            echo -e "  ${GREEN}$idx) $model${NC} ($weight model, $context context) - $desc ${GREEN}[Recommended]${NC}"
        else
            echo -e "  $idx) $model ($weight model, $context context) - $desc"
        fi
    done

    echo ""

    # Get user selection
    while true; do
        read -r -p "Enter selection (1-2): " selection

        # Validate numeric input in range 1-2
        if [[ "$selection" =~ ^[1-2]$ ]]; then
            local idx=$((selection - 1))
            CODEGEMMA_MODEL="${models[$idx]}"
            print_status "Selected: $CODEGEMMA_MODEL"
            break
        else
            print_error "Invalid selection. Please enter 1 or 2."
        fi
    done
}

#############################################
# Context Window Selection
#############################################

# Interactive context window selection
# Sets CONTEXT_LENGTH global based on user choice
# Shows GPU fit status for each option
#
# Globals read:
#   - MODEL_SIZE: Model variant (e.g., "31b", "26b")
#   - GEMMA_MODEL: Full model name (e.g., "gemma4:31b")
#   - RECOMMENDED_CONTEXT: Hardware-recommended context length
#   - DETECTED_RAM_GB: Detected RAM in GB
# Globals set:
#   - CONTEXT_LENGTH: Selected context length in tokens
select_context_window() {
    print_header "Context Window Selection"

    # Determine model's native max context
    # e2b and latest: 128K max, 26b and 31b: 256K max
    local max_context
    case "$MODEL_SIZE" in
        e2b|latest|e4b)
            max_context=131072  # 128K
            ;;
        26b|31b)
            max_context=262144  # 256K
            ;;
        *)
            max_context=131072  # Default to 128K
            ;;
    esac

    echo -e "${BLUE}Model: ${GEMMA_MODEL} (native max: $((max_context / 1024))K context)${NC}"
    echo -e "${BLUE}Recommended context for your hardware: $((RECOMMENDED_CONTEXT / 1024))K tokens${NC}"

    # Explain why this context was recommended
    local next_context
    case "$RECOMMENDED_CONTEXT" in
        32768)  next_context="64K" ;;
        65536)  next_context="128K" ;;
        131072) next_context="256K" ;;
        *)      next_context="larger" ;;
    esac
    echo -e "${BLUE}Why: Largest context that fits 100% on GPU. $next_context+ requires CPU/GPU split (slower).${NC}"

    echo ""
    echo "Select a context window size:"
    echo ""

    # Build available context options (only up to model's max)
    local -a context_options=(32768 65536 131072 262144)
    local -a context_labels=("32K" "64K" "128K" "256K")
    local -a available_contexts=()
    local -a available_labels=()
    local recommended_idx=-1
    local display_idx=1

    for i in "${!context_options[@]}"; do
        local ctx="${context_options[$i]}"
        local label="${context_labels[$i]}"

        # Skip options beyond model's native max context
        if [[ $ctx -gt $max_context ]]; then
            continue
        fi

        # Track recommended index
        if [[ $ctx -eq $RECOMMENDED_CONTEXT ]]; then
            recommended_idx=$display_idx
        fi

        # Display with GPU fit status
        if validate_gpu_fit "$DETECTED_RAM_GB" "$MODEL_SIZE" "$ctx"; then
            if [[ $ctx -eq $RECOMMENDED_CONTEXT ]]; then
                echo -e "  ${GREEN}$display_idx) ${label} (${ctx} tokens) - Recommended${NC}"
            else
                echo -e "  ${GREEN}$display_idx) ${label} (${ctx} tokens) - 100% GPU${NC}"
            fi
        else
            echo -e "  ${YELLOW}$display_idx) ${label} (${ctx} tokens) - CPU/GPU split (slower)${NC}"
        fi

        available_contexts+=("$ctx")
        available_labels+=("$label")
        display_idx=$((display_idx + 1))
    done

    echo ""

    # Get user selection
    local num_options=${#available_contexts[@]}
    while true; do
        read -r -p "Enter selection (1-$num_options, default=$recommended_idx): " selection

        # Default to recommended if empty
        if [[ -z "$selection" ]]; then
            selection=$recommended_idx
        fi

        # Validate numeric input in range
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -le $num_options ]]; then
            local idx=$((selection - 1))
            CONTEXT_LENGTH="${available_contexts[$idx]}"
            print_status "Selected: ${available_labels[$idx]} (${CONTEXT_LENGTH} tokens)"
            break
        else
            print_error "Invalid selection. Please enter a number between 1 and $num_options."
        fi
    done
}

#############################################
# GPU Validation
#############################################

# Validate and display GPU compatibility
# Allows user to continue with incompatible model or fallback to recommended
#
# Globals read:
#   - GEMMA_MODEL: Selected model
#   - MODEL_SIZE: Model variant
#   - CONTEXT_LENGTH: Selected context length
#   - DETECTED_RAM_GB: Detected RAM
#   - METAL_MEMORY: Calculated Metal memory
#   - RECOMMENDED_MODEL: Recommended model
#   - AUTO_MODE: Whether in auto mode
# Globals set (if fallback chosen):
#   - GEMMA_MODEL: Updated to recommended model
#   - MODEL_SIZE: Updated model size
#   - CONTEXT_LENGTH: Updated context length
#   - CUSTOM_MODEL_NAME: Regenerated with new settings
validate_and_prompt_gpu_fit() {
    print_header "Validating GPU Compatibility"

    local metal_gb=$((METAL_MEMORY / BYTES_PER_GB))
    local model_weight_gb
    local kv_cache_gb
    local total_needed_gb

    model_weight_gb=$(get_model_weight_gb "$MODEL_SIZE")
    kv_cache_gb=$(calculate_kv_cache_gb "$MODEL_SIZE" "$CONTEXT_LENGTH")
    total_needed_gb=$((model_weight_gb + kv_cache_gb))

    echo "Selected Model: $GEMMA_MODEL"
    echo "Context Window: $(format_context_k "$CONTEXT_LENGTH") tokens"
    echo ""
    echo "GPU Memory Requirements:"
    echo "  • Model weights:     ${model_weight_gb}GB"
    echo "  • KV cache:          ${kv_cache_gb}GB"
    echo "  • Total needed:      ${total_needed_gb}GB"
    echo "  • Available Metal:   ${metal_gb}GB"
    echo ""

    if ! validate_gpu_fit "$DETECTED_RAM_GB" "$MODEL_SIZE" "$CONTEXT_LENGTH"; then
        print_error "Model $GEMMA_MODEL will NOT fit entirely on GPU!"
        print_warning "This will result in CPU/GPU split and poor performance"
        echo ""
        echo "Recommended alternative: $RECOMMENDED_MODEL"

        if [[ "$AUTO_MODE" != true ]]; then
            read -p "Continue anyway? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "Using recommended model instead"
                GEMMA_MODEL="$RECOMMENDED_MODEL"
                MODEL_SIZE=$(get_model_size "$GEMMA_MODEL")
                CONTEXT_LENGTH=$(calculate_context_length "$DETECTED_RAM_GB" "$MODEL_SIZE")
                METAL_MEMORY=$(calculate_metal_memory "$DETECTED_RAM_GB")
                # Regenerate custom model name with new context
                CUSTOM_MODEL_NAME=$(generate_custom_model_name "$MODEL_SIZE" "$CONTEXT_LENGTH")
            fi
        else
            print_error "Cannot proceed in --auto mode with incompatible model"
            exit 1
        fi
    else
        print_status "Model will run at 100% GPU - optimal performance!"

        # Check for tight fit (less than 10% headroom)
        local headroom_gb=$((metal_gb - total_needed_gb))
        local min_headroom=$((metal_gb / 10))
        if [[ $headroom_gb -lt $min_headroom ]]; then
            print_warning "Running close to GPU memory limit (${headroom_gb}GB headroom)"
            print_info "Performance may degrade under memory pressure or with concurrent apps"
            print_info "Consider closing other apps or using a smaller model for best stability"
        fi
    fi
}

#############################################
# Custom Model Naming
#############################################

# Interactive custom model naming
# Sets CUSTOM_MODEL_NAME global based on user choice
#
# Globals read:
#   - MODEL_SIZE: Model variant (e.g., "31b", "26b")
#   - CONTEXT_LENGTH: Selected context length in tokens
# Globals set:
#   - CUSTOM_MODEL_NAME: User's custom model name or generated default
select_custom_name() {
    print_header "Custom Model Naming"

    # Suggest default name with context
    local default_name
    default_name=$(generate_custom_model_name "$MODEL_SIZE" "$CONTEXT_LENGTH")

    echo -e "${BLUE}Suggested name: ${default_name}${NC}"
    echo ""
    echo "This is the name you'll use with 'ollama run' and OpenCode."
    echo "Examples of custom names:"
    echo "  • gemma4-coding-fast    (for quick coding tasks)"
    echo "  • gemma4-research-deep  (for research with large context)"
    echo "  • gemma4-31b-balanced   (descriptive of model + purpose)"
    echo ""
    echo "Name requirements:"
    echo "  • Lowercase letters, numbers, hyphens (-), underscores (_), dots (.)"
    echo "  • No spaces or special characters"
    echo "  • Should be memorable and descriptive"
    echo ""
    read -p "Use suggested name? (Y/n) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Nn]$ ]]; then
        while true; do
            echo ""
            read -r -p "Enter custom model name: " custom_input

            # Use default if empty
            if [[ -z "$custom_input" ]]; then
                print_info "No input, using suggested name"
                CUSTOM_MODEL_NAME="$default_name"
                break
            fi

            # Validate format: lowercase alphanumeric + hyphens, underscores, dots only
            # No spaces, no special chars that could break shell/ollama
            if [[ "$custom_input" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
                # Additional validation: reasonable length
                if [[ ${#custom_input} -gt 64 ]]; then
                    print_error "Name too long (max 64 characters)"
                    continue
                fi

                # Warn if no prefix (recommended to start with "gemma" for clarity)
                if [[ ! "$custom_input" =~ ^gemma ]]; then
                    echo ""
                    print_warning "Name doesn't start with 'gemma' - may be unclear this is a Gemma model"
                    read -p "Use this name anyway? (y/N) " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        continue
                    fi
                fi

                CUSTOM_MODEL_NAME="$custom_input"
                print_status "Using custom name: $CUSTOM_MODEL_NAME"
                break
            else
                print_error "Invalid name format"
                echo "  • Must start with a letter or number"
                echo "  • Can only contain: a-z, 0-9, hyphens (-), underscores (_), dots (.)"
                echo "  • No uppercase, spaces, or special characters"
            fi
        done
    else
        CUSTOM_MODEL_NAME="$default_name"
    fi
}

#############################################
# IDE Tool Selection
#############################################

# Interactive IDE tool selection
# Sets IDE_TOOLS global array with selected tools
#
# Globals set:
#   - IDE_TOOLS: Array of selected tools ("opencode" and/or "jetbrains")
select_ide_tools() {
    print_header "IDE Tool Configuration"

    echo "Which IDE tool(s) would you like to configure?"
    echo ""
    echo -e "${BLUE}Available Options:${NC}"
    echo ""
    echo "  1) OpenCode only"
    echo "     • VS Code extension for AI-assisted coding"
    echo "     • Uses: Gemma4 for all features"
    echo "     • Open source: https://opencode.ai"
    echo ""
    echo "  2) JetBrains AI Assistant only"
    echo "     • Official JetBrains AI integration"
    echo "     • Uses: Gemma4 (core + instant helpers) + CodeGemma (completion)"
    echo "     • Works with IntelliJ, PyCharm, WebStorm, etc."
    echo ""
    echo "  3) Both OpenCode and JetBrains"
    echo "     • Configure both tools for maximum flexibility"
    echo "     • Downloads: Gemma4 + CodeGemma"
    echo "     • Recommended if you use multiple IDEs"
    echo ""

    # Get user selection
    while true; do
        read -r -p "Enter selection (1-3): " selection

        case "$selection" in
            1)
                IDE_TOOLS=("opencode")
                print_status "Selected: OpenCode"
                break
                ;;
            2)
                IDE_TOOLS=("jetbrains")
                print_status "Selected: JetBrains AI Assistant"
                break
                ;;
            3)
                IDE_TOOLS=("opencode" "jetbrains")
                print_status "Selected: Both OpenCode and JetBrains"
                break
                ;;
            *)
                print_error "Invalid selection. Please enter 1, 2, or 3."
                ;;
        esac
    done
}
