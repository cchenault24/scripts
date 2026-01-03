#!/bin/zsh
#
# validate_backup_safety.sh
# Validates that all plugins call backup() before destructive operations (static analysis)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGINS_DIR="$PROJECT_ROOT/plugins"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track results
ISSUES=0
FILES_CHECKED=0
UNSAFE_OPERATIONS=0

echo "=== Backup Safety Validation (Static Analysis) ==="
echo ""

# Destructive operations that should be preceded by backup()
# Using static pattern matching
DESTRUCTIVE_PATTERNS=(
  'rm[[:space:]]+-rf'
  'rm[[:space:]]+-r'
  'rm[[:space:]]+-f'
  'find.*-delete'
  'find.*-exec[[:space:]]+rm'
)

check_plugin_file() {
  local file="$1"
  local has_issues=false
  local line_num=0
  local last_backup_line=0
  local destructive_ops_found=0
  
  # Skip base.sh and common.sh (they're utilities, not plugins)
  [[ "$file" == *"/base.sh" ]] && return 0
  [[ "$file" == *"/common.sh" ]] && return 0
  
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))
    
    # Safety: limit to first 5000 lines per file
    [[ $line_num -gt 5000 ]] && break
    
    # Skip comments
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    
    # Track backup() calls (look for backup function calls)
    # Shell functions are called as: backup "arg" or backup("arg") or backup ( "arg" )
    if echo "$line" | grep -qE '\bbackup\s*[("]'; then
      last_backup_line=$line_num
    fi
    
    # Check for destructive operations
    for pattern in "${DESTRUCTIVE_PATTERNS[@]}"; do
      if echo "$line" | grep -qE "$pattern"; then
        destructive_ops_found=$((destructive_ops_found + 1))
        
        # Exception: safe_remove and safe_clean_dir are safe functions that handle backup internally
        if echo "$line" | grep -qE '\b(safe_remove|safe_clean_dir)\s*\('; then
          # These functions should handle backup internally, so this is OK
          continue
        fi
        
        # Check if backup was called recently (within 20 lines) or on same line
        local backup_distance=$((line_num - last_backup_line))
        
        if [[ $backup_distance -gt 20 && $last_backup_line -eq 0 ]]; then
          echo -e "${RED}✗${NC} Line $line_num: Destructive operation without preceding backup"
          echo "  Operation: $pattern"
          echo "  File: $file"
          echo "  Code: $line"
          ISSUES=$((ISSUES + 1))
          UNSAFE_OPERATIONS=$((UNSAFE_OPERATIONS + 1))
          has_issues=true
        elif [[ $backup_distance -gt 20 ]]; then
          echo -e "${YELLOW}⚠${NC} Line $line_num: Destructive operation far from backup call"
          echo "  Operation: $pattern"
          echo "  File: $file"
          echo "  Last backup call: line $last_backup_line (distance: $backup_distance lines)"
          ISSUES=$((ISSUES + 1))
          has_issues=true
        fi
      fi
    done
  done < "$file"
  
  # Check if plugin has destructive operations but no backup calls at all
  if [[ $destructive_ops_found -gt 0 && $last_backup_line -eq 0 ]]; then
    # But allow if all operations use safe_remove/safe_clean_dir
    local unsafe_ops
    unsafe_ops=$(grep -E '\b(rm[[:space:]]+-rf|rm[[:space:]]+-r|rm[[:space:]]+-f|find.*-delete|find.*-exec[[:space:]]+rm)' "$file" 2>/dev/null | grep -vE '\b(safe_remove|safe_clean_dir)' | wc -l | tr -d ' ')
    if [[ ${unsafe_ops:-0} -gt 0 ]]; then
      echo -e "${RED}✗${NC} File has destructive operations but no backup() calls"
      echo "  File: $file"
      echo "  Destructive operations found: $destructive_ops_found"
      ISSUES=$((ISSUES + 1))
      UNSAFE_OPERATIONS=$((UNSAFE_OPERATIONS + 1))
      has_issues=true
    fi
  fi
  
  if [[ "$has_issues" == "false" && $destructive_ops_found -gt 0 ]]; then
    echo -e "${GREEN}✓${NC} $file (has backup protection)"
  elif [[ $destructive_ops_found -eq 0 ]]; then
    # File has no destructive operations, skip
    return 0
  fi
}

# Check all plugin files
echo "Checking for backup() calls before destructive operations (static analysis)..."
echo ""

for plugin_file in "$PLUGINS_DIR"/**/*.sh(N); do
  FILES_CHECKED=$((FILES_CHECKED + 1))
  check_plugin_file "$plugin_file"
done

# Also verify safe_remove and safe_clean_dir handle backup internally
echo ""
echo "Verifying safe_remove and safe_clean_dir implementations..."
if grep -q "backup" "$PROJECT_ROOT/lib/utils.sh" 2>/dev/null; then
  echo -e "${GREEN}✓${NC} safe_remove/safe_clean_dir appear to handle backup"
else
  echo -e "${YELLOW}⚠${NC} Review safe_remove/safe_clean_dir - they should handle backup internally"
  ISSUES=$((ISSUES + 1))
fi

# Summary
echo ""
echo "=== Summary ==="
echo "Files checked: $FILES_CHECKED"
echo -e "Unsafe operations found: ${RED}$UNSAFE_OPERATIONS${NC}"
echo -e "Total issues: ${RED}$ISSUES${NC}"

if [[ $ISSUES -eq 0 ]]; then
  echo -e "${GREEN}✓ Backup safety validation passed${NC}"
  exit 0
else
  echo -e "${RED}✗ Backup safety validation failed${NC}"
  echo "All destructive operations must be preceded by backup() calls"
  exit 1
fi
