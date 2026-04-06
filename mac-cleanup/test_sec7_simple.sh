#!/bin/zsh
#
# Simplified SEC-7 test - Tests the actual behavior of path validation
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Load main script environment (includes all libraries)
export MC_DRY_RUN=true  # Don't actually do cleanup
export MC_QUIET_MODE=true

# Source the main script's library loader
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/constants.sh"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/validation.sh"

# Initialize logging
MC_LOG_FILE="/tmp/mac-cleanup-sec7-test-$$.log"

echo "SEC-7: Testing Path Validation"
echo "==============================="
echo ""

PASSED=0
FAILED=0

# Test function
test_path() {
  local desc="$1"
  local path="$2"
  local should_pass="$3"  # "pass" or "fail"

  # Capture both stdout and exit code
  local result
  local exit_code
  result=$(validate_and_canonicalize_path "$path" "cleanup" 2>&1)
  exit_code=$?

  if [[ "$should_pass" == "pass" ]]; then
    # For pass tests, check exit code is 0
    if [[ $exit_code -eq 0 ]]; then
      echo "✓ PASS: $desc"
      PASSED=$((PASSED + 1))
    else
      echo "✗ FAIL: $desc (expected to pass but failed with exit code $exit_code)"
      FAILED=$((FAILED + 1))
    fi
  else
    # For fail tests, check exit code is non-zero
    if [[ $exit_code -ne 0 ]]; then
      echo "✓ PASS: $desc (correctly blocked)"
      PASSED=$((PASSED + 1))
    else
      echo "✗ FAIL: $desc (expected to fail but passed with exit code $exit_code)"
      FAILED=$((FAILED + 1))
    fi
  fi
}

echo "Testing attack vectors (should FAIL):"
test_path "Block ../../../../etc/passwd" "../../../../etc/passwd" "fail"
test_path "Block /usr/bin/sudo" "/usr/bin/sudo" "fail"
test_path "Block /System/Library" "/System/Library/Caches/test" "fail"
test_path "Block /etc/hosts" "/etc/hosts" "fail"

echo ""
echo "Testing valid paths (should PASS):"
mkdir -p "$HOME/Library/Caches/test-sec7" 2>/dev/null
mkdir -p "$HOME/Library/Logs/test-sec7" 2>/dev/null
mkdir -p "/tmp/test-sec7-$$" 2>/dev/null
test_path "Allow \$HOME/Library/Caches" "$HOME/Library/Caches/test-sec7" "pass"
test_path "Allow \$HOME/Library/Logs" "$HOME/Library/Logs/test-sec7" "pass"
test_path "Allow /tmp" "/tmp/test-sec7-$$" "pass"

# Cleanup
rm -rf "/tmp/test-sec7-$$" 2>/dev/null || true

# Cleanup
rm -rf "$HOME/Library/Caches/test-sec7" 2>/dev/null || true
rm -rf "$HOME/Library/Logs/test-sec7" 2>/dev/null || true
rm -f "$MC_LOG_FILE" 2>/dev/null || true

echo ""
echo "==============================="
echo "Results: $PASSED passed, $FAILED failed"

if [[ $FAILED -eq 0 ]]; then
  echo "✓ ALL TESTS PASSED"
  exit 0
else
  echo "✗ SOME TESTS FAILED"
  exit 1
fi
