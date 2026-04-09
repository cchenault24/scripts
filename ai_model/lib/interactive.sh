#!/bin/bash
# lib/interactive.sh - Interactive user selection functions
#
# Provides:
# - Context window selection with GPU fit visualization
# - Custom model naming with validation

set -euo pipefail

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
#   - METAL_MEMORY: Calculated Metal memory allocation
#   - BYTES_PER_GB: Bytes per GB constant
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
    echo ""
    echo "Available context window sizes:"
    echo ""

    # Context options to display (only up to model's max)
    local -a context_options=(32768 65536 131072 262144)
    local -a context_labels=("32K" "64K" "128K" "256K")

    for i in "${!context_options[@]}"; do
        local ctx="${context_options[$i]}"
        local label="${context_labels[$i]}"

        # Skip options beyond model's native max context
        if [[ $ctx -gt $max_context ]]; then
            continue
        fi

        # Calculate if it fits
        if validate_gpu_fit "$DETECTED_RAM_GB" "$MODEL_SIZE" "$ctx"; then
            if [[ $ctx -eq $RECOMMENDED_CONTEXT ]]; then
                echo -e "  ${GREEN}✓ ${label} (${ctx} tokens) - Recommended${NC}"
            else
                echo -e "  ${GREEN}✓ ${label} (${ctx} tokens) - 100% GPU${NC}"
            fi
        else
            echo -e "  ${YELLOW}⚠ ${label} (${ctx} tokens) - CPU/GPU split (slower)${NC}"
        fi
    done

    echo ""
    read -p "Use recommended $((RECOMMENDED_CONTEXT / 1024))K context? (Y/n) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Nn]$ ]]; then
        # Build valid options string based on model max
        local valid_options
        if [[ $max_context -eq 262144 ]]; then
            valid_options="32K, 64K, 128K, or 256K"
        else
            valid_options="32K, 64K, or 128K"
        fi

        while true; do
            echo ""
            read -r -p "Enter context size ($valid_options): " context_input

            # Parse input (use tr for bash 3.2 compatibility)
            local context_lower
            context_lower=$(echo "$context_input" | tr '[:upper:]' '[:lower:]')
            case "$context_lower" in
                32k|32)
                    CONTEXT_LENGTH=32768
                    break
                    ;;
                64k|64)
                    CONTEXT_LENGTH=65536
                    break
                    ;;
                128k|128)
                    CONTEXT_LENGTH=131072
                    break
                    ;;
                256k|256)
                    if [[ $max_context -lt 262144 ]]; then
                        print_error "256K exceeds model's native max context ($((max_context / 1024))K)"
                        print_info "This model supports up to $((max_context / 1024))K context"
                    else
                        CONTEXT_LENGTH=262144
                        break
                    fi
                    ;;
                "")
                    print_info "No input, using recommended $((RECOMMENDED_CONTEXT / 1024))K"
                    CONTEXT_LENGTH=$RECOMMENDED_CONTEXT
                    break
                    ;;
                *)
                    print_error "Invalid input. Please enter $valid_options"
                    ;;
            esac
        done
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
