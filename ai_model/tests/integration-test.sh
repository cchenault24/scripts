#!/bin/bash
# integration-test.sh - Comprehensive integration tests for AI model setup
# Tests the complete installation and usage flow for each model family

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/model-families.sh"

PASSED=0
FAILED=0
SKIPPED=0

#############################################
# Test Framework Functions
#############################################

test_case() {
    local name="$1"
    local command="$2"

    echo -e "\n${BLUE}Testing:${NC} $name"
    if eval "$command" 2>/dev/null; then
        print_status "PASS: $name"
        ((PASSED++))
        return 0
    else
        print_error "FAIL: $name"
        ((FAILED++))
        return 1
    fi
}

test_case_verbose() {
    local name="$1"
    local command="$2"

    echo -e "\n${BLUE}Testing:${NC} $name"
    if eval "$command"; then
        print_status "PASS: $name"
        ((PASSED++))
        return 0
    else
        print_error "FAIL: $name"
        ((FAILED++))
        return 1
    fi
}

skip_test() {
    local name="$1"
    local reason="$2"
    echo -e "\n${YELLOW}Skipping:${NC} $name - $reason"
    ((SKIPPED++))
}

#############################################
# Test Suite 1: Library Scripts
#############################################

test_library_scripts() {
    print_header "Test Suite 1: Library Scripts"

    test_case "common.sh exists" \
        "[[ -f '$SCRIPT_DIR/lib/common.sh' ]]"

    test_case "common.sh is readable" \
        "[[ -r '$SCRIPT_DIR/lib/common.sh' ]]"

    test_case "model-families.sh exists" \
        "[[ -f '$SCRIPT_DIR/lib/model-families.sh' ]]"

    test_case "model-selection.sh exists" \
        "[[ -f '$SCRIPT_DIR/lib/model-selection.sh' ]]"

    test_case "ollama-setup.sh exists" \
        "[[ -f '$SCRIPT_DIR/lib/ollama-setup.sh' ]]"

    test_case "opencode-setup.sh exists" \
        "[[ -f '$SCRIPT_DIR/lib/opencode-setup.sh' ]]"

    test_case "webui-setup.sh exists" \
        "[[ -f '$SCRIPT_DIR/lib/webui-setup.sh' ]]"

    test_case "continue-setup.sh exists" \
        "[[ -f '$SCRIPT_DIR/lib/continue-setup.sh' ]]"
}

#############################################
# Test Suite 2: Hardware Detection
#############################################

test_hardware_detection() {
    print_header "Test Suite 2: Hardware Detection"

    test_case "RAM detection returns positive value" \
        "[[ $TOTAL_RAM_GB -gt 0 ]]"

    test_case "RAM is at least 8GB" \
        "[[ $TOTAL_RAM_GB -ge 8 ]]"

    test_case "Chip detection is not empty" \
        "[[ -n '$M_CHIP' ]]"

    test_case "GPU cores detection returns value" \
        "[[ $GPU_CORES -gt 0 ]]"

    test_case "RAM tier is defined" \
        "[[ -n '$RAM_TIER' ]]"

    test_case "RAM tier is valid" \
        "[[ '$RAM_TIER' =~ ^tier[1-3]$ ]]"

    echo -e "\n${BLUE}Hardware Info:${NC}"
    echo "  Chip: $M_CHIP"
    echo "  GPU Cores: $GPU_CORES"
    echo "  Total RAM: ${TOTAL_RAM_GB}GB"
    echo "  RAM Tier: $RAM_TIER"
}

#############################################
# Test Suite 3: Model Families
#############################################

test_model_families() {
    print_header "Test Suite 3: Model Families"

    test_case "Llama models available" \
        "[[ \$(list_models_by_family llama 2>/dev/null | wc -l | tr -d ' ') -ge 3 ]]"

    test_case "Mistral models available" \
        "[[ \$(list_models_by_family mistral 2>/dev/null | wc -l | tr -d ' ') -ge 2 ]]"

    test_case "Phi models available" \
        "[[ \$(list_models_by_family phi 2>/dev/null | wc -l | tr -d ' ') -ge 1 ]]"

    test_case "Gemma models available" \
        "[[ \$(list_models_by_family gemma 2>/dev/null | wc -l | tr -d ' ') -ge 2 ]]"

    test_case "Total model count is accurate" \
        "[[ \$(get_total_model_count 2>/dev/null) -ge 12 ]]"

    echo -e "\n${BLUE}Model Family Counts:${NC}"
    for family in llama mistral phi gemma; do
        local count
        count=$(get_family_model_count "$family" 2>/dev/null)
        echo "  $family: $count models"
    done
}

#############################################
# Test Suite 4: Security Filter
#############################################

test_security_filter() {
    print_header "Test Suite 4: Security Filter"

    test_case "Allow Meta Llama models" \
        "is_model_allowed 'llama3.3:70b-instruct-q4_K_M'"

    test_case "Allow Mistral models" \
        "is_model_allowed 'mistral-nemo:12b-instruct-q8_0'"

    test_case "Allow Microsoft Phi models" \
        "is_model_allowed 'phi4:14b-q8_0'"

    test_case "Allow Google Gemma models" \
        "is_model_allowed 'gemma4:31b-it-q8_0'"

    test_case "Block DeepSeek models" \
        "! is_model_allowed 'deepseek:67b'"

    test_case "Block Qwen models" \
        "! is_model_allowed 'qwen2:72b'"

    test_case "Block Yi models" \
        "! is_model_allowed 'yi:34b'"

    test_case "Block invalid model names" \
        "! is_model_allowed 'invalid:model'"

    test_case "Block unknown model families" \
        "! is_model_allowed 'unknown-family:1b'"
}

#############################################
# Test Suite 5: Model Metadata Parsing
#############################################

test_model_metadata() {
    print_header "Test Suite 5: Model Metadata Parsing"

    local test_model="llama3.3:70b-instruct-q4_K_M|42|48|128000|q4_K_M|best_overall"

    test_case "Parse model name" \
        "[[ \$(get_model_info '$test_model' name) == 'llama3.3:70b-instruct-q4_K_M' ]]"

    test_case "Parse model size" \
        "[[ \$(get_model_info '$test_model' size) == '42' ]]"

    test_case "Parse min RAM" \
        "[[ \$(get_model_info '$test_model' min_ram) == '48' ]]"

    test_case "Parse context window" \
        "[[ \$(get_model_info '$test_model' context) == '128000' ]]"

    test_case "Parse quantization" \
        "[[ \$(get_model_info '$test_model' quantization) == 'q4_K_M' ]]"

    test_case "Parse use case" \
        "[[ \$(get_model_info '$test_model' use_case) == 'best_overall' ]]"
}

#############################################
# Test Suite 6: RAM Tier Classification
#############################################

test_ram_tiers() {
    print_header "Test Suite 6: RAM Tier Classification"

    # Check bash version - get_recommended_models requires bash 4+ (uses associative arrays)
    local bash_version
    bash_version=$(bash --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)

    if [[ "$bash_version" -lt 4 ]]; then
        skip_test "RAM tier recommendations" "requires bash 4+ (current: bash $bash_version)"
        skip_test "Tier1 recommendations" "requires bash 4+"
        skip_test "Tier2 recommendations" "requires bash 4+"
        skip_test "Tier3 recommendations" "requires bash 4+"
        skip_test "Tier1 model count" "requires bash 4+"
        skip_test "Tier2 model count" "requires bash 4+"
        skip_test "Tier3 model count" "requires bash 4+"
        echo -e "\n${YELLOW}Note:${NC} Install bash 4+ with: brew install bash"
    else
        # Test that functions exist and can be called
        echo -e "\n${BLUE}Testing:${NC} Get tier1 recommendations (16GB)"
        if get_recommended_models tier1 >/dev/null 2>&1; then
            print_status "PASS: Get tier1 recommendations (16GB)"
            ((PASSED++))
        else
            print_error "FAIL: Get tier1 recommendations (16GB)"
            ((FAILED++))
        fi

        echo -e "\n${BLUE}Testing:${NC} Get tier2 recommendations (32GB)"
        if get_recommended_models tier2 >/dev/null 2>&1; then
            print_status "PASS: Get tier2 recommendations (32GB)"
            ((PASSED++))
        else
            print_error "FAIL: Get tier2 recommendations (32GB)"
            ((FAILED++))
        fi

        echo -e "\n${BLUE}Testing:${NC} Get tier3 recommendations (48GB+)"
        if get_recommended_models tier3 >/dev/null 2>&1; then
            print_status "PASS: Get tier3 recommendations (48GB+)"
            ((PASSED++))
        else
            print_error "FAIL: Get tier3 recommendations (48GB+)"
            ((FAILED++))
        fi

        # Test model counts by actually calling the function and storing result
        echo -e "\n${BLUE}Testing:${NC} Tier1 has at least 1 model"
        local tier1_models
        tier1_models=$(get_recommended_models tier1 2>/dev/null)
        if [[ $(echo "$tier1_models" | wc -l) -ge 1 ]]; then
            print_status "PASS: Tier1 has at least 1 model"
            ((PASSED++))
        else
            print_error "FAIL: Tier1 has at least 1 model"
            ((FAILED++))
        fi

        echo -e "\n${BLUE}Testing:${NC} Tier2 has at least 3 models"
        local tier2_models
        tier2_models=$(get_recommended_models tier2 2>/dev/null)
        if [[ $(echo "$tier2_models" | wc -l) -ge 3 ]]; then
            print_status "PASS: Tier2 has at least 3 models"
            ((PASSED++))
        else
            print_error "FAIL: Tier2 has at least 3 models"
            ((FAILED++))
        fi

        echo -e "\n${BLUE}Testing:${NC} Tier3 has at least 5 models"
        local tier3_models
        tier3_models=$(get_recommended_models tier3 2>/dev/null)
        if [[ $(echo "$tier3_models" | wc -l) -ge 5 ]]; then
            print_status "PASS: Tier3 has at least 5 models"
            ((PASSED++))
        else
            print_error "FAIL: Tier3 has at least 5 models"
            ((FAILED++))
        fi
    fi

    echo -e "\n${BLUE}Current System RAM Tier:${NC} $RAM_TIER (${TOTAL_RAM_GB}GB)"
}

#############################################
# Test Suite 7: Utility Scripts
#############################################

test_utility_scripts() {
    print_header "Test Suite 7: Utility Scripts"

    test_case "llama-control.sh exists" \
        "[[ -f '$SCRIPT_DIR/llama-control.sh' ]]"

    test_case "llama-control.sh is executable" \
        "[[ -x '$SCRIPT_DIR/llama-control.sh' ]]"

    test_case "switch-model.sh exists" \
        "[[ -f '$SCRIPT_DIR/switch-model.sh' ]]"

    test_case "switch-model.sh is executable" \
        "[[ -x '$SCRIPT_DIR/switch-model.sh' ]]"

    test_case "benchmark.sh exists" \
        "[[ -f '$SCRIPT_DIR/benchmark.sh' ]]"

    test_case "benchmark.sh is executable" \
        "[[ -x '$SCRIPT_DIR/benchmark.sh' ]]"

    test_case "diagnose.sh exists" \
        "[[ -f '$SCRIPT_DIR/diagnose.sh' ]]"

    test_case "diagnose.sh is executable" \
        "[[ -x '$SCRIPT_DIR/diagnose.sh' ]]"

    test_case "uninstall.sh exists" \
        "[[ -f '$SCRIPT_DIR/uninstall.sh' ]]"

    test_case "uninstall.sh is executable" \
        "[[ -x '$SCRIPT_DIR/uninstall.sh' ]]"
}

#############################################
# Test Suite 8: Documentation
#############################################

test_documentation() {
    print_header "Test Suite 8: Documentation"

    test_case "README.md exists" \
        "[[ -f '$SCRIPT_DIR/README.md' ]]"

    test_case "README.md is not empty" \
        "[[ -s '$SCRIPT_DIR/README.md' ]]"

    test_case "MODEL_GUIDE.md exists" \
        "[[ -f '$SCRIPT_DIR/docs/MODEL_GUIDE.md' ]]"

    test_case "CLIENT_SETUP.md exists" \
        "[[ -f '$SCRIPT_DIR/docs/CLIENT_SETUP.md' ]]"

    test_case "TROUBLESHOOTING.md exists" \
        "[[ -f '$SCRIPT_DIR/docs/TROUBLESHOOTING.md' ]]"

    test_case "TEAM_DEPLOYMENT.md exists" \
        "[[ -f '$SCRIPT_DIR/docs/TEAM_DEPLOYMENT.md' ]]"
}

#############################################
# Test Suite 9: Presets
#############################################

test_presets() {
    print_header "Test Suite 9: Presets"

    test_case "Presets directory exists" \
        "[[ -d '$SCRIPT_DIR/presets' ]]"

    test_case "Developer preset exists" \
        "[[ -f '$SCRIPT_DIR/presets/developer.env' ]]"

    test_case "Researcher preset exists" \
        "[[ -f '$SCRIPT_DIR/presets/researcher.env' ]]"

    test_case "Production preset exists" \
        "[[ -f '$SCRIPT_DIR/presets/production.env' ]]"

    test_case "Presets README exists" \
        "[[ -f '$SCRIPT_DIR/presets/README.md' ]]"
}

#############################################
# Test Suite 10: Build Optimizations
#############################################

test_build_optimizations() {
    print_header "Test Suite 10: Build Optimizations"

    # Read ollama-setup.sh to check for optimization flags
    local ollama_setup="$SCRIPT_DIR/lib/ollama-setup.sh"

    test_case "Ollama setup contains CGO_CFLAGS" \
        "grep -q 'CGO_CFLAGS' '$ollama_setup'"

    test_case "Ollama setup contains optimization flags" \
        "grep -q '\-O3' '$ollama_setup'"

    test_case "Ollama setup contains Metal support" \
        "grep -q 'metal' '$ollama_setup' || grep -q 'gpu_metal' '$ollama_setup'"

    # Read opencode-setup.sh to check for build optimizations
    local opencode_setup="$SCRIPT_DIR/lib/opencode-setup.sh"

    test_case "OpenCode setup contains production build" \
        "grep -q 'bun build' '$opencode_setup' || grep -q 'production' '$opencode_setup'"
}

#############################################
# Test Suite 11: Error Handling
#############################################

test_error_handling() {
    print_header "Test Suite 11: Error Handling"

    test_case "Invalid family returns error" \
        "! list_models_by_family 'invalid_family' 2>/dev/null"

    test_case "Invalid RAM tier returns error" \
        "! get_recommended_models 'invalid_tier' 2>/dev/null"

    test_case "Invalid model field returns error" \
        "! get_model_info 'llama3.3:70b|42|48' 'invalid_field' 2>/dev/null"

    test_case "Uninstall script contains safety checks" \
        "grep -q 'read -p' '$SCRIPT_DIR/uninstall.sh' || grep -q 'confirm' '$SCRIPT_DIR/uninstall.sh'"
}

#############################################
# Test Suite 12: Directory Structure
#############################################

test_directory_structure() {
    print_header "Test Suite 12: Directory Structure"

    test_case "lib directory exists" \
        "[[ -d '$SCRIPT_DIR/lib' ]]"

    test_case "docs directory exists" \
        "[[ -d '$SCRIPT_DIR/docs' ]]"

    test_case "presets directory exists" \
        "[[ -d '$SCRIPT_DIR/presets' ]]"

    test_case "tests directory exists" \
        "[[ -d '$SCRIPT_DIR/tests' ]]"

    test_case ".gitignore exists" \
        "[[ -f '$SCRIPT_DIR/.gitignore' ]]"
}

#############################################
# Test Suite 13: Runtime Dependencies (Optional)
#############################################

test_runtime_dependencies() {
    print_header "Test Suite 13: Runtime Dependencies (Optional)"

    # These tests check for runtime dependencies but don't fail the suite
    if command -v brew &>/dev/null; then
        print_status "Homebrew is installed"
        ((PASSED++))
    else
        skip_test "Homebrew check" "not installed (optional for testing)"
    fi

    if command -v git &>/dev/null; then
        print_status "Git is installed"
        ((PASSED++))
    else
        skip_test "Git check" "not installed (optional for testing)"
    fi

    if command -v go &>/dev/null; then
        print_status "Go is installed"
        ((PASSED++))
    else
        skip_test "Go check" "not installed (optional for testing)"
    fi

    if command -v bun &>/dev/null; then
        print_status "Bun is installed"
        ((PASSED++))
    else
        skip_test "Bun check" "not installed (optional for testing)"
    fi

    if command -v docker &>/dev/null; then
        print_status "Docker is installed"
        ((PASSED++))
    else
        skip_test "Docker check" "not installed (optional for testing)"
    fi
}

#############################################
# Test Suite 14: Port Conflict Detection
#############################################

test_port_detection() {
    print_header "Test Suite 14: Port Conflict Detection (Optional)"

    if command -v lsof &>/dev/null; then
        test_case "lsof is available" \
            "command -v lsof &>/dev/null"

        # Check if common ports are in use
        local ollama_port=11434
        local webui_port=8080
        local opencode_port=8000

        if lsof -i ":$ollama_port" &>/dev/null; then
            print_warning "Port $ollama_port (Ollama) is in use"
        else
            print_status "Port $ollama_port (Ollama) is available"
            ((PASSED++))
        fi

        if lsof -i ":$webui_port" &>/dev/null; then
            print_warning "Port $webui_port (WebUI) is in use"
        else
            print_status "Port $webui_port (WebUI) is available"
            ((PASSED++))
        fi

        if lsof -i ":$opencode_port" &>/dev/null; then
            print_warning "Port $opencode_port (OpenCode) is in use"
        else
            print_status "Port $opencode_port (OpenCode) is available"
            ((PASSED++))
        fi
    else
        skip_test "Port detection" "lsof not available"
    fi
}

#############################################
# Test Suite 15: Function Exports
#############################################

test_function_exports() {
    print_header "Test Suite 15: Function Exports"

    test_case "is_model_allowed is exported" \
        "declare -F is_model_allowed &>/dev/null"

    test_case "list_models_by_family is exported" \
        "declare -F list_models_by_family &>/dev/null"

    test_case "get_model_info is exported" \
        "declare -F get_model_info &>/dev/null"

    test_case "get_recommended_models is exported" \
        "declare -F get_recommended_models &>/dev/null"

    test_case "print_header is available" \
        "declare -F print_header &>/dev/null"

    test_case "print_status is available" \
        "declare -F print_status &>/dev/null"

    test_case "print_error is available" \
        "declare -F print_error &>/dev/null"
}

#############################################
# Main Test Runner
#############################################

main() {
    print_header "AI Model Setup - Integration Test Suite"
    echo -e "${BLUE}Script Directory:${NC} $SCRIPT_DIR"
    echo -e "${BLUE}Test Start Time:${NC} $(date)"
    echo ""

    # Run all test suites
    test_library_scripts
    test_hardware_detection
    test_model_families
    test_security_filter
    test_model_metadata
    test_ram_tiers
    test_utility_scripts
    test_documentation
    test_presets
    test_build_optimizations
    test_error_handling
    test_directory_structure
    test_runtime_dependencies
    test_port_detection
    test_function_exports

    # Print summary
    echo ""
    print_header "Integration Test Results"
    echo -e "${GREEN}Passed:${NC}  $PASSED"
    echo -e "${RED}Failed:${NC}  $FAILED"
    echo -e "${YELLOW}Skipped:${NC} $SKIPPED"
    echo -e "${BLUE}Total:${NC}   $((PASSED + FAILED + SKIPPED))"
    echo ""

    if [[ $FAILED -eq 0 ]]; then
        print_status "All tests passed!"
        echo -e "${BLUE}Test End Time:${NC} $(date)"
        exit 0
    else
        print_error "$FAILED test(s) failed"
        echo -e "${BLUE}Test End Time:${NC} $(date)"
        exit 1
    fi
}

# Run main function
main
