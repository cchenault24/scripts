#!/usr/bin/env bash

#==============================================================================
# test_runner.sh - Test Runner
#
# Main test runner with reporting
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test helpers
source "$SCRIPT_DIR/test_helpers.sh"

#------------------------------------------------------------------------------
# Test Discovery and Execution
#------------------------------------------------------------------------------

# Find all test files
find_tests() {
    local test_dir="${1:-$SCRIPT_DIR}"
    find "$test_dir" -name "test_*.sh" -type f | sort
}

# Run a single test file
run_test_file() {
    local test_file="$1"
    local test_name=$(basename "$test_file" .sh)
    
    echo ""
    echo "=========================================="
    echo "Running: $test_name"
    echo "=========================================="
    
    # Setup test environment
    test_setup
    
    # Run test file
    if bash "$test_file"; then
        echo -e "${GREEN}✓ $test_name passed${NC}"
    else
        echo -e "${RED}✗ $test_name failed${NC}"
        TEST_FAILED=$((TEST_FAILED + 1))
    fi
    
    # Cleanup
    test_cleanup
}

# Run all tests
run_all_tests() {
    local test_dir="${1:-$SCRIPT_DIR}"
    local test_files=()
    
    echo "Discovering tests in $test_dir..."
    
    while IFS= read -r test_file; do
        [[ -f "$test_file" ]] && test_files+=("$test_file")
    done < <(find_tests "$test_dir")
    
    if [[ ${#test_files[@]} -eq 0 ]]; then
        echo "No tests found in $test_dir"
        return 1
    fi
    
    echo "Found ${#test_files[@]} test file(s)"
    echo ""
    
    # Run each test file
    for test_file in "${test_files[@]}"; do
        run_test_file "$test_file"
    done
    
    # Print summary
    test_summary
}

# Run specific test
run_test() {
    local test_name="$1"
    local test_file="$SCRIPT_DIR/test_${test_name}.sh"
    
    if [[ ! -f "$test_file" ]]; then
        echo "Test file not found: $test_file"
        return 1
    fi
    
    run_test_file "$test_file"
    test_summary
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

main() {
    local command="${1:-all}"
    
    case "$command" in
        all)
            run_all_tests
            ;;
        *)
            run_test "$command"
            ;;
    esac
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
