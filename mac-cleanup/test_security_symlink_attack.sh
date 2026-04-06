#!/usr/bin/env zsh
#
# SEC-5: Test suite for symlink attack prevention in safe_clean_dir
# Tests that symlinks are removed without following them to their targets
#

set -euo pipefail
setopt NULL_GLOB 2>/dev/null || true

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Get script directory (works in both Bash and Zsh)
if [[ -n "${ZSH_VERSION:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Source required libraries in correct order (same as main script)
source "$SCRIPT_DIR/lib/constants.sh"
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/admin.sh"
source "$SCRIPT_DIR/lib/validation.sh"
source "$SCRIPT_DIR/lib/error_handler.sh"

# Mock backup function to always succeed (for testing)
backup() { return 0; }

# Override settings for testing
MC_DRY_RUN=false
MC_LOG_LEVEL=INFO

# Temporary test directory
TEST_BASE_DIR="/tmp/mac-cleanup-sec5-test-$$"

# Cleanup function
cleanup() {
  if [[ -d "$TEST_BASE_DIR" ]]; then
    # Clean up test directory
    find "$TEST_BASE_DIR" -mindepth 1 -delete 2>/dev/null || true
    rmdir "$TEST_BASE_DIR" 2>/dev/null || true
  fi
}

trap cleanup EXIT

# Print functions
print_test_header() {
  echo ""
  echo -e "${YELLOW}=== $1 ===${NC}"
}

print_pass() {
  echo -e "${GREEN}✓ PASS:${NC} $1"
  ((TESTS_PASSED++))
}

print_fail() {
  echo -e "${RED}✗ FAIL:${NC} $1"
  ((TESTS_FAILED++))
}

# Test helper function
run_test() {
  local test_name="$1"
  local test_function="$2"

  ((TESTS_RUN++))
  print_test_header "Test $TESTS_RUN: $test_name"

  if $test_function; then
    print_pass "$test_name"
    return 0
  else
    print_fail "$test_name"
    return 1
  fi
}

# Setup test environment
setup_test_env() {
  mkdir -p "$TEST_BASE_DIR"
}

# Test 1: Basic symlink attack prevention
test_basic_symlink_attack() {
  local cache_dir="$TEST_BASE_DIR/cache-basic"
  local sensitive_file="$TEST_BASE_DIR/sensitive-basic.txt"

  echo "  Creating test files..."
  mkdir -p "$cache_dir" || { echo "Failed to create cache dir"; return 1; }
  echo "SENSITIVE DATA" > "$sensitive_file" || { echo "Failed to create sensitive file"; return 1; }

  # Attacker creates malicious symlink
  echo "  Creating malicious symlink..."
  ln -s "$sensitive_file" "$cache_dir/malicious_link" || { echo "Failed to create symlink"; return 1; }

  # Verify symlink exists and points to sensitive file
  if [[ ! -L "$cache_dir/malicious_link" ]]; then
    echo "  Setup failed: Symlink not created"
    return 1
  fi

  # Call safe_clean_dir
  echo "  Running safe_clean_dir..."
  MC_DRY_RUN=false
  safe_clean_dir "$cache_dir" "test-basic" 2>&1 || { echo "safe_clean_dir failed"; return 1; }

  # Verify: Symlink removed, but target file still exists
  echo "  Verifying results..."
  if [[ -L "$cache_dir/malicious_link" ]]; then
    echo "  FAIL: Symlink was not removed"
    return 1
  fi

  if [[ ! -f "$sensitive_file" ]]; then
    echo "  FAIL: Target file was deleted (SYMLINK ATTACK SUCCEEDED)"
    return 1
  fi

  # Verify content unchanged
  local content=$(cat "$sensitive_file")
  if [[ "$content" != "SENSITIVE DATA" ]]; then
    echo "  FAIL: Target file content was modified"
    return 1
  fi

  echo "  SUCCESS: Symlink removed, target file preserved"
  return 0
}

# Test 2: Multiple symlinks to different targets
test_multiple_symlinks() {
  local cache_dir="$TEST_BASE_DIR/cache-multiple"
  local sensitive_file1="$TEST_BASE_DIR/sensitive-1.txt"
  local sensitive_file2="$TEST_BASE_DIR/sensitive-2.txt"

  mkdir -p "$cache_dir"
  echo "SENSITIVE DATA 1" > "$sensitive_file1"
  echo "SENSITIVE DATA 2" > "$sensitive_file2"

  # Create multiple malicious symlinks
  ln -s "$sensitive_file1" "$cache_dir/link1"
  ln -s "$sensitive_file2" "$cache_dir/link2"

  # Call safe_clean_dir
  MC_DRY_RUN=false
  safe_clean_dir "$cache_dir" "test-multiple"

  # Verify: All symlinks removed, all targets preserved
  if [[ -L "$cache_dir/link1" ]] || [[ -L "$cache_dir/link2" ]]; then
    echo "FAIL: Symlinks were not removed"
    return 1
  fi

  if [[ ! -f "$sensitive_file1" ]] || [[ ! -f "$sensitive_file2" ]]; then
    echo "FAIL: Target files were deleted (SYMLINK ATTACK SUCCEEDED)"
    return 1
  fi

  echo "SUCCESS: All symlinks removed, all targets preserved"
  return 0
}

# Test 3: Symlink to directory
test_symlink_to_directory() {
  local cache_dir="$TEST_BASE_DIR/cache-dir"
  local sensitive_dir="$TEST_BASE_DIR/sensitive-dir"
  local sensitive_file="$sensitive_dir/important.txt"

  mkdir -p "$cache_dir"
  mkdir -p "$sensitive_dir"
  echo "IMPORTANT DATA" > "$sensitive_file"

  # Create symlink to directory
  ln -s "$sensitive_dir" "$cache_dir/dir_link"

  # Call safe_clean_dir
  MC_DRY_RUN=false
  safe_clean_dir "$cache_dir" "test-dir"

  # Verify: Symlink removed, target directory and file preserved
  if [[ -L "$cache_dir/dir_link" ]]; then
    echo "FAIL: Symlink was not removed"
    return 1
  fi

  if [[ ! -d "$sensitive_dir" ]] || [[ ! -f "$sensitive_file" ]]; then
    echo "FAIL: Target directory or file was deleted (SYMLINK ATTACK SUCCEEDED)"
    return 1
  fi

  echo "SUCCESS: Directory symlink removed, target preserved"
  return 0
}

# Test 4: Hidden symlink (dotfile)
test_hidden_symlink() {
  local cache_dir="$TEST_BASE_DIR/cache-hidden"
  local sensitive_file="$TEST_BASE_DIR/.sensitive-hidden"

  mkdir -p "$cache_dir"
  echo "HIDDEN SENSITIVE DATA" > "$sensitive_file"

  # Create hidden symlink
  ln -s "$sensitive_file" "$cache_dir/.hidden_link"

  # Call safe_clean_dir
  MC_DRY_RUN=false
  safe_clean_dir "$cache_dir" "test-hidden"

  # Verify: Hidden symlink removed, target preserved
  if [[ -L "$cache_dir/.hidden_link" ]]; then
    echo "FAIL: Hidden symlink was not removed"
    return 1
  fi

  if [[ ! -f "$sensitive_file" ]]; then
    echo "FAIL: Target file was deleted (SYMLINK ATTACK SUCCEEDED)"
    return 1
  fi

  echo "SUCCESS: Hidden symlink removed, target preserved"
  return 0
}

# Test 5: Symlink with regular files mixed
test_mixed_content() {
  local cache_dir="$TEST_BASE_DIR/cache-mixed"
  local sensitive_file="$TEST_BASE_DIR/sensitive-mixed.txt"
  local cache_file="$cache_dir/cache.txt"

  mkdir -p "$cache_dir"
  echo "SENSITIVE DATA" > "$sensitive_file"
  echo "CACHE DATA" > "$cache_file"

  # Create symlink alongside regular file
  ln -s "$sensitive_file" "$cache_dir/link"

  # Call safe_clean_dir
  MC_DRY_RUN=false
  safe_clean_dir "$cache_dir" "test-mixed"

  # Verify: Both symlink and cache file removed, target preserved
  if [[ -L "$cache_dir/link" ]]; then
    echo "FAIL: Symlink was not removed"
    return 1
  fi

  if [[ -f "$cache_file" ]]; then
    echo "FAIL: Cache file was not removed"
    return 1
  fi

  if [[ ! -f "$sensitive_file" ]]; then
    echo "FAIL: Target file was deleted (SYMLINK ATTACK SUCCEEDED)"
    return 1
  fi

  echo "SUCCESS: Symlink and cache file removed, target preserved"
  return 0
}

# Test 6: Symlink to system file
test_symlink_to_system_file() {
  local cache_dir="$TEST_BASE_DIR/cache-system"
  local system_file="/etc/hosts"

  mkdir -p "$cache_dir"

  # Create symlink to critical system file
  ln -s "$system_file" "$cache_dir/hosts_link"

  # Backup system file checksum
  local checksum_before=$(shasum "$system_file" | awk '{print $1}')

  # Call safe_clean_dir
  MC_DRY_RUN=false
  safe_clean_dir "$cache_dir" "test-system"

  # Verify: Symlink removed, system file unchanged
  if [[ -L "$cache_dir/hosts_link" ]]; then
    echo "FAIL: Symlink was not removed"
    return 1
  fi

  if [[ ! -f "$system_file" ]]; then
    echo "FAIL: System file was deleted (CRITICAL SYMLINK ATTACK)"
    return 1
  fi

  local checksum_after=$(shasum "$system_file" | awk '{print $1}')
  if [[ "$checksum_before" != "$checksum_after" ]]; then
    echo "FAIL: System file was modified"
    return 1
  fi

  echo "SUCCESS: Symlink removed, critical system file preserved"
  return 0
}

# Test 7: Nested directory with symlink
test_nested_symlink() {
  local cache_dir="$TEST_BASE_DIR/cache-nested"
  local nested_dir="$cache_dir/subdir"
  local sensitive_file="$TEST_BASE_DIR/sensitive-nested.txt"

  mkdir -p "$nested_dir"
  echo "NESTED SENSITIVE DATA" > "$sensitive_file"

  # Create symlink in subdirectory
  ln -s "$sensitive_file" "$nested_dir/nested_link"

  # Call safe_clean_dir on parent directory
  MC_DRY_RUN=false
  safe_clean_dir "$cache_dir" "test-nested"

  # Verify: Entire nested structure removed, target preserved
  if [[ -d "$nested_dir" ]] || [[ -L "$nested_dir/nested_link" ]]; then
    echo "FAIL: Nested directory or symlink was not removed"
    return 1
  fi

  if [[ ! -f "$sensitive_file" ]]; then
    echo "FAIL: Target file was deleted (SYMLINK ATTACK SUCCEEDED)"
    return 1
  fi

  echo "SUCCESS: Nested directory with symlink removed, target preserved"
  return 0
}

# Test 8: Symlink chain (symlink to symlink)
test_symlink_chain() {
  local cache_dir="$TEST_BASE_DIR/cache-chain"
  local sensitive_file="$TEST_BASE_DIR/sensitive-chain.txt"
  local intermediate_link="$TEST_BASE_DIR/intermediate-link"

  mkdir -p "$cache_dir"
  echo "CHAIN SENSITIVE DATA" > "$sensitive_file"

  # Create symlink chain
  ln -s "$sensitive_file" "$intermediate_link"
  ln -s "$intermediate_link" "$cache_dir/chain_link"

  # Call safe_clean_dir
  MC_DRY_RUN=false
  safe_clean_dir "$cache_dir" "test-chain"

  # Verify: First link removed, intermediate and target preserved
  if [[ -L "$cache_dir/chain_link" ]]; then
    echo "FAIL: First symlink was not removed"
    return 1
  fi

  if [[ ! -L "$intermediate_link" ]] || [[ ! -f "$sensitive_file" ]]; then
    echo "FAIL: Intermediate link or target was deleted (SYMLINK ATTACK)"
    return 1
  fi

  # Cleanup intermediate link manually
  rm -f "$intermediate_link"

  echo "SUCCESS: First symlink removed, chain not followed"
  return 0
}

# Main execution
main() {
  echo "========================================"
  echo "SEC-5: Symlink Attack Prevention Tests"
  echo "========================================"

  setup_test_env

  # Run all tests
  run_test "Basic symlink attack prevention" test_basic_symlink_attack
  run_test "Multiple symlinks to different targets" test_multiple_symlinks
  run_test "Symlink to directory" test_symlink_to_directory
  run_test "Hidden symlink (dotfile)" test_hidden_symlink
  run_test "Symlink with regular files mixed" test_mixed_content
  run_test "Symlink to system file" test_symlink_to_system_file
  run_test "Nested directory with symlink" test_nested_symlink
  run_test "Symlink chain (symlink to symlink)" test_symlink_chain

  # Print summary
  echo ""
  echo "========================================"
  echo "Test Summary"
  echo "========================================"
  echo "Tests run:    $TESTS_RUN"
  echo -e "${GREEN}Tests passed: $TESTS_PASSED${NC}"
  if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}Tests failed: $TESTS_FAILED${NC}"
  else
    echo "Tests failed: $TESTS_FAILED"
  fi
  echo "========================================"

  if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
  fi

  exit 0
}

main "$@"
