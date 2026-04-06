#!/bin/zsh
# Consolidated Security Test Runner
# Runs all Phase 1 security fixes validation tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo "Phase 1: Security Fixes Validation"
echo "========================================"
echo ""

TOTAL=0
PASSED=0
FAILED=0

run_test() {
  local test_name="$1"
  local test_file="$2"

  echo "Running: $test_name"
  echo "----------------------------------------"

  if [[ ! -f "$test_file" ]]; then
    echo "⊘ SKIP: Test file not found: $test_file"
    echo ""
    return
  fi

  TOTAL=$((TOTAL + 1))

  if zsh "$test_file" 2>&1; then
    echo "✓ PASS: $test_name"
    PASSED=$((PASSED + 1))
  else
    echo "✗ FAIL: $test_name"
    FAILED=$((FAILED + 1))
  fi

  echo ""
}

# Run all security tests
run_test "SEC-1: Command Injection" "test_security_simple.sh"
run_test "SEC-6/SEC-8: Temp Files + Strict Mode" "test-sec6-sec8.sh"
run_test "SEC-7: Path Traversal" "test_security_path_traversal.sh"
run_test "SEC-9: Backup Permissions" "test_security_permissions.sh"
run_test "SEC-10: Input Validation" "test_security_input_validation.sh"

echo "========================================"
echo "Summary"
echo "========================================"
echo "Total tests:  $TOTAL"
echo "Passed:       $PASSED"
echo "Failed:       $FAILED"
echo ""

if [[ $FAILED -eq 0 ]]; then
  echo "✓ All security tests passed!"
  exit 0
else
  echo "✗ Some tests failed. Review output above."
  exit 1
fi
