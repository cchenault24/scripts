# ai_model Test Suite

Comprehensive testing infrastructure for the ai_model project.

## Overview

This test suite provides quality assurance, unit testing, and integration testing for all components of the ai_model project. The tests ensure code quality, security, and correctness before deployment.

## Test Structure

```
tests/
├── README.md                  # This file
├── run_all_tests.sh          # Main test runner (runs all tests)
├── helpers.sh                # Test utilities and assertion functions
├── quality-checks.sh         # Shellcheck + security audits
├── test-hardware-config.sh   # Hardware configuration unit tests
├── test-validation.sh        # Input validation and security tests
└── test-integration.sh       # Integration and end-to-end tests
```

## Quick Start

### Run All Tests

```bash
# Run all tests with summary output
./tests/run_all_tests.sh

# Run all tests with detailed output
./tests/run_all_tests.sh --verbose
```

### Run Individual Test Suites

```bash
# Quality checks (must pass before commits)
./tests/quality-checks.sh

# Hardware configuration tests
./tests/test-hardware-config.sh

# Input validation tests
./tests/test-validation.sh

# Integration tests
./tests/test-integration.sh
```

## Test Suites

### 1. Quality Checks (`quality-checks.sh`)

**Purpose:** Ensure code quality, security, and best practices.

**Checks:**
- **Shellcheck validation** - Lints all shell scripts
- **Strict mode validation** - Ensures all scripts use `set -euo pipefail`
- **Security audits:**
  - Localhost binding only (no 0.0.0.0)
  - No hardcoded credentials
  - Proper variable quoting
  - No dangerous patterns (eval, rm -rf /)
- **File permissions** - No world-writable files
- **Documentation** - README exists, scripts have usage info
- **JSON validation** - Config files are syntactically valid

**Test Count:** 9 check categories

**Critical:** YES - Must pass before commits

**Example:**
```bash
./tests/quality-checks.sh
./tests/quality-checks.sh --verbose  # Detailed output
```

### 2. Hardware Configuration Tests (`test-hardware-config.sh`)

**Purpose:** Validate hardware optimization calculations.

**Tests:**
- `calculate_metal_memory()` - 6 tests across RAM tiers (8GB-128GB)
- `calculate_kv_cache_gb()` - 5 tests for all model variants
- `validate_gpu_fit()` - 6 tests for GPU memory validation
- `recommend_model()` - 6 tests for model recommendations
- `calculate_context_length()` - 12 tests for context optimization
- `calculate_num_parallel()` - 5 tests for parallel request settings
- `get_model_weight_gb()` - 4 tests for model sizes
- `get_model_size()` - 4 tests for model parsing
- `get_model_specs()` - 5 tests for specification lookup

**Test Count:** 53 unit tests

**Coverage:**
- Metal memory allocation (8GB to 128GB RAM)
- KV cache calculations for all models
- GPU fit validation (edge cases and extremes)
- Model recommendation logic
- Context window optimization
- Parallel request calculation

**Example:**
```bash
./tests/test-hardware-config.sh
```

### 3. Input Validation Tests (`test-validation.sh`)

**Purpose:** Ensure robust input validation and security.

**Tests:**
- Valid model names (gemma4:e2b, latest, 26b, 31b)
- Invalid model names (empty, unknown variants)
- Path traversal prevention (../../../etc/passwd)
- Command injection prevention (; && | $() ``)
- Special character handling
- Unicode and encoding (emoji, newlines, null bytes)
- Case sensitivity (GEMMA4 vs gemma4)
- Whitespace handling (leading/trailing spaces)
- Multiple colons (gemma4::e2b)
- Length validation (very long inputs)
- Format variations

**Test Count:** 43 security tests

**Security Focus:**
- Path traversal attacks
- Command injection
- Script injection
- Buffer overflow attempts
- Encoding attacks

**Example:**
```bash
./tests/test-validation.sh
```

### 4. Integration Tests (`test-integration.sh`)

**Purpose:** Validate end-to-end functionality and component integration.

**Tests:**
- Help text availability
- Library sourcing (no errors when sourcing)
- Hardware detection integration
- Model recommendation flow
- Context length calculation flow
- Print function output
- Byte conversion functions
- Constants defined correctly
- Directory structure
- Script permissions

**Test Count:** 25 integration tests

**Coverage:**
- Full hardware detection → model recommendation → context calculation flow
- Library function integration
- Configuration validation
- Directory structure verification

**Example:**
```bash
./tests/test-integration.sh
```

## Test Helpers (`helpers.sh`)

Provides reusable test utilities:

### Assertion Functions

```bash
assert_equals "expected" "actual" "test_name"
assert_contains "substring" "value" "test_name"
assert_file_exists "/path/to/file" "test_name"
assert_dir_exists "/path/to/dir" "test_name"
assert_success "command" "test_name"
assert_failure "command" "test_name"
assert_greater "10" "5" "test_name"
assert_greater_equal "10" "10" "test_name"
```

### Test Lifecycle

```bash
init_tests()                    # Initialize test suite
begin_test "test name"          # Start a test
pass_test                       # Mark test as passed
fail_test "error message"       # Mark test as failed
print_test_summary              # Print results (returns 0/1)
```

### Mock Functions

```bash
mock_sysctl "M4" "64" "8"      # Mock hardware detection
mock_ollama "list"              # Mock ollama commands
mock_curl "success"             # Mock API calls
```

### Utilities

```bash
create_test_dir                 # Create temp directory
cleanup_test_dir "/tmp/test"    # Remove temp directory
print_section "Header"          # Print section header
```

## Writing New Tests

### Basic Test Template

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_my_feature() {
    print_section "Testing My Feature"

    begin_test "Feature works correctly"
    if my_function "input"; then
        pass_test
    else
        fail_test "Expected success"
    fi

    assert_equals "expected" "$(my_function)" "Feature returns correct value"
}

main() {
    init_tests
    test_my_feature
    print_test_summary && exit 0 || exit 1
}

main "$@"
```

### Using Assertions

```bash
# Simple equality check
assert_equals "gemma4:e2b" "$result" "Model name is correct"

# Substring check
assert_contains "error" "$output" "Error message present"

# File existence
assert_file_exists "/tmp/config.json" "Config file created"

# Command success
assert_success "validate_model_name 'gemma4:latest'" "Valid model accepted"

# Command failure (security test)
assert_failure "validate_model_name '../../etc/passwd'" "Path traversal rejected"
```

## Pre-Commit Workflow

Before committing changes:

```bash
# Run all tests
./tests/run_all_tests.sh

# If tests fail, run with verbose output to debug
./tests/run_all_tests.sh --verbose

# Run quality checks specifically
./tests/quality-checks.sh --verbose
```

## CI/CD Integration

These tests are designed for CI/CD integration:

```bash
# Exit code 0 = all tests passed
# Exit code 1 = one or more tests failed

if ./tests/run_all_tests.sh; then
    echo "Tests passed - deploying..."
else
    echo "Tests failed - blocking deployment"
    exit 1
fi
```

## Test Coverage

| Component | Unit Tests | Integration Tests | Security Tests |
|-----------|------------|-------------------|----------------|
| Hardware Config | 53 | 4 | - |
| Model Selection | 12 | 2 | - |
| Input Validation | - | 2 | 43 |
| Library Functions | 10 | 8 | - |
| Print Functions | - | 5 | - |
| Constants | - | 3 | - |
| **Total** | **75** | **24** | **43** |

**Overall: 142+ individual test assertions**

## Dependencies

### Required
- bash 3.2+ (macOS default)
- Standard Unix utilities (grep, find, chmod)

### Optional (highly recommended)
- **shellcheck** - Shell script linting
  ```bash
  brew install shellcheck
  ```
- **jq** - JSON validation
  ```bash
  brew install jq
  ```

Tests will run without optional dependencies but some checks will be skipped.

## Exit Codes

All test scripts follow consistent exit code conventions:

- `0` - All tests passed
- `1` - One or more tests failed

The main test runner (`run_all_tests.sh`) aggregates results from all suites.

## Verbose Mode

All test scripts support `--verbose` flag for detailed output:

```bash
./tests/run_all_tests.sh --verbose
./tests/quality-checks.sh --verbose
./tests/test-hardware-config.sh --verbose
```

Verbose mode shows:
- Individual test progress
- Detailed failure information
- Line numbers for issues
- Specific values being tested

## Debugging Failed Tests

### 1. Run with verbose output
```bash
./tests/test-hardware-config.sh --verbose
```

### 2. Run specific test file
Instead of `run_all_tests.sh`, run the failing suite directly:
```bash
./tests/quality-checks.sh
```

### 3. Check script syntax
```bash
shellcheck tests/test-hardware-config.sh
```

### 4. Manual testing
Source the helpers and test individual functions:
```bash
source tests/helpers.sh
source lib/hardware-config.sh
calculate_metal_memory 64
```

## Known Issues

### Hardware-Specific Tests

Some hardware configuration tests may show different results based on your system's RAM. This is expected - the tests validate the logic, but recommendations may vary based on actual hardware.

### Mock Limitations

Mock functions simulate system behavior but may not cover all edge cases. Integration tests use real system calls when possible.

## Contributing

When adding new functionality:

1. Write tests first (TDD approach)
2. Add unit tests for individual functions
3. Add integration tests for component interactions
4. Update security tests if handling user input
5. Run full test suite before committing
6. Update this README if adding new test suites

## Support

For issues with tests:
1. Run with `--verbose` flag
2. Check that dependencies are installed
3. Verify you're in the correct directory
4. Review the test output for specific error messages

## License

Part of the ai_model project. See main project LICENSE.
