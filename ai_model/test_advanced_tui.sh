#!/bin/bash
# Test script for advanced TUI features

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/tui-advanced.sh"

export VERBOSITY_LEVEL=1

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         Advanced TUI Features Demonstration               ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Test 1: Spinner
echo "=== Test 1: Animated Spinner ==="
start_spinner "Downloading model..."
sleep 3
stop_spinner
print_status "Download complete"
echo ""

# Test 2: Progress Bar
echo "=== Test 2: Progress Bar ==="
for i in 0 10 20 30 40 50 60 70 80 90 100; do
    draw_progress_bar $i 100
    echo ""
    sleep 0.2
done
print_status "Progress complete"
echo ""

# Test 3: Download Progress
echo "=== Test 3: Download Progress with ETA ==="
for i in 0 50 100 150 200 250 300 350 400 450 500; do
    draw_download_progress $i 500 5.2
    sleep 0.2
done
print_status "Download complete"
echo ""

# Test 4: Box Drawing
echo "=== Test 4: Info Box ==="
draw_info_box \
    "Hardware Configuration" \
    "Chip: M4" \
    "RAM: 48GB" \
    "CPU Cores: 10"

# Test 5: Error Box
echo "=== Test 5: Error Box ==="
draw_error_box \
    "Model Download Failed" \
    "Failed to download model from Ollama registry.

Possible causes:
  • Network connection issues
  • Insufficient disk space
  • Ollama service not running" \
    "Retry download|Check disk space|View logs|Skip"

# Test 6: Tree Structure
echo "=== Test 6: Tree Display ==="
echo "[1/3] Installing Components"
tree_node 0 0 "✓" "Ollama v0.20.4 found"
tree_node 0 0 "⣾" "Checking for updates..."
tree_node 0 1 "✓" "Up to date"
echo ""

# Test 7: Configuration Preview
echo "=== Test 7: Configuration Preview ==="
show_config_preview \
    "M4" \
    "48" \
    "10" \
    "gemma4:31b" \
    "19" \
    "codegemma:7b" \
    "5.0" \
    "OpenCode + JetBrains"

# Test 8: System Resources
echo "=== Test 8: System Resources Monitor ==="
show_system_resources
echo ""

# Test 9: Interactive Menu (commented out since it clears screen)
# echo "=== Test 9: Interactive Menu ==="
# echo "(Arrow key navigation - commented out to avoid clearing screen)"
# # result=$(show_menu "Select Model" "gemma4:e2b|gemma4:latest|gemma4:26b|gemma4:31b")
# # echo "Selected: $result"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              All Tests Complete! ✓                        ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "These features are now integrated into the setup script!"
echo "Run: ./setup-gemma4-opencode.sh"
echo ""
