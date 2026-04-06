#!/bin/zsh
#
# test-sec6-sec8.sh - Test script for SEC-6 and SEC-8 security fixes
#
# SEC-6: Secure temporary file creation using mktemp
# SEC-8: Strict mode (set -euo pipefail) in main script
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"

# Test colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_test() {
  echo -e "${BLUE}[TEST]${NC} $1"
}

print_pass() {
  echo -e "${GREEN}[PASS]${NC} $1"
}

print_fail() {
  echo -e "${RED}[FAIL]${NC} $1"
}

print_info() {
  echo -e "${YELLOW}[INFO]${NC} $1"
}

# Source required libraries
source "$SCRIPT_DIR/lib/constants.sh"
source "$SCRIPT_DIR/lib/utils.sh"

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
  local test_name="$1"
  local test_func="$2"

  TESTS_RUN=$((TESTS_RUN + 1))
  print_test "$test_name"

  if $test_func; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    print_pass "$test_name"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    print_fail "$test_name"
    return 1
  fi
}

###############################################################################
# SEC-8: Test strict mode in main script
###############################################################################

test_sec8_strict_mode_enabled() {
  # Check that line 2 of mac-cleanup.sh contains 'set -euo pipefail'
  local line2=$(sed -n '2p' "$SCRIPT_DIR/mac-cleanup.sh")
  if [[ "$line2" =~ "set -euo pipefail" ]]; then
    print_info "Strict mode is enabled on line 2"
    return 0
  else
    print_info "Expected: set -euo pipefail"
    print_info "Got: $line2"
    return 1
  fi
}

test_sec8_undefined_variable_fails() {
  # Test that referencing an undefined variable causes script to exit
  # We'll do this by running a subshell with strict mode
  local test_script=$(mktemp -t "test-undef.XXXXXXXXXX")
  cat > "$test_script" <<'EOF'
#!/bin/zsh
set -euo pipefail
echo "$UNDEFINED_VAR"
EOF
  chmod +x "$test_script"

  # Run the script - it should fail
  if "$test_script" 2>/dev/null; then
    rm -f "$test_script"
    print_info "Script should have failed on undefined variable"
    return 1
  else
    rm -f "$test_script"
    print_info "Script correctly exits on undefined variable"
    return 0
  fi
}

test_sec8_pipeline_failure_detected() {
  # Test that pipeline failures are detected
  local test_script=$(mktemp -t "test-pipe.XXXXXXXXXX")
  cat > "$test_script" <<'EOF'
#!/bin/zsh
set -euo pipefail
false | true
EOF
  chmod +x "$test_script"

  # Run the script - it should fail because left side of pipe fails
  if "$test_script" 2>/dev/null; then
    rm -f "$test_script"
    print_info "Script should have failed on pipeline failure"
    return 1
  else
    rm -f "$test_script"
    print_info "Script correctly detects pipeline failures"
    return 0
  fi
}

###############################################################################
# SEC-6: Test secure temporary file creation
###############################################################################

test_sec6_create_secure_temp_file_exists() {
  # Check that create_secure_temp_file function exists
  if type create_secure_temp_file &>/dev/null; then
    print_info "create_secure_temp_file function exists"
    return 0
  else
    print_info "create_secure_temp_file function not found"
    return 1
  fi
}

test_sec6_temp_file_creation() {
  # Test that create_secure_temp_file creates a file with correct permissions
  local temp_file=$(create_secure_temp_file "test-prefix" 2>/dev/null || echo "")

  if [[ -z "$temp_file" ]]; then
    print_info "Failed to create temp file"
    return 1
  fi

  if [[ ! -f "$temp_file" ]]; then
    print_info "Temp file was not created: $temp_file"
    return 1
  fi

  # Check permissions (should be 600)
  local perms=$(stat -f "%Lp" "$temp_file" 2>/dev/null || echo "")
  rm -f "$temp_file"

  if [[ "$perms" != "600" ]]; then
    print_info "Expected permissions: 600, got: $perms"
    return 1
  fi

  print_info "Temp file created with correct permissions (600)"
  return 0
}

test_sec6_temp_file_unpredictable() {
  # Test that temp file names are unpredictable (contain random chars)
  local temp_file1=$(create_secure_temp_file "test" 2>/dev/null || echo "")
  local temp_file2=$(create_secure_temp_file "test" 2>/dev/null || echo "")

  if [[ -z "$temp_file1" || -z "$temp_file2" ]]; then
    print_info "Failed to create temp files"
    [[ -f "$temp_file1" ]] && rm -f "$temp_file1"
    [[ -f "$temp_file2" ]] && rm -f "$temp_file2"
    return 1
  fi

  # Files should have different names
  if [[ "$temp_file1" == "$temp_file2" ]]; then
    print_info "Temp files have same name (not random): $temp_file1"
    rm -f "$temp_file1" "$temp_file2"
    return 1
  fi

  # Names should not be predictable (should not contain just $$)
  if [[ "$temp_file1" =~ -[0-9]+\.tmp$ ]]; then
    print_info "Temp file name appears predictable: $temp_file1"
    rm -f "$temp_file1" "$temp_file2"
    return 1
  fi

  print_info "Temp file names are unpredictable"
  print_info "  File 1: $(basename "$temp_file1")"
  print_info "  File 2: $(basename "$temp_file2")"
  rm -f "$temp_file1" "$temp_file2"
  return 0
}

test_sec6_no_insecure_patterns() {
  # Check that mac-cleanup.sh doesn't use insecure temp file patterns
  local insecure_count=0
  if grep -q '\$\$\.tmp' "$SCRIPT_DIR/mac-cleanup.sh" 2>/dev/null; then
    insecure_count=$(grep -c '\$\$\.tmp' "$SCRIPT_DIR/mac-cleanup.sh" 2>/dev/null)
  fi

  if [[ $insecure_count -gt 0 ]]; then
    print_info "Found $insecure_count instances of insecure pattern \$\$.tmp"
    grep -n '\$\$\.tmp' "$SCRIPT_DIR/mac-cleanup.sh"
    return 1
  fi

  print_info "No insecure temp file patterns found"
  return 0
}

test_sec6_all_temp_files_secure() {
  # Check that all temp file creation in mac-cleanup.sh uses create_secure_temp_file
  local secure_count=0
  if grep -q 'create_secure_temp_file' "$SCRIPT_DIR/mac-cleanup.sh" 2>/dev/null; then
    secure_count=$(grep -c 'create_secure_temp_file' "$SCRIPT_DIR/mac-cleanup.sh" 2>/dev/null)
  fi

  if [[ $secure_count -lt 4 ]]; then
    print_info "Expected at least 4 uses of create_secure_temp_file, found: $secure_count"
    return 1
  fi

  print_info "Found $secure_count uses of create_secure_temp_file"
  return 0
}

test_sec6_race_condition_prevention() {
  # Test that multiple processes can't predict/hijack temp files
  # Create 10 temp files in parallel and verify all are unique
  local pids=()
  local temp_files=()
  local result_file=$(mktemp -t "race-test.XXXXXXXXXX")

  for i in {1..10}; do
    (
      temp=$(create_secure_temp_file "race-test" 2>/dev/null || echo "")
      if [[ -n "$temp" ]]; then
        echo "$temp" >> "$result_file"
        rm -f "$temp"
      fi
    ) &
    pids+=($!)
  done

  # Wait for all processes
  for pid in "${pids[@]}"; do
    wait $pid 2>/dev/null || true
  done

  # Check that all temp files are unique
  local total_lines=$(wc -l < "$result_file" | tr -d ' ')
  local unique_lines=$(sort "$result_file" | uniq | wc -l | tr -d ' ')

  rm -f "$result_file"

  if [[ $total_lines -ne $unique_lines ]]; then
    print_info "Found duplicate temp file names (race condition)"
    print_info "Total: $total_lines, Unique: $unique_lines"
    return 1
  fi

  if [[ $unique_lines -ne 10 ]]; then
    print_info "Expected 10 unique temp files, got: $unique_lines"
    return 1
  fi

  print_info "All 10 parallel temp files were unique (no race condition)"
  return 0
}

###############################################################################
# Run all tests
###############################################################################

echo ""
echo "======================================================================"
echo "SEC-6 & SEC-8 Security Test Suite"
echo "======================================================================"
echo ""

echo "Testing SEC-8: Strict Mode in Main Script"
echo "----------------------------------------------------------------------"
run_test "SEC-8.1: Strict mode enabled on line 2" test_sec8_strict_mode_enabled
run_test "SEC-8.2: Undefined variable causes exit" test_sec8_undefined_variable_fails
run_test "SEC-8.3: Pipeline failure detected" test_sec8_pipeline_failure_detected
echo ""

echo "Testing SEC-6: Secure Temporary File Creation"
echo "----------------------------------------------------------------------"
run_test "SEC-6.1: create_secure_temp_file function exists" test_sec6_create_secure_temp_file_exists
run_test "SEC-6.2: Temp file created with correct permissions" test_sec6_temp_file_creation
run_test "SEC-6.3: Temp file names are unpredictable" test_sec6_temp_file_unpredictable
run_test "SEC-6.4: No insecure patterns in main script" test_sec6_no_insecure_patterns
run_test "SEC-6.5: All temp files use secure creation" test_sec6_all_temp_files_secure
run_test "SEC-6.6: Race condition prevention" test_sec6_race_condition_prevention
echo ""

echo "======================================================================"
echo "Test Summary"
echo "======================================================================"
echo "Tests run:    $TESTS_RUN"
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
  print_pass "All tests passed!"
  exit 0
else
  print_fail "$TESTS_FAILED test(s) failed"
  exit 1
fi
