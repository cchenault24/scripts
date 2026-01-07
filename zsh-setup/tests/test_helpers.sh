#!/usr/bin/env bash

#==============================================================================
# test_helpers.sh - Test Helper Functions
#
# Provides common test utilities and assertions
#==============================================================================

# Test counters
TEST_PASSED=0
TEST_FAILED=0
TEST_TOTAL=0
CURRENT_TEST=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#------------------------------------------------------------------------------
# Test Framework Functions
#------------------------------------------------------------------------------

# Start a test
test_start() {
    CURRENT_TEST="$1"
    ((TEST_TOTAL++))
    echo -n "Testing: $CURRENT_TEST... "
}

# Assert that a command succeeds
assert_success() {
    local cmd="$1"
    local description="${2:-Command should succeed}"
    
    if eval "$cmd" >/dev/null 2>&1; then
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        echo "  → $description"
        ((TEST_FAILED++))
        return 1
    fi
}

# Assert that a command fails
assert_failure() {
    local cmd="$1"
    local description="${2:-Command should fail}"
    
    if ! eval "$cmd" >/dev/null 2>&1; then
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        echo "  → $description"
        ((TEST_FAILED++))
        return 1
    fi
}

# Assert two values are equal
assert_equal() {
    local expected="$1"
    local actual="$2"
    local description="${3:-Values should be equal}"
    
    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        echo "  → $description"
        echo "    Expected: $expected"
        echo "    Actual: $actual"
        ((TEST_FAILED++))
        return 1
    fi
}

# Assert a file exists
assert_file_exists() {
    local file="$1"
    local description="${2:-File should exist}"
    
    if [[ -f "$file" ]]; then
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        echo "  → $description: $file"
        ((TEST_FAILED++))
        return 1
    fi
}

# Assert a directory exists
assert_dir_exists() {
    local dir="$1"
    local description="${2:-Directory should exist}"
    
    if [[ -d "$dir" ]]; then
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        echo "  → $description: $dir"
        ((TEST_FAILED++))
        return 1
    fi
}

# Assert a string contains a substring
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local description="${3:-String should contain substring}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        echo "  → $description"
        echo "    Looking for: $needle"
        echo "    In: $haystack"
        ((TEST_FAILED++))
        return 1
    fi
}

# Mark test as passed
test_pass() {
    echo -e "${GREEN}PASS${NC}"
    ((TEST_PASSED++))
}

# Mark test as failed
test_fail() {
    local reason="$1"
    echo -e "${RED}FAIL${NC}"
    [[ -n "$reason" ]] && echo "  → $reason"
    ((TEST_FAILED++))
}

# Skip a test
test_skip() {
    local reason="$1"
    echo -e "${YELLOW}SKIP${NC}"
    [[ -n "$reason" ]] && echo "  → $reason"
}

# Setup test environment
test_setup() {
    export ZSH_SETUP_ROOT="${TEST_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    export TEST_TMPDIR=$(mktemp -d -t zsh_setup_test.XXXXXX)
    export ZSH_SETUP_STATE_FILE="$TEST_TMPDIR/test_state.json"
}

# Cleanup test environment
test_cleanup() {
    [[ -n "$TEST_TMPDIR" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# Print test summary
test_summary() {
    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Total:  $TEST_TOTAL"
    echo -e "Passed: ${GREEN}$TEST_PASSED${NC}"
    echo -e "Failed: ${RED}$TEST_FAILED${NC}"
    echo "=========================================="
    
    if [[ $TEST_FAILED -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}
