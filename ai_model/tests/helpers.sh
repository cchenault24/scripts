#!/bin/bash
# tests/helpers.sh - Test helper utilities for ai_model tests
#
# Provides:
# - Assertion functions for test validation
# - Mock functions for system calls
# - Test result tracking and reporting
# - Color-coded output for test results

set -euo pipefail

#############################################
# Color Definitions
#############################################
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#############################################
# Test State
#############################################
TESTS_PASSED=0
TESTS_FAILED=0
CURRENT_TEST_NAME=""

#############################################
# Test Lifecycle Functions
#############################################

# Initialize test suite
init_tests() {
    TESTS_PASSED=0
    TESTS_FAILED=0
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Running Test Suite${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Begin a test
begin_test() {
    CURRENT_TEST_NAME="$1"
    echo -ne "${BLUE}Testing:${NC} $CURRENT_TEST_NAME ... "
}

# Mark test as passed
pass_test() {
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}PASS${NC}"
}

# Mark test as failed
fail_test() {
    local message="${1:-}"
    ((TESTS_FAILED++)) || true
    echo -e "${RED}FAIL${NC}"
    if [[ -n "$message" ]]; then
        echo -e "  ${RED}Error:${NC} $message"
    fi
}

# Print test summary
print_test_summary() {
    local total=$((TESTS_PASSED + TESTS_FAILED))
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Test Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "Total:  $total tests"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    else
        echo -e "Failed: 0"
    fi
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    fi
}

#############################################
# Assertion Functions
#############################################

# Assert two values are equal
# Usage: assert_equals "expected" "actual" "test_name"
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="${3:-$CURRENT_TEST_NAME}"

    if [[ "$expected" == "$actual" ]]; then
        if [[ -z "$CURRENT_TEST_NAME" ]]; then
            begin_test "$test_name"
        fi
        pass_test
        return 0
    else
        if [[ -z "$CURRENT_TEST_NAME" ]]; then
            begin_test "$test_name"
        fi
        fail_test "Expected '$expected', got '$actual'"
        return 1
    fi
}

# Assert value contains substring
# Usage: assert_contains "substring" "value" "test_name"
assert_contains() {
    local substring="$1"
    local value="$2"
    local test_name="${3:-$CURRENT_TEST_NAME}"

    if [[ "$value" == *"$substring"* ]]; then
        if [[ -z "$CURRENT_TEST_NAME" ]]; then
            begin_test "$test_name"
        fi
        pass_test
        return 0
    else
        if [[ -z "$CURRENT_TEST_NAME" ]]; then
            begin_test "$test_name"
        fi
        fail_test "Expected to contain '$substring', got '$value'"
        return 1
    fi
}

# Assert file exists
# Usage: assert_file_exists "/path/to/file" "test_name"
assert_file_exists() {
    local file_path="$1"
    local test_name="${2:-$CURRENT_TEST_NAME}"

    if [[ -f "$file_path" ]]; then
        if [[ -z "$CURRENT_TEST_NAME" ]]; then
            begin_test "$test_name"
        fi
        pass_test
        return 0
    else
        if [[ -z "$CURRENT_TEST_NAME" ]]; then
            begin_test "$test_name"
        fi
        fail_test "File does not exist: $file_path"
        return 1
    fi
}

# Assert directory exists
# Usage: assert_dir_exists "/path/to/dir" "test_name"
assert_dir_exists() {
    local dir_path="$1"
    local test_name="${2:-$CURRENT_TEST_NAME}"

    if [[ -d "$dir_path" ]]; then
        if [[ -z "$CURRENT_TEST_NAME" ]]; then
            begin_test "$test_name"
        fi
        pass_test
        return 0
    else
        if [[ -z "$CURRENT_TEST_NAME" ]]; then
            begin_test "$test_name"
        fi
        fail_test "Directory does not exist: $dir_path"
        return 1
    fi
}

# Assert command succeeds
# Usage: assert_success "command" "test_name"
assert_success() {
    local test_name="${2:-$CURRENT_TEST_NAME}"

    if [[ -z "$CURRENT_TEST_NAME" ]]; then
        begin_test "$test_name"
    fi

    if eval "$1" &> /dev/null; then
        pass_test
        return 0
    else
        fail_test "Command failed: $1"
        return 1
    fi
}

# Assert command fails
# Usage: assert_failure "command" "test_name"
assert_failure() {
    local test_name="${2:-$CURRENT_TEST_NAME}"

    if [[ -z "$CURRENT_TEST_NAME" ]]; then
        begin_test "$test_name"
    fi

    if eval "$1" &> /dev/null; then
        fail_test "Command should have failed but succeeded: $1"
        return 1
    else
        pass_test
        return 0
    fi
}

# Assert numeric comparison
# Usage: assert_greater "10" "5" "test_name"
assert_greater() {
    local value1="$1"
    local value2="$2"
    local test_name="${3:-$CURRENT_TEST_NAME}"

    if [[ "$value1" -gt "$value2" ]]; then
        if [[ -z "$CURRENT_TEST_NAME" ]]; then
            begin_test "$test_name"
        fi
        pass_test
        return 0
    else
        if [[ -z "$CURRENT_TEST_NAME" ]]; then
            begin_test "$test_name"
        fi
        fail_test "Expected $value1 > $value2"
        return 1
    fi
}

# Assert numeric comparison
# Usage: assert_greater_equal "10" "10" "test_name"
assert_greater_equal() {
    local value1="$1"
    local value2="$2"
    local test_name="${3:-$CURRENT_TEST_NAME}"

    if [[ "$value1" -ge "$value2" ]]; then
        if [[ -z "$CURRENT_TEST_NAME" ]]; then
            begin_test "$test_name"
        fi
        pass_test
        return 0
    else
        if [[ -z "$CURRENT_TEST_NAME" ]]; then
            begin_test "$test_name"
        fi
        fail_test "Expected $value1 >= $value2"
        return 1
    fi
}

#############################################
# Mock Functions
#############################################

# Mock sysctl for testing hardware detection
# Usage: mock_sysctl "M4" "64" "8"
mock_sysctl() {
    local chip="$1"
    local ram_gb="$2"
    local cpu_cores="$3"

    local ram_bytes=$((ram_gb * 1024 * 1024 * 1024))

    # Override sysctl command
    sysctl() {
        case "$2" in
            machdep.cpu.brand_string)
                echo "Apple $chip Pro"
                ;;
            hw.memsize)
                echo "$ram_bytes"
                ;;
            hw.perflevel0.logicalcpu|hw.ncpu)
                echo "$cpu_cores"
                ;;
            *)
                echo ""
                ;;
        esac
    }
    export -f sysctl
}

# Mock ollama command for testing
# Usage: mock_ollama "list|pull|run" "output"
mock_ollama() {
    local subcommand="${1:-list}"
    local output="${2:-}"

    ollama() {
        local cmd="$1"
        shift
        case "$cmd" in
            list)
                cat << EOF
NAME                    ID              SIZE    MODIFIED
gemma4:e2b              abc123          7.2 GB  2 days ago
gemma4:latest           def456          9.6 GB  1 day ago
gemma4-optimized        ghi789          9.6 GB  1 hour ago
EOF
                ;;
            pull)
                echo "pulling manifest"
                echo "success"
                return 0
                ;;
            run)
                echo "Model response: Hello!"
                return 0
                ;;
            --version)
                echo "ollama version is 0.1.25"
                ;;
            *)
                echo "Mock ollama command: $cmd $*"
                ;;
        esac
    }
    export -f ollama
}

# Mock curl for testing API calls
mock_curl() {
    local response="${1:-success}"

    curl() {
        case "$response" in
            success)
                echo '{"models":[]}'
                return 0
                ;;
            failure)
                return 1
                ;;
            *)
                echo "$response"
                return 0
                ;;
        esac
    }
    export -f curl
}

#############################################
# Utility Functions
#############################################

# Create temporary test directory
create_test_dir() {
    local test_dir
    test_dir=$(mktemp -d "/tmp/ai_model_test.XXXXXX")
    echo "$test_dir"
}

# Cleanup temporary test directory
cleanup_test_dir() {
    local test_dir="$1"
    if [[ -n "$test_dir" && -d "$test_dir" ]]; then
        rm -rf "$test_dir"
    fi
}

# Print section header
print_section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}
