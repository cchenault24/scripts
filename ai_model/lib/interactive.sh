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
}

# Helper: Display single model with GPU fit indicator
display_model_gpu_fit() {
    local model_key=$1
    local context=$2

    # Get model weight and display name from registry
    local model_weight_gb
    model_weight_gb=$(get_registry_model_weight_gb "$model_key")
    local display_name
    display_name=$(get_registry_display_name "$model_key")

    if validate_gpu_fit "$DETECTED_RAM_GB" "$model_key" "$context"; then
        echo "  ✓ $model_key    (${model_weight_gb}GB model, $((context/1024))K context, 100% GPU)"
    else
        echo "  ⚠ $model_key    (${model_weight_gb}GB model, $((context/1024))K context, CPU/GPU split - not recommended)"
    fi
}

#############################################
# Model Selection
#############################################

# Interactive model selection from available models
# Sets SELECTED_MODEL global based on user choice
#
# Globals read:
#   - DETECTED_RAM_GB: Detected RAM in GB
#   - RECOMMENDED_MODEL: Recommended model (optional)
# Globals set:
#   - SELECTED_MODEL: Selected model name (e.g., "gemma4:31b", "phi4:latest")
select_model_interactive() {
    local show_default="${1:-false}"  # Whether to show default in prompt

    print_header "Model Selection"

    # Build arrays dynamically from registry with composite scoring
    # Score = (coding_priority * 10) + weight_GB
    # This prioritizes coding quality but considers model capability (size)
    local -a scored_models=()

    while IFS= read -r model_key; do
        # Get minimum RAM required
        local min_ram
        min_ram=$(get_registry_min_ram "$model_key")

        # Only include models that meet minimum RAM requirement
        if [[ $DETECTED_RAM_GB -ge $min_ram ]]; then
            # Calculate composite score for sorting
            local weight
            weight=$(get_registry_model_weight_gb "$model_key")
            local coding_priority
            coding_priority=$(get_registry_coding_priority "$model_key")
            local score=$((coding_priority * 10 + weight))

            # Store as "score:model_key" for sorting
            scored_models+=("${score}:${model_key}")
        fi
    done < <(list_all_models)

    # Sort by score (descending - highest score first)
    # Use process substitution to sort and rebuild array
    local -a models=()
    while IFS=':' read -r score model_key; do
        models+=("$model_key")
    done < <(printf '%s\n' "${scored_models[@]}" | sort -t: -k1 -rn)

    # Find recommended index if provided
    local recommended_idx=0
    if [[ -n "${RECOMMENDED_MODEL:-}" ]]; then
        for i in "${!models[@]}"; do
            if [[ "${models[$i]}" == "$RECOMMENDED_MODEL" ]]; then
                recommended_idx=$((i + 1))
                break
            fi
        done
    fi

    echo "Select a model from the list below:"
    echo -e "${GRAY}(Sorted by coding quality + capability, best first)${NC}"
    echo ""

    # Display models with GPU fit status
    for i in "${!models[@]}"; do
        local idx=$((i + 1))
        local model_key="${models[$i]}"

        # Get specs from registry
        local weight_gb
        weight_gb=$(get_registry_model_weight_gb "$model_key")
        local display_name
        display_name=$(get_registry_display_name "$model_key")

        # Get context for this model at current RAM
        local context
        context=$(calculate_context_length "$DETECTED_RAM_GB" "$model_key")
        local context_k=$((context / 1024))

        # Check if it fits on GPU and if it's recommended
        local suffix=""
        if [[ $idx -eq $recommended_idx ]]; then
            suffix=" [Recommended]"
        fi

        if validate_gpu_fit "$DETECTED_RAM_GB" "$model_key" "$context"; then
            if [[ $idx -eq $recommended_idx ]]; then
                echo -e "  ${GREEN}$idx) $model_key (${weight_gb}GB, 100% GPU)$suffix${NC}"
            else
                echo -e "  $idx) $model_key (${weight_gb}GB, 100% GPU)$suffix"
            fi
        else
            echo -e "  ${YELLOW}$idx) $model_key (${weight_gb}GB, CPU/GPU split)$suffix${NC}"
        fi
    done

    echo ""

    # Get user selection
    local num_models=${#models[@]}
    while true; do
        if [[ "$show_default" == "true" && $recommended_idx -gt 0 ]]; then
            read -r -p "Enter selection (1-$num_models, recommended: $recommended_idx): " selection

            # Default to recommended if empty
            if [[ -z "$selection" ]]; then
                selection=$recommended_idx
            fi
        else
            read -r -p "Enter selection (1-$num_models): " selection
        fi

        # Validate numeric input in range
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -le $num_models ]]; then
            local idx=$((selection - 1))
            SELECTED_MODEL="${models[$idx]}"
            print_status "Selected: $SELECTED_MODEL"
            break
        else
            print_error "Invalid selection. Please enter a number between 1 and $num_models."
        fi
    done
}

#############################################
# FIM Model Selection (for JetBrains)
#############################################

# Interactive FIM model selection for JetBrains AI Assistant
# FIM (Fill-In-Middle) models support inline code completion
#
# Globals read:
#   - DETECTED_RAM_GB: Detected RAM for recommendations and filtering
# Globals set:
#   - CODESELECTED_MODEL: Selected FIM model (e.g., "codegemma:7b-code")
select_fim_model_interactive() {
    print_header "FIM Model Selection (for JetBrains AI Assistant)"

    echo -e "${BLUE}JetBrains AI Assistant needs a FIM-capable model for code completion${NC}"
    echo ""
    echo "FIM (Fill-In-Middle) models are optimized for:"
    echo "  • Inline code completion"
    echo "  • Code infilling and suggestions"
    echo "  • Context-aware auto-completion"
    echo ""

    # Build scored array dynamically from registry
    # Score = (fim_priority * 10) + weight_GB (prioritizes FIM quality over size)
    local -a scored_models=()

    while IFS= read -r model_key; do
        local weight
        weight=$(get_fim_model_weight_gb "$model_key")

        # Only include models that fit in available RAM (leave 8GB headroom)
        local available_ram=$((DETECTED_RAM_GB - 8))
        if [[ $weight -le $available_ram ]]; then
            # Calculate composite score for sorting
            local fim_priority
            fim_priority=$(get_fim_coding_priority "$model_key")
            local score=$((fim_priority * 10 + weight))

            # Store as "score:model_key" for sorting
            scored_models+=("${score}:${model_key}")
        fi
    done < <(list_fim_models)

    # Sort by score (descending - highest score first)
    local -a models=()
    local -a weights=()
    local -a display_names=()
    local -a descriptions=()

    while IFS=':' read -r score model_key; do
        models+=("$model_key")
        local weight
        weight=$(get_fim_model_weight_gb "$model_key")
        weights+=("${weight}GB")
        display_names+=("$(get_fim_model_display_name "$model_key")")
        descriptions+=("$(get_fim_model_description "$model_key")")
    done < <(printf '%s\n' "${scored_models[@]}" | sort -t: -k1 -rn)

    # Display models with recommendations
    local recommended_model
    recommended_model=$(recommend_fim_model "$DETECTED_RAM_GB")
    local recommended_idx=-1

    echo "Select a FIM model:"
    echo -e "${GRAY}(Sorted by FIM quality + capability, best first)${NC}"
    echo ""

    for i in "${!models[@]}"; do
        local idx=$((i + 1))
        local model="${models[$i]}"
        local weight="${weights[$i]}"
        local display="${display_names[$i]}"
        local desc="${descriptions[$i]}"

        # Mark recommended model
        if [[ "$model" == "$recommended_model" ]]; then
            recommended_idx=$idx
            echo -e "  ${GREEN}$idx) $display ($weight) - $desc [Recommended]${NC}"
        else
            echo -e "  $idx) $display ($weight) - $desc"
        fi
    done

    echo ""

    # Get user selection
    while true; do
        if [[ $recommended_idx -gt 0 ]]; then
            read -r -p "Enter selection (1-${#models[@]}, recommended: $recommended_idx): " selection
            if [[ -z "$selection" ]]; then
                selection=$recommended_idx
            fi
        else
            read -r -p "Enter selection (1-${#models[@]}): " selection
        fi

        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -le ${#models[@]} ]]; then
            local idx=$((selection - 1))
            CODESELECTED_MODEL="${models[$idx]}"
            print_status "Selected: $CODESELECTED_MODEL"
            break
        else
            print_error "Invalid selection. Please enter 1-${#models[@]}."
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
#   - SELECTED_MODEL: Full model name (e.g., "gemma4:31b", "phi4:latest")
#   - RECOMMENDED_CONTEXT: Hardware-recommended context length
#   - DETECTED_RAM_GB: Detected RAM in GB
# Globals set:
#   - CONTEXT_LENGTH: Selected context length in tokens
select_context_window() {
    print_header "Context Window Selection"

    # Get model's native max context from registry
    local max_context
    max_context=$(get_registry_max_context "$SELECTED_MODEL")

    echo -e "${BLUE}Model: ${SELECTED_MODEL} (native max: $((max_context / 1024))K context)${NC}"
    echo -e "${BLUE}Recommended context for your hardware: $((RECOMMENDED_CONTEXT / 1024))K tokens${NC}"

    # Explain why this context was recommended
    local next_context
    case "$RECOMMENDED_CONTEXT" in
        4096)   next_context="8K" ;;
        8192)   next_context="16K" ;;
        16384)  next_context="32K" ;;
        32768)  next_context="64K" ;;
        *)      next_context="larger" ;;
    esac
    echo -e "${BLUE}Why: Optimized for fast responses. ${next_context}+ will be slower but provide more context.${NC}"

    echo ""
    echo "Select a context window size:"
    echo ""

    # Build available context options (speed-focused, smaller sizes)
    local -a context_options=(4096 8192 16384 32768 65536 131072 262144)
    local -a context_labels=("4K" "8K" "16K" "32K" "64K" "128K" "256K")
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
        if validate_gpu_fit "$DETECTED_RAM_GB" "$SELECTED_MODEL" "$ctx"; then
            if [[ $ctx -eq $RECOMMENDED_CONTEXT ]]; then
                echo -e "  ${GREEN}$display_idx) ${label} (${ctx} tokens) - Recommended${NC}"
            else
                echo -e "  $display_idx) ${label} (${ctx} tokens) - 100% GPU"
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
        read -r -p "Enter selection (1-$num_options, recommended: $recommended_idx): " selection

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
#   - SELECTED_MODEL: Selected model
#   - MODEL_VARIANT: Model variant
#   - CONTEXT_LENGTH: Selected context length
#   - DETECTED_RAM_GB: Detected RAM
#   - METAL_MEMORY: Calculated Metal memory
#   - RECOMMENDED_MODEL: Recommended model
#   - AUTO_MODE: Whether in auto mode
# Globals set (if fallback chosen):
#   - SELECTED_MODEL: Updated to recommended model
#   - MODEL_VARIANT: Updated model variant
#   - CONTEXT_LENGTH: Updated context length
#   - CUSTOM_MODEL_NAME: Regenerated with new settings
validate_and_prompt_gpu_fit() {
    print_header "Validating GPU Compatibility"

    local metal_gb=$((METAL_MEMORY / BYTES_PER_GB))
    local model_weight_gb
    local kv_cache_gb
    local total_needed_gb

    model_weight_gb=$(get_model_weight_gb "$SELECTED_MODEL")
    kv_cache_gb=$(calculate_kv_cache_gb "$SELECTED_MODEL" "$CONTEXT_LENGTH")
    total_needed_gb=$((model_weight_gb + kv_cache_gb))

    echo "Selected Model: $SELECTED_MODEL"
    echo "Context Window: $(format_context_k "$CONTEXT_LENGTH") tokens"
    echo ""
    echo "GPU Memory Requirements:"
    echo "  • Model weights:     ${model_weight_gb}GB"
    echo "  • KV cache:          ${kv_cache_gb}GB"
    echo "  • Total needed:      ${total_needed_gb}GB"
    echo "  • Available Metal:   ${metal_gb}GB"
    echo ""

    if ! validate_gpu_fit "$DETECTED_RAM_GB" "$SELECTED_MODEL" "$CONTEXT_LENGTH"; then
        print_error "Model $SELECTED_MODEL will NOT fit entirely on GPU!"
        print_warning "This will result in CPU/GPU split and poor performance"
        echo ""
        echo "Recommended alternative: $RECOMMENDED_MODEL"

        if [[ "$AUTO_MODE" != true ]]; then
            read -p "Continue anyway? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "Using recommended model instead"
                SELECTED_MODEL="$RECOMMENDED_MODEL"
                MODEL_VARIANT=$(get_model_variant "$SELECTED_MODEL")
                CONTEXT_LENGTH=$(calculate_context_length "$DETECTED_RAM_GB" "$SELECTED_MODEL")
                METAL_MEMORY=$(calculate_metal_memory "$DETECTED_RAM_GB")
                # Regenerate custom model name with new context
                CUSTOM_MODEL_NAME=$(generate_custom_model_name "$SELECTED_MODEL" "$CONTEXT_LENGTH")
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
#   - MODEL_VARIANT: Model variant (e.g., "31b", "latest")
#   - CONTEXT_LENGTH: Selected context length in tokens
# Globals set:
#   - CUSTOM_MODEL_NAME: User's custom model name or generated default
select_custom_name() {
    print_header "Custom Model Naming"

    # Suggest default name with context
    local default_name
    default_name=$(generate_custom_model_name "$SELECTED_MODEL" "$CONTEXT_LENGTH")

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
    read -p "Use suggested name \"$default_name\"? (Y/n) " -n 1 -r
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

                # Warn if no model family prefix (recommended for clarity)
                local model_family="${SELECTED_MODEL%%:*}"
                if [[ ! "$custom_input" =~ ^${model_family} ]]; then
                    echo ""
                    print_warning "Name doesn't start with '${model_family}' - may be unclear which model family this is"
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

# Detect if JetBrains IDE is installed
# Returns 0 if found, 1 if not found
detect_jetbrains_ide() {
    local jetbrains_apps=(
        "IntelliJ IDEA"
        "PyCharm"
        "WebStorm"
        "PhpStorm"
        "CLion"
        "GoLand"
        "RubyMine"
        "Rider"
        "DataGrip"
        "AppCode"
        "Fleet"
    )

    # Check /Applications
    for app in "${jetbrains_apps[@]}"; do
        if ls /Applications/"${app}"*.app &>/dev/null; then
            return 0
        fi
    done

    # Check ~/Applications (Toolbox installs here)
    for app in "${jetbrains_apps[@]}"; do
        if ls "$HOME/Applications/${app}"*.app &>/dev/null; then
            return 0
        fi
    done

    return 1
}

# Interactive IDE tool selection
# Sets IDE_TOOLS global array with selected tools
#
# Globals set:
#   - IDE_TOOLS: Array of selected tools ("opencode" and/or "jetbrains")
select_ide_tools() {
    print_header "IDE Tool Configuration"

    # Detect JetBrains IDE installation
    local has_jetbrains=false
    if detect_jetbrains_ide; then
        has_jetbrains=true
    fi

    echo "Which IDE tool(s) would you like to configure?"
    echo ""
    echo -e "${BLUE}Available Options:${NC}"
    echo ""

    # Calculate hardware-based recommendation
    local recommended_option=1  # Default to OpenCode only
    local max_option=1

    if [[ "$has_jetbrains" == true ]]; then
        max_option=3
        # Hardware-based recommendation (only if JetBrains is installed)
        if [[ $DETECTED_RAM_GB -ge 16 ]]; then
            recommended_option=3  # Both - plenty of resources
        elif [[ $DETECTED_RAM_GB -ge 12 ]]; then
            recommended_option=2  # JetBrains only - enough for one tool + FIM
        else
            recommended_option=1  # OpenCode only - limited RAM
        fi
    fi

    # Show option 1 (always available)
    if [[ $recommended_option -eq 1 ]]; then
        echo -e "  ${GREEN}1) OpenCode Terminal UI only${NC}"
    else
        echo "  1) OpenCode Terminal UI only"
    fi
    echo ""

    # Show options 2 and 3 only if JetBrains is detected
    if [[ "$has_jetbrains" == true ]]; then
        if [[ $recommended_option -eq 2 ]]; then
            echo -e "  ${GREEN}2) JetBrains AI Assistant Plugin only${NC}"
        else
            echo "  2) JetBrains AI Assistant Plugin only"
        fi
        echo ""

        if [[ $recommended_option -eq 3 ]]; then
            echo -e "  ${GREEN}3) Both OpenCode and JetBrains AI Assistant${NC}"
        else
            echo "  3) Both OpenCode and JetBrains AI Assistant"
        fi
        echo ""
    else
        echo -e "${YELLOW}Note: JetBrains options not available (no JetBrains IDE detected)${NC}"
        echo ""
    fi

    # Get user selection
    while true; do
        if [[ $max_option -eq 1 ]]; then
            read -r -p "Press Enter to continue with OpenCode: " selection
            selection=1
        else
            read -r -p "Enter selection (1-${max_option}, recommended: ${recommended_option}): " selection

            # Default to recommended option if empty
            if [[ -z "$selection" ]]; then
                selection=$recommended_option
            fi
        fi

        case "$selection" in
            1)
                IDE_TOOLS=("opencode")
                print_status "Selected: OpenCode"
                break
                ;;
            2)
                if [[ "$has_jetbrains" == true ]]; then
                    IDE_TOOLS=("jetbrains")
                    print_status "Selected: JetBrains AI Assistant"
                    break
                else
                    print_error "JetBrains option not available (no JetBrains IDE detected)"
                fi
                ;;
            3)
                if [[ "$has_jetbrains" == true ]]; then
                    IDE_TOOLS=("opencode" "jetbrains")
                    print_status "Selected: Both OpenCode and JetBrains"
                    break
                else
                    print_error "JetBrains option not available (no JetBrains IDE detected)"
                fi
                ;;
            *)
                print_error "Invalid selection. Please enter 1-${max_option}."
                ;;
        esac
    done
}
