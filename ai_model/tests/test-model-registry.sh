#!/bin/bash
# tests/test-model-registry.sh - Unit tests for model registry
#
# Tests all model registry lookup functions:
# - get_registry_model_weight_gb() - Model weights
# - get_registry_max_context() - Context windows
# - get_registry_min_ram() - RAM requirements
# - get_registry_kv_bytes_per_token() - KV cache calculations
# - get_registry_display_name() - Display names
# - get_registry_coding_priority() - Coding benchmark rankings
# - list_all_models() - Model enumeration
# - FIM model functions
#
# Usage: ./tests/test-model-registry.sh [--verbose]

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test helpers
source "$SCRIPT_DIR/helpers.sh"

# Source model registry
source "$PROJECT_DIR/lib/model-registry.sh"

# Verbose mode
VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE=true
fi

#############################################
# Test: Model Weight Lookups
#############################################

test_model_weights() {
    print_section "Testing Model Weight Lookups"

    # Test Gemma4 models
    begin_test "gemma4:e2b weight is 7GB"
    local weight=$(get_registry_model_weight_gb "gemma4:e2b")
    if [[ "$weight" == "7" ]]; then
        pass_test
    else
        fail_test "Expected 7, got $weight"
    fi

    begin_test "gemma4:latest weight is 10GB"
    weight=$(get_registry_model_weight_gb "gemma4:latest")
    if [[ "$weight" == "10" ]]; then
        pass_test
    else
        fail_test "Expected 10, got $weight"
    fi

    begin_test "gemma4:26b weight is 17GB"
    weight=$(get_registry_model_weight_gb "gemma4:26b")
    if [[ "$weight" == "17" ]]; then
        pass_test
    else
        fail_test "Expected 17, got $weight"
    fi

    begin_test "gemma4:31b weight is 19GB"
    weight=$(get_registry_model_weight_gb "gemma4:31b")
    if [[ "$weight" == "19" ]]; then
        pass_test
    else
        fail_test "Expected 19, got $weight"
    fi

    # Test Phi-4 models
    begin_test "phi4:latest weight is 9GB"
    weight=$(get_registry_model_weight_gb "phi4:latest")
    if [[ "$weight" == "9" ]]; then
        pass_test
    else
        fail_test "Expected 9, got $weight"
    fi

    begin_test "phi4-mini:latest weight is 3GB"
    weight=$(get_registry_model_weight_gb "phi4-mini:latest")
    if [[ "$weight" == "3" ]]; then
        pass_test
    else
        fail_test "Expected 3, got $weight"
    fi

    # Test Llama models
    begin_test "llama3.1:8b weight is 5GB"
    weight=$(get_registry_model_weight_gb "llama3.1:8b")
    if [[ "$weight" == "5" ]]; then
        pass_test
    else
        fail_test "Expected 5, got $weight"
    fi

    begin_test "llama3.1:70b weight is 40GB"
    weight=$(get_registry_model_weight_gb "llama3.1:70b")
    if [[ "$weight" == "40" ]]; then
        pass_test
    else
        fail_test "Expected 40, got $weight"
    fi

    # Test Granite models
    begin_test "granite-code:34b weight is 20GB"
    weight=$(get_registry_model_weight_gb "granite-code:34b")
    if [[ "$weight" == "20" ]]; then
        pass_test
    else
        fail_test "Expected 20, got $weight"
    fi
}

#############################################
# Test: Max Context Lookups
#############################################

test_max_context() {
    print_section "Testing Max Context Lookups"

    begin_test "gemma4:31b has 262144 token context"
    local context=$(get_registry_max_context "gemma4:31b")
    if [[ "$context" == "262144" ]]; then
        pass_test
    else
        fail_test "Expected 262144, got $context"
    fi

    begin_test "phi4:latest has 16384 token context"
    context=$(get_registry_max_context "phi4:latest")
    if [[ "$context" == "16384" ]]; then
        pass_test
    else
        fail_test "Expected 16384, got $context"
    fi

    begin_test "llama3.1:8b has 131072 token context"
    context=$(get_registry_max_context "llama3.1:8b")
    if [[ "$context" == "131072" ]]; then
        pass_test
    else
        fail_test "Expected 131072, got $context"
    fi
}

#############################################
# Test: Minimum RAM Requirements
#############################################

test_min_ram() {
    print_section "Testing Minimum RAM Requirements"

    begin_test "gemma4:e2b requires 12GB RAM"
    local min_ram=$(get_registry_min_ram "gemma4:e2b")
    if [[ "$min_ram" == "12" ]]; then
        pass_test
    else
        fail_test "Expected 12, got $min_ram"
    fi

    begin_test "gemma4:31b requires 48GB RAM"
    min_ram=$(get_registry_min_ram "gemma4:31b")
    if [[ "$min_ram" == "48" ]]; then
        pass_test
    else
        fail_test "Expected 48, got $min_ram"
    fi

    begin_test "phi4-mini:latest requires 8GB RAM"
    min_ram=$(get_registry_min_ram "phi4-mini:latest")
    if [[ "$min_ram" == "8" ]]; then
        pass_test
    else
        fail_test "Expected 8, got $min_ram"
    fi

    begin_test "llama3.1:70b requires 48GB RAM"
    min_ram=$(get_registry_min_ram "llama3.1:70b")
    if [[ "$min_ram" == "48" ]]; then
        pass_test
    else
        fail_test "Expected 48, got $min_ram"
    fi
}

#############################################
# Test: KV Cache Bytes Per Token
#############################################

test_kv_bytes_per_token() {
    print_section "Testing KV Cache Bytes Per Token"

    begin_test "gemma4:e2b has correct KV bytes/token"
    local kv_bytes=$(get_registry_kv_bytes_per_token "gemma4:e2b")
    if [[ "$kv_bytes" == "197000" ]]; then
        pass_test
    else
        fail_test "Expected 197000, got $kv_bytes"
    fi

    begin_test "gemma4:31b has correct KV bytes/token"
    kv_bytes=$(get_registry_kv_bytes_per_token "gemma4:31b")
    if [[ "$kv_bytes" == "524288" ]]; then
        pass_test
    else
        fail_test "Expected 524288, got $kv_bytes"
    fi

    begin_test "phi4-mini:latest has correct KV bytes/token"
    kv_bytes=$(get_registry_kv_bytes_per_token "phi4-mini:latest")
    if [[ "$kv_bytes" == "65000" ]]; then
        pass_test
    else
        fail_test "Expected 65000, got $kv_bytes"
    fi
}

#############################################
# Test: Display Names
#############################################

test_display_names() {
    print_section "Testing Display Names"

    begin_test "gemma4:31b has readable display name"
    local display=$(get_registry_display_name "gemma4:31b")
    if [[ "$display" == *"Gemma4"* ]] && [[ "$display" == *"31b"* ]]; then
        pass_test
    else
        fail_test "Expected 'Gemma4 31b' in display name, got: $display"
    fi

    begin_test "phi4-reasoning:latest has readable display name"
    display=$(get_registry_display_name "phi4-reasoning:latest")
    if [[ "$display" == *"Phi-4"* ]] && [[ "$display" == *"Reasoning"* ]]; then
        pass_test
    else
        fail_test "Expected 'Phi-4 Reasoning' in display name, got: $display"
    fi

    begin_test "llama3.1:70b has readable display name"
    display=$(get_registry_display_name "llama3.1:70b")
    if [[ "$display" == *"Llama"* ]] && [[ "$display" == *"70B"* ]]; then
        pass_test
    else
        fail_test "Expected 'Llama 70B' in display name, got: $display"
    fi
}

#############################################
# Test: Coding Priority Rankings
#############################################

test_coding_priority() {
    print_section "Testing Coding Priority Rankings"

    begin_test "gemma4:31b has rank 15 (best coding)"
    local priority=$(get_registry_coding_priority "gemma4:31b")
    if [[ "$priority" == "15" ]]; then
        pass_test
    else
        fail_test "Expected 15, got $priority"
    fi

    begin_test "gemma4:26b has rank 14"
    priority=$(get_registry_coding_priority "gemma4:26b")
    if [[ "$priority" == "14" ]]; then
        pass_test
    else
        fail_test "Expected 14, got $priority"
    fi

    begin_test "phi4-mini:latest has rank 1 (lowest)"
    priority=$(get_registry_coding_priority "phi4-mini:latest")
    if [[ "$priority" == "1" ]]; then
        pass_test
    else
        fail_test "Expected 1, got $priority"
    fi

    begin_test "All priorities are between 1 and 15"
    local all_valid=true
    while IFS= read -r model_key; do
        priority=$(get_registry_coding_priority "$model_key")
        if [[ $priority -lt 1 ]] || [[ $priority -gt 15 ]]; then
            all_valid=false
            if [[ "$VERBOSE" == true ]]; then
                echo "    $model_key has invalid priority: $priority"
            fi
        fi
    done < <(list_all_models)

    if [[ "$all_valid" == true ]]; then
        pass_test
    else
        fail_test "Some models have invalid priority scores"
    fi
}

#############################################
# Test: List All Models
#############################################

test_list_all_models() {
    print_section "Testing List All Models"

    begin_test "list_all_models returns at least 15 models"
    local model_count=$(list_all_models | wc -l | tr -d ' ')
    if [[ $model_count -ge 15 ]]; then
        pass_test
        if [[ "$VERBOSE" == true ]]; then
            echo "    Found $model_count models"
        fi
    else
        fail_test "Expected at least 15 models, got $model_count"
    fi

    begin_test "All listed models have valid format"
    local all_valid=true
    while IFS= read -r model_key; do
        # Check format: family:variant
        if [[ ! "$model_key" =~ ^[a-z0-9._-]+:[a-z0-9._-]+$ ]]; then
            all_valid=false
            if [[ "$VERBOSE" == true ]]; then
                echo "    Invalid format: $model_key"
            fi
        fi
    done < <(list_all_models)

    if [[ "$all_valid" == true ]]; then
        pass_test
    else
        fail_test "Some models have invalid format"
    fi

    begin_test "All models can be looked up in registry"
    all_valid=true
    while IFS= read -r model_key; do
        # Try to get weight (will error if model not in registry)
        if ! get_registry_model_weight_gb "$model_key" &>/dev/null; then
            all_valid=false
            if [[ "$VERBOSE" == true ]]; then
                echo "    Model not in registry: $model_key"
            fi
        fi
    done < <(list_all_models)

    if [[ "$all_valid" == true ]]; then
        pass_test
    else
        fail_test "Some models listed but not in registry"
    fi
}

#############################################
# Test: FIM Model Functions
#############################################

test_fim_models() {
    print_section "Testing FIM Model Functions"

    begin_test "list_fim_models returns FIM models"
    local fim_count=$(list_fim_models | wc -l | tr -d ' ')
    if [[ $fim_count -ge 5 ]]; then
        pass_test
        if [[ "$VERBOSE" == true ]]; then
            echo "    Found $fim_count FIM models"
        fi
    else
        fail_test "Expected at least 5 FIM models, got $fim_count"
    fi

    begin_test "codegemma:7b-code weight is 5GB"
    local weight=$(get_fim_model_weight_gb "codegemma:7b-code")
    if [[ "$weight" == "5" ]]; then
        pass_test
    else
        fail_test "Expected 5, got $weight"
    fi

    begin_test "codestral:latest has highest FIM priority (7)"
    local priority=$(get_fim_coding_priority "codestral:latest")
    if [[ "$priority" == "7" ]]; then
        pass_test
    else
        fail_test "Expected 7, got $priority"
    fi

    begin_test "All FIM models have valid display names"
    local all_valid=true
    while IFS= read -r model_key; do
        local display=$(get_fim_model_display_name "$model_key")
        if [[ -z "$display" ]]; then
            all_valid=false
            if [[ "$VERBOSE" == true ]]; then
                echo "    Empty display name for: $model_key"
            fi
        fi
    done < <(list_fim_models)

    if [[ "$all_valid" == true ]]; then
        pass_test
    else
        fail_test "Some FIM models have invalid display names"
    fi
}

#############################################
# Test: Error Handling
#############################################

test_error_handling() {
    print_section "Testing Error Handling"

    begin_test "Unknown model returns error"
    if get_registry_model_weight_gb "unknown:model" 2>/dev/null; then
        fail_test "Should return error for unknown model"
    else
        pass_test
    fi

    begin_test "Empty string returns error"
    if get_registry_model_weight_gb "" 2>/dev/null; then
        fail_test "Should return error for empty string"
    else
        pass_test
    fi

    begin_test "Invalid format returns error"
    if get_registry_model_weight_gb "no-colon" 2>/dev/null; then
        fail_test "Should return error for invalid format"
    else
        pass_test
    fi
}

#############################################
# Test: Registry Consistency
#############################################

test_registry_consistency() {
    print_section "Testing Registry Consistency"

    begin_test "All models have all required fields"
    local all_complete=true
    while IFS= read -r model_key; do
        # Check each lookup function
        if ! get_registry_model_weight_gb "$model_key" &>/dev/null || \
           ! get_registry_max_context "$model_key" &>/dev/null || \
           ! get_registry_min_ram "$model_key" &>/dev/null || \
           ! get_registry_kv_bytes_per_token "$model_key" &>/dev/null || \
           ! get_registry_display_name "$model_key" &>/dev/null || \
           ! get_registry_coding_priority "$model_key" &>/dev/null; then
            all_complete=false
            if [[ "$VERBOSE" == true ]]; then
                echo "    Incomplete registry for: $model_key"
            fi
        fi
    done < <(list_all_models)

    if [[ "$all_complete" == true ]]; then
        pass_test
    else
        fail_test "Some models missing required fields"
    fi

    begin_test "Model weights are reasonable (1-50GB)"
    local all_reasonable=true
    while IFS= read -r model_key; do
        local weight=$(get_registry_model_weight_gb "$model_key")
        if [[ $weight -lt 1 ]] || [[ $weight -gt 50 ]]; then
            all_reasonable=false
            if [[ "$VERBOSE" == true ]]; then
                echo "    Unreasonable weight for $model_key: ${weight}GB"
            fi
        fi
    done < <(list_all_models)

    if [[ "$all_reasonable" == true ]]; then
        pass_test
    else
        fail_test "Some models have unreasonable weights"
    fi

    begin_test "Min RAM >= Model Weight (with reasonable overhead)"
    local all_reasonable=true
    while IFS= read -r model_key; do
        local weight=$(get_registry_model_weight_gb "$model_key")
        local min_ram=$(get_registry_min_ram "$model_key")
        # Min RAM should be at least weight + 3GB overhead
        if [[ $min_ram -lt $((weight + 1)) ]]; then
            all_reasonable=false
            if [[ "$VERBOSE" == true ]]; then
                echo "    $model_key: min_ram=${min_ram}GB < weight=${weight}GB"
            fi
        fi
    done < <(list_all_models)

    if [[ "$all_reasonable" == true ]]; then
        pass_test
    else
        fail_test "Some models have min_ram < weight"
    fi
}

#############################################
# Main Execution
#############################################

main() {
    init_tests

    # Run all test suites
    test_model_weights
    test_max_context
    test_min_ram
    test_kv_bytes_per_token
    test_display_names
    test_coding_priority
    test_list_all_models
    test_fim_models
    test_error_handling
    test_registry_consistency

    # Print summary and exit
    if print_test_summary; then
        exit 0
    else
        exit 1
    fi
}

# Run main
main "$@"
