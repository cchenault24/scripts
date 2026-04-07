#!/bin/bash
# model-selection.sh - Intelligent two-stage model selection
# This file should be sourced, not executed directly

# Source required libraries if not already loaded
if ! declare -f print_header >/dev/null 2>&1; then
    SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
    source "$SCRIPT_DIR/common.sh"
    source "$SCRIPT_DIR/model-families.sh"
fi

#############################################
# Global Variables
#############################################
export SELECTED_FAMILY=""
export SELECTED_MODEL=""
export OLLAMA_PORT="${OLLAMA_PORT:-11434}"

#############################################
# Installed Models Detection
#############################################

# Check if a model is installed
# Usage: is_model_installed <model_name>
# Returns: 0 if installed, 1 if not
is_model_installed() {
    local model_name="$1"
    local installed_models

    # Query Ollama API for installed models
    installed_models=$(curl -s "http://127.0.0.1:$OLLAMA_PORT/api/tags" 2>/dev/null || echo '{"models":[]}')

    # Check if model exists in the response
    if echo "$installed_models" | grep -q "\"name\":\"$model_name\""; then
        return 0
    else
        return 1
    fi
}

# Get list of all installed models
# Returns: One model name per line
get_installed_models() {
    local installed_models
    installed_models=$(curl -s "http://127.0.0.1:$OLLAMA_PORT/api/tags" 2>/dev/null || echo '{"models":[]}')

    # Extract model names (simple grep-based approach)
    echo "$installed_models" | grep -o '"name":"[^"]*"' | sed 's/"name":"//g' | sed 's/"//g'
}

#############################################
# Recommendation Logic
#############################################

# Get recommended model for a family and RAM tier
# Usage: get_family_recommendation <family> <ram_gb>
# Returns: model_name or empty string
get_family_recommendation() {
    local family="$1"
    local ram_gb="$2"
    local recommended=""

    case "$family" in
        llama)
            if [[ "$ram_gb" -ge 48 ]]; then
                recommended="llama3.3:70b-instruct-q4_K_M"
            elif [[ "$ram_gb" -ge 32 ]]; then
                recommended="llama3.2:11b-instruct-q8_0"
            elif [[ "$ram_gb" -ge 16 ]]; then
                recommended="llama3.2:3b-instruct-q8_0"
            fi
            ;;
        mistral)
            if [[ "$ram_gb" -ge 32 ]]; then
                recommended="codestral:22b-v0.1-q4_K_M"
            elif [[ "$ram_gb" -ge 24 ]]; then
                recommended="mistral-nemo:12b-instruct-q8_0"
            fi
            ;;
        phi)
            if [[ "$ram_gb" -ge 24 ]]; then
                recommended="phi4:14b-q8_0"
            else
                recommended="phi3.5:3.8b-mini-instruct-q8_0"
            fi
            ;;
        gemma)
            if [[ "$ram_gb" -ge 48 ]]; then
                recommended="gemma4:31b-it-q8_0"
            elif [[ "$ram_gb" -ge 32 ]]; then
                recommended="gemma4:26b-a4b-it-q4_K_M"
            elif [[ "$ram_gb" -ge 24 ]]; then
                recommended="gemma4:e4b-it-q8_0"
            else
                recommended="gemma4:e2b-it-q4_K_M"
            fi
            ;;
    esac

    echo "$recommended"
}

#############################################
# Stage 1: Family Selection
#############################################

# Select model family interactively
# Sets SELECTED_FAMILY environment variable
select_family() {
    # Check if family is already set via environment variable
    if [[ -n "${OLLAMA_MODEL_FAMILY:-}" ]]; then
        SELECTED_FAMILY="$OLLAMA_MODEL_FAMILY"
        print_info "Using family from OLLAMA_MODEL_FAMILY: $SELECTED_FAMILY"
        return 0
    fi

    echo ""
    print_header "Choose Model Family"

    echo -e "${BLUE}1)${NC} Meta Llama    - Best overall quality, strong reasoning"
    echo -e "${BLUE}2)${NC} Mistral       - Efficient, excellent code generation"
    echo -e "${BLUE}3)${NC} Microsoft Phi - Fast, small models for quick responses"
    echo -e "${BLUE}4)${NC} Google Gemma  - Large context windows (256K)"
    echo ""

    local choice
    while true; do
        read -p "Select family (1-4): " choice

        case "$choice" in
            1)
                SELECTED_FAMILY="llama"
                break
                ;;
            2)
                SELECTED_FAMILY="mistral"
                break
                ;;
            3)
                SELECTED_FAMILY="phi"
                break
                ;;
            4)
                SELECTED_FAMILY="gemma"
                break
                ;;
            *)
                print_error "Invalid selection. Please choose 1-4."
                ;;
        esac
    done

    export SELECTED_FAMILY
    print_status "Selected family: $SELECTED_FAMILY"
}

#############################################
# Stage 2: Model Selection
#############################################

# Filter models by available RAM
# Usage: filter_models_by_ram <family> <ram_gb>
# Returns: Filtered model lines (pipe-delimited format)
filter_models_by_ram() {
    local family="$1"
    local ram_gb="$2"
    local models

    models=$(list_models_by_family "$family")

    # Filter models that fit in available RAM
    while IFS= read -r model_line; do
        local min_ram
        min_ram=$(get_model_info "$model_line" "min_ram")

        if [[ "$min_ram" -le "$ram_gb" ]]; then
            echo "$model_line"
        fi
    done <<< "$models"
}

# Display model selection menu
# Usage: display_model_menu <family> <ram_gb>
display_model_menu() {
    local family="$1"
    local ram_gb="$2"
    local filtered_models
    local recommended

    # Get filtered models
    filtered_models=$(filter_models_by_ram "$family" "$ram_gb")

    if [[ -z "$filtered_models" ]]; then
        print_error "No models available for $family with ${ram_gb}GB RAM"
        return 1
    fi

    # Get recommendation
    recommended=$(get_family_recommendation "$family" "$ram_gb")

    # Display header
    echo ""
    print_header "Available $(echo "$family" | tr '[:lower:]' '[:upper:]') Models (${ram_gb}GB RAM)"

    # Display models
    local index=1
    local -a model_names=()

    while IFS= read -r model_line; do
        local name size min_ram context
        name=$(get_model_info "$model_line" "name")
        size=$(get_model_info "$model_line" "size")
        min_ram=$(get_model_info "$model_line" "min_ram")
        context=$(get_model_info "$model_line" "context")

        # Build display line
        local display_line="${BLUE}${index})${NC} ${name} (${size}GB, ${min_ram}GB min)"

        # Add recommended badge
        if [[ "$name" == "$recommended" ]]; then
            display_line="${display_line} ${YELLOW}✨ RECOMMENDED${NC}"
        fi

        # Add installed checkmark
        if is_model_installed "$name"; then
            display_line="${display_line} ${GREEN}✓${NC}"
        fi

        echo -e "$display_line"
        model_names+=("$name")
        ((index++))
    done <<< "$filtered_models"

    echo ""
    echo -e "${BLUE}Context Windows:${NC} Llama/Mistral/Phi (128K), Gemma (256K)"
    echo ""

    # Return model names array (store in global)
    export MODEL_MENU_OPTIONS=("${model_names[@]}")
}

# Select model from family
# Usage: select_model_from_family <family>
# Sets SELECTED_MODEL environment variable
select_model_from_family() {
    local family="$1"
    local ram_gb="$TOTAL_RAM_GB"

    # Display menu
    display_model_menu "$family" "$ram_gb" || return 1

    # Get user selection
    local choice
    while true; do
        read -p "Select model (1-${#MODEL_MENU_OPTIONS[@]}) or type custom name: " choice

        # Check if numeric selection
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            local idx=$((choice - 1))
            if [[ $idx -ge 0 ]] && [[ $idx -lt ${#MODEL_MENU_OPTIONS[@]} ]]; then
                SELECTED_MODEL="${MODEL_MENU_OPTIONS[$idx]}"
                break
            else
                print_error "Invalid selection. Please choose 1-${#MODEL_MENU_OPTIONS[@]}."
            fi
        else
            # Custom model name
            if [[ -n "$choice" ]]; then
                # Validate model name with security filter
                if is_model_allowed "$choice"; then
                    SELECTED_MODEL="$choice"
                    print_warning "Custom model selected: $choice"
                    break
                else
                    print_error "Model '$choice' is not allowed by security policy."
                fi
            else
                print_error "Please enter a valid selection."
            fi
        fi
    done

    export SELECTED_MODEL
    print_status "Selected model: $SELECTED_MODEL"
}

#############################################
# Main Selection Flow
#############################################

# Run complete two-stage selection
# Returns: 0 on success, 1 on failure
# Sets: SELECTED_FAMILY and SELECTED_MODEL
run_model_selection() {
    # Display hardware info
    local chip_type gpu_cores
    chip_type="$M_CHIP"
    gpu_cores="$GPU_CORES"

    echo ""
    print_header "Hardware Detection"
    echo -e "${GREEN}Chip:${NC} $chip_type"
    echo -e "${GREEN}GPU Cores:${NC} $gpu_cores"
    echo -e "${GREEN}RAM:${NC} ${TOTAL_RAM_GB}GB (Tier: $RAM_TIER)"

    # Stage 1: Select family
    select_family || return 1

    # Stage 2: Select model
    select_model_from_family "$SELECTED_FAMILY" || return 1

    # Summary
    echo ""
    print_header "Selection Complete"
    echo -e "${GREEN}Family:${NC} $SELECTED_FAMILY"
    echo -e "${GREEN}Model:${NC} $SELECTED_MODEL"

    return 0
}

#############################################
# Export Functions
#############################################

# Make all functions available when sourced
export -f is_model_installed
export -f get_installed_models
export -f get_family_recommendation
export -f select_family
export -f filter_models_by_ram
export -f display_model_menu
export -f select_model_from_family
export -f run_model_selection
