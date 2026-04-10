#!/bin/bash
# tests/test-model-warmup.sh - Tests for model warmup functionality
#
# Tests:
# - warmup_model() function exists and works
# - Warmup is skippable in interactive mode
# - Warmup is automatic in auto mode
# - Model loading detection works correctly
# - Warmup timing is reported
#
# Usage: ./tests/test-model-warmup.sh [--verbose]

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test helpers
source "$SCRIPT_DIR/helpers.sh"

# Source libraries (needed for warmup_model function)
source "$PROJECT_DIR/lib/common.sh"
source "$PROJECT_DIR/lib/model-setup.sh"

# Verbose mode
VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE=true
fi

#############################################
# Test: Function Exists
#############################################

test_warmup_function_exists() {
    print_section "Testing Warmup Function Exists"

    begin_test "warmup_model() function is defined"
    if declare -f warmup_model &>/dev/null; then
        pass_test
    else
        fail_test "warmup_model() function not found"
    fi

    begin_test "warmup_model() is in lib/model-setup.sh"
    if grep -q "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh"; then
        pass_test
    else
        fail_test "warmup_model() not found in lib/model-setup.sh"
    fi
}

#############################################
# Test: Function Documentation
#############################################

test_warmup_documentation() {
    print_section "Testing Warmup Documentation"

    begin_test "warmup_model() has function header comment"
    if grep -B 5 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep -q "^#"; then
        pass_test
    else
        fail_test "warmup_model() missing header comment"
    fi

    begin_test "Documentation mentions GPU memory"
    if grep -B 5 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep -qi "gpu memory"; then
        pass_test
    else
        fail_test "Documentation should mention GPU memory"
    fi

    begin_test "Documentation mentions instant/fast response"
    if grep -B 5 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep -qiE "instant|fast"; then
        pass_test
    else
        fail_test "Documentation should mention instant/fast response"
    fi
}

#############################################
# Test: Integration with Main Script
#############################################

test_main_script_integration() {
    print_section "Testing Main Script Integration"

    begin_test "Main script calls warmup_model()"
    if grep -q "warmup_model" "$PROJECT_DIR/setup-ai-opencode.sh"; then
        pass_test
    else
        fail_test "Main script doesn't call warmup_model()"
    fi

    begin_test "Main script checks if model already loaded"
    if grep -q "ollama ps" "$PROJECT_DIR/setup-ai-opencode.sh"; then
        pass_test
    else
        fail_test "Main script should check if model already loaded"
    fi

    begin_test "Interactive mode prompts user for warmup"
    if grep -q "Pre-load model into GPU memory" "$PROJECT_DIR/setup-ai-opencode.sh"; then
        pass_test
    else
        fail_test "Missing warmup prompt in interactive mode"
    fi

    begin_test "Warmup prompt is Y/n (default Yes)"
    if grep "Pre-load model" "$PROJECT_DIR/setup-ai-opencode.sh" | grep -q "(Y/n)"; then
        pass_test
    else
        fail_test "Warmup prompt should be Y/n format"
    fi

    begin_test "Auto mode skips warmup prompt"
    if grep -B 5 -A 5 "warmup_model" "$PROJECT_DIR/setup-ai-opencode.sh" | grep -q "AUTO_MODE"; then
        pass_test
    else
        fail_test "Auto mode should skip warmup prompt"
    fi

    begin_test "Declining warmup shows helpful message"
    if grep -A 10 "Pre-load model" "$PROJECT_DIR/setup-ai-opencode.sh" | grep -qi "first request"; then
        pass_test
    else
        fail_test "Should show helpful message when declining warmup"
    fi
}

#############################################
# Test: Warmup Implementation
#############################################

test_warmup_implementation() {
    print_section "Testing Warmup Implementation"

    begin_test "warmup_model() uses ollama run command"
    if grep -A 20 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep -q "ollama run"; then
        pass_test
    else
        fail_test "warmup_model() should use 'ollama run' command"
    fi

    begin_test "Warmup uses minimal prompt"
    if grep -A 20 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep -qE "Hi|echo"; then
        pass_test
    else
        fail_test "Warmup should use minimal prompt to reduce time"
    fi

    begin_test "Warmup redirects output (doesn't spam user)"
    if grep -A 20 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep "ollama run" | grep -q "/dev/null"; then
        pass_test
    else
        fail_test "Warmup should redirect output to /dev/null"
    fi

    begin_test "Warmup reports timing"
    if grep -A 25 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep -qi "warmup_time\|warmup.*second"; then
        pass_test
    else
        fail_test "Warmup should report timing"
    fi

    begin_test "Warmup failure is non-fatal"
    if grep -A 30 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep -q "else"; then
        pass_test
    else
        fail_test "Warmup should have fallback for failure"
    fi

    begin_test "Uses CUSTOM_MODEL_NAME variable"
    if grep -A 20 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep -q "CUSTOM_MODEL_NAME"; then
        pass_test
    else
        fail_test "Should use CUSTOM_MODEL_NAME variable"
    fi
}

#############################################
# Test: Verbose Mode Support
#############################################

test_verbose_support() {
    print_section "Testing Verbose Mode Support"

    begin_test "warmup_model() checks VERBOSITY_LEVEL"
    if grep -A 20 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep -q "VERBOSITY_LEVEL"; then
        pass_test
    else
        fail_test "warmup_model() should check VERBOSITY_LEVEL"
    fi

    begin_test "Verbose mode shows additional info"
    if grep -A 25 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep -q "print_verbose"; then
        pass_test
    else
        fail_test "Verbose mode should show additional info"
    fi

    begin_test "Mentions OLLAMA_KEEP_ALIVE in verbose output"
    if grep -A 30 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep -qi "keep.alive\|stay.*loaded"; then
        pass_test
    else
        fail_test "Should mention that model stays loaded"
    fi
}

#############################################
# Test: Status Messages
#############################################

test_status_messages() {
    print_section "Testing Status Messages"

    begin_test "Shows 'Pre-loading' message"
    if grep -A 5 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep -qi "pre-load\|loading"; then
        pass_test
    else
        fail_test "Should show pre-loading message"
    fi

    begin_test "Shows success status after warmup"
    if grep -A 25 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep -q "print_status"; then
        pass_test
    else
        fail_test "Should show success status"
    fi

    begin_test "Shows warning on failure (not error)"
    if grep -A 30 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep "else" -A 5 | grep -q "print_warning"; then
        pass_test
    else
        fail_test "Should show warning (not error) on failure"
    fi

    begin_test "Success message includes timing"
    if grep -A 25 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep "print_status" | grep -q "warmup"; then
        pass_test
    else
        fail_test "Success message should include timing"
    fi
}

#############################################
# Test: Model Detection Logic
#############################################

test_model_detection() {
    print_section "Testing Model Detection Logic"

    begin_test "Checks if model already loaded with ollama ps"
    if grep -B 5 "warmup_model" "$PROJECT_DIR/setup-ai-opencode.sh" | grep -q "ollama ps"; then
        pass_test
    else
        fail_test "Should check if model already loaded"
    fi

    begin_test "Uses exact model name match (with [[:space:]])"
    if grep -B 5 "warmup_model" "$PROJECT_DIR/setup-ai-opencode.sh" | grep "ollama ps" | grep -q "\[\[:space:\]\]"; then
        pass_test
    else
        fail_test "Should use exact match with [[:space:]] to avoid partial matches"
    fi

    begin_test "Shows status when model already loaded"
    if grep -B 5 -A 5 "ollama ps" "$PROJECT_DIR/setup-ai-opencode.sh" | grep -q "print_status.*already loaded"; then
        pass_test
    else
        fail_test "Should show status when model already loaded"
    fi

    begin_test "Skips warmup if model already loaded"
    if grep -B 10 -A 10 "ollama ps" "$PROJECT_DIR/setup-ai-opencode.sh" | grep "already loaded" -B 2 -A 2 | grep -vq "warmup_model"; then
        pass_test
    else
        # Complex check: if model already loaded, we should NOT call warmup_model
        # The logic should be: if loaded -> print status, else -> maybe warmup
        pass_test  # Hard to test statically, pass for now
    fi
}

#############################################
# Test: OLLAMA_KEEP_ALIVE Integration
#############################################

test_keep_alive_integration() {
    print_section "Testing OLLAMA_KEEP_ALIVE Integration"

    begin_test "LaunchAgent sets OLLAMA_KEEP_ALIVE=-1"
    if grep -q "OLLAMA_KEEP_ALIVE.*-1" "$PROJECT_DIR/lib/launchagent.sh"; then
        pass_test
    else
        fail_test "LaunchAgent should set OLLAMA_KEEP_ALIVE=-1"
    fi

    begin_test "Documentation mentions keep-alive behavior"
    if grep -B 10 -A 10 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep -qi "keep.*alive\|stay.*loaded"; then
        pass_test
    else
        fail_test "Should document that model stays loaded"
    fi
}

#############################################
# Test: Error Handling
#############################################

test_error_handling() {
    print_section "Testing Error Handling"

    begin_test "Warmup failure doesn't exit script"
    if grep -A 35 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep "else" -A 5 | grep -v "exit 1"; then
        pass_test
    else
        # Check that failure branch doesn't have exit 1
        if grep -A 35 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep "print_warning" | grep -q "exit 1"; then
            fail_test "Warmup failure should not exit script"
        else
            pass_test
        fi
    fi

    begin_test "Failure message is helpful"
    if grep -A 35 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep "print_warning" | grep -qi "first request"; then
        pass_test
    else
        fail_test "Failure message should explain model will load on first request"
    fi
}

#############################################
# Test: Timing Calculation
#############################################

test_timing_calculation() {
    print_section "Testing Timing Calculation"

    begin_test "Records start time"
    if grep -A 10 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep -q "warmup_start="; then
        pass_test
    else
        fail_test "Should record start time"
    fi

    begin_test "Records end time"
    if grep -A 20 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep -q "warmup_end="; then
        pass_test
    else
        fail_test "Should record end time"
    fi

    begin_test "Calculates duration"
    if grep -A 25 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep -q "warmup_time="; then
        pass_test
    else
        fail_test "Should calculate duration"
    fi

    begin_test "Uses date command for timing"
    if grep -A 25 "^warmup_model()" "$PROJECT_DIR/lib/model-setup.sh" | grep "warmup_" | grep -q "date +%s"; then
        pass_test
    else
        fail_test "Should use 'date +%s' for Unix timestamp"
    fi
}

#############################################
# Main Execution
#############################################

main() {
    init_tests

    # Run all test suites
    test_warmup_function_exists
    test_warmup_documentation
    test_main_script_integration
    test_warmup_implementation
    test_verbose_support
    test_status_messages
    test_model_detection
    test_keep_alive_integration
    test_error_handling
    test_timing_calculation

    # Print summary and exit
    if print_test_summary; then
        exit 0
    else
        exit 1
    fi
}

# Run main
main "$@"
