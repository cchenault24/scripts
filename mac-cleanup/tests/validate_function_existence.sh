#!/bin/zsh
#
# validate_function_existence.sh
# Validates that all functions referenced in plugin registrations actually exist (static analysis)
#

set -euo pipefail
# Disable debug output if enabled
set +x 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGINS_DIR="$PROJECT_ROOT/plugins"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track results
ERRORS=0
WARNINGS=0
FUNCTIONS_CHECKED=0

echo "=== Function Existence Validation (Static Analysis) ==="
echo ""

# Extract register_plugin calls and parse function names (static)
extract_plugin_functions() {
  local file="$1"
  # Extract function name (3rd argument) from register_plugin calls
  grep -E '^[[:space:]]*register_plugin[[:space:]]+' "$file" 2>/dev/null | \
    sed -E 's/.*register_plugin[[:space:]]+"[^"]+"[[:space:]]+"[^"]+"[[:space:]]+"([^"]+)".*/\1/' || true
}

# Check if function is defined in file (static check)
function_defined_in_file() {
  local file="$1"
  local func_name="$2"
  # Look for function definition
  grep -qE "^[[:space:]]*${func_name}[[:space:]]*\(\)[[:space:]]*\{|^[[:space:]]*function[[:space:]]+${func_name}" "$file" 2>/dev/null
}

# Find function in any related files
find_function_definition() {
  local plugin_file="$1"
  local func_name="$2"
  
  # Check in current file
  if function_defined_in_file "$plugin_file" "$func_name"; then
    return 0
  fi
  
  # Check in base.sh
  if [[ -f "$PLUGINS_DIR/base.sh" ]] && function_defined_in_file "$PLUGINS_DIR/base.sh" "$func_name"; then
    return 0
  fi
  
  # Check in common.sh in same directory
  local common_file
  common_file="$(dirname "$plugin_file")/common.sh"
  if [[ -f "$common_file" ]] && function_defined_in_file "$common_file" "$func_name"; then
    return 0
  fi
  
  # Check in lib files (for utility functions)
  for lib_file in "$PROJECT_ROOT/lib"/*.sh "$PROJECT_ROOT/lib"/*/*.sh; do
    [[ -f "$lib_file" ]] && function_defined_in_file "$lib_file" "$func_name" && return 0
  done
  
  return 1
}

echo "Checking registered plugin functions (static analysis)..."
echo ""

# Check all plugin files
for plugin_file in "$PLUGINS_DIR"/**/*.sh(N); do
  [[ "$plugin_file" == *"/base.sh" ]] && continue
  [[ "$plugin_file" == *"/common.sh" ]] && continue
  
  local func_list
  { func_list=$(extract_plugin_functions "$plugin_file"); } 2>/dev/null
  
  if [[ -z "$func_list" ]]; then
    continue
  fi
  
  while IFS= read -r func_name; do
    [[ -z "$func_name" ]] && continue
    
    FUNCTIONS_CHECKED=$((FUNCTIONS_CHECKED + 1))
    
    if find_function_definition "$plugin_file" "$func_name"; then
      echo -e "${GREEN}✓${NC} Function '$func_name' found (plugin: $(basename "$plugin_file"))"
    else
      echo -e "${RED}✗${NC} Function '$func_name' not found"
      echo "  Plugin file: $plugin_file"
      ERRORS=$((ERRORS + 1))
    fi
  done <<< "$func_list"
done

# Summary
echo ""
echo "=== Summary ==="
echo "Functions checked: $FUNCTIONS_CHECKED"
echo -e "Errors: ${RED}$ERRORS${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"

if [[ $ERRORS -eq 0 ]]; then
  echo -e "${GREEN}✓ All registered functions exist${NC}"
  exit 0
else
  echo -e "${RED}✗ Function existence validation failed${NC}"
  exit 1
fi
