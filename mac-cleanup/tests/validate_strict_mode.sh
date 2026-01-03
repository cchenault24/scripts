#!/bin/zsh
#
# validate_strict_mode.sh
# Validates that all shell scripts have set -euo pipefail
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track results
MISSING_STRICT=0
FILES_CHECKED=0

echo "=== Strict Mode Validation ==="
echo ""

# Check if file has strict mode
check_strict_mode() {
  local file="$1"
  local has_strict=false
  local line_num=0
  
  # Read first 20 lines (strict mode should be near the top)
  while IFS= read -r line && [[ $line_num -lt 20 ]]; do
    line_num=$((line_num + 1))
    
    # Skip shebang
    [[ $line_num -eq 1 && "$line" =~ ^#! ]] && continue
    
    # Skip empty lines and comments before strict mode
    [[ -z "${line// }" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    
    # Check for strict mode patterns
    if echo "$line" | grep -qE 'set[[:space:]]+(-euo[[:space:]]+pipefail|-euo|-eu|pipefail)'; then
      has_strict=true
      break
    fi
    
    # If we hit actual code (not comments/empty), strict mode should have appeared
    if [[ ! "$line" =~ ^[[:space:]]*# ]] && [[ $line_num -gt 10 ]]; then
      break
    fi
  done < "$file"
  
  if [[ "$has_strict" == "false" ]]; then
    echo -e "${RED}✗${NC} Missing strict mode: $file"
    MISSING_STRICT=$((MISSING_STRICT + 1))
    return 1
  else
    echo -e "${GREEN}✓${NC} $file"
    return 0
  fi
}

# Check all shell scripts
echo "Checking for 'set -euo pipefail' in all shell scripts..."
echo ""

for script_file in "$PROJECT_ROOT"/**/*.sh(N); do
  # Skip test files (they're allowed to not have strict mode for testing)
  [[ "$script_file" == *"/tests/"* ]] && continue
  [[ "$script_file" == *".git/"* ]] && continue
  
  FILES_CHECKED=$((FILES_CHECKED + 1))
  check_strict_mode "$script_file"
done

# Summary
echo ""
echo "=== Summary ==="
echo "Files checked: $FILES_CHECKED"
echo -e "Missing strict mode: ${RED}$MISSING_STRICT${NC}"

if [[ $MISSING_STRICT -eq 0 ]]; then
  echo -e "${GREEN}✓ All files have strict mode enabled${NC}"
  exit 0
else
  echo -e "${RED}✗ Some files are missing strict mode${NC}"
  echo "All production shell scripts should have 'set -euo pipefail' near the top"
  exit 1
fi
