#!/bin/bash
# tests/test-hardware-config.sh - Unit tests for hardware configuration functions
#
# Tests all critical functions from lib/hardware-config.sh:
# - calculate_metal_memory() - Metal memory allocation
# - calculate_kv_cache_gb() - KV cache size calculations
# - validate_gpu_fit() - GPU memory fit validation
# - recommend_model() - Model recommendation logic
# - calculate_context_length() - Context window optimization
#
# Usage: ./tests/test-hardware-config.sh [--verbose]

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test helpers
source "$SCRIPT_DIR/helpers.sh"

# Source library files
source "$PROJECT_DIR/lib/common.sh"
source "$PROJECT_DIR/lib/hardware-config.sh"

# Verbose mode
VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE=true
fi

#############################################
# Test: calculate_metal_memory()
#############################################

test_calculate_metal_memory() {
    print_section "Testing calculate_metal_memory()"

    # Test 8GB RAM (90% = 7.6GB)
    begin_test "8GB RAM -> ~7.3GB Metal"
    local result
    result=$(calculate_metal_memory 8)
    local expected=$((8 * 1024 * 1024 * 1024 * 90 / 100))
    if [[ $result -eq $expected ]]; then
        pass_test
    else
        fail_test "Expected $expected, got $result"
    fi

    # Test 16GB RAM (90% = 14.4GB)
    begin_test "16GB RAM -> ~14.4GB Metal"
    result=$(calculate_metal_memory 16)
    expected=$((16 * 1024 * 1024 * 1024 * 90 / 100))
    if [[ $result -eq $expected ]]; then
        pass_test
    else
        fail_test "Expected $expected, got $result"
    fi

    # Test 32GB RAM (95% = 30.4GB)
    begin_test "32GB RAM -> ~30.4GB Metal"
    result=$(calculate_metal_memory 32)
    expected=$((32 * 1024 * 1024 * 1024 * 95 / 100))
    if [[ $result -eq $expected ]]; then
        pass_test
    else
        fail_test "Expected $expected, got $result"
    fi

    # Test 48GB RAM (95% = 45.6GB)
    begin_test "48GB RAM -> ~45.6GB Metal"
    result=$(calculate_metal_memory 48)
    expected=$((48 * 1024 * 1024 * 1024 * 95 / 100))
    if [[ $result -eq $expected ]]; then
        pass_test
    else
        fail_test "Expected $expected, got $result"
    fi

    # Test 64GB RAM (95% = 60.8GB)
    begin_test "64GB RAM -> ~60.8GB Metal"
    result=$(calculate_metal_memory 64)
    expected=$((64 * 1024 * 1024 * 1024 * 95 / 100))
    if [[ $result -eq $expected ]]; then
        pass_test
    else
        fail_test "Expected $expected, got $result"
    fi

    # Test 128GB RAM (should cap at 80GB)
    begin_test "128GB RAM -> capped at 80GB Metal"
    result=$(calculate_metal_memory 128)
    expected=$((80 * 1024 * 1024 * 1024))
    if [[ $result -eq $expected ]]; then
        pass_test
    else
        fail_test "Expected $expected (80GB cap), got $result"
    fi
}

#############################################
# Test: calculate_kv_cache_gb()
#############################################

test_calculate_kv_cache_gb() {
    print_section "Testing calculate_kv_cache_gb()"

    # Test gemma4:e2b model (197K bytes/token, conservative)
    begin_test "gemma4:e2b @ 64K context -> ~12GB KV cache"
    local result
    result=$(calculate_kv_cache_gb "gemma4:e2b" 65536)
    if [[ $result -ge 11 && $result -le 13 ]]; then
        pass_test
    else
        fail_test "Expected ~12GB, got ${result}GB"
    fi

    # Test gemma4:latest model (295K bytes/token, conservative)
    begin_test "gemma4:latest @ 64K context -> ~18GB KV cache"
    result=$(calculate_kv_cache_gb "gemma4:latest" 65536)
    if [[ $result -ge 17 && $result -le 19 ]]; then
        pass_test
    else
        fail_test "Expected ~18GB, got ${result}GB"
    fi

    # Test gemma4:26b model (400K bytes/token, conservative)
    begin_test "gemma4:26b @ 64K context -> ~24GB KV cache"
    result=$(calculate_kv_cache_gb "gemma4:26b" 65536)
    if [[ $result -ge 23 && $result -le 25 ]]; then
        pass_test
    else
        fail_test "Expected ~24GB, got ${result}GB"
    fi

    # Test gemma4:31b model (524K bytes/token, conservative)
    begin_test "gemma4:31b @ 64K context -> ~32GB KV cache"
    result=$(calculate_kv_cache_gb "gemma4:31b" 65536)
    if [[ $result -ge 31 && $result -le 33 ]]; then
        pass_test
    else
        fail_test "Expected ~32GB, got ${result}GB"
    fi

    # Test with 128K context (double the cache)
    begin_test "gemma4:latest @ 128K context -> ~36GB KV cache"
    result=$(calculate_kv_cache_gb "gemma4:latest" 131072)
    if [[ $result -ge 35 && $result -le 37 ]]; then
        pass_test
    else
        fail_test "Expected ~36GB, got ${result}GB"
    fi
}

#############################################
# Test: validate_gpu_fit()
#############################################

test_validate_gpu_fit() {
    print_section "Testing validate_gpu_fit()"

    # Test: 16GB RAM with gemma4:e2b @ 32K (should fit)
    begin_test "16GB RAM + gemma4:e2b @ 32K -> should fit"
    if validate_gpu_fit 16 "gemma4:e2b" 32768; then
        pass_test
    else
        fail_test "Should fit on GPU"
    fi

    # Test: 16GB RAM with gemma4:latest @ 64K (should NOT fit with conservative values)
    begin_test "16GB RAM + gemma4:latest @ 64K -> should NOT fit"
    if validate_gpu_fit 16 "gemma4:latest" 65536; then
        fail_test "Should NOT fit on GPU"
    else
        pass_test
    fi

    # Test: 16GB RAM with gemma4:31b @ 64K (should NOT fit)
    begin_test "16GB RAM + gemma4:31b @ 64K -> should NOT fit"
    if validate_gpu_fit 16 "gemma4:31b" 65536; then
        fail_test "Should NOT fit on GPU"
    else
        pass_test
    fi

    # Test: 64GB RAM with gemma4:31b @ 64K (should fit)
    begin_test "64GB RAM + gemma4:31b @ 64K -> should fit"
    if validate_gpu_fit 64 "gemma4:31b" 65536; then
        pass_test
    else
        fail_test "Should fit on GPU"
    fi

    # Test: 32GB RAM with gemma4:26b @ 32K (should fit)
    begin_test "32GB RAM + gemma4:26b @ 32K -> should fit"
    if validate_gpu_fit 32 "gemma4:26b" 32768; then
        pass_test
    else
        fail_test "Should fit on GPU"
    fi

    # Test: Edge case - exactly at limit
    begin_test "48GB RAM + gemma4:26b @ 65K -> edge case"
    # Just verify function doesn't crash
    validate_gpu_fit 48 "gemma4:26b" 65536 || true
    pass_test
}

#############################################
# Test: recommend_model()
#############################################

test_recommend_model() {
    print_section "Testing recommend_model()"

    # Test 12GB RAM -> should recommend a model that fits with min_ram <= 12GB
    begin_test "12GB RAM -> valid model"
    local result
    result=$(recommend_model 12)
    if [[ -n "$result" ]]; then
        pass_test
    else
        fail_test "Expected valid model, got empty"
    fi

    # Test 16GB RAM -> should recommend a model that fits
    begin_test "16GB RAM -> valid model"
    result=$(recommend_model 16)
    if [[ -n "$result" ]]; then
        pass_test
    else
        fail_test "Expected valid model, got empty"
    fi

    # Test 24GB RAM -> should recommend a model
    begin_test "24GB RAM -> valid model"
    result=$(recommend_model 24)
    if [[ -n "$result" ]]; then
        pass_test
    else
        fail_test "Expected valid model, got empty"
    fi

    # Test 32GB RAM -> should recommend a model
    begin_test "32GB RAM -> valid model"
    result=$(recommend_model 32)
    if [[ -n "$result" ]]; then
        pass_test
    else
        fail_test "Expected valid model, got empty"
    fi

    # Test 48GB RAM -> should recommend a large model
    begin_test "48GB RAM -> valid model"
    result=$(recommend_model 48)
    if [[ -n "$result" ]]; then
        pass_test
    else
        fail_test "Expected valid model, got empty"
    fi

    # Test 64GB RAM -> should recommend a very large model
    begin_test "64GB RAM -> valid model"
    result=$(recommend_model 64)
    if [[ -n "$result" ]]; then
        pass_test
    else
        fail_test "Expected valid model, got empty"
    fi
}

#############################################
# Test: calculate_context_length()
#############################################

test_calculate_context_length() {
    print_section "Testing calculate_context_length()"

    # Test gemma4:e2b model
    begin_test "16GB RAM + gemma4:e2b -> 32K context"
    local result
    result=$(calculate_context_length 16 "gemma4:e2b")
    if [[ $result -eq 32768 ]]; then
        pass_test
    else
        fail_test "Expected 32768, got $result"
    fi

    begin_test "32GB RAM + gemma4:e2b -> 64K context"
    result=$(calculate_context_length 32 "gemma4:e2b")
    if [[ $result -eq 65536 ]]; then
        pass_test
    else
        fail_test "Expected 65536, got $result"
    fi

    begin_test "48GB RAM + gemma4:e2b -> 128K context"
    result=$(calculate_context_length 48 "gemma4:e2b")
    if [[ $result -eq 131072 ]]; then
        pass_test
    else
        fail_test "Expected 131072, got $result"
    fi

    # Test gemma4:latest model (GPU-validated contexts)
    begin_test "16GB RAM + gemma4:latest -> 16K context"
    result=$(calculate_context_length 16 "gemma4:latest")
    if [[ $result -eq 16384 ]]; then
        pass_test
    else
        fail_test "Expected 16384, got $result"
    fi

    begin_test "32GB RAM + gemma4:latest -> 64K context"
    result=$(calculate_context_length 32 "gemma4:latest")
    if [[ $result -eq 65536 ]]; then
        pass_test
    else
        fail_test "Expected 65536, got $result"
    fi

    begin_test "48GB RAM + gemma4:latest -> 64K context"
    result=$(calculate_context_length 48 "gemma4:latest")
    if [[ $result -eq 65536 ]]; then
        pass_test
    else
        fail_test "Expected 65536, got $result"
    fi

    # Test gemma4:26b model (new algorithm is more conservative, validates GPU fit)
    begin_test "32GB RAM + gemma4:26b -> valid context"
    result=$(calculate_context_length 32 "gemma4:26b")
    if [[ $result -ge 16384 && $result -le 65536 ]]; then
        pass_test
    else
        fail_test "Expected 16K-64K, got $result"
    fi

    begin_test "48GB RAM + gemma4:26b -> valid context"
    result=$(calculate_context_length 48 "gemma4:26b")
    if [[ $result -ge 32768 && $result -le 131072 ]]; then
        pass_test
    else
        fail_test "Expected 32K-128K, got $result"
    fi

    begin_test "64GB RAM + gemma4:26b -> valid context"
    result=$(calculate_context_length 64 "gemma4:26b")
    if [[ $result -ge 32768 && $result -le 131072 ]]; then
        pass_test
    else
        fail_test "Expected 32K-128K, got $result"
    fi

    # Test gemma4:31b model (new algorithm validates GPU fit)
    begin_test "48GB RAM + gemma4:31b -> valid context"
    result=$(calculate_context_length 48 "gemma4:31b")
    if [[ $result -ge 16384 && $result -le 65536 ]]; then
        pass_test
    else
        fail_test "Expected 16K-64K, got $result"
    fi

    begin_test "64GB RAM + gemma4:31b -> valid context"
    result=$(calculate_context_length 64 "gemma4:31b")
    if [[ $result -ge 16384 && $result -le 65536 ]]; then
        pass_test
    else
        fail_test "Expected 16K-64K, got $result"
    fi

    begin_test "80GB RAM + gemma4:31b -> valid context"
    result=$(calculate_context_length 80 "gemma4:31b")
    if [[ $result -ge 32768 && $result -le 131072 ]]; then
        pass_test
    else
        fail_test "Expected 32K-128K, got $result"
    fi
}

#############################################
# Test: calculate_num_parallel()
#############################################

test_calculate_num_parallel() {
    print_section "Testing calculate_num_parallel()"

    # Test various RAM tiers
    begin_test "16GB RAM -> 1 parallel"
    local result
    result=$(calculate_num_parallel 16)
    if [[ $result -eq 1 ]]; then
        pass_test
    else
        fail_test "Expected 1, got $result"
    fi

    begin_test "24GB RAM -> 2 parallel"
    result=$(calculate_num_parallel 24)
    if [[ $result -eq 2 ]]; then
        pass_test
    else
        fail_test "Expected 2, got $result"
    fi

    begin_test "32GB RAM -> 3 parallel"
    result=$(calculate_num_parallel 32)
    if [[ $result -eq 3 ]]; then
        pass_test
    else
        fail_test "Expected 3, got $result"
    fi

    begin_test "48GB RAM -> 4 parallel"
    result=$(calculate_num_parallel 48)
    if [[ $result -eq 4 ]]; then
        pass_test
    else
        fail_test "Expected 4, got $result"
    fi

    begin_test "64GB RAM -> 6 parallel"
    result=$(calculate_num_parallel 64)
    if [[ $result -eq 6 ]]; then
        pass_test
    else
        fail_test "Expected 6, got $result"
    fi
}

#############################################
# Test: get_model_weight_gb()
#############################################

test_get_model_weight_gb() {
    print_section "Testing get_model_weight_gb()"

    begin_test "gemma4:e2b -> 7GB"
    local result
    result=$(get_model_weight_gb "gemma4:e2b")
    if [[ $result -eq 7 ]]; then
        pass_test
    else
        fail_test "Expected 7, got $result"
    fi

    begin_test "gemma4:latest -> 10GB"
    result=$(get_model_weight_gb "gemma4:latest")
    if [[ $result -eq 10 ]]; then
        pass_test
    else
        fail_test "Expected 10, got $result"
    fi

    begin_test "gemma4:26b -> 17GB"
    result=$(get_model_weight_gb "gemma4:26b")
    if [[ $result -eq 17 ]]; then
        pass_test
    else
        fail_test "Expected 17, got $result"
    fi

    begin_test "gemma4:31b -> 19GB"
    result=$(get_model_weight_gb "gemma4:31b")
    if [[ $result -eq 19 ]]; then
        pass_test
    else
        fail_test "Expected 19, got $result"
    fi
}

#############################################
# Test: get_model_size()
#############################################

test_get_model_variant() {
    print_section "Testing get_model_variant()"

    begin_test "gemma4:e2b -> e2b"
    local result
    result=$(get_model_variant "gemma4:e2b")
    if [[ "$result" == "e2b" ]]; then
        pass_test
    else
        fail_test "Expected 'e2b', got '$result'"
    fi

    begin_test "gemma4:latest -> latest"
    result=$(get_model_variant "gemma4:latest")
    if [[ "$result" == "latest" ]]; then
        pass_test
    else
        fail_test "Expected 'latest', got '$result'"
    fi

    begin_test "gemma4:26b -> 26b"
    result=$(get_model_variant "gemma4:26b")
    if [[ "$result" == "26b" ]]; then
        pass_test
    else
        fail_test "Expected '26b', got '$result'"
    fi

    begin_test "gemma4 (no variant) -> latest"
    result=$(get_model_variant "gemma4")
    if [[ "$result" == "latest" ]]; then
        pass_test
    else
        fail_test "Expected 'latest', got '$result'"
    fi
}

#############################################
# Test: Registry Functions (tested indirectly)
#############################################
# Note: Registry functions (get_registry_*) are tested indirectly
# through the wrapper functions above (get_model_weight_gb, etc.)

#############################################
# Main Execution
#############################################

main() {
    init_tests

    # Run all test suites
    test_calculate_metal_memory
    test_calculate_kv_cache_gb
    test_validate_gpu_fit
    test_recommend_model
    test_calculate_context_length
    test_calculate_num_parallel
    test_get_model_weight_gb
    test_get_model_variant

    # Print summary and exit
    if print_test_summary; then
        exit 0
    else
        exit 1
    fi
}

# Run main
main "$@"
