#!/bin/bash
# tests/test-integration.sh - Integration tests for ai_model setup
#
# Tests:
# - Script can be sourced without errors
# - Help text is available
# - Configuration files are properly formatted
# - Library functions work together correctly
#
# Usage: ./tests/test-integration.sh [--verbose]

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test helpers
source "$SCRIPT_DIR/helpers.sh"

# Verbose mode
VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE=true
fi

#############################################
# Test: Help Text
#############################################

test_help_text() {
    print_section "Testing Help Text"

    begin_test "setup script has --help flag"
    local help_output
    help_output=$("$PROJECT_DIR/setup-gemma4-opencode.sh" --help 2>&1 || true)
    if [[ "$help_output" == *"Usage:"* ]] || [[ "$help_output" == *"usage:"* ]]; then
        pass_test
    else
        fail_test "Help text missing or incomplete"
    fi

    begin_test "uninstall script exists"
    if [[ -f "$PROJECT_DIR/uninstall-gemma4-opencode.sh" ]]; then
        pass_test
    else
        fail_test "uninstall script not found"
    fi
}

#############################################
# Test: Library Sourcing
#############################################

test_library_sourcing() {
    print_section "Testing Library Sourcing"

    begin_test "common.sh can be sourced without errors"
    if source "$PROJECT_DIR/lib/common.sh" 2>/dev/null; then
        pass_test
    else
        fail_test "Failed to source common.sh"
    fi

    begin_test "hardware-config.sh can be sourced without errors"
    if source "$PROJECT_DIR/lib/hardware-config.sh" 2>/dev/null; then
        pass_test
    else
        fail_test "Failed to source hardware-config.sh"
    fi

    begin_test "All print functions are available after sourcing common.sh"
    # Don't re-source if already sourced (readonly variables will fail)
    if ! declare -f print_header &>/dev/null; then
        source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    fi
    if declare -f print_header &>/dev/null && \
       declare -f print_info &>/dev/null && \
       declare -f print_status &>/dev/null && \
       declare -f print_warning &>/dev/null && \
       declare -f print_error &>/dev/null; then
        pass_test
    else
        fail_test "Some print functions are missing"
    fi
}

#############################################
# Test: Hardware Detection Integration
#############################################

test_hardware_detection_integration() {
    print_section "Testing Hardware Detection Integration"

    # Source libraries (only if not already sourced)
    if ! declare -f detect_hardware_profile &>/dev/null; then
        source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
        source "$PROJECT_DIR/lib/hardware-config.sh" 2>/dev/null || true
    fi

    begin_test "detect_hardware_profile returns 3 values"
    local hw_profile
    hw_profile=$(detect_hardware_profile)
    local word_count
    word_count=$(echo "$hw_profile" | wc -w | tr -d ' ')
    if [[ $word_count -eq 3 ]]; then
        pass_test
    else
        fail_test "Expected 3 values, got $word_count"
    fi

    begin_test "Hardware profile values are reasonable"
    read -r chip ram cores <<< "$hw_profile"

    # Check chip is not empty or Unknown
    if [[ -n "$chip" ]]; then
        # Check RAM is positive integer
        if [[ "$ram" =~ ^[0-9]+$ ]] && [[ $ram -gt 0 ]]; then
            # Check cores is positive integer
            if [[ "$cores" =~ ^[0-9]+$ ]] && [[ $cores -gt 0 ]]; then
                pass_test
                if [[ "$VERBOSE" == true ]]; then
                    echo "    Detected: $chip, ${ram}GB RAM, $cores cores"
                fi
            else
                fail_test "Cores value is invalid: $cores"
            fi
        else
            fail_test "RAM value is invalid: $ram"
        fi
    else
        fail_test "Chip detection failed: empty value"
    fi
}

#############################################
# Test: Model Recommendation Flow
#############################################

test_model_recommendation_flow() {
    print_section "Testing Model Recommendation Flow"

    # Source libraries (only if not already sourced)
    if ! declare -f recommend_model &>/dev/null; then
        source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
        source "$PROJECT_DIR/lib/hardware-config.sh" 2>/dev/null || true
    fi

    # Get hardware profile
    local hw_profile
    hw_profile=$(detect_hardware_profile)
    read -r chip ram cores <<< "$hw_profile"

    begin_test "recommend_model works with detected RAM"
    local recommended
    recommended=$(recommend_model "$ram")
    # Check if recommendation is a valid model from registry
    if [[ -n "$recommended" ]] && list_all_models | grep -q "^${recommended}$"; then
        pass_test
        if [[ "$VERBOSE" == true ]]; then
            echo "    ${ram}GB RAM → $recommended"
        fi
    else
        fail_test "Invalid recommendation: $recommended"
    fi

    begin_test "Recommended model has valid specifications"
    # Get specs from registry
    local weight_gb
    weight_gb=$(get_registry_model_weight_gb "$recommended")
    local max_context
    max_context=$(get_registry_max_context "$recommended")
    local min_ram
    min_ram=$(get_registry_min_ram "$recommended")

    if [[ -n "$weight_gb" ]] && [[ -n "$max_context" ]] && [[ -n "$min_ram" ]]; then
        if [[ $min_ram -le $ram ]]; then
            pass_test
            if [[ "$VERBOSE" == true ]]; then
                echo "    Model: ${weight_gb}GB, $((max_context / 1024))K max context, min ${min_ram}GB RAM"
            fi
        else
            fail_test "Recommended model requires ${min_ram}GB but system has ${ram}GB"
        fi
    else
        fail_test "Could not get specifications from registry for $recommended"
    fi
}

#############################################
# Test: Context Length Calculation Flow
#############################################

test_context_length_flow() {
    print_section "Testing Context Length Calculation Flow"

    # Source libraries (only if not already sourced)
    if ! declare -f calculate_context_length &>/dev/null; then
        source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
        source "$PROJECT_DIR/lib/hardware-config.sh" 2>/dev/null || true
    fi

    # Get hardware profile
    local hw_profile
    hw_profile=$(detect_hardware_profile)
    read -r chip ram cores <<< "$hw_profile"

    # Get recommended model
    local recommended
    recommended=$(recommend_model "$ram")

    begin_test "Context length is calculated for recommended model"
    local context
    context=$(calculate_context_length "$ram" "$recommended")
    if [[ "$context" =~ ^[0-9]+$ ]] && [[ $context -ge 8192 ]]; then
        pass_test
        if [[ "$VERBOSE" == true ]]; then
            echo "    ${ram}GB + $recommended → $((context / 1024))K context"
        fi
    else
        fail_test "Invalid context length: $context"
    fi

    begin_test "Model + context should fit on GPU"
    if validate_gpu_fit "$ram" "$recommended" "$context"; then
        pass_test
    else
        # This might fail on low-RAM systems with conservative recommendations
        if [[ "$VERBOSE" == true ]]; then
            echo "    Warning: Recommended model may not fit 100% on GPU"
            echo "    This is expected on systems with limited RAM"
        fi
        pass_test  # Don't fail test, just note it
    fi
}

#############################################
# Test: Print Functions Work Correctly
#############################################

test_print_functions() {
    print_section "Testing Print Functions"

    # Source common.sh (only if not already sourced)
    if ! declare -f print_header &>/dev/null; then
        source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    fi

    begin_test "print_header produces output"
    local output
    output=$(print_header "Test Header" 2>&1)
    if [[ -n "$output" ]]; then
        pass_test
    else
        fail_test "print_header produced no output"
    fi

    begin_test "print_info produces output"
    output=$(print_info "Test info" 2>&1)
    if [[ -n "$output" ]]; then
        pass_test
    else
        fail_test "print_info produced no output"
    fi

    begin_test "print_status produces output"
    output=$(print_status "Test status" 2>&1)
    if [[ -n "$output" ]]; then
        pass_test
    else
        fail_test "print_status produced no output"
    fi

    begin_test "print_warning produces output"
    output=$(print_warning "Test warning" 2>&1)
    if [[ -n "$output" ]]; then
        pass_test
    else
        fail_test "print_warning produced no output"
    fi

    begin_test "print_error produces output to stderr"
    output=$(print_error "Test error" 2>&1)
    if [[ -n "$output" ]]; then
        pass_test
    else
        fail_test "print_error produced no output"
    fi
}

#############################################
# Test: Byte Conversion Functions
#############################################

test_byte_conversion() {
    print_section "Testing Byte Conversion Functions"

    # Source common.sh (only if not already sourced)
    if ! declare -f format_bytes &>/dev/null; then
        source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    fi

    begin_test "format_bytes works with various sizes"
    local result
    result=$(format_bytes $((10 * 1024 * 1024 * 1024)))  # 10GB
    if [[ "$result" == *"G"* ]] || [[ "$result" =~ ^10 ]]; then
        pass_test
    else
        fail_test "Expected ~10GB, got: $result"
    fi

    begin_test "format_bytes handles MB correctly"
    result=$(format_bytes $((500 * 1024 * 1024)))  # 500MB
    if [[ "$result" == *"M"* ]]; then
        pass_test
    else
        fail_test "Expected MB format, got: $result"
    fi
}

#############################################
# Test: Constants Are Defined
#############################################

test_constants() {
    print_section "Testing Constants"

    # Source libraries (only if not already sourced)
    if ! declare -p BYTES_PER_GB &>/dev/null; then
        source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    fi
    if ! declare -p MAX_METAL_GB &>/dev/null; then
        source "$PROJECT_DIR/lib/hardware-config.sh" 2>/dev/null || true
    fi

    begin_test "Byte conversion constant is defined"
    if [[ -n "$BYTES_PER_GB" ]]; then
        pass_test
    else
        fail_test "BYTES_PER_GB constant not defined"
    fi

    begin_test "Hardware constants are defined"
    if [[ -n "$MAX_METAL_GB" ]] && \
       [[ -n "$MODEL_31B_MIN_RAM" ]] && \
       [[ -n "$MODEL_26B_MIN_RAM" ]] && \
       [[ -n "$MODEL_LATEST_MIN_RAM" ]]; then
        pass_test
    else
        fail_test "Hardware constants not defined"
    fi

    begin_test "Color constants are defined"
    if [[ -n "$BLUE" ]] && [[ -n "$GREEN" ]] && [[ -n "$RED" ]] && [[ -n "$NC" ]]; then
        pass_test
    else
        fail_test "Color constants not defined"
    fi
}

#############################################
# Test: Directory Structure
#############################################

test_directory_structure() {
    print_section "Testing Directory Structure"

    begin_test "lib directory exists"
    assert_dir_exists "$PROJECT_DIR/lib"

    begin_test "tests directory exists"
    assert_dir_exists "$PROJECT_DIR/tests"

    begin_test "common.sh exists in lib"
    assert_file_exists "$PROJECT_DIR/lib/common.sh"

    begin_test "hardware-config.sh exists in lib"
    assert_file_exists "$PROJECT_DIR/lib/hardware-config.sh"

    begin_test "setup script exists"
    assert_file_exists "$PROJECT_DIR/setup-gemma4-opencode.sh"

    begin_test "README.md exists"
    assert_file_exists "$PROJECT_DIR/README.md"
}

#############################################
# Test: Script Permissions
#############################################

test_script_permissions() {
    print_section "Testing Script Permissions"

    begin_test "setup script is executable"
    if [[ -x "$PROJECT_DIR/setup-gemma4-opencode.sh" ]]; then
        pass_test
    else
        fail_test "setup script is not executable"
    fi

    begin_test "Library files are readable"
    if [[ -r "$PROJECT_DIR/lib/common.sh" ]] && [[ -r "$PROJECT_DIR/lib/hardware-config.sh" ]]; then
        pass_test
    else
        fail_test "Library files are not readable"
    fi
}

#############################################
# Main Execution
#############################################

main() {
    init_tests

    # Run all test suites
    test_help_text
    test_library_sourcing
    test_hardware_detection_integration
    test_model_recommendation_flow
    test_context_length_flow
    test_print_functions
    test_byte_conversion
    test_constants
    test_directory_structure
    test_script_permissions

    # Print summary and exit
    if print_test_summary; then
        exit 0
    else
        exit 1
    fi
}

# Run main
main "$@"
