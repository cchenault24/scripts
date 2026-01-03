#!/bin/zsh
#
# validate_shellcheck.sh
# Runs ShellCheck on all shell scripts and reports issues
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if shellcheck is installed
if ! command -v shellcheck >/dev/null 2>&1; then
  echo -e "${YELLOW}Warning: shellcheck is not installed${NC}"
  echo "Install with: brew install shellcheck"
  echo "Skipping ShellCheck validation..."
  exit 0
fi

# Track results
ERRORS=0
WARNINGS=0
FILES_CHECKED=0
CRITICAL_ISSUES=0

echo "=== ShellCheck Validation ==="
echo ""

# Find all shell scripts
while IFS= read -r -d '' script_file; do
  FILES_CHECKED=$((FILES_CHECKED + 1))
  echo "Checking: $script_file"
  
  # Run shellcheck and capture output
  local output
  output=$(shellcheck -f gcc "$script_file" 2>&1 || true)
  
  if [[ -n "$output" ]]; then
    # Count issues by severity
    local error_count
    error_count=$(echo "$output" | grep -c "error:" || echo "0")
    local warning_count
    warning_count=$(echo "$output" | grep -c "warning:" || echo "0")
    local note_count
    note_count=$(echo "$output" | grep -c "note:" || echo "0")
    
    ERRORS=$((ERRORS + error_count))
    WARNINGS=$((WARNINGS + warning_count))
    
    # Check for critical issues
    if echo "$output" | grep -qE "(SC2086|SC2068|SC2046|SC2155|SC1091)"; then
      CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
      echo -e "${RED}✗${NC} Critical issues found:"
      echo "$output" | grep -E "(SC2086|SC2068|SC2046|SC2155|SC1091)" || true
    fi
    
    if [[ $error_count -gt 0 || $warning_count -gt 0 ]]; then
      echo -e "${YELLOW}Issues found:${NC}"
      echo "$output"
      echo ""
    fi
  else
    echo -e "${GREEN}✓${NC} No issues"
  fi
  
  echo ""
done < <(find "$PROJECT_ROOT" -name "*.sh" -type f -print0 | grep -v "/tests/" | grep -v ".git/")

# Summary
echo "=== Summary ==="
echo "Files checked: $FILES_CHECKED"
echo -e "Errors: ${RED}$ERRORS${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
echo -e "Critical issues: ${RED}$CRITICAL_ISSUES${NC}"

if [[ $ERRORS -eq 0 && $CRITICAL_ISSUES -eq 0 ]]; then
  echo -e "${GREEN}✓ ShellCheck validation passed${NC}"
  exit 0
elif [[ $CRITICAL_ISSUES -gt 0 ]]; then
  echo -e "${RED}✗ Critical ShellCheck issues found${NC}"
  exit 1
else
  echo -e "${YELLOW}⚠ ShellCheck validation passed with warnings${NC}"
  exit 0
fi
