#!/bin/zsh
#
# validate_plugin_registration.sh
# Validates that all plugins register correctly using static analysis
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
PLUGINS_CHECKED=0

echo "=== Plugin Registration Validation (Static Analysis) ==="
echo ""

# Extract plugin registrations from source files (static analysis)
extract_plugin_registrations() {
  local file="$1"
  grep -E '^[[:space:]]*register_plugin[[:space:]]+' "$file" 2>/dev/null || true
}

# Parse register_plugin call to extract components
parse_plugin_registration() {
  local line="$1"
  # register_plugin "Name" "category" "function_name" "requires_admin" ["size_function"] ["version"] ["dependencies"]
  # Extract using simple pattern matching
  echo "$line" | sed -E 's/.*register_plugin[[:space:]]+"([^"]+)"[[:space:]]+"([^"]+)"[[:space:]]+"([^"]+)"[[:space:]]+"([^"]+)".*/\1|\2|\3|\4/'
}

# Check if function is defined in file (static check)
function_defined_in_file() {
  local file="$1"
  local func_name="$2"
  # Look for function definition: function_name() { or function_name() {
  grep -qE "^[[:space:]]*${func_name}[[:space:]]*\(\)[[:space:]]*\{|^[[:space:]]*function[[:space:]]+${func_name}" "$file" 2>/dev/null
}

# Check plugin file structure
check_plugin_file() {
  local plugin_file="$1"
  [[ "$plugin_file" == *"/base.sh" ]] && return 0  # Skip base.sh
  [[ "$plugin_file" == *"/common.sh" ]] && return 0  # Skip common.sh
  
  local registrations
  registrations=$(extract_plugin_registrations "$plugin_file")
  
  if [[ -z "$registrations" ]]; then
    # Not all files need to register plugins
    return 0
  fi
  
  local has_errors=false
  
  local line_count=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_count=$((line_count + 1))
    [[ $line_count -gt 100 ]] && break  # Safety limit
    [[ -z "$line" ]] && continue
    
    PLUGINS_CHECKED=$((PLUGINS_CHECKED + 1))
    
    # Parse registration
    local parsed
    parsed=$(parse_plugin_registration "$line")
    
    if [[ -z "$parsed" ]]; then
      echo -e "${RED}✗${NC} Failed to parse registration: $line"
      echo "  File: $plugin_file"
      ERRORS=$((ERRORS + 1))
      has_errors=true
      continue
    fi
    
    local name category function_name requires_admin
    { IFS='|' read -r name category function_name requires_admin <<< "$parsed"; } 2>/dev/null
    
    # Validate required fields
    if [[ -z "$name" || -z "$category" || -z "$function_name" || -z "$requires_admin" ]]; then
      echo -e "${RED}✗${NC} Incomplete registration: $line"
      echo "  File: $plugin_file"
      echo "  Missing required fields"
      ERRORS=$((ERRORS + 1))
      has_errors=true
      continue
    fi
    
    # Check if function is defined in this file or base files
    local function_found=false
    
    # Check in current file
    if function_defined_in_file "$plugin_file" "$function_name"; then
      function_found=true
    fi
    
    # Check in base.sh (common functions)
    if [[ -f "$PLUGINS_DIR/base.sh" ]] && function_defined_in_file "$PLUGINS_DIR/base.sh" "$function_name"; then
      function_found=true
    fi
    
    # Check in common.sh if it exists in same directory
    local common_file
    common_file="$(dirname "$plugin_file")/common.sh"
    if [[ -f "$common_file" ]] && function_defined_in_file "$common_file" "$function_name"; then
      function_found=true
    fi
    
    if [[ "$function_found" == "false" ]]; then
      echo -e "${RED}✗${NC} Function '$function_name' not found for plugin '$name'"
      echo "  File: $plugin_file"
      echo "  Registration: $line"
      ERRORS=$((ERRORS + 1))
      has_errors=true
    else
      echo -e "${GREEN}✓${NC} Plugin '$name' -> function '$function_name' (category: $category)"
    fi
    
    # Check requires_admin is valid
    if [[ "$requires_admin" != "true" && "$requires_admin" != "false" ]]; then
      echo -e "${YELLOW}⚠${NC} Invalid requires_admin value: '$requires_admin' (should be 'true' or 'false')"
      echo "  Plugin: $name"
      echo "  File: $plugin_file"
      WARNINGS=$((WARNINGS + 1))
    fi
  done <<< "$registrations"
  
  return 0
}

echo "Checking plugin registrations (static analysis)..."
echo ""

# Check all plugin files
for plugin_file in "$PLUGINS_DIR"/**/*.sh(N); do
  check_plugin_file "$plugin_file"
done

# Summary
echo ""
echo "=== Summary ==="
echo "Plugins checked: $PLUGINS_CHECKED"
echo -e "Errors: ${RED}$ERRORS${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"

if [[ $ERRORS -eq 0 ]]; then
  echo -e "${GREEN}✓ All plugin registrations are valid${NC}"
  exit 0
else
  echo -e "${RED}✗ Plugin registration validation failed${NC}"
  exit 1
fi
