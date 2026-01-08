#!/bin/bash
#
# constants.sh - Constants and configuration for setup-local-llm.sh
#
# This file contains all constants, model lists, and helper functions
# that don't depend on other modules.

# Script metadata
STATE_DIR="$HOME/.local-llm-setup"
STATE_FILE="$STATE_DIR/state.json"
LOG_FILE="$STATE_DIR/setup.log"

# Colors for output
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Approved models (no DeepSeek)
readonly APPROVED_MODELS=(
  "qwen2.5-coder:14b"
  "llama3.1:8b"
  "llama3.1:70b"
  "codestral:22b"
  "qwen2.5-coder:7b"
)

# Hardware tier thresholds (RAM in GB)
readonly TIER_S_MIN=48
readonly TIER_A_MIN=32
readonly TIER_B_MIN=16

# Model resource estimates (RAM in GB) - Quantized variants for Apple Silicon
# Function to get model RAM (reflects Q4_K_M/Q5_K_M quantization)
get_model_ram() {
  local model="$1"
  case "$model" in
    "qwen2.5-coder:7b") echo "3.5" ;;      # Q5_K_M: ~3.5GB (was 4.5GB unquantized)
    "llama3.1:8b") echo "4.2" ;;            # Q5_K_M: ~4.2GB (was 5GB unquantized)
    "qwen2.5-coder:14b") echo "7.5" ;;      # Q4_K_M: ~7.5GB (was 9GB unquantized)
    "codestral:22b") echo "11.5" ;;         # Q4_K_M: ~11.5GB (was 14GB unquantized)
    "llama3.1:70b") echo "35" ;;            # Q4_K_M: ~35GB (was 40GB unquantized)
    *) echo "0" ;;
  esac
}

# Function to get model description
get_model_desc() {
  local model="$1"
  case "$model" in
    "qwen2.5-coder:14b") echo "Best balance: quality + speed for React/TS" ;;
    "llama3.1:8b") echo "Fast general-purpose TypeScript assistant" ;;
    "llama3.1:70b") echo "Highest quality for complex refactoring (Tier S)" ;;
    "codestral:22b") echo "Excellent code generation for complex tasks" ;;
    "qwen2.5-coder:7b") echo "Lightweight, fast autocomplete & simple edits" ;;
    *) echo "No description" ;;
  esac
}
