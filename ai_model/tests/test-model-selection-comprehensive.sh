#!/bin/bash
# Comprehensive test for model-selection.sh

# Source the library
source "$(dirname "$0")/lib/model-selection.sh"

echo "=========================================="
echo "Model Selection Library - Test Suite"
echo "=========================================="
echo ""

# Test 1: Hardware Detection
echo "Test 1: Hardware Detection"
echo "  Chip: $M_CHIP"
echo "  GPU Cores: $GPU_CORES"
echo "  Total RAM: ${TOTAL_RAM_GB}GB"
echo "  RAM Tier: $RAM_TIER"
echo ""

# Test 2: RAM Filtering
echo "Test 2: RAM Filtering (Llama family)"
echo "  48GB RAM (should show all 4 models):"
models_48=$(filter_models_by_ram llama 48 | wc -l)
echo "    Found: $models_48 models"

echo "  32GB RAM (should show 3 models, exclude 70B):"
models_32=$(filter_models_by_ram llama 32 | wc -l)
echo "    Found: $models_32 models"

echo "  16GB RAM (should show 2 models):"
models_16=$(filter_models_by_ram llama 16 | wc -l)
echo "    Found: $models_16 models"
echo ""

# Test 3: Recommendations
echo "Test 3: Recommendation System"
echo "  Llama 48GB: $(get_family_recommendation llama 48)"
echo "  Llama 32GB: $(get_family_recommendation llama 32)"
echo "  Llama 16GB: $(get_family_recommendation llama 16)"
echo "  Mistral 32GB: $(get_family_recommendation mistral 32)"
echo "  Phi 24GB: $(get_family_recommendation phi 24)"
echo "  Phi 16GB: $(get_family_recommendation phi 16)"
echo "  Gemma 48GB: $(get_family_recommendation gemma 48)"
echo "  Gemma 32GB: $(get_family_recommendation gemma 32)"
echo ""

# Test 4: Security Filter
echo "Test 4: Security Filter"
test_models=("llama3.2:3b" "mistral:7b" "phi4:14b" "gemma4:31b" "deepseek:7b" "qwen:14b" "yi:34b")
for model in "${test_models[@]}"; do
    if is_model_allowed "$model"; then
        echo "  ✓ $model - ALLOWED"
    else
        echo "  ✗ $model - BLOCKED"
    fi
done
echo ""

# Test 5: Environment Variable Support
echo "Test 5: Environment Variable Support"
echo "  Setting OLLAMA_MODEL_FAMILY=gemma"
export OLLAMA_MODEL_FAMILY=gemma
SELECTED_FAMILY=""
select_family > /dev/null 2>&1
echo "  Result: SELECTED_FAMILY=$SELECTED_FAMILY"
unset OLLAMA_MODEL_FAMILY
echo ""

# Test 6: Display Sample Menu
echo "Test 6: Sample Menu Display (Current System)"
echo "  Using detected RAM: ${TOTAL_RAM_GB}GB"
echo ""
display_model_menu llama "$TOTAL_RAM_GB"

echo ""
echo "=========================================="
echo "All Tests Complete"
echo "=========================================="
