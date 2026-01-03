#!/bin/zsh
#
# validate_variable_quoting.sh
# Checks for unquoted variables in dangerous commands (rm, find, tar, etc.)
# Uses static analysis only - no code execution
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
ISSUES=0
FILES_CHECKED=0

echo "=== Variable Quoting Safety Validation (Static Analysis) ==="
echo ""

# Dangerous commands that require quoted variables
DANGEROUS_COMMANDS=("rm" "find" "tar" "mv" "cp" "mkdir" "rmdir")

check_file() {
  local file="$1"
  local line_num=0
  local has_issues=false
  
  # Read file line by line with safety limit
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))
    
    # Safety: limit to first 5000 lines per file
    [[ $line_num -gt 5000 ]] && break
    
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    
    # Check for dangerous commands
    for cmd in "${DANGEROUS_COMMANDS[@]}"; do
      # Check if line contains the command
      if ! echo "$line" | grep -qE "\b${cmd}\b"; then
        continue
      fi
      
      # Simple pattern: look for ${VAR} that might be unquoted
      # This is a heuristic check - may have false positives
      if echo "$line" | grep -qE "\b${cmd}\b.*\$\{[A-Za-z_][A-Za-z0-9_]*\}"; then
        # Count quotes in the line
        local quote_count
        quote_count=$(echo "$line" | grep -o '"' | wc -l | tr -d ' ' || echo "0")
        
        # If no quotes or even number, might be unquoted (simplified heuristic)
        if [[ $((quote_count % 2)) -eq 0 ]]; then
          echo -e "${YELLOW}⚠${NC} Line $line_num: Check variable quoting in $cmd command"
          echo "  $line"
          ISSUES=$((ISSUES + 1))
          has_issues=true
          break  # Only report once per line
        fi
      fi
      
      # Check for simple $VAR patterns (not ${VAR})
      if echo "$line" | grep -qE "\b${cmd}\b.*[[:space:]]\$[A-Za-z_][A-Za-z0-9_]*[[:space:]]"; then
        echo -e "${YELLOW}⚠${NC} Line $line_num: Check variable quoting in $cmd command"
        echo "  $line"
        ISSUES=$((ISSUES + 1))
        has_issues=true
        break
      fi
    done
  done < "$file"
  
  if [[ "$has_issues" == "false" ]]; then
    echo -e "${GREEN}✓${NC} $file"
  fi
}

# Check all shell scripts
echo "Checking for unquoted variables in dangerous commands..."
echo ""

for script_file in "$PROJECT_ROOT"/**/*.sh(N); do
  # Skip test files
  [[ "$script_file" == *"/tests/"* ]] && continue
  [[ "$script_file" == *".git/"* ]] && continue
  
  FILES_CHECKED=$((FILES_CHECKED + 1))
  check_file "$script_file"
done

# Summary
echo ""
echo "=== Summary ==="
echo "Files checked: $FILES_CHECKED"
echo -e "Potential issues: ${YELLOW}$ISSUES${NC}"

if [[ $ISSUES -eq 0 ]]; then
  echo -e "${GREEN}✓ Variable quoting validation passed${NC}"
  exit 0
else
  echo -e "${YELLOW}⚠ Review the above issues - some may be false positives${NC}"
  echo "Note: This is a heuristic check. Manual review is recommended."
  exit 0  # Don't fail, just warn
fi
