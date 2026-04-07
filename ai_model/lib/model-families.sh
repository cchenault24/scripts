#!/bin/bash
# model-families.sh - Model family definitions and management
# This file should be sourced, not executed directly

# Source common utilities
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

#############################################
# Model Family Definitions
#############################################
# Format: name|size_gb|min_ram_gb|context_window|quantization|use_case

# Meta Llama Models
LLAMA_MODELS=(
    "llama3.3:70b-instruct-q4_K_M|42|48|128000|q4_K_M|best_overall"
    "llama3.2:11b-instruct-q8_0|12|24|128000|q8_0|balanced"
    "llama3.2:11b-instruct-q4_K_M|7|16|128000|q4_K_M|balanced_small"
    "llama3.2:3b-instruct-q8_0|3|8|128000|q8_0|fast"
)

# Mistral Models
MISTRAL_MODELS=(
    "codestral:22b-v0.1-q8_0|25|32|128000|q8_0|code_quality"
    "codestral:22b-v0.1-q4_K_M|14|24|128000|q4_K_M|code_fast"
    "mistral-nemo:12b-instruct-q8_0|13|24|128000|q8_0|efficient"
)

# Microsoft Phi Models
PHI_MODELS=(
    "phi4:14b-q8_0|14|24|128000|q8_0|reasoning"
    "phi3.5:3.8b-mini-instruct-q8_0|4|8|128000|q8_0|ultra_fast"
)

# Google Gemma Models
GEMMA_MODELS=(
    "gemma4:31b-it-q8_0|34|48|256000|q8_0|large_context"
    "gemma4:26b-a4b-it-q4_K_M|18|32|256000|q4_K_M|large_context_small"
    "gemma4:e4b-it-q8_0|12|24|128000|q8_0|balanced"
    "gemma4:e2b-it-q4_K_M|7|16|128000|q4_K_M|small"
)

#############################################
# Security Functions
#############################################

# Check if model passes security filter
# Returns: 0 if allowed, 1 if blocked
is_model_allowed() {
    local model="$1"

    # Allowlist: Meta, Mistral, Microsoft, Google
    if [[ "$model" =~ ^(llama|mistral|codestral|phi|gemma) ]]; then
        # Blocklist: Chinese sources
        if [[ "$model" =~ (deepseek|qwen|yi|baichuan|chatglm) ]]; then
            return 1
        fi
        return 0
    fi
    return 1
}

#############################################
# Helper Functions
#############################################

# List all models in a family
# Usage: list_models_by_family <family_name>
# Returns: One model per line in pipe-delimited format
list_models_by_family() {
    local family="$1"
    case "$family" in
        llama) printf '%s\n' "${LLAMA_MODELS[@]}" ;;
        mistral) printf '%s\n' "${MISTRAL_MODELS[@]}" ;;
        phi) printf '%s\n' "${PHI_MODELS[@]}" ;;
        gemma) printf '%s\n' "${GEMMA_MODELS[@]}" ;;
        *)
            print_error "Unknown family: $family"
            return 1
            ;;
    esac
}

# Parse model metadata
# Usage: get_model_info <model_line> <field>
# Fields: name, size, min_ram, context, quantization, use_case
get_model_info() {
    local model_line="$1"
    local field="$2"

    IFS='|' read -r name size min_ram context quant use_case <<< "$model_line"

    case "$field" in
        name) echo "$name" ;;
        size) echo "$size" ;;
        min_ram) echo "$min_ram" ;;
        context) echo "$context" ;;
        quantization) echo "$quant" ;;
        use_case) echo "$use_case" ;;
        *)
            print_error "Unknown field: $field"
            return 1
            ;;
    esac
}

# Get recommended models for RAM tier
# Usage: get_recommended_models <ram_tier>
# Returns: List of recommended model names
get_recommended_models() {
    local ram_tier="$1"
    local ram_gb=0

    case "$ram_tier" in
        tier1) ram_gb=16 ;;
        tier2) ram_gb=32 ;;
        tier3) ram_gb=48 ;;
        *)
            print_error "Unknown RAM tier: $ram_tier"
            return 1
            ;;
    esac

    local -a recommended=()
    local -A best_family_models=()

    # Collect all models from all families
    local -a all_models=()
    all_models+=("${LLAMA_MODELS[@]}")
    all_models+=("${MISTRAL_MODELS[@]}")
    all_models+=("${PHI_MODELS[@]}")
    all_models+=("${GEMMA_MODELS[@]}")

    # Find models that fit in RAM and track best per family
    for model_line in "${all_models[@]}"; do
        local model_name model_size model_min_ram model_context model_quant model_use_case
        IFS='|' read -r model_name model_size model_min_ram model_context model_quant model_use_case <<< "$model_line"

        # Determine family from model name
        local model_family=""
        if [[ "$model_name" =~ ^llama ]]; then
            model_family="llama"
        elif [[ "$model_name" =~ ^(mistral|codestral) ]]; then
            model_family="mistral"
        elif [[ "$model_name" =~ ^phi ]]; then
            model_family="phi"
        elif [[ "$model_name" =~ ^gemma ]]; then
            model_family="gemma"
        fi

        # Check if model fits in available RAM (numeric comparison)
        if [[ "$model_min_ram" -le "$ram_gb" ]]; then
            recommended+=("$model_name")

            # Track best model per family (highest min_ram = most capable)
            local current_best="${best_family_models[$model_family]:-}"
            if [[ -z "$current_best" ]]; then
                best_family_models[$model_family]="$model_min_ram:$model_name"
            else
                local current_ram="${current_best%%:*}"
                if [[ "$model_min_ram" -gt "$current_ram" ]]; then
                    best_family_models[$model_family]="$model_min_ram:$model_name"
                fi
            fi
        fi
    done

    # If we have recommended models, print them
    if [[ ${#recommended[@]} -gt 0 ]]; then
        printf '%s\n' "${recommended[@]}" | sort -u
    else
        print_warning "No models found for RAM tier: $ram_tier ($ram_gb GB)"
        return 1
    fi
}

# List all available model families
list_all_families() {
    echo "llama"
    echo "mistral"
    echo "phi"
    echo "gemma"
}

# Get total model count across all families
get_total_model_count() {
    local count=0
    count=$((${#LLAMA_MODELS[@]} + ${#MISTRAL_MODELS[@]} + ${#PHI_MODELS[@]} + ${#GEMMA_MODELS[@]}))
    echo "$count"
}

# Get model count for a specific family
get_family_model_count() {
    local family="$1"
    case "$family" in
        llama) echo "${#LLAMA_MODELS[@]}" ;;
        mistral) echo "${#MISTRAL_MODELS[@]}" ;;
        phi) echo "${#PHI_MODELS[@]}" ;;
        gemma) echo "${#GEMMA_MODELS[@]}" ;;
        *)
            print_error "Unknown family: $family"
            return 1
            ;;
    esac
}

# Display summary of all model families
display_model_families_summary() {
    print_header "Model Families Summary"

    echo -e "${BLUE}Total Models:${NC} $(get_total_model_count)"
    echo ""

    for family in $(list_all_families); do
        local count
        count=$(get_family_model_count "$family")
        echo -e "${GREEN}$family:${NC} $count models"
    done
}

#############################################
# Export Functions
#############################################

# Make all functions available when sourced
export -f is_model_allowed
export -f list_models_by_family
export -f get_model_info
export -f get_recommended_models
export -f list_all_families
export -f get_total_model_count
export -f get_family_model_count
export -f display_model_families_summary
