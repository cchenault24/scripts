#!/bin/zsh
#
# test_security_command_injection.sh - Test for command injection vulnerabilities
# SEC-1: Verify that eval has been removed and command injection is not possible
#

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test results tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Get script directory
SCRIPT_DIR="${0:A:h}"
LIB_DIR="$SCRIPT_DIR/lib"

# Source required libraries
source "$LIB_DIR/constants.sh"
source "$LIB_DIR/ui.sh"
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/error_handler.sh"

print_test_header() {
  echo "\n${YELLOW}=== $1 ===${NC}"
  ((TESTS_RUN++))
}

print_test_pass() {
  echo "${GREEN}✓ PASS${NC}: $1"
  ((TESTS_PASSED++))
}

print_test_fail() {
  echo "${RED}✗ FAIL${NC}: $1"
  ((TESTS_FAILED++))
}

print_summary() {
  echo "\n${YELLOW}=== Test Summary ===${NC}"
  echo "Tests run:    $TESTS_RUN"
  echo "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
  echo "Tests failed: ${RED}$TESTS_FAILED${NC}"

  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "\n${GREEN}All tests passed!${NC}"
    return 0
  else
    echo "\n${RED}Some tests failed!${NC}"
    return 1
  fi
}

# Test 1: Verify eval is not present in any shell scripts
test_no_eval_in_codebase() {
  print_test_header "Test 1: Verify no eval commands in codebase"

  # Exclude lines that are comments (both full-line and inline comments)
  local eval_results=$(grep -rn "\beval\b" "$LIB_DIR" --include="*.sh" 2>/dev/null | grep -v "^\s*#" | grep -v ":[[:space:]]*#" || true)

  if [[ -z "$eval_results" ]]; then
    print_test_pass "No eval commands found in codebase (excluding comments)"
  else
    local eval_count=$(echo "$eval_results" | wc -l | xargs)
    print_test_fail "Found $eval_count eval command(s) in codebase"
    echo "$eval_results"
  fi
}

# Test 2: Attempt command injection via error messages
test_error_handler_injection() {
  print_test_header "Test 2: Attempt command injection via error handler"

  # Create a temporary file to check if commands execute
  local test_file="/tmp/mac-cleanup-injection-test-$$"
  rm -f "$test_file"

  # Try various injection payloads in error messages
  local injection_payloads=(
    "error; touch $test_file"
    "error\`touch $test_file\`"
    "error\$(touch $test_file)"
    "error| touch $test_file"
    "error& touch $test_file"
    "error && touch $test_file"
    "error || touch $test_file"
    "error > $test_file"
  )

  local injection_detected=false

  for payload in "${injection_payloads[@]}"; do
    # Try to trigger command injection through error handler
    mc_handle_plugin_error "test_operation" "$payload" 1 "test_plugin" "test_suggestion" 2>/dev/null || true

    # Check if injection succeeded
    if [[ -f "$test_file" ]]; then
      print_test_fail "Command injection succeeded with payload: $payload"
      injection_detected=true
      rm -f "$test_file"
      break
    fi
  done

  if ! $injection_detected; then
    print_test_pass "No command injection possible via error handler"
  fi

  # Cleanup
  rm -f "$test_file"
}

# Test 3: Attempt command injection via backup error handler
test_backup_error_injection() {
  print_test_header "Test 3: Attempt command injection via backup error handler"

  local test_file="/tmp/mac-cleanup-backup-injection-test-$$"
  rm -f "$test_file"

  local injection_payloads=(
    "path; touch $test_file"
    "backup\$(touch $test_file)"
    "plugin| touch $test_file"
    "reason&& touch $test_file"
  )

  local injection_detected=false

  for payload in "${injection_payloads[@]}"; do
    mc_handle_backup_error "$payload" "test_backup" "test_plugin" "$payload" 2>/dev/null || true

    if [[ -f "$test_file" ]]; then
      print_test_fail "Command injection succeeded with payload: $payload"
      injection_detected=true
      rm -f "$test_file"
      break
    fi
  done

  if ! $injection_detected; then
    print_test_pass "No command injection possible via backup error handler"
  fi

  rm -f "$test_file"
}

# Test 4: Attempt command injection via cleanup error handler
test_cleanup_error_injection() {
  print_test_header "Test 4: Attempt command injection via cleanup error handler"

  local test_file="/tmp/mac-cleanup-cleanup-injection-test-$$"
  rm -f "$test_file"

  local injection_payloads=(
    "path; touch $test_file"
    "description\$(touch $test_file)"
    "plugin| touch $test_file"
    "reason&& touch $test_file"
  )

  local injection_detected=false

  for payload in "${injection_payloads[@]}"; do
    mc_handle_cleanup_error "$payload" "$payload" "test_plugin" "$payload" 2>/dev/null || true

    if [[ -f "$test_file" ]]; then
      print_test_fail "Command injection succeeded with payload: $payload"
      injection_detected=true
      rm -f "$test_file"
      break
    fi
  done

  if ! $injection_detected; then
    print_test_pass "No command injection possible via cleanup error handler"
  fi

  rm -f "$test_file"
}

# Test 5: Attempt command injection via return value checker
test_check_return_value_injection() {
  print_test_header "Test 5: Attempt command injection via return value checker"

  local test_file="/tmp/mac-cleanup-return-injection-test-$$"
  rm -f "$test_file"

  local injection_payloads=(
    "success; touch $test_file"
    "error\$(touch $test_file)"
    "plugin| touch $test_file"
  )

  local injection_detected=false

  for payload in "${injection_payloads[@]}"; do
    mc_check_return_value 1 "$payload" "$payload" "$payload" 2>/dev/null || true

    if [[ -f "$test_file" ]]; then
      print_test_fail "Command injection succeeded with payload: $payload"
      injection_detected=true
      rm -f "$test_file"
      break
    fi
  done

  if ! $injection_detected; then
    print_test_pass "No command injection possible via return value checker"
  fi

  rm -f "$test_file"
}

# Test 6: Verify shellcheck passes on error_handler.sh
test_shellcheck_error_handler() {
  print_test_header "Test 6: Verify shellcheck passes on error_handler.sh"

  if ! command -v shellcheck &>/dev/null; then
    print_test_pass "shellcheck not installed, skipping"
    return 0
  fi

  local shellcheck_output=$(shellcheck "$LIB_DIR/error_handler.sh" 2>&1 || true)

  if [[ -z "$shellcheck_output" ]]; then
    print_test_pass "shellcheck passed on error_handler.sh"
  else
    print_test_fail "shellcheck found issues in error_handler.sh:"
    echo "$shellcheck_output"
  fi
}

# Test 7: Verify shellcheck passes on core.sh (where eval was removed)
test_shellcheck_core() {
  print_test_header "Test 7: Verify shellcheck passes on core.sh"

  if ! command -v shellcheck &>/dev/null; then
    print_test_pass "shellcheck not installed, skipping"
    return 0
  fi

  local shellcheck_output=$(shellcheck "$LIB_DIR/core.sh" 2>&1 || true)

  if [[ -z "$shellcheck_output" ]]; then
    print_test_pass "shellcheck passed on core.sh"
  else
    print_test_fail "shellcheck found issues in core.sh:"
    echo "$shellcheck_output"
  fi
}

# Test 8: Verify that removed function no longer exists
test_removed_function() {
  print_test_header "Test 8: Verify mc_execute_with_error_handling was removed"

  # Check if the function exists in error_handler.sh
  if grep -q "^mc_execute_with_error_handling()" "$LIB_DIR/error_handler.sh"; then
    print_test_fail "mc_execute_with_error_handling function still exists"
  else
    print_test_pass "mc_execute_with_error_handling function has been removed"
  fi

  # Check if the function is defined anywhere
  local function_count=$(grep -r "mc_execute_with_error_handling()" "$LIB_DIR" --include="*.sh" 2>/dev/null | grep -v "^[[:space:]]*#" | wc -l | tr -d ' ')

  if [[ $function_count -eq 0 ]]; then
    print_test_pass "mc_execute_with_error_handling not defined anywhere in codebase"
  else
    print_test_fail "mc_execute_with_error_handling still defined in $function_count file(s)"
  fi
}

# Test 9: Verify core.sh glob qualifier test doesn't use eval
test_glob_qualifier_no_eval() {
  print_test_header "Test 9: Verify glob qualifier test doesn't use eval"

  # Find the glob qualifier test section and verify it doesn't use eval
  local glob_test_lines=$(grep -A2 "Verify zsh-specific features" "$LIB_DIR/core.sh" | grep -v "^--$" || true)

  if echo "$glob_test_lines" | grep -q "eval"; then
    print_test_fail "core.sh glob qualifier test still contains eval"
    echo "$glob_test_lines" | grep "eval"
  else
    print_test_pass "core.sh glob qualifier test no longer uses eval"
  fi
}

# Main test execution
main() {
  echo "${YELLOW}=== SEC-1: Command Injection Security Tests ===${NC}"
  echo "Testing for command injection vulnerabilities after eval removal"

  # Run all tests
  test_no_eval_in_codebase
  test_error_handler_injection
  test_backup_error_injection
  test_cleanup_error_injection
  test_check_return_value_injection
  test_shellcheck_error_handler
  test_shellcheck_core
  test_removed_function
  test_glob_qualifier_no_eval

  # Print summary and exit
  print_summary
}

# Run tests
main
