#!/usr/bin/env zsh
#
# SEC-5: Comprehensive symlink attack prevention test suite
# Tests that safe_clean_dir removes symlinks without following them
#

# Don't use set -e because tests return non-zero on failure
setopt NULL_GLOB 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"

# Source libraries
source "$SCRIPT_DIR/lib/constants.sh"
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/admin.sh"
source "$SCRIPT_DIR/lib/validation.sh"
source "$SCRIPT_DIR/lib/error_handler.sh"

# Disable pipefail to allow tests to run fully
set +e
setopt NO_ERR_EXIT 2>/dev/null || true

# Mock backup
backup() { return 0; }

MC_DRY_RUN=false

echo "========================================"
echo "SEC-5: Symlink Attack Prevention Tests"
echo "========================================"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
  local test_name="$1"
  local test_func="$2"

  echo "Test: $test_name"
  # Run in subshell to avoid set -e issues
  if ( $test_func ); then
    echo "✓ PASS"
    ((TESTS_PASSED++))
  else
    echo "✗ FAIL"
    ((TESTS_FAILED++))
  fi
  echo ""
}

# Test 1: Basic symlink attack
test_basic_symlink() {
  local test_dir="/tmp/sec5-test1-$$"
  local sensitive_file="/tmp/sec5-sensitive1-$$.txt"

  mkdir -p "$test_dir"
  echo "SENSITIVE DATA" > "$sensitive_file"
  ln -s "$sensitive_file" "$test_dir/link"

  safe_clean_dir "$test_dir" "test1" >/dev/null 2>&1

  local result=0
  if [[ -L "$test_dir/link" ]]; then
    echo "  ERROR: Symlink was not removed"
    result=1
  fi

  if [[ ! -f "$sensitive_file" ]]; then
    echo "  ERROR: Target file was deleted (SYMLINK ATTACK SUCCEEDED)"
    result=1
  elif [[ "$(cat "$sensitive_file")" != "SENSITIVE DATA" ]]; then
    echo "  ERROR: Target file content was modified"
    result=1
  fi

  rm -rf "$test_dir" "$sensitive_file"
  return $result
}

# Test 2: Multiple symlinks
test_multiple_symlinks() {
  local test_dir="/tmp/sec5-test2-$$"
  local file1="/tmp/sec5-file1-$$.txt"
  local file2="/tmp/sec5-file2-$$.txt"

  mkdir -p "$test_dir"
  echo "FILE1" > "$file1"
  echo "FILE2" > "$file2"
  ln -s "$file1" "$test_dir/link1"
  ln -s "$file2" "$test_dir/link2"

  safe_clean_dir "$test_dir" "test2" >/dev/null 2>&1

  local result=0
  if [[ -L "$test_dir/link1" ]] || [[ -L "$test_dir/link2" ]]; then
    echo "  ERROR: Symlinks were not removed"
    result=1
  fi

  if [[ ! -f "$file1" ]] || [[ ! -f "$file2" ]]; then
    echo "  ERROR: Target files were deleted (SYMLINK ATTACK SUCCEEDED)"
    result=1
  fi

  rm -rf "$test_dir" "$file1" "$file2"
  return $result
}

# Test 3: Symlink to directory
test_symlink_to_directory() {
  local test_dir="/tmp/sec5-test3-$$"
  local sensitive_dir="/tmp/sec5-sensitivedir-$$"
  local sensitive_file="$sensitive_dir/important.txt"

  mkdir -p "$test_dir"
  mkdir -p "$sensitive_dir"
  echo "IMPORTANT" > "$sensitive_file"
  ln -s "$sensitive_dir" "$test_dir/dir_link"

  safe_clean_dir "$test_dir" "test3" >/dev/null 2>&1

  local result=0
  if [[ -L "$test_dir/dir_link" ]]; then
    echo "  ERROR: Directory symlink was not removed"
    result=1
  fi

  if [[ ! -d "$sensitive_dir" ]] || [[ ! -f "$sensitive_file" ]]; then
    echo "  ERROR: Target directory or file was deleted (SYMLINK ATTACK SUCCEEDED)"
    result=1
  fi

  rm -rf "$test_dir" "$sensitive_dir"
  return $result
}

# Test 4: Hidden symlink (dotfile)
test_hidden_symlink() {
  local test_dir="/tmp/sec5-test4-$$"
  local sensitive_file="/tmp/.sec5-hidden-$$.txt"

  mkdir -p "$test_dir"
  echo "HIDDEN DATA" > "$sensitive_file"
  ln -s "$sensitive_file" "$test_dir/.hidden_link"

  safe_clean_dir "$test_dir" "test4" >/dev/null 2>&1

  local result=0
  if [[ -L "$test_dir/.hidden_link" ]]; then
    echo "  ERROR: Hidden symlink was not removed"
    result=1
  fi

  if [[ ! -f "$sensitive_file" ]]; then
    echo "  ERROR: Hidden target file was deleted (SYMLINK ATTACK SUCCEEDED)"
    result=1
  fi

  rm -rf "$test_dir" "$sensitive_file"
  return $result
}

# Test 5: Mixed content (symlink + regular files)
test_mixed_content() {
  local test_dir="/tmp/sec5-test5-$$"
  local sensitive_file="/tmp/sec5-sensitive5-$$.txt"
  local cache_file="$test_dir/cache.txt"

  mkdir -p "$test_dir"
  echo "SENSITIVE" > "$sensitive_file"
  echo "CACHE" > "$cache_file"
  ln -s "$sensitive_file" "$test_dir/link"

  safe_clean_dir "$test_dir" "test5" >/dev/null 2>&1

  local result=0
  if [[ -L "$test_dir/link" ]]; then
    echo "  ERROR: Symlink was not removed"
    result=1
  fi

  if [[ -f "$cache_file" ]]; then
    echo "  ERROR: Cache file was not removed"
    result=1
  fi

  if [[ ! -f "$sensitive_file" ]]; then
    echo "  ERROR: Sensitive target was deleted (SYMLINK ATTACK SUCCEEDED)"
    result=1
  fi

  rm -rf "$test_dir" "$sensitive_file"
  return $result
}

# Test 6: Symlink to system file
test_symlink_to_system_file() {
  local test_dir="/tmp/sec5-test6-$$"
  local system_file="/etc/hosts"

  mkdir -p "$test_dir"
  ln -s "$system_file" "$test_dir/hosts_link"

  local checksum_before=$(shasum "$system_file" | awk '{print $1}')

  safe_clean_dir "$test_dir" "test6" >/dev/null 2>&1

  local result=0
  if [[ -L "$test_dir/hosts_link" ]]; then
    echo "  ERROR: System file symlink was not removed"
    result=1
  fi

  if [[ ! -f "$system_file" ]]; then
    echo "  ERROR: System file was deleted (CRITICAL SYMLINK ATTACK)"
    result=1
  fi

  local checksum_after=$(shasum "$system_file" | awk '{print $1}')
  if [[ "$checksum_before" != "$checksum_after" ]]; then
    echo "  ERROR: System file was modified"
    result=1
  fi

  rm -rf "$test_dir"
  return $result
}

# Test 7: Nested directory with symlink (clean twice - directory then parent)
test_nested_symlink() {
  local test_dir="/tmp/sec5-test7-$$"
  local nested_dir="$test_dir/subdir"
  local sensitive_file="/tmp/sec5-nested-$$.txt"

  mkdir -p "$nested_dir"
  echo "NESTED DATA" > "$sensitive_file"
  ln -s "$sensitive_file" "$nested_dir/nested_link"

  # Clean the nested directory first (this is how it would be used in practice)
  safe_clean_dir "$nested_dir" "test7-nested" >/dev/null 2>&1

  local result=0
  # Check that symlink in nested dir was removed
  if [[ -L "$nested_dir/nested_link" ]]; then
    echo "  ERROR: Nested symlink was not removed"
    result=1
  fi

  # Check that target file still exists (key security check)
  if [[ ! -f "$sensitive_file" ]]; then
    echo "  ERROR: Nested target was deleted (SYMLINK ATTACK SUCCEEDED)"
    result=1
  fi

  rm -rf "$test_dir" "$sensitive_file"
  return $result
}

# Test 8: Symlink chain
test_symlink_chain() {
  local test_dir="/tmp/sec5-test8-$$"
  local sensitive_file="/tmp/sec5-chain-$$.txt"
  local intermediate_link="/tmp/sec5-intermediate-$$"

  mkdir -p "$test_dir"
  echo "CHAIN DATA" > "$sensitive_file"
  ln -s "$sensitive_file" "$intermediate_link"
  ln -s "$intermediate_link" "$test_dir/chain_link"

  safe_clean_dir "$test_dir" "test8" >/dev/null 2>&1

  local result=0
  if [[ -L "$test_dir/chain_link" ]]; then
    echo "  ERROR: Chain symlink was not removed"
    result=1
  fi

  if [[ ! -L "$intermediate_link" ]]; then
    echo "  ERROR: Intermediate link was deleted (chain was followed)"
    result=1
  fi

  if [[ ! -f "$sensitive_file" ]]; then
    echo "  ERROR: Chain target was deleted (SYMLINK ATTACK SUCCEEDED)"
    result=1
  fi

  rm -rf "$test_dir" "$intermediate_link" "$sensitive_file"
  return $result
}

# Run all tests
run_test "Basic symlink attack prevention" test_basic_symlink
run_test "Multiple symlinks to different targets" test_multiple_symlinks
run_test "Symlink to directory" test_symlink_to_directory
run_test "Hidden symlink (dotfile)" test_hidden_symlink
run_test "Mixed content (symlink + regular files)" test_mixed_content
run_test "Symlink to system file (/etc/hosts)" test_symlink_to_system_file
run_test "Nested directory with symlink" test_nested_symlink
run_test "Symlink chain (symlink to symlink)" test_symlink_chain

# Print summary
echo "========================================"
echo "Test Summary:"
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo "========================================"

if [[ $TESTS_FAILED -gt 0 ]]; then
  exit 1
else
  echo "All tests passed! SEC-5 fix verified."
  exit 0
fi
