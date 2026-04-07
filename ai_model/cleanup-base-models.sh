#!/bin/bash
#
# Remove base models, keeping only optimized versions
#

OLLAMA_BUILD_DIR="/tmp/ollama-build"
PORT=3456
export OLLAMA_HOST="127.0.0.1:$PORT"

echo "Removing base models (keeping optimized versions)..."
echo ""

# Remove base models that have optimized versions
OLLAMA_HOST="127.0.0.1:$PORT" "$OLLAMA_BUILD_DIR/ollama" rm gemma4:e2b-it-q8_0 2>/dev/null && echo "✓ Removed gemma4:e2b-it-q8_0" || echo "✗ gemma4:e2b-it-q8_0 not found"
OLLAMA_HOST="127.0.0.1:$PORT" "$OLLAMA_BUILD_DIR/ollama" rm gemma4:26b-a4b-it-q4_K_M 2>/dev/null && echo "✓ Removed gemma4:26b-a4b-it-q4_K_M" || echo "✗ gemma4:26b-a4b-it-q4_K_M not found"

echo ""
echo "Current models:"
OLLAMA_HOST="127.0.0.1:$PORT" "$OLLAMA_BUILD_DIR/ollama" list
