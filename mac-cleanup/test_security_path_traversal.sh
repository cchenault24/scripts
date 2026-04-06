#!/bin/zsh
#
# test_security_path_traversal.sh - Test SEC-7 path validation and canonicalization
#
# Tests path traversal attack prevention with whitelist/blacklist approach

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
source "$SCRIPT_DIR/lib/validation.sh"
source "$SCRIPT_DIR/lib/utils.sh"

# Initialize globals needed by validation
MC_LOG_FILE="/tmp/mac-cleanup-test-$$.log"

# Test helper - expect failure
expect_failure() {
  local test_name="$1"
  local path="$2"
  local operation="${3:-cleanup}"

  TESTS_RUN=$((TESTS_RUN + 1))
  print_test "$test_name"

  if validate_and_canonicalize_path "$path" "$operation" >/dev/null 2>&1; then
    print_fail "Expected validation to FAIL but it PASSED for: $path"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  else
    print_pass "Correctly blocked: $path"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
  fi
}

# Test helper - expect success
expect_success() {
  local test_name="$1"
  local path="$2"
  local operation="${3:-cleanup}"

  TESTS_RUN=$((TESTS_RUN + 1))
  print_test "$test_name"

  local result=$(validate_and_canonicalize_path "$path" "$operation" 2>/dev/null)
  if [[ -z "$result" ]]; then
    print_fail "Expected validation to PASS but it FAILED for: $path"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  else
    print_pass "Correctly allowed: $path -> $result"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
  fi
}

echo "========================================"
echo "SEC-7: Path Traversal Attack Prevention"
echo "========================================"
echo ""

# Create test directories for valid paths
mkdir -p "$HOME/Library/Caches/test-cleanup"
mkdir -p "$HOME/Library/Logs/test-cleanup"
mkdir -p "$HOME/.cache/test-cleanup"
mkdir -p "$HOME/Downloads/test-cleanup"
mkdir -p "$HOME/.Trash/test-cleanup"

print_info "Testing path traversal attacks (should all FAIL)..."
echo ""

# Test 1: Classic path traversal to /etc/passwd
expect_failure "Block path traversal to /etc/passwd" "../../../../etc/passwd"

# Test 2: Path traversal to system directory
expect_failure "Block path traversal to /System" "../../../System/Library"

# Test 3: Path traversal using absolute path to sensitive location
expect_failure "Block absolute path to /usr/bin" "/usr/bin/sudo"

# Test 4: Path traversal to /private
expect_failure "Block path to /private/etc" "/private/etc/hosts"

# Test 5: Symlink to system directory
expect_failure "Block symlink escape attempt" "$HOME/Library/../../../etc/passwd"

echo ""
print_info "Testing blacklist violations (should all FAIL)..."
echo ""

# Test 6: /System directory
expect_failure "Block /System directory" "/System/Library/Caches/test"

# Test 7: /usr directory
expect_failure "Block /usr directory" "/usr/local/bin/test"

# Test 8: /bin directory
expect_failure "Block /bin directory" "/bin/bash"

# Test 9: /sbin directory
expect_failure "Block /sbin directory" "/sbin/mount"

# Test 10: /etc directory
expect_failure "Block /etc directory" "/etc/hosts"

# Test 11: /var/db directory
expect_failure "Block /var/db directory" "/var/db/SystemPolicyConfiguration"

# Test 12: LaunchDaemons
expect_failure "Block LaunchDaemons" "/Library/LaunchDaemons/test.plist"

# Test 13: LaunchAgents
expect_failure "Block LaunchAgents" "/Library/LaunchAgents/test.plist"

echo ""
print_info "Testing valid paths (should all PASS)..."
echo ""

# Test 14: Valid user cache directory
expect_success "Allow user cache directory" "$HOME/Library/Caches/test-cleanup"

# Test 15: Valid user logs directory
expect_success "Allow user logs directory" "$HOME/Library/Logs/test-cleanup"

# Test 16: Valid .cache directory
expect_success "Allow .cache directory" "$HOME/.cache/test-cleanup"

# Test 17: Valid Downloads directory
expect_success "Allow Downloads directory" "$HOME/Downloads/test-cleanup"

# Test 18: Valid Trash directory
expect_success "Allow Trash directory" "$HOME/.Trash/test-cleanup"

# Test 19: Valid /tmp directory
expect_success "Allow /tmp directory" "/tmp/test-cleanup-$$"

# Test 20: Valid backup directory
expect_success "Allow backup directory" "$HOME/.mac-cleanup-backups/test"

# Test 21: Valid fallback backup directory
expect_success "Allow fallback backup directory" "/tmp/mac-cleanup-backups/test"

# Test 22: Valid Application Support cache
expect_success "Allow Application Support cache" "$HOME/Library/Application Support/Google/Chrome/Default/Cache/test"

echo ""
print_info "Testing edge cases..."
echo ""

# Test 23: Empty path
expect_failure "Block empty path" ""

# Test 24: Path with .. that stays in whitelist
mkdir -p "$HOME/Library/Caches/subdir/test"
expect_success "Allow path with .. that stays within whitelist" "$HOME/Library/Caches/subdir/../test"

# Test 25: Non-existent parent directory
expect_failure "Block path with non-existent parent" "/nonexistent/directory/test"

# Cleanup test directories
rm -rf "$HOME/Library/Caches/test-cleanup" 2>/dev/null || true
rm -rf "$HOME/Library/Logs/test-cleanup" 2>/dev/null || true
rm -rf "$HOME/.cache/test-cleanup" 2>/dev/null || true
rm -rf "$HOME/Downloads/test-cleanup" 2>/dev/null || true
rm -rf "$HOME/.Trash/test-cleanup" 2>/dev/null || true
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
