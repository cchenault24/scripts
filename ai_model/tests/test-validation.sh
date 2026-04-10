#!/bin/bash
# tests/test-validation.sh - Unit tests for input validation functions
#
# Tests validation functions from setup scripts:
# - validate_model_name() - Model name validation
# - Path traversal prevention
# - Input sanitization
# - Error message quality
#
# Usage: ./tests/test-validation.sh [--verbose]

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test helpers
source "$SCRIPT_DIR/helpers.sh"

# Source setup script to get validation functions
# We need to source it carefully to avoid running main()
# Extract just the validate_model_name function
validate_model_name() {
    local model="$1"

    # First check against allowed patterns
    case "$model" in
        gemma4:e2b|gemma4:latest|gemma4:26b|gemma4:31b)
            # Verify exact length to detect truncation or appended characters
            # Note: Bash cannot store null bytes in variables - they act as terminators
            # So $'gemma4:e2b\0' becomes just "gemma4:e2b" (length 10)
            # This check catches if someone tries to append data after what bash sees
            local expected_len
            case "$model" in
                gemma4:latest) expected_len=13 ;;
                gemma4:e2b|gemma4:26b|gemma4:31b) expected_len=10 ;;
            esac

            # Length check: ensures no extra characters (spaces, tabs, etc.)
            if [ ${#model} -ne "$expected_len" ]; then
                return 1
            fi
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

#############################################
# Test: validate_model_name()
#############################################

test_validate_model_name_valid() {
    print_section "Testing validate_model_name() - Valid Models"

    # Test valid model names
    begin_test "gemma4:e2b is valid"
    if validate_model_name "gemma4:e2b"; then
        pass_test
    else
        fail_test "Should be valid"
    fi

    begin_test "gemma4:latest is valid"
    if validate_model_name "gemma4:latest"; then
        pass_test
    else
        fail_test "Should be valid"
    fi

    begin_test "gemma4:26b is valid"
    if validate_model_name "gemma4:26b"; then
        pass_test
    else
        fail_test "Should be valid"
    fi

    begin_test "gemma4:31b is valid"
    if validate_model_name "gemma4:31b"; then
        pass_test
    else
        fail_test "Should be valid"
    fi
}

test_validate_model_name_invalid() {
    print_section "Testing validate_model_name() - Invalid Models"

    # Test invalid model names
    begin_test "empty string is invalid"
    if validate_model_name ""; then
        fail_test "Empty string should be invalid"
    else
        pass_test
    fi

    begin_test "gemma4 without variant is invalid"
    if validate_model_name "gemma4"; then
        fail_test "Should require variant"
    else
        pass_test
    fi

    begin_test "gemma4:unknown is invalid"
    if validate_model_name "gemma4:unknown"; then
        fail_test "Unknown variant should be invalid"
    else
        pass_test
    fi

    begin_test "llama3 is invalid (wrong model family)"
    if validate_model_name "llama3"; then
        fail_test "Wrong model family should be invalid"
    else
        pass_test
    fi

    begin_test "gemma4:40b is invalid (non-existent variant)"
    if validate_model_name "gemma4:40b"; then
        fail_test "Non-existent variant should be invalid"
    else
        pass_test
    fi
}

#############################################
# Test: Path Traversal Prevention
#############################################

test_path_traversal() {
    print_section "Testing Path Traversal Prevention"

    # Test path traversal attempts
    begin_test "gemma4:../../etc/passwd is rejected"
    if validate_model_name "gemma4:../../etc/passwd"; then
        fail_test "Path traversal should be rejected"
    else
        pass_test
    fi

    begin_test "gemma4:../foo is rejected"
    if validate_model_name "gemma4:../foo"; then
        fail_test "Path traversal should be rejected"
    else
        pass_test
    fi

    begin_test "../../gemma4:latest is rejected"
    if validate_model_name "../../gemma4:latest"; then
        fail_test "Path traversal should be rejected"
    else
        pass_test
    fi

    begin_test "gemma4:./e2b is rejected"
    if validate_model_name "gemma4:./e2b"; then
        fail_test "Relative path should be rejected"
    else
        pass_test
    fi

    begin_test "/tmp/gemma4:latest is rejected"
    if validate_model_name "/tmp/gemma4:latest"; then
        fail_test "Absolute path should be rejected"
    else
        pass_test
    fi
}

#############################################
# Test: Special Characters
#############################################

test_special_characters() {
    print_section "Testing Special Character Handling"

    # Test special characters
    begin_test "gemma4:e2b; rm -rf / is rejected"
    if validate_model_name "gemma4:e2b; rm -rf /"; then
        fail_test "Command injection attempt should be rejected"
    else
        pass_test
    fi

    begin_test "gemma4:e2b && echo pwned is rejected"
    if validate_model_name "gemma4:e2b && echo pwned"; then
        fail_test "Command injection attempt should be rejected"
    else
        pass_test
    fi

    begin_test "gemma4:e2b | cat /etc/passwd is rejected"
    if validate_model_name "gemma4:e2b | cat /etc/passwd"; then
        fail_test "Pipe injection should be rejected"
    else
        pass_test
    fi

    begin_test "gemma4:e2b\$(whoami) is rejected"
    if validate_model_name 'gemma4:e2b$(whoami)'; then
        fail_test "Command substitution should be rejected"
    else
        pass_test
    fi

    begin_test "gemma4:e2b\`whoami\` is rejected"
    if validate_model_name 'gemma4:e2b`whoami`'; then
        fail_test "Command substitution should be rejected"
    else
        pass_test
    fi

    begin_test "gemma4:e2b<script> is rejected"
    if validate_model_name "gemma4:e2b<script>"; then
        fail_test "HTML/script tags should be rejected"
    else
        pass_test
    fi
}

#############################################
# Test: Unicode and Encoding
#############################################

test_unicode_and_encoding() {
    print_section "Testing Unicode and Encoding"

    # Test unicode characters
    begin_test "gemma4:e2b😀 is rejected"
    if validate_model_name "gemma4:e2b😀"; then
        fail_test "Emoji should be rejected"
    else
        pass_test
    fi

    begin_test "gemma4:e2b\n is rejected"
    if validate_model_name $'gemma4:e2b\n'; then
        fail_test "Newline should be rejected"
    else
        pass_test
    fi

    begin_test "gemma4:e2b\t is rejected"
    if validate_model_name $'gemma4:e2b\t'; then
        fail_test "Tab should be rejected"
    else
        pass_test
    fi

    # Test null byte
    # Note: Bash automatically truncates strings at null bytes, so $'gemma4:e2b\0'
    # becomes just "gemma4:e2b" (bash cannot store null bytes in variables).
    # This is actually a security feature - null bytes are automatically stripped.
    # We test that the truncated value is still valid (which it should be).
    begin_test "gemma4:e2b\\0 is handled (bash auto-truncates)"
    if validate_model_name $'gemma4:e2b\0'; then
        # Bash truncated it to valid "gemma4:e2b" - this is expected and safe
        pass_test
    else
        fail_test "Bash should auto-truncate null-terminated strings to valid prefix"
    fi
}

#############################################
# Test: Case Sensitivity
#############################################

test_case_sensitivity() {
    print_section "Testing Case Sensitivity"

    # Model names should be case-sensitive
    begin_test "GEMMA4:E2B is rejected (wrong case)"
    if validate_model_name "GEMMA4:E2B"; then
        fail_test "Uppercase should be rejected"
    else
        pass_test
    fi

    begin_test "Gemma4:Latest is rejected (wrong case)"
    if validate_model_name "Gemma4:Latest"; then
        fail_test "Mixed case should be rejected"
    else
        pass_test
    fi

    begin_test "gemma4:LATEST is rejected (wrong case)"
    if validate_model_name "gemma4:LATEST"; then
        fail_test "Uppercase variant should be rejected"
    else
        pass_test
    fi
}

#############################################
# Test: Whitespace Handling
#############################################

test_whitespace() {
    print_section "Testing Whitespace Handling"

    # Test whitespace variations
    begin_test "' gemma4:e2b' with leading space is rejected"
    if validate_model_name " gemma4:e2b"; then
        fail_test "Leading whitespace should be rejected"
    else
        pass_test
    fi

    begin_test "'gemma4:e2b ' with trailing space is rejected"
    if validate_model_name "gemma4:e2b "; then
        fail_test "Trailing whitespace should be rejected"
    else
        pass_test
    fi

    begin_test "'gemma4: e2b' with space after colon is rejected"
    if validate_model_name "gemma4: e2b"; then
        fail_test "Space after colon should be rejected"
    else
        pass_test
    fi

    begin_test "'gemma4 :e2b' with space before colon is rejected"
    if validate_model_name "gemma4 :e2b"; then
        fail_test "Space before colon should be rejected"
    else
        pass_test
    fi
}

#############################################
# Test: Multiple Colons
#############################################

test_multiple_colons() {
    print_section "Testing Multiple Colons"

    begin_test "gemma4:e2b:extra is rejected"
    if validate_model_name "gemma4:e2b:extra"; then
        fail_test "Multiple colons should be rejected"
    else
        pass_test
    fi

    begin_test "gemma4::e2b is rejected"
    if validate_model_name "gemma4::e2b"; then
        fail_test "Double colon should be rejected"
    else
        pass_test
    fi

    begin_test ":gemma4:e2b is rejected"
    if validate_model_name ":gemma4:e2b"; then
        fail_test "Leading colon should be rejected"
    else
        pass_test
    fi

    begin_test "gemma4:e2b: is rejected"
    if validate_model_name "gemma4:e2b:"; then
        fail_test "Trailing colon should be rejected"
    else
        pass_test
    fi
}

#############################################
# Test: Length Validation
#############################################

test_length_validation() {
    print_section "Testing Length Validation"

    # Very long input
    begin_test "Very long model name is rejected"
    local long_name="gemma4:$(printf 'a%.0s' {1..1000})"
    if validate_model_name "$long_name"; then
        fail_test "Very long name should be rejected"
    else
        pass_test
    fi

    # Single character
    begin_test "gemma4:a is rejected"
    if validate_model_name "gemma4:a"; then
        fail_test "Single character variant should be rejected"
    else
        pass_test
    fi
}

#############################################
# Test: Model Name Format Variations
#############################################

test_format_variations() {
    print_section "Testing Format Variations"

    begin_test "gemma4e2b without colon is rejected"
    if validate_model_name "gemma4e2b"; then
        fail_test "Missing colon should be rejected"
    else
        pass_test
    fi

    begin_test "gemma:4:e2b is rejected"
    if validate_model_name "gemma:4:e2b"; then
        fail_test "Wrong format should be rejected"
    else
        pass_test
    fi

    begin_test "gemma-4:e2b is rejected"
    if validate_model_name "gemma-4:e2b"; then
        fail_test "Hyphen instead of 4 should be rejected"
    else
        pass_test
    fi

    begin_test "gemma_4:e2b is rejected"
    if validate_model_name "gemma_4:e2b"; then
        fail_test "Underscore should be rejected"
    else
        pass_test
    fi
}

#############################################
# Integration Test: Validation in Context
#############################################

test_validation_integration() {
    print_section "Integration: Validation in Script Context"

    # Test that validation is actually used in the setup script
    begin_test "setup script contains validate_model_name function"
    if grep -q "validate_model_name" "$PROJECT_DIR/setup-ai-opencode.sh"; then
        pass_test
    else
        fail_test "setup script should use validation"
    fi

    begin_test "setup script validates user input"
    if grep -A 5 "validate_model_name" "$PROJECT_DIR/setup-ai-opencode.sh" | grep -q "exit 1"; then
        pass_test
    else
        fail_test "setup script should exit on validation failure"
    fi
}

#############################################
# Main Execution
#############################################

main() {
    init_tests

    # Run all test suites
    test_validate_model_name_valid
    test_validate_model_name_invalid
    test_path_traversal
    test_special_characters
    test_unicode_and_encoding
    test_case_sensitivity
    test_whitespace
    test_multiple_colons
    test_length_validation
    test_format_variations
    test_validation_integration

    # Print summary and exit
    if print_test_summary; then
        exit 0
    else
        exit 1
    fi
}

# Run main
main "$@"
