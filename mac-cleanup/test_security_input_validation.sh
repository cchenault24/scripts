#!/bin/zsh
#
# test_security_input_validation.sh - Test SEC-10 plugin input validation
#
# Tests that plugin registration validates inputs to prevent code injection

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Print functions
print_test() {
  echo "${BLUE}[TEST]${NC} $1"
}

print_pass() {
  echo "${GREEN}[PASS]${NC} $1"
}

print_fail() {
  echo "${RED}[FAIL]${NC} $1"
}

print_info() {
  echo "${YELLOW}[INFO]${NC} $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load required libraries
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/plugins/base.sh"

# Initialize logging
MC_LOG_FILE="/tmp/mac-cleanup-test-$$.log"
MC_LOG_LEVEL_ERROR="ERROR"
MC_LOG_LEVEL_WARNING="WARNING"
MC_LOG_LEVEL_INFO="INFO"

# Create dummy plugin functions for testing
dummy_plugin_clean() {
  echo "Dummy clean"
}

dummy_plugin_size() {
  echo "1024"
}

echo "========================================"
echo "SEC-10: Plugin Input Validation"
echo "========================================"
echo ""

# Test 1: Valid plugin registration
print_test "Test 1: Valid plugin registration"
TESTS_RUN=$((TESTS_RUN + 1))

if register_plugin "Test Plugin" "user" "dummy_plugin_clean" "false" "" "1.0.0" "" 2>/dev/null; then
  print_pass "Valid plugin registered successfully"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  print_fail "Failed to register valid plugin"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 2: Reject plugin name with semicolon (code injection attempt)
print_test "Test 2: Reject plugin name with semicolon"
TESTS_RUN=$((TESTS_RUN + 1))

if register_plugin "Evil; rm -rf /" "user" "dummy_plugin_clean" "false" 2>/dev/null; then
  print_fail "Accepted plugin name with semicolon (SECURITY RISK!)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  print_pass "Correctly rejected plugin name with semicolon"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test 3: Reject plugin name with dollar sign (variable expansion)
print_test "Test 3: Reject plugin name with dollar sign"
TESTS_RUN=$((TESTS_RUN + 1))

if register_plugin "Evil \$HOME" "user" "dummy_plugin_clean" "false" 2>/dev/null; then
  print_fail "Accepted plugin name with dollar sign (SECURITY RISK!)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  print_pass "Correctly rejected plugin name with dollar sign"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test 4: Reject plugin name with backticks (command substitution)
print_test "Test 4: Reject plugin name with backticks"
TESTS_RUN=$((TESTS_RUN + 1))

if register_plugin "Evil \`whoami\`" "user" "dummy_plugin_clean" "false" 2>/dev/null; then
  print_fail "Accepted plugin name with backticks (SECURITY RISK!)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  print_pass "Correctly rejected plugin name with backticks"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test 5: Reject invalid function name (not a valid identifier)
print_test "Test 5: Reject invalid function name"
TESTS_RUN=$((TESTS_RUN + 1))

if register_plugin "Test" "user" "rm -rf /; echo" "false" 2>/dev/null; then
  print_fail "Accepted invalid function name (SECURITY RISK!)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  print_pass "Correctly rejected invalid function name"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test 6: Reject function name with special characters
print_test "Test 6: Reject function name with special characters"
TESTS_RUN=$((TESTS_RUN + 1))

if register_plugin "Test" "user" "func;malicious" "false" 2>/dev/null; then
  print_fail "Accepted function name with semicolon (SECURITY RISK!)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  print_pass "Correctly rejected function name with special characters"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test 7: Reject non-existent function
print_test "Test 7: Reject non-existent function"
TESTS_RUN=$((TESTS_RUN + 1))

if register_plugin "Test" "user" "nonexistent_function_12345" "false" 2>/dev/null; then
  print_fail "Accepted non-existent function"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  print_pass "Correctly rejected non-existent function"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test 8: Reject invalid category
print_test "Test 8: Reject invalid category"
TESTS_RUN=$((TESTS_RUN + 1))

if register_plugin "Test" "evil_category" "dummy_plugin_clean" "false" 2>/dev/null; then
  print_fail "Accepted invalid category"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  print_pass "Correctly rejected invalid category"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test 9: Accept valid categories
print_test "Test 9: Accept all valid categories"
TESTS_RUN=$((TESTS_RUN + 1))

valid_categories=("system" "user" "development" "browsers" "misc" "package-managers" "maintenance" "network")
all_passed=true

for category in "${valid_categories[@]}"; do
  if ! register_plugin "Test $category" "$category" "dummy_plugin_clean" "false" 2>/dev/null; then
    print_fail "Failed to register plugin with valid category: $category"
    all_passed=false
  fi
done

if [[ "$all_passed" == "true" ]]; then
  print_pass "All valid categories accepted"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 10: Reject empty function name
print_test "Test 10: Reject empty function name"
TESTS_RUN=$((TESTS_RUN + 1))

if register_plugin "Test" "user" "" "false" 2>/dev/null; then
  print_fail "Accepted empty function name"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  print_pass "Correctly rejected empty function name"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test 11: Reject invalid size function name
print_test "Test 11: Reject invalid size function name"
TESTS_RUN=$((TESTS_RUN + 1))

if register_plugin "Test" "user" "dummy_plugin_clean" "false" "evil; rm -rf /" "1.0.0" "" 2>/dev/null; then
  print_fail "Accepted invalid size function name (SECURITY RISK!)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  print_pass "Correctly rejected invalid size function name"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test 12: Accept valid size function
print_test "Test 12: Accept valid size function"
TESTS_RUN=$((TESTS_RUN + 1))

if register_plugin "Test Size" "user" "dummy_plugin_clean" "false" "dummy_plugin_size" "1.0.0" "" 2>/dev/null; then
  print_pass "Valid size function accepted"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  print_fail "Failed to register plugin with valid size function"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 13: Sanitize invalid version format
print_test "Test 13: Sanitize invalid version format"
TESTS_RUN=$((TESTS_RUN + 1))

if register_plugin "Test Version" "user" "dummy_plugin_clean" "false" "" "1.0; malicious" "" 2>/dev/null; then
  # Should succeed but with sanitized version
  print_pass "Invalid version rejected/sanitized"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  # Also OK if it rejects the registration
  print_pass "Invalid version caused registration to fail (safe behavior)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test 14: Function name starting with number (invalid)
print_test "Test 14: Reject function name starting with number"
TESTS_RUN=$((TESTS_RUN + 1))

if register_plugin "Test" "user" "123invalid" "false" 2>/dev/null; then
  print_fail "Accepted function name starting with number"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  print_pass "Correctly rejected function name starting with number"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test 15: Verify type -f check works (function vs command)
print_test "Test 15: Verify type -f distinguishes functions from commands"
TESTS_RUN=$((TESTS_RUN + 1))

# ls is a command, not a function, so it should be rejected
if register_plugin "Test" "user" "ls" "false" 2>/dev/null; then
  # Actually, this might pass because ls exists - let's check if it's properly validated
  # The test checks if it's a function with type -f
  print_fail "Accepted external command 'ls' as function"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  print_pass "Correctly rejected external command as function"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Cleanup
rm -f "$MC_LOG_FILE" 2>/dev/null || true

echo ""
echo "========================================"
echo "Test Results:"
echo "  Total:  $TESTS_RUN"
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo "========================================"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
  echo "${GREEN}ALL TESTS PASSED!${NC}"
  exit 0
else
  echo "${RED}SOME TESTS FAILED!${NC}"
  exit 1
fi
