#!/bin/bash
# tests/run_all_tests.sh - Main test runner for ai_model project
#
# Runs all test suites in sequence:
# - quality-checks.sh - Shellcheck + security audit
# - test-hardware-config.sh - Hardware configuration unit tests
# - test-validation.sh - Input validation tests
#
# Exit code: 0 if all tests pass, 1 if any test fails
#
# Usage: ./tests/run_all_tests.sh [--verbose]

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color definitions
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Verbose mode
VERBOSE_FLAG=""
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE_FLAG="--verbose"
fi

#############################################
# Configuration
#############################################

# Test suites to run
TEST_SUITES=(
    "quality-checks.sh|Quality Checks (Shellcheck + Security)|critical"
    "test-hardware-config.sh|Hardware Configuration Tests|unit"
    "test-validation.sh|Input Validation Tests|unit"
    "test-integration.sh|Integration Tests|integration"
    "test-e2e-flow.sh|E2E Interactive Flow Tests|e2e"
)

# Track results
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
SKIPPED_SUITES=0

# Track timing
START_TIME=$(date +%s)

#############################################
# Helper Functions
#############################################

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_suite_header() {
    echo ""
    echo -e "${BLUE}┌────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│ $1${NC}"
    echo -e "${BLUE}└────────────────────────────────────────┘${NC}"
}

print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

#############################################
# Test Suite Runner
#############################################

run_test_suite() {
    local suite_file="$1"
    local suite_name="$2"
    local suite_type="$3"  # critical, unit, integration

    ((TOTAL_SUITES++)) || true

    # Check if test file exists
    if [[ ! -f "$SCRIPT_DIR/$suite_file" ]]; then
        print_warning "$suite_name - Test file not found: $suite_file"
        ((SKIPPED_SUITES++)) || true
        return 1
    fi

    # Make sure test is executable
    chmod +x "$SCRIPT_DIR/$suite_file"

    print_suite_header "$suite_name"
    echo -e "${BLUE}Running:${NC} $suite_file"

    local start_time
    start_time=$(date +%s)

    # Run the test suite
    local exit_code=0
    if [[ -n "$VERBOSE_FLAG" ]]; then
        "$SCRIPT_DIR/$suite_file" "$VERBOSE_FLAG" || exit_code=$?
    else
        "$SCRIPT_DIR/$suite_file" || exit_code=$?
    fi

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Report result
    echo ""
    if [[ $exit_code -eq 0 ]]; then
        print_status "$suite_name completed successfully (${duration}s)"
        ((PASSED_SUITES++)) || true
        return 0
    else
        print_error "$suite_name failed (${duration}s)"
        ((FAILED_SUITES++)) || true
        return 1
    fi
}

#############################################
# Pre-flight Checks
#############################################

preflight_checks() {
    print_header "Pre-flight Checks"

    local all_good=true

    # Check that we're in the right directory
    if [[ ! -f "$PROJECT_DIR/setup-gemma4-opencode.sh" ]]; then
        print_error "Not in ai_model project directory"
        all_good=false
    else
        print_status "Project directory: $PROJECT_DIR"
    fi

    # Check for lib directory
    if [[ ! -d "$PROJECT_DIR/lib" ]]; then
        print_error "lib directory not found"
        all_good=false
    else
        print_status "lib directory found"
    fi

    # Check for test helpers
    if [[ ! -f "$SCRIPT_DIR/helpers.sh" ]]; then
        print_error "Test helpers not found: helpers.sh"
        all_good=false
    else
        print_status "Test helpers found"
    fi

    # Optional tools (warn but don't fail)
    if ! command -v shellcheck &> /dev/null; then
        print_warning "shellcheck not installed (some tests will be skipped)"
        print_info "Install with: brew install shellcheck"
    else
        print_status "shellcheck found"
    fi

    if ! command -v jq &> /dev/null; then
        print_warning "jq not installed (JSON validation will be skipped)"
        print_info "Install with: brew install jq"
    else
        print_status "jq found"
    fi

    echo ""
    if [[ "$all_good" != true ]]; then
        print_error "Pre-flight checks failed"
        return 1
    fi

    print_status "Pre-flight checks passed"
    return 0
}

#############################################
# Main Test Execution
#############################################

run_all_tests() {
    print_header "ai_model Test Suite"
    echo -e "Project: ${BLUE}ai_model${NC}"
    echo -e "Tests:   ${BLUE}${#TEST_SUITES[@]} suites${NC}"
    if [[ -n "$VERBOSE_FLAG" ]]; then
        echo -e "Mode:    ${BLUE}verbose${NC}"
    fi

    # Run pre-flight checks
    if ! preflight_checks; then
        return 1
    fi

    # Run all test suites
    local all_passed=true
    for suite in "${TEST_SUITES[@]}"; do
        IFS='|' read -r file name type <<< "$suite"
        if ! run_test_suite "$file" "$name" "$type"; then
            all_passed=false
            # For critical tests, we might want to stop
            if [[ "$type" == "critical" ]]; then
                print_warning "Critical test failed - continuing with remaining tests"
            fi
        fi
    done

    return 0
}

#############################################
# Final Summary
#############################################

print_summary() {
    local end_time
    end_time=$(date +%s)
    local total_duration=$((end_time - START_TIME))

    print_header "Test Summary"

    echo -e "Total Suites:  $TOTAL_SUITES"
    echo -e "${GREEN}Passed:        $PASSED_SUITES${NC}"
    if [[ $FAILED_SUITES -gt 0 ]]; then
        echo -e "${RED}Failed:        $FAILED_SUITES${NC}"
    else
        echo -e "Failed:        0"
    fi
    if [[ $SKIPPED_SUITES -gt 0 ]]; then
        echo -e "${YELLOW}Skipped:       $SKIPPED_SUITES${NC}"
    else
        echo -e "Skipped:       0"
    fi
    echo -e "Duration:      ${total_duration}s"
    echo ""

    if [[ $FAILED_SUITES -eq 0 && $SKIPPED_SUITES -eq 0 ]]; then
        echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║                                        ║${NC}"
        echo -e "${GREEN}║   ✓ All tests passed successfully!     ║${NC}"
        echo -e "${GREEN}║                                        ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
        echo ""
        echo "Safe to commit changes."
        return 0
    elif [[ $FAILED_SUITES -eq 0 ]]; then
        echo -e "${YELLOW}⚠ All tests passed but some were skipped${NC}"
        echo ""
        echo "Review skipped tests and install missing tools."
        return 0
    else
        echo -e "${RED}╔════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                                        ║${NC}"
        echo -e "${RED}║   ✗ Some tests failed                  ║${NC}"
        echo -e "${RED}║                                        ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════╝${NC}"
        echo ""
        echo "Please fix the failing tests before committing."
        echo ""
        echo "Tip: Run with --verbose for detailed output:"
        echo "  ./tests/run_all_tests.sh --verbose"
        return 1
    fi
}

#############################################
# Usage Information
#############################################

print_usage() {
    cat << EOF
Usage: ./tests/run_all_tests.sh [OPTIONS]

Main test runner for ai_model project.

OPTIONS:
    --verbose    Show detailed output from all tests
    --help       Show this help message

EXAMPLES:
    # Run all tests with summary output
    ./tests/run_all_tests.sh

    # Run all tests with detailed output
    ./tests/run_all_tests.sh --verbose

    # Run specific test suite
    ./tests/test-hardware-config.sh
    ./tests/quality-checks.sh

TEST SUITES:
    quality-checks.sh         - Shellcheck + security audit
    test-hardware-config.sh   - Hardware configuration tests
    test-validation.sh        - Input validation tests
    test-integration.sh       - Integration tests

EXIT CODES:
    0    All tests passed
    1    One or more tests failed

EOF
}

#############################################
# Main Entry Point
#############################################

main() {
    # Handle help flag
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        print_usage
        exit 0
    fi

    # Run all tests
    run_all_tests

    # Print summary
    if print_summary; then
        exit 0
    else
        exit 1
    fi
}

# Run main
main "$@"
