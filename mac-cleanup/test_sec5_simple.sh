#!/usr/bin/env zsh

# Simple test for SEC-5 symlink attack prevention

SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"

# Source libraries
source "$SCRIPT_DIR/lib/constants.sh"
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/admin.sh"
source "$SCRIPT_DIR/lib/validation.sh"
source "$SCRIPT_DIR/lib/error_handler.sh"

# Mock backup
backup() { return 0; }

MC_DRY_RUN=false

echo "SEC-5: Symlink Attack Prevention Test"
echo "======================================"

# Test 1: Basic symlink attack
test_dir="/tmp/sec5-test-$$"
sensitive_file="/tmp/sec5-sensitive-$$.txt"

mkdir -p "$test_dir"
echo "SENSITIVE DATA" > "$sensitive_file"
ln -s "$sensitive_file" "$test_dir/link"

echo ""
echo "Before cleanup:"
echo "- Symlink exists: $(test -L "$test_dir/link" && echo YES || echo NO)"
echo "- Target exists: $(test -f "$sensitive_file" && echo YES || echo NO)"

echo ""
echo "Running safe_clean_dir..."
safe_clean_dir "$test_dir" "test" >/dev/null 2>&1

echo ""
echo "After cleanup:"
echo "- Symlink exists: $(test -L "$test_dir/link" && echo YES || echo NO)"
echo "- Target exists: $(test -f "$sensitive_file" && echo YES || echo NO)"
echo "- Target content: $(cat "$sensitive_file" 2>/dev/null || echo MISSING)"

# Verify
if [[ -L "$test_dir/link" ]]; then
  echo ""
  echo "FAIL: Symlink was not removed"
  rm -rf "$test_dir" "$sensitive_file"
  exit 1
fi

if [[ ! -f "$sensitive_file" ]]; then
  echo ""
  echo "FAIL: Target file was deleted (SYMLINK ATTACK)"
  rm -rf "$test_dir" "$sensitive_file"
  exit 1
fi

echo ""
echo "PASS: Symlink removed, target preserved"

# Cleanup
rm -rf "$test_dir" "$sensitive_file"
exit 0
