#!/bin/zsh
#
# test_security_simple.sh - Simple test for SEC-1 eval removal
#

echo "=== SEC-1: Command Injection Security Tests ==="
echo ""

# Test 1: Verify no eval commands in codebase (excluding comments)
echo "Test 1: Verify no eval commands in codebase"
eval_results=$(grep -rn "\beval\b" lib --include="*.sh" 2>/dev/null | grep -v "^\s*#" | grep -v ":[[:space:]]*#" || true)

if [[ -z "$eval_results" ]]; then
  echo "✓ PASS: No eval commands found in codebase (excluding comments)"
else
  echo "✗ FAIL: Found eval command(s) in codebase:"
  echo "$eval_results"
  exit 1
fi

# Test 2: Verify mc_execute_with_error_handling was removed
echo ""
echo "Test 2: Verify mc_execute_with_error_handling was removed"
if grep -q "^mc_execute_with_error_handling()" lib/error_handler.sh 2>/dev/null; then
  echo "✗ FAIL: mc_execute_with_error_handling function still exists"
  exit 1
else
  echo "✓ PASS: mc_execute_with_error_handling function has been removed"
fi

# Test 3: Verify core.sh glob qualifier test doesn't use eval
echo ""
echo "Test 3: Verify core.sh glob qualifier test doesn't use eval"
glob_test_lines=$(grep -A5 "Verify zsh-specific features" lib/core.sh | grep -v "^--$" || true)

if echo "$glob_test_lines" | grep -qv "^#" | grep -q "eval"; then
  echo "✗ FAIL: core.sh glob qualifier test still contains eval in non-comment line"
  echo "$glob_test_lines" | grep "eval"
  exit 1
else
  echo "✓ PASS: core.sh glob qualifier test no longer uses eval"
fi

# Test 4: Run shellcheck on error_handler.sh if available
echo ""
echo "Test 4: Run shellcheck on error_handler.sh"
if ! command -v shellcheck &>/dev/null; then
  echo "⊘ SKIP: shellcheck not installed"
else
  if shellcheck lib/error_handler.sh 2>&1 | grep -q "error:"; then
    echo "✗ FAIL: shellcheck found errors in error_handler.sh"
    shellcheck lib/error_handler.sh
    exit 1
  else
    echo "✓ PASS: shellcheck passed on error_handler.sh"
  fi
fi

# Test 5: Run shellcheck on core.sh if available
echo ""
echo "Test 5: Run shellcheck on core.sh"
if ! command -v shellcheck &>/dev/null; then
  echo "⊘ SKIP: shellcheck not installed"
else
  if shellcheck lib/core.sh 2>&1 | grep -q "error:"; then
    echo "✗ FAIL: shellcheck found errors in core.sh"
    shellcheck lib/core.sh
    exit 1
  else
    echo "✓ PASS: shellcheck passed on core.sh"
  fi
fi

echo ""
echo "=== All tests passed! ==="
