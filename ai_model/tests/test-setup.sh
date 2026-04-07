#!/bin/bash
# test-setup.sh - Test the setup.sh orchestrator structure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Testing setup.sh orchestrator..."
echo ""

# Test 1: Help works
echo "Test 1: Help output"
if ./setup.sh --help > /dev/null 2>&1; then
    echo "  ✓ Help works"
else
    echo "  ✗ Help failed"
    exit 1
fi

# Test 2: Invalid option shows error
echo "Test 2: Invalid option handling"
OUTPUT=$(./setup.sh --invalid 2>&1 || true)
if echo "$OUTPUT" | grep -q "Unknown option"; then
    echo "  ✓ Invalid option handling works"
else
    echo "  ✗ Invalid option handling failed"
    echo "  Output: $OUTPUT"
    exit 1
fi

# Test 3: All libraries can be sourced
echo "Test 3: Library sourcing"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/model-families.sh"
source "$SCRIPT_DIR/lib/model-selection.sh"
source "$SCRIPT_DIR/lib/ollama-setup.sh"
source "$SCRIPT_DIR/lib/continue-setup.sh"
source "$SCRIPT_DIR/lib/webui-setup.sh"
source "$SCRIPT_DIR/lib/opencode-setup.sh"
echo "  ✓ All libraries sourced successfully"

# Test 4: Check critical functions are defined
echo "Test 4: Critical functions"
declare -F | grep -q "print_header" || { echo "  ✗ print_header not found"; exit 1; }
declare -F | grep -q "detect_hardware" || { echo "  ✗ detect_hardware not found"; exit 1; }
declare -F | grep -q "get_family_models" || { echo "  ✗ get_family_models not found"; exit 1; }
declare -F | grep -q "select_model" || { echo "  ✗ select_model not found"; exit 1; }
declare -F | grep -q "build_ollama" || { echo "  ✗ build_ollama not found"; exit 1; }
declare -F | grep -q "setup_continue" || { echo "  ✗ setup_continue not found"; exit 1; }
declare -F | grep -q "setup_webui" || { echo "  ✗ setup_webui not found"; exit 1; }
declare -F | grep -q "setup_opencode" || { echo "  ✗ setup_opencode not found"; exit 1; }
echo "  ✓ All critical functions defined"

# Test 5: Hardware detection works
echo "Test 5: Hardware detection"
if [[ -n "$M_CHIP" && -n "$TOTAL_RAM_GB" && -n "$RAM_TIER" ]]; then
    echo "  ✓ Hardware detected: $M_CHIP, ${TOTAL_RAM_GB}GB, $RAM_TIER"
else
    echo "  ✗ Hardware detection failed"
    exit 1
fi

# Test 6: Model families are defined
echo "Test 6: Model families"
if [[ ${#LLAMA_MODELS[@]} -gt 0 && ${#GEMMA_MODELS[@]} -gt 0 ]]; then
    echo "  ✓ Model families defined (Llama: ${#LLAMA_MODELS[@]}, Gemma: ${#GEMMA_MODELS[@]})"
else
    echo "  ✗ Model families not properly defined"
    exit 1
fi

echo ""
echo "All tests passed! ✓"
echo ""
echo "Setup structure is valid and ready for use."
