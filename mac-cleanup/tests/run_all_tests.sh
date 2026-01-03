#!/bin/zsh
#
# run_all_tests.sh
# Master test runner that executes all validation scripts
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track overall results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNED_TESTS=0

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  macOS Cleanup Utility - Automated Test Suite            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Make all test scripts executable
chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true

# Test 1: Strict Mode Validation
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Test 1: Strict Mode Validation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if "$SCRIPT_DIR/validate_strict_mode.sh"; then
  PASSED_TESTS=$((PASSED_TESTS + 1))
  echo -e "${GREEN}✓ PASSED${NC}"
else
  FAILED_TESTS=$((FAILED_TESTS + 1))
  echo -e "${RED}✗ FAILED${NC}"
fi
echo ""

# Test 2: ShellCheck Validation
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Test 2: ShellCheck Validation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if "$SCRIPT_DIR/validate_shellcheck.sh"; then
  PASSED_TESTS=$((PASSED_TESTS + 1))
  echo -e "${GREEN}✓ PASSED${NC}"
else
  local exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    WARNED_TESTS=$((WARNED_TESTS + 1))
    echo -e "${YELLOW}⚠ WARNED${NC}"
  else
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo -e "${RED}✗ FAILED${NC}"
  fi
fi
echo ""

# Test 3: Variable Quoting Validation
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Test 3: Variable Quoting Validation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if "$SCRIPT_DIR/validate_variable_quoting.sh"; then
  PASSED_TESTS=$((PASSED_TESTS + 1))
  echo -e "${GREEN}✓ PASSED${NC}"
else
  local exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    WARNED_TESTS=$((WARNED_TESTS + 1))
    echo -e "${YELLOW}⚠ WARNED${NC}"
  else
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo -e "${RED}✗ FAILED${NC}"
  fi
fi
echo ""

# Test 4: Plugin Registration Validation
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Test 4: Plugin Registration Validation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if "$SCRIPT_DIR/validate_plugin_registration.sh"; then
  PASSED_TESTS=$((PASSED_TESTS + 1))
  echo -e "${GREEN}✓ PASSED${NC}"
else
  FAILED_TESTS=$((FAILED_TESTS + 1))
  echo -e "${RED}✗ FAILED${NC}"
fi
echo ""

# Test 5: Function Existence Validation
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Test 5: Function Existence Validation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if "$SCRIPT_DIR/validate_function_existence.sh"; then
  PASSED_TESTS=$((PASSED_TESTS + 1))
  echo -e "${GREEN}✓ PASSED${NC}"
else
  FAILED_TESTS=$((FAILED_TESTS + 1))
  echo -e "${RED}✗ FAILED${NC}"
fi
echo ""

# Test 6: Backup Safety Validation
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Test 6: Backup Safety Validation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if "$SCRIPT_DIR/validate_backup_safety.sh"; then
  PASSED_TESTS=$((PASSED_TESTS + 1))
  echo -e "${GREEN}✓ PASSED${NC}"
else
  FAILED_TESTS=$((FAILED_TESTS + 1))
  echo -e "${RED}✗ FAILED${NC}"
fi
echo ""

# Final Summary
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Test Summary                                               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Total Tests: $TOTAL_TESTS"
echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
echo -e "Warned: ${YELLOW}$WARNED_TESTS${NC}"
echo ""

if [[ $FAILED_TESTS -eq 0 && $WARNED_TESTS -eq 0 ]]; then
  echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║  ✓ ALL TESTS PASSED                                       ║${NC}"
  echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
  exit 0
elif [[ $FAILED_TESTS -eq 0 ]]; then
  echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}║  ⚠ ALL TESTS PASSED WITH WARNINGS                         ║${NC}"
  echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
  exit 0
else
  echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║  ✗ SOME TESTS FAILED                                       ║${NC}"
  echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
  exit 1
fi
