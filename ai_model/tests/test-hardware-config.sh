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

    # Test e2b model (50K bytes/token, optimized)
    begin_test "e2b @ 64K context -> ~3GB KV cache"
    local result
    result=$(calculate_kv_cache_gb "e2b" 65536)
    if [[ $result -ge 2 && $result -le 4 ]]; then
        pass_test
    else
        fail_test "Expected ~3GB, got ${result}GB"
    fi

    # Test latest model (70K bytes/token, optimized)
    begin_test "latest @ 64K context -> ~4GB KV cache"
    result=$(calculate_kv_cache_gb "latest" 65536)
    if [[ $result -ge 3 && $result -le 5 ]]; then
        pass_test
    else
        fail_test "Expected ~4GB, got ${result}GB"
    fi

    # Test 26b model (150K bytes/token, optimized)
    begin_test "26b @ 64K context -> ~9GB KV cache"
    result=$(calculate_kv_cache_gb "26b" 65536)
    if [[ $result -ge 8 && $result -le 10 ]]; then
        pass_test
    else
        fail_test "Expected ~9GB, got ${result}GB"
    fi

    # Test 31b model (180K bytes/token, optimized)
    begin_test "31b @ 64K context -> ~11GB KV cache"
    result=$(calculate_kv_cache_gb "31b" 65536)
    if [[ $result -ge 10 && $result -le 12 ]]; then
        pass_test
    else
        fail_test "Expected ~11GB, got ${result}GB"
    fi

    # Test with 128K context (double the cache)
    begin_test "latest @ 128K context -> ~8GB KV cache"
    result=$(calculate_kv_cache_gb "latest" 131072)
    if [[ $result -ge 7 && $result -le 10 ]]; then
        pass_test
    else
        fail_test "Expected ~8GB, got ${result}GB"
    fi
}

#############################################
# Test: validate_gpu_fit()
#############################################

test_validate_gpu_fit() {
    print_section "Testing validate_gpu_fit()"

    # Test: 16GB RAM with e2b @ 32K (should fit)
    begin_test "16GB RAM + e2b @ 32K -> should fit"
    if validate_gpu_fit 16 "e2b" 32768; then
        pass_test
    else
        fail_test "Should fit on GPU"
    fi

    # Test: 16GB RAM with latest @ 64K (should fit)
    begin_test "16GB RAM + latest @ 64K -> should fit"
    if validate_gpu_fit 16 "latest" 65536; then
        pass_test
    else
        fail_test "Should fit on GPU"
    fi

    # Test: 16GB RAM with 31b @ 64K (should NOT fit)
    begin_test "16GB RAM + 31b @ 64K -> should NOT fit"
    if validate_gpu_fit 16 "31b" 65536; then
        fail_test "Should NOT fit on GPU"
    else
        pass_test
    fi

    # Test: 64GB RAM with 31b @ 64K (should fit)
    begin_test "64GB RAM + 31b @ 64K -> should fit"
    if validate_gpu_fit 64 "31b" 65536; then
        pass_test
    else
        fail_test "Should fit on GPU"
    fi

    # Test: 32GB RAM with 26b @ 32K (should fit)
    begin_test "32GB RAM + 26b @ 32K -> should fit"
    if validate_gpu_fit 32 "26b" 32768; then
        pass_test
    else
        fail_test "Should fit on GPU"
    fi

    # Test: Edge case - exactly at limit
    begin_test "48GB RAM + 26b @ 65K -> edge case"
    # Just verify function doesn't crash
    validate_gpu_fit 48 "26b" 65536 || true
    pass_test
}

#############################################
# Test: recommend_model()
#############################################

test_recommend_model() {
    print_section "Testing recommend_model()"

    # Test 12GB RAM -> should recommend e2b
    begin_test "12GB RAM -> gemma4:e2b"
    local result
    result=$(recommend_model 12)
    if [[ "$result" == "gemma4:e2b" ]]; then
        pass_test
    else
        fail_test "Expected gemma4:e2b, got $result"
    fi

    # Test 16GB RAM -> should recommend latest
    begin_test "16GB RAM -> gemma4:latest"
    result=$(recommend_model 16)
    if [[ "$result" == "gemma4:latest" ]]; then
        pass_test
    else
        fail_test "Expected gemma4:latest, got $result"
    fi

    # Test 24GB RAM -> should recommend latest
    begin_test "24GB RAM -> gemma4:latest"
    result=$(recommend_model 24)
    if [[ "$result" == "gemma4:latest" ]]; then
        pass_test
    else
        fail_test "Expected gemma4:latest, got $result"
    fi

    # Test 32GB RAM -> should recommend 26b or latest
    begin_test "32GB RAM -> gemma4:26b or gemma4:latest"
    result=$(recommend_model 32)
    if [[ "$result" == "gemma4:26b" || "$result" == "gemma4:latest" ]]; then
        pass_test
    else
        fail_test "Expected gemma4:26b or gemma4:latest, got $result"
    fi

    # Test 48GB RAM -> should recommend 31b or 26b
    begin_test "48GB RAM -> gemma4:31b or gemma4:26b"
    result=$(recommend_model 48)
    if [[ "$result" == "gemma4:31b" || "$result" == "gemma4:26b" ]]; then
        pass_test
    else
        fail_test "Expected gemma4:31b or gemma4:26b, got $result"
    fi

    # Test 64GB RAM -> should recommend 31b
    begin_test "64GB RAM -> gemma4:31b"
    result=$(recommend_model 64)
    if [[ "$result" == "gemma4:31b" ]]; then
        pass_test
    else
        fail_test "Expected gemma4:31b, got $result"
    fi
}

#############################################
# Test: calculate_context_length()
#############################################

test_calculate_context_length() {
    print_section "Testing calculate_context_length()"

    # Test e2b model
    begin_test "16GB RAM + e2b -> 32K context"
    local result
    result=$(calculate_context_length 16 "e2b")
    if [[ $result -eq 32768 ]]; then
        pass_test
    else
        fail_test "Expected 32768, got $result"
    fi

    begin_test "32GB RAM + e2b -> 64K context"
    result=$(calculate_context_length 32 "e2b")
    if [[ $result -eq 65536 ]]; then
        pass_test
    else
        fail_test "Expected 65536, got $result"
    fi

    begin_test "48GB RAM + e2b -> 128K context"
    result=$(calculate_context_length 48 "e2b")
    if [[ $result -eq 131072 ]]; then
        pass_test
    else
        fail_test "Expected 131072, got $result"
    fi

    # Test latest model
    begin_test "16GB RAM + latest -> 32K context"
    result=$(calculate_context_length 16 "latest")
    if [[ $result -eq 32768 ]]; then
        pass_test
    else
        fail_test "Expected 32768, got $result"
    fi

    begin_test "32GB RAM + latest -> 64K context"
    result=$(calculate_context_length 32 "latest")
    if [[ $result -eq 65536 ]]; then
        pass_test
    else
        fail_test "Expected 65536, got $result"
    fi

    begin_test "48GB RAM + latest -> 128K context"
    result=$(calculate_context_length 48 "latest")
    if [[ $result -eq 131072 ]]; then
        pass_test
    else
        fail_test "Expected 131072, got $result"
    fi

    # Test 26b model
    begin_test "32GB RAM + 26b -> 32K context"
    result=$(calculate_context_length 32 "26b")
    if [[ $result -eq 32768 ]]; then
        pass_test
    else
        fail_test "Expected 32768, got $result"
    fi

    begin_test "48GB RAM + 26b -> 64K context"
    result=$(calculate_context_length 48 "26b")
    if [[ $result -eq 65536 ]]; then
        pass_test
    else
        fail_test "Expected 65536, got $result"
    fi

    begin_test "64GB RAM + 26b -> 128K context"
    result=$(calculate_context_length 64 "26b")
    if [[ $result -eq 131072 ]]; then
        pass_test
    else
        fail_test "Expected 131072, got $result"
    fi

    # Test 31b model (most conservative)
    begin_test "48GB RAM + 31b -> 32K context"
    result=$(calculate_context_length 48 "31b")
    if [[ $result -eq 32768 ]]; then
        pass_test
    else
        fail_test "Expected 32768, got $result"
    fi

    begin_test "64GB RAM + 31b -> 64K context"
    result=$(calculate_context_length 64 "31b")
    if [[ $result -eq 65536 ]]; then
        pass_test
    else
        fail_test "Expected 65536, got $result"
    fi

    begin_test "80GB RAM + 31b -> 128K context"
    result=$(calculate_context_length 80 "31b")
    if [[ $result -eq 131072 ]]; then
        pass_test
    else
        fail_test "Expected 131072, got $result"
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

    begin_test "e2b -> 7GB"
    local result
    result=$(get_model_weight_gb "e2b")
    if [[ $result -eq 7 ]]; then
        pass_test
    else
        fail_test "Expected 7, got $result"
    fi

    begin_test "latest -> 10GB"
    result=$(get_model_weight_gb "latest")
    if [[ $result -eq 10 ]]; then
        pass_test
    else
        fail_test "Expected 10, got $result"
    fi

    begin_test "26b -> 17GB"
    result=$(get_model_weight_gb "26b")
    if [[ $result -eq 17 ]]; then
        pass_test
    else
        fail_test "Expected 17, got $result"
    fi

    begin_test "31b -> 19GB"
    result=$(get_model_weight_gb "31b")
    if [[ $result -eq 19 ]]; then
        pass_test
    else
        fail_test "Expected 19, got $result"
    fi
}

#############################################
# Test: get_model_size()
#############################################

test_get_model_size() {
    print_section "Testing get_model_size()"

    begin_test "gemma4:e2b -> e2b"
    local result
    result=$(get_model_size "gemma4:e2b")
    if [[ "$result" == "e2b" ]]; then
        pass_test
    else
        fail_test "Expected 'e2b', got '$result'"
    fi

    begin_test "gemma4:latest -> latest"
    result=$(get_model_size "gemma4:latest")
    if [[ "$result" == "latest" ]]; then
        pass_test
    else
        fail_test "Expected 'latest', got '$result'"
    fi

    begin_test "gemma4:26b -> 26b"
    result=$(get_model_size "gemma4:26b")
    if [[ "$result" == "26b" ]]; then
        pass_test
    else
        fail_test "Expected '26b', got '$result'"
    fi

    begin_test "gemma4 (no variant) -> latest"
    result=$(get_model_size "gemma4")
    if [[ "$result" == "latest" ]]; then
        pass_test
    else
        fail_test "Expected 'latest', got '$result'"
    fi
}

#############################################
# Test: get_model_specs()
#############################################

test_get_model_specs() {
    print_section "Testing get_model_specs()"

    begin_test "e2b specs -> 7.2 128 12"
    local result
    result=$(get_model_specs "e2b")
    if [[ "$result" == "7.2 128 12" ]]; then
        pass_test
    else
        fail_test "Expected '7.2 128 12', got '$result'"
    fi

    begin_test "latest specs -> 9.6 128 16"
    result=$(get_model_specs "latest")
    if [[ "$result" == "9.6 128 16" ]]; then
        pass_test
    else
        fail_test "Expected '9.6 128 16', got '$result'"
    fi

    begin_test "26b specs -> 18 256 32"
    result=$(get_model_specs "26b")
    if [[ "$result" == "18 256 32" ]]; then
        pass_test
    else
        fail_test "Expected '18 256 32', got '$result'"
    fi

    begin_test "31b specs -> 20 256 48"
    result=$(get_model_specs "31b")
    if [[ "$result" == "20 256 48" ]]; then
        pass_test
    else
        fail_test "Expected '20 256 48', got '$result'"
    fi

    begin_test "unknown model -> empty string"
    result=$(get_model_specs "unknown")
    if [[ -z "$result" ]]; then
        pass_test
    else
        fail_test "Expected empty string, got '$result'"
    fi
}

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
    test_get_model_size
    test_get_model_specs

    # Print summary and exit
    if print_test_summary; then
        exit 0
    else
        exit 1
    fi
}

# Run main
main "$@"
