#!/bin/zsh
# Test script for SEC-2 & SEC-3: Validate sudo command injection fixes
# This test verifies the code changes without requiring actual sudo execution

set -euo pipefail

echo "SEC-2/SEC-3 Security Validation Test"
echo "====================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

test_passed=0
test_failed=0

# Test 1: Verify no 'sudo sh -c' patterns exist
echo -e "${YELLOW}Test 1: Verify all 'sudo sh -c' patterns removed${NC}"
if grep -rn "sudo sh -c" . --include="*.sh" --exclude="test-*.sh" 2>/dev/null; then
  echo -e "${RED}✗ FAIL: Found 'sudo sh -c' patterns${NC}"
  test_failed=$((test_failed + 1))
else
  echo -e "${GREEN}✓ PASS: No 'sudo sh -c' patterns found${NC}"
  test_passed=$((test_passed + 1))
fi
echo ""

# Test 2: Verify no 'sudo -n sh -c' patterns exist
echo -e "${YELLOW}Test 2: Verify all 'sudo -n sh -c' patterns removed${NC}"
if grep -rn "sudo -n sh -c" . --include="*.sh" --exclude="test-*.sh" 2>/dev/null; then
  echo -e "${RED}✗ FAIL: Found 'sudo -n sh -c' patterns${NC}"
  test_failed=$((test_failed + 1))
else
  echo -e "${GREEN}✓ PASS: No 'sudo -n sh -c' patterns found${NC}"
  test_passed=$((test_passed + 1))
fi
echo ""

# Test 3: Verify safe_sudo_exec function exists
echo -e "${YELLOW}Test 3: Verify safe_sudo_exec function exists${NC}"
if grep -q "^safe_sudo_exec()" lib/admin.sh; then
  echo -e "${GREEN}✓ PASS: safe_sudo_exec function found in admin.sh${NC}"
  test_passed=$((test_passed + 1))
else
  echo -e "${RED}✗ FAIL: safe_sudo_exec function not found${NC}"
  test_failed=$((test_failed + 1))
fi
echo ""

# Test 4: Verify safe_sudo_exec uses 'sudo --'
echo -e "${YELLOW}Test 4: Verify safe_sudo_exec uses 'sudo --' for argument safety${NC}"
if grep -A10 "^safe_sudo_exec()" lib/admin.sh | grep -q 'sudo --'; then
  echo -e "${GREEN}✓ PASS: safe_sudo_exec uses 'sudo --' pattern${NC}"
  test_passed=$((test_passed + 1))
else
  echo -e "${RED}✗ FAIL: safe_sudo_exec doesn't use 'sudo --' pattern${NC}"
  test_failed=$((test_failed + 1))
fi
echo ""

# Test 5: Verify run_as_admin uses bash -s with here-string
echo -e "${YELLOW}Test 5: Verify run_as_admin uses 'bash -s' with here-string${NC}"
if grep -A50 "^run_as_admin()" lib/admin.sh | grep -q 'sudo -n bash -s'; then
  echo -e "${GREEN}✓ PASS: run_as_admin uses 'bash -s' pattern${NC}"
  test_passed=$((test_passed + 1))
else
  echo -e "${RED}✗ FAIL: run_as_admin doesn't use 'bash -s' pattern${NC}"
  test_failed=$((test_failed + 1))
fi
echo ""

# Test 6: Verify system_cache.sh uses direct sudo
echo -e "${YELLOW}Test 6: Verify system_cache.sh uses direct 'sudo -- du'${NC}"
if grep -q 'sudo -- du -sk' plugins/system/system_cache.sh; then
  echo -e "${GREEN}✓ PASS: system_cache.sh uses direct sudo execution${NC}"
  test_passed=$((test_passed + 1))
else
  echo -e "${RED}✗ FAIL: system_cache.sh doesn't use direct sudo${NC}"
  test_failed=$((test_failed + 1))
fi
echo ""

# Test 7: Verify logs.sh uses direct sudo
echo -e "${YELLOW}Test 7: Verify logs.sh uses direct 'sudo -n -- du'${NC}"
if grep -q 'sudo -n -- du -sk' plugins/system/logs.sh; then
  echo -e "${GREEN}✓ PASS: logs.sh uses direct sudo execution${NC}"
  test_passed=$((test_passed + 1))
else
  echo -e "${RED}✗ FAIL: logs.sh doesn't use direct sudo${NC}"
  test_failed=$((test_failed + 1))
fi
echo ""

# Test 8: Verify SEC-2/SEC-3 comments exist
echo -e "${YELLOW}Test 8: Verify SEC-2/SEC-3 security comments exist${NC}"
sec_comments=$(grep -r "SEC-2/SEC-3" lib/admin.sh plugins/system/system_cache.sh plugins/system/logs.sh | wc -l)
if [ "$sec_comments" -ge 5 ]; then
  echo -e "${GREEN}✓ PASS: Found $sec_comments SEC-2/SEC-3 security comments${NC}"
  test_passed=$((test_passed + 1))
else
  echo -e "${RED}✗ FAIL: Only found $sec_comments SEC-2/SEC-3 comments (expected >= 5)${NC}"
  test_failed=$((test_failed + 1))
fi
echo ""

# Test 9: Verify no printf %q escaping used (replaced with direct execution)
echo -e "${YELLOW}Test 9: Verify old printf %q + sudo sh -c pattern removed${NC}"
if grep -B2 -A2 "sudo sh -c" plugins/system/system_cache.sh plugins/system/logs.sh 2>/dev/null | grep -q 'printf.*%q'; then
  echo -e "${RED}✗ FAIL: Old printf %q + sudo sh -c pattern still exists${NC}"
  test_failed=$((test_failed + 1))
else
  echo -e "${GREEN}✓ PASS: Old printf %q + sudo sh -c pattern removed${NC}"
  test_passed=$((test_passed + 1))
fi
echo ""

# Summary
echo "====================================="
echo "Test Summary:"
echo -e "${GREEN}Passed: $test_passed${NC}"
echo -e "${RED}Failed: $test_failed${NC}"
echo ""

if [ $test_failed -eq 0 ]; then
  echo -e "${GREEN}✓ All SEC-2/SEC-3 security validations passed!${NC}"
  echo ""
  echo "Security improvements verified:"
  echo "  • All 'sudo sh -c' patterns eliminated"
  echo "  • Direct sudo execution with '--' for simple commands"
  echo "  • safe_sudo_exec() function for array-based execution"
  echo "  • run_as_admin() uses 'bash -s <<<' instead of 'sh -c'"
  echo "  • Proper quoting with direct variable expansion"
  echo ""
  exit 0
else
  echo -e "${RED}✗ Some SEC-2/SEC-3 security validations failed!${NC}"
  exit 1
fi
