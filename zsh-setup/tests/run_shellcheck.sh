#!/usr/bin/env bash

#==============================================================================
# run_shellcheck.sh - Shell Script Linting
#
# Runs shellcheck on all shell scripts in the project
#==============================================================================

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 Running shellcheck on zsh-setup..."
echo

# Check if shellcheck is installed
if ! command -v shellcheck &>/dev/null; then
    echo -e "${RED}❌ shellcheck not installed${NC}"
    echo
    echo "Install with:"
    echo "  macOS:    brew install shellcheck"
    echo "  Ubuntu:   apt install shellcheck"
    echo "  Fedora:   dnf install ShellCheck"
    exit 1
fi

# Get shellcheck version
SHELLCHECK_VERSION=$(shellcheck --version | grep "^version:" | awk '{print $2}')
echo "Using shellcheck version: $SHELLCHECK_VERSION"
echo

# Find all shell scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

# Count files
TOTAL_FILES=0
FAILED_FILES=0
declare -a FAILED_FILE_LIST=()

echo "Checking files..."
echo

# Check main executable
FILES_TO_CHECK=()
if [[ -f "zsh-setup" ]]; then
    FILES_TO_CHECK+=("zsh-setup")
fi

# Find all .sh files
while IFS= read -r -d '' file; do
    FILES_TO_CHECK+=("$file")
done < <(find . -name "*.sh" -type f -print0)

# Run shellcheck on each file
for file in "${FILES_TO_CHECK[@]}"; do
    ((TOTAL_FILES++))

    # Run shellcheck
    if shellcheck -x -S warning "$file" 2>&1; then
        echo -e "${GREEN}✓${NC} $file"
    else
        echo -e "${RED}✗${NC} $file"
        ((FAILED_FILES++))
        FAILED_FILE_LIST+=("$file")
    fi
done

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Report results
if [[ $FAILED_FILES -eq 0 ]]; then
    echo -e "${GREEN}✅ All $TOTAL_FILES files passed shellcheck${NC}"
    exit 0
else
    echo -e "${RED}❌ $FAILED_FILES of $TOTAL_FILES files failed shellcheck${NC}"
    echo
    echo "Failed files:"
    for file in "${FAILED_FILE_LIST[@]}"; do
        echo "  - $file"
    done
    echo
    echo "Run shellcheck on individual files for details:"
    echo "  shellcheck -x <file>"
    exit 1
fi
