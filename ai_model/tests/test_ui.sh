#!/bin/bash
set -euo pipefail
# Quick UI test to demonstrate verbosity levels

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

echo "=========================================="
echo "Testing UI Verbosity Levels"
echo "=========================================="
echo ""

# Test Normal Mode (VERBOSITY_LEVEL=1)
echo "=== NORMAL MODE (default) ==="
export VERBOSITY_LEVEL=1
print_header "Installation Step"
print_step "1/3" "Installing Component"
print_status "Component installed (1.2.3)"
print_verbose "This message is hidden in normal mode"
print_info "Processing configuration..."
print_status "Configuration complete"
echo ""

# Test Verbose Mode (VERBOSITY_LEVEL=2)
echo "=== VERBOSE MODE (-v) ==="
export VERBOSITY_LEVEL=2
print_header "Installation Step"
print_step "1/3" "Installing Component"
print_status "Component installed (1.2.3)"
print_verbose "This message is visible in verbose mode"
print_info "Processing configuration..."
print_status "Configuration complete"
echo ""

# Test Quiet Mode (VERBOSITY_LEVEL=0)
echo "=== QUIET MODE (-q) ==="
export VERBOSITY_LEVEL=0
print_header "Installation Step"
print_step "1/3" "Installing Component"
print_status "Component installed (1.2.3)"
print_verbose "This message is hidden in quiet mode"
print_info "This is also hidden in quiet mode"
print_status "This is also hidden in quiet mode"
print_error "Only errors show in quiet mode"
echo ""

# Reset to normal
export VERBOSITY_LEVEL=1

# Show summary comparison
echo "=========================================="
echo "Usage Examples:"
echo "=========================================="
echo ""
echo "Normal (default):      ./setup-ai-opencode.sh"
echo "Verbose (all details): ./setup-ai-opencode.sh -v"
echo "Quiet (minimal):       ./setup-ai-opencode.sh -q"
echo ""
