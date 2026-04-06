#!/bin/zsh
#
# test_security_permissions.sh - Test SEC-9 backup directory permissions
#
# Tests that backup directories are created with restrictive permissions (700)

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
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/backup/storage.sh"

# Test directory prefix
TEST_PREFIX="/tmp/mac-cleanup-sec9-test-$$"

echo "========================================"
echo "SEC-9: Backup Directory Permissions"
echo "========================================"
echo ""

# Test 1: _create_backup_dir creates directory with 700 permissions
print_test "Test 1: _create_backup_dir creates directory with 700 permissions"
TESTS_RUN=$((TESTS_RUN + 1))

MC_BACKUP_DIR="${TEST_PREFIX}/test1"
_create_backup_dir

if [[ ! -d "$MC_BACKUP_DIR" ]]; then
  print_fail "Backup directory was not created: $MC_BACKUP_DIR"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  perms=$(stat -f "%Lp" "$MC_BACKUP_DIR")
  if [[ "$perms" == "700" ]]; then
    print_pass "Directory created with correct permissions: 700"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    print_fail "Directory has incorrect permissions: $perms (expected 700)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
fi

# Test 2: _create_backup_dir verifies ownership
print_test "Test 2: _create_backup_dir verifies ownership"
TESTS_RUN=$((TESTS_RUN + 1))

owner=$(stat -f "%Su" "$MC_BACKUP_DIR")
if [[ "$owner" == "$USER" ]]; then
  print_pass "Directory owned by correct user: $USER"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  print_fail "Directory owned by wrong user: $owner (expected $USER)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 3: _create_backup_dir fixes insecure permissions on existing directory
print_test "Test 3: _create_backup_dir fixes insecure permissions on existing directory"
TESTS_RUN=$((TESTS_RUN + 1))

MC_BACKUP_DIR="${TEST_PREFIX}/test2"
mkdir -p "$MC_BACKUP_DIR"
chmod 755 "$MC_BACKUP_DIR"  # Insecure permissions

_create_backup_dir 2>/dev/null

perms=$(stat -f "%Lp" "$MC_BACKUP_DIR")
if [[ "$perms" == "700" ]]; then
  print_pass "Insecure permissions fixed: 755 -> 700"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  print_fail "Failed to fix permissions: $perms (expected 700)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 4: mc_storage_ensure_dir creates directory with 700 permissions
print_test "Test 4: mc_storage_ensure_dir creates directory with 700 permissions"
TESTS_RUN=$((TESTS_RUN + 1))

test_dir="${TEST_PREFIX}/test3"
result=$(mc_storage_ensure_dir "$test_dir" 2>/dev/null)

if [[ -z "$result" ]]; then
  print_fail "mc_storage_ensure_dir failed to create directory"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  perms=$(stat -f "%Lp" "$test_dir")
  if [[ "$perms" == "700" ]]; then
    print_pass "Directory created with correct permissions: 700"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    print_fail "Directory has incorrect permissions: $perms (expected 700)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
fi

# Test 5: mc_storage_ensure_dir verifies ownership
print_test "Test 5: mc_storage_ensure_dir verifies ownership"
TESTS_RUN=$((TESTS_RUN + 1))

owner=$(stat -f "%Su" "$test_dir")
if [[ "$owner" == "$USER" ]]; then
  print_pass "Directory owned by correct user: $USER"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  print_fail "Directory owned by wrong user: $owner (expected $USER)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 6: mc_storage_ensure_dir fixes insecure permissions on existing directory
print_test "Test 6: mc_storage_ensure_dir fixes insecure permissions on existing directory"
TESTS_RUN=$((TESTS_RUN + 1))

test_dir="${TEST_PREFIX}/test4"
mkdir -p "$test_dir"
chmod 777 "$test_dir"  # Very insecure permissions

result=$(mc_storage_ensure_dir "$test_dir" 2>/dev/null)

perms=$(stat -f "%Lp" "$test_dir")
if [[ "$perms" == "700" ]]; then
  print_pass "Insecure permissions fixed: 777 -> 700"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  print_fail "Failed to fix permissions: $perms (expected 700)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 7: Verify umask is restored after directory creation
print_test "Test 7: Verify umask is restored after directory creation"
TESTS_RUN=$((TESTS_RUN + 1))

original_umask=$(umask)
test_dir="${TEST_PREFIX}/test5"
mc_storage_ensure_dir "$test_dir" >/dev/null 2>&1
current_umask=$(umask)

if [[ "$original_umask" == "$current_umask" ]]; then
  print_pass "umask correctly restored: $current_umask"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  print_fail "umask not restored: was $original_umask, now $current_umask"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 8: Fallback directory also gets 700 permissions
print_test "Test 8: Fallback directory gets 700 permissions"
TESTS_RUN=$((TESTS_RUN + 1))

# Create a directory we can't write to
readonly_dir="${TEST_PREFIX}/readonly"
mkdir -p "$readonly_dir"
chmod 555 "$readonly_dir"

# Try to create backup dir inside readonly dir (should fail and use fallback)
MC_BACKUP_FALLBACK_DIR="${TEST_PREFIX}/fallback"
test_dir="${readonly_dir}/should-fail"
result=$(mc_storage_ensure_dir "$test_dir" 2>/dev/null)

if [[ -n "$result" ]]; then
  # Check if fallback was used
  if [[ "$result" == "${TEST_PREFIX}/fallback"* ]]; then
    perms=$(stat -f "%Lp" "$result")
    if [[ "$perms" == "700" ]]; then
      print_pass "Fallback directory created with correct permissions: 700"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    else
      print_fail "Fallback directory has incorrect permissions: $perms (expected 700)"
      TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
  else
    print_fail "Unexpected result directory: $result"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
else
  print_fail "mc_storage_ensure_dir failed completely (no fallback)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Cleanup
chmod 755 "$readonly_dir" 2>/dev/null || true
rm -rf "$TEST_PREFIX" 2>/dev/null || true

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
