#!/bin/bash
# Test script for model-selection.sh

# Source the library
source "$(dirname "$0")/lib/model-selection.sh"

# Test display for different scenarios
echo "=========================================="
echo "Test 1: Display menu for Llama (48GB RAM)"
echo "=========================================="
display_model_menu llama 48

echo ""
echo "=========================================="
echo "Test 2: Display menu for Llama (32GB RAM)"
echo "=========================================="
display_model_menu llama 32

echo ""
echo "=========================================="
echo "Test 3: Display menu for Llama (16GB RAM)"
echo "=========================================="
display_model_menu llama 16

echo ""
echo "=========================================="
echo "Test 4: Display menu for Mistral (32GB RAM)"
echo "=========================================="
display_model_menu mistral 32

echo ""
echo "=========================================="
echo "Test 5: Display menu for Gemma (48GB RAM)"
echo "=========================================="
display_model_menu gemma 48

echo ""
echo "=========================================="
echo "Test 6: Display menu for Phi (16GB RAM)"
echo "=========================================="
display_model_menu phi 16
