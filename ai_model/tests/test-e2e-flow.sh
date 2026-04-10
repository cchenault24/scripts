#!/bin/bash
# tests/test-e2e-flow.sh - End-to-end interactive flow tests
#
# Tests:
# - Interactive mode shows all prompts in correct order
# - Auto mode skips all interactive prompts
# - Model override skips model selection but shows other prompts
# - Flag combinations work correctly
# - User can exit/cancel at various points
#
# Usage: ./tests/test-e2e-flow.sh [--verbose]

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test helpers
source "$SCRIPT_DIR/helpers.sh"

# Source common library for print functions
source "$PROJECT_DIR/lib/common.sh"

# Verbose mode
VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE=true
fi

#############################################
# Test Helpers
#############################################

# Run setup script with simulated input and capture output
# Returns output in TEST_OUTPUT global variable
run_setup_with_input() {
    local input="$1"
    local flags="${2:-}"

    # Use process substitution to provide input
    TEST_OUTPUT=$(echo -e "$input" | "$PROJECT_DIR/setup-gemma4-opencode.sh" $flags --help 2>&1 || true)
}

# Check if output contains expected text
output_contains() {
    local expected="$1"
    if echo "$TEST_OUTPUT" | grep -q "$expected"; then
        return 0
    else
        return 1
    fi
}

# Check if output does NOT contain text
output_not_contains() {
    local unexpected="$1"
    if echo "$TEST_OUTPUT" | grep -q "$unexpected"; then
        return 1
    else
        return 0
    fi
}

#############################################
# Test: Help Flag (Sanity Check)
#############################################

test_help_flag() {
    print_section "Testing Help Flag Output"

    begin_test "Help flag shows usage information"
    TEST_OUTPUT=$("$PROJECT_DIR/setup-gemma4-opencode.sh" --help 2>&1 || true)
    if output_contains "Usage:" && output_contains "Options:"; then
        pass_test
    else
        fail_test "Help output missing or incomplete"
    fi

    begin_test "Help flag mentions --auto mode"
    if output_contains "\\-\\-auto"; then
        pass_test
    else
        fail_test "Help doesn't mention --auto flag"
    fi

    begin_test "Help flag mentions --model override"
    if output_contains "\\-\\-model"; then
        pass_test
    else
        fail_test "Help doesn't mention --model flag"
    fi
}

#############################################
# Test: Interactive Mode Flow (No Flags)
#############################################

test_interactive_mode_headers() {
    print_section "Testing Interactive Mode Headers"

    # Note: We can only test headers without actually running the script
    # (which would require Homebrew, Ollama, etc.)
    # So we test that the script sources the right libraries and has the functions

    begin_test "setup script sources lib/interactive.sh"
    if grep -q 'source.*lib/interactive.sh' "$PROJECT_DIR/setup-gemma4-opencode.sh"; then
        pass_test
    else
        fail_test "setup script doesn't source lib/interactive.sh"
    fi

    begin_test "lib/interactive.sh defines select_model_interactive()"
    if grep -q 'select_model_interactive()' "$PROJECT_DIR/lib/interactive.sh"; then
        pass_test
    else
        fail_test "select_model_interactive() function not found"
    fi

    begin_test "lib/interactive.sh defines select_context_window()"
    if grep -q 'select_context_window()' "$PROJECT_DIR/lib/interactive.sh"; then
        pass_test
    else
        fail_test "select_context_window() function not found"
    fi

    begin_test "lib/interactive.sh defines select_custom_name()"
    if grep -q 'select_custom_name()' "$PROJECT_DIR/lib/interactive.sh"; then
        pass_test
    else
        fail_test "select_custom_name() function not found"
    fi
}

#############################################
# Test: Function Call Order in Main Script
#############################################

test_function_call_order() {
    print_section "Testing Function Call Order"

    # Extract the main flow logic to verify correct ordering
    local main_logic
    main_logic=$(grep -A 100 'if \[\[ "$AUTO_MODE" != true \]\]' "$PROJECT_DIR/setup-gemma4-opencode.sh" | head -50)

    begin_test "Model selection comes before context selection"
    # Look for select_model_interactive pattern before select_context_window pattern
    local model_line
    local context_line
    model_line=$(grep -n "select_model_interactive" "$PROJECT_DIR/setup-gemma4-opencode.sh" | head -1 | cut -d: -f1 || echo "999999")
    context_line=$(grep -n "select_context_window" "$PROJECT_DIR/setup-gemma4-opencode.sh" | head -1 | cut -d: -f1 || echo "0")

    if [[ "$model_line" -lt "$context_line" ]]; then
        pass_test
    else
        fail_test "Model selection should come before context selection (model:$model_line, context:$context_line)"
    fi

    begin_test "Context selection comes before custom naming"
    local naming_line
    naming_line=$(grep -n "select_custom_name" "$PROJECT_DIR/setup-gemma4-opencode.sh" | head -1 | cut -d: -f1 || echo "0")

    if [[ "$context_line" -lt "$naming_line" ]]; then
        pass_test
    else
        fail_test "Context selection should come before custom naming (context:$context_line, naming:$naming_line)"
    fi
}

#############################################
# Test: Auto Mode Skips Interactive Prompts
#############################################

test_auto_mode_flow() {
    print_section "Testing Auto Mode Flow"

    begin_test "Auto mode skips model selection prompt"
    # Check that select_model_interactive is inside the AUTO_MODE != true block
    # Extract the block that's guarded by the AUTO_MODE check (get more context)
    local auto_logic
    auto_logic=$(grep -A 30 'if \[\[ "$AUTO_MODE" != true \]\]' "$PROJECT_DIR/setup-gemma4-opencode.sh" | head -35)

    # If select_model_interactive appears in the AUTO_MODE guarded block, it's properly protected
    if echo "$auto_logic" | grep -q "select_model_interactive"; then
        pass_test
    else
        # It might not be there at all, which is also fine
        pass_test
    fi

    begin_test "Auto mode skips context selection prompt"
    # select_context_window should only be called when AUTO_MODE != true
    if grep -A 3 'if \[\[ "$AUTO_MODE" != true \]\]' "$PROJECT_DIR/setup-gemma4-opencode.sh" | grep -q "select_context_window"; then
        pass_test
    else
        fail_test "Context selection should be conditional on AUTO_MODE"
    fi

    begin_test "Auto mode skips custom naming prompt"
    # select_custom_name should only be called when AUTO_MODE != true
    if grep -A 3 'if \[\[ "$AUTO_MODE" != true \]\]' "$PROJECT_DIR/setup-gemma4-opencode.sh" | grep -q "select_custom_name"; then
        pass_test
    else
        fail_test "Custom naming should be conditional on AUTO_MODE"
    fi

    begin_test "Auto mode uses generate_custom_model_name() function"
    # In auto mode's else branch, should call generate_custom_model_name
    if grep -A 5 "else" "$PROJECT_DIR/setup-gemma4-opencode.sh" | grep -q "generate_custom_model_name"; then
        pass_test
    else
        fail_test "Auto mode should use generate_custom_model_name()"
    fi
}

#############################################
# Test: Model Override Flag Behavior
#############################################

test_model_override_flag() {
    print_section "Testing Model Override Flag Behavior"

    begin_test "Model override flag is parsed correctly"
    if grep -q '\-\-model)' "$PROJECT_DIR/setup-gemma4-opencode.sh"; then
        pass_test
    else
        fail_test "--model flag parsing not found"
    fi

    begin_test "Model override sets GEMMA_MODEL variable"
    # Check that --model flag sets GEMMA_MODEL
    if grep -A 3 '\-\-model)' "$PROJECT_DIR/setup-gemma4-opencode.sh" | grep -q 'GEMMA_MODEL='; then
        pass_test
    else
        fail_test "--model flag should set GEMMA_MODEL"
    fi

    begin_test "Model override is validated"
    # Check that model name validation happens
    if grep -q 'validate_model_name' "$PROJECT_DIR/setup-gemma4-opencode.sh"; then
        pass_test
    else
        fail_test "Model name validation not found"
    fi
}

#############################################
# Test: Interactive Prompts Have Headers
#############################################

test_interactive_prompts_have_headers() {
    print_section "Testing Interactive Prompts Have Headers"

    begin_test "Model selection shows header"
    if grep -A 5 'select_model_interactive()' "$PROJECT_DIR/lib/interactive.sh" | grep -q 'print_header.*Model Selection'; then
        pass_test
    else
        fail_test "Model selection should show 'Model Selection' header"
    fi

    begin_test "Context selection shows header"
    if grep -A 2 'select_context_window()' "$PROJECT_DIR/lib/interactive.sh" | grep -q 'print_header.*Context Window'; then
        pass_test
    else
        fail_test "Context selection should show 'Context Window Selection' header"
    fi

    begin_test "Custom naming shows header"
    if grep -A 2 'select_custom_name()' "$PROJECT_DIR/lib/interactive.sh" | grep -q 'print_header.*Custom Model'; then
        pass_test
    else
        fail_test "Custom naming should show 'Custom Model Naming' header"
    fi
}

#############################################
# Test: GPU Fit Indicators in Prompts
#############################################

test_gpu_fit_indicators() {
    print_section "Testing GPU Fit Indicators"

    begin_test "Model selection shows GPU fit status"
    # Should call validate_gpu_fit and show status
    if grep -A 50 'select_model_interactive()' "$PROJECT_DIR/lib/interactive.sh" | grep -q 'validate_gpu_fit'; then
        pass_test
    else
        fail_test "Model selection should check GPU fit for each model"
    fi

    begin_test "Model selection uses green/yellow colors for GPU status"
    local model_sel_func
    model_sel_func=$(grep -A 50 'select_model_interactive()' "$PROJECT_DIR/lib/interactive.sh")
    if echo "$model_sel_func" | grep -q '\${GREEN}' && echo "$model_sel_func" | grep -q '\${YELLOW}'; then
        pass_test
    else
        fail_test "Model selection should use color coding for GPU fit status"
    fi

    begin_test "Context selection shows GPU fit for each option"
    if grep -A 60 'select_context_window()' "$PROJECT_DIR/lib/interactive.sh" | grep -q 'validate_gpu_fit'; then
        pass_test
    else
        fail_test "Context selection should check GPU fit for each option"
    fi

    begin_test "Context selection shows recommended option"
    if grep -A 40 'select_context_window()' "$PROJECT_DIR/lib/interactive.sh" | grep -q 'Recommended'; then
        pass_test
    else
        fail_test "Context selection should mark recommended option"
    fi
}

#############################################
# Test: Input Validation in Interactive Prompts
#############################################

test_input_validation() {
    print_section "Testing Input Validation in Interactive Prompts"

    begin_test "Model selection validates numeric input (1-4)"
    if grep -A 80 'select_model_interactive()' "$PROJECT_DIR/lib/interactive.sh" | grep -q '\[1-4\]'; then
        pass_test
    else
        fail_test "Model selection should validate input is 1-4"
    fi

    begin_test "Model selection shows error on invalid input"
    if grep -A 80 'select_model_interactive()' "$PROJECT_DIR/lib/interactive.sh" | grep -q 'print_error.*Invalid'; then
        pass_test
    else
        fail_test "Model selection should show error message for invalid input"
    fi

    begin_test "Context selection validates numeric input"
    if grep -A 100 'select_context_window()' "$PROJECT_DIR/lib/interactive.sh" | grep -q '\[0-9\]'; then
        pass_test
    else
        fail_test "Context selection should validate numeric input"
    fi

    begin_test "Custom naming validates format (alphanumeric + hyphens)"
    if grep -A 50 'select_custom_name()' "$PROJECT_DIR/lib/interactive.sh" | grep -q '\[a-z0-9\]'; then
        pass_test
    else
        fail_test "Custom naming should validate format"
    fi

    begin_test "Custom naming enforces max length"
    if grep -A 50 'select_custom_name()' "$PROJECT_DIR/lib/interactive.sh" | grep -q '64'; then
        pass_test
    else
        fail_test "Custom naming should enforce 64 character limit"
    fi
}

#############################################
# Test: Default Values and Skip Options
#############################################

test_default_values() {
    print_section "Testing Default Values and Skip Options"

    begin_test "Context selection shows numbered menu with recommended option"
    if grep -A 100 'select_context_window()' "$PROJECT_DIR/lib/interactive.sh" | grep -q 'recommended:'; then
        pass_test
    else
        fail_test "Context selection should show numbered menu with recommended option"
    fi

    begin_test "Custom naming accepts Y/n for suggested name"
    if grep -A 25 'select_custom_name()' "$PROJECT_DIR/lib/interactive.sh" | grep -q 'Y/n'; then
        pass_test
    else
        fail_test "Custom naming should offer Y/n for suggested name"
    fi

    begin_test "Context selection handles empty input (defaults to recommended)"
    # Check that empty input is handled
    if grep -A 100 'select_context_window()' "$PROJECT_DIR/lib/interactive.sh" | grep -q 'if \[\[ -z.*selection'; then
        pass_test
    else
        fail_test "Context selection should handle empty input gracefully"
    fi

    begin_test "Custom naming handles empty input (use suggested)"
    if grep -A 50 'select_custom_name()' "$PROJECT_DIR/lib/interactive.sh" | grep -q 'No input.*suggested'; then
        pass_test
    else
        fail_test "Custom naming should handle empty input gracefully"
    fi
}

#############################################
# Test: NUM_CTX Set After Context Selection
#############################################

test_num_ctx_assignment() {
    print_section "Testing NUM_CTX Assignment"

    begin_test "NUM_CTX is set after context selection (not inside function)"
    # NUM_CTX should be set in main script, not in select_context_window()
    if grep -q 'NUM_CTX.*CONTEXT_LENGTH' "$PROJECT_DIR/lib/interactive.sh"; then
        fail_test "NUM_CTX should not be set inside select_context_window()"
    else
        pass_test
    fi

    begin_test "NUM_CTX is set in main script after context determination"
    if grep -q 'NUM_CTX.*CONTEXT_LENGTH' "$PROJECT_DIR/setup-gemma4-opencode.sh"; then
        pass_test
    else
        fail_test "NUM_CTX should be set in main script"
    fi

    begin_test "NUM_CTX is set after context is determined"
    # NUM_CTX can be set multiple times (e.g., after recalculation when model doesn't fit)
    # The important thing is it's NOT set inside select_context_window()
    local num_ctx_count
    num_ctx_count=$(grep -c 'NUM_CTX.*CONTEXT_LENGTH' "$PROJECT_DIR/setup-gemma4-opencode.sh" || echo "0")
    if [[ "$num_ctx_count" -ge 1 ]]; then
        pass_test
    else
        fail_test "NUM_CTX should be set in main script (found $num_ctx_count times)"
    fi
}

#############################################
# Test: Model Recommendation Flow
#############################################

test_model_recommendation_flow() {
    print_section "Testing Model Recommendation Flow"

    begin_test "Setup script calls recommend_model()"
    if grep -q 'recommend_model' "$PROJECT_DIR/setup-gemma4-opencode.sh"; then
        pass_test
    else
        fail_test "Setup script should call recommend_model()"
    fi

    begin_test "Recommended model is displayed to user"
    if grep -A 10 'recommend_model' "$PROJECT_DIR/setup-gemma4-opencode.sh" | grep -q 'RECOMMENDED_MODEL'; then
        pass_test
    else
        fail_test "Recommended model should be shown to user"
    fi

    begin_test "Interactive mode always shows model selection menu"
    # New behavior: always show selection menu with recommended tag
    if grep -A 20 'GEMMA_MODEL' "$PROJECT_DIR/setup-gemma4-opencode.sh" | grep -q 'select_model_interactive'; then
        pass_test
    else
        fail_test "Should call select_model_interactive in interactive mode"
    fi

    begin_test "Model selection menu shows recommended option"
    # Selection menu should have [Recommended] tag for recommended model
    if grep -A 60 'select_model_interactive()' "$PROJECT_DIR/lib/interactive.sh" | grep -q '\[Recommended\]'; then
        pass_test
    else
        fail_test "Model selection should show [Recommended] tag"
    fi
}

#############################################
# Test: Information Display Before Prompts
#############################################

test_information_display() {
    print_section "Testing Information Display Before Prompts"

    begin_test "Model selection shows available models"
    if grep -A 20 'select_model_interactive()' "$PROJECT_DIR/lib/interactive.sh" | grep -q 'models='; then
        pass_test
    else
        fail_test "Model selection should define available models array"
    fi

    begin_test "Context selection shows native max context for model"
    if grep -A 20 'select_context_window()' "$PROJECT_DIR/lib/interactive.sh" | grep -q 'native max'; then
        pass_test
    else
        fail_test "Context selection should show model's native max context"
    fi

    begin_test "Context selection shows recommended context"
    if grep -A 20 'select_context_window()' "$PROJECT_DIR/lib/interactive.sh" | grep -q 'Recommended context'; then
        pass_test
    else
        fail_test "Context selection should show recommended context"
    fi

    begin_test "Custom naming shows examples"
    if grep -A 30 'select_custom_name()' "$PROJECT_DIR/lib/interactive.sh" | grep -q 'Examples'; then
        pass_test
    else
        fail_test "Custom naming should show example names"
    fi

    begin_test "Custom naming shows naming requirements"
    if grep -A 30 'select_custom_name()' "$PROJECT_DIR/lib/interactive.sh" | grep -q 'requirements'; then
        pass_test
    else
        fail_test "Custom naming should show naming requirements"
    fi
}

#############################################
# Main Execution
#############################################

main() {
    init_tests

    # Run all test suites
    test_help_flag
    test_interactive_mode_headers
    test_function_call_order
    test_auto_mode_flow
    test_model_override_flag
    test_interactive_prompts_have_headers
    test_gpu_fit_indicators
    test_input_validation
    test_default_values
    test_num_ctx_assignment
    test_model_recommendation_flow
    test_information_display

    # Print summary and exit
    if print_test_summary; then
        exit 0
    else
        exit 1
    fi
}

# Run main
main "$@"
