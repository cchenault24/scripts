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

# Approved models (Ollama-compatible from Continue.dev recommendations, excluding Qwen)
# Based on Continue.dev recommendations: https://docs.continue.dev/customize/models#recommended-models
# All models listed here are available via Ollama and recommended by Continue.dev
readonly APPROVED_MODELS=(
  # Agent Plan / Chat / Edit (Best open models for Ollama)
  "devstral:27b"         # Devstral 27B - Excellent for agent planning and reasoning
  "gpt-oss:20b"          # gpt-oss 20B - Strong coding capabilities
  "codestral"            # Codestral - Excellent code generation (autocomplete capable)
  # General purpose / Autocomplete
  "llama3.1:8b"          # Llama 3.1 8B - Fast general-purpose, good for autocomplete
  "llama3.1:70b"         # Llama 3.1 70B - Highest quality (Tier S only)
  "gemma2:9b"            # Gemma 2 9B - Fast, efficient model for autocomplete
  # Embedding models
  "nomic-embed-text"     # Nomic Embed Text - Best open embedding model
  # Rerank models
  "zerank-1"             # zerank-1 - Best open reranker
  "zerank-1-small"       # zerank-1-small - Smaller reranker
  # Next Edit
  "instinct"             # Instinct - Best open model for next edit predictions
)

# Hardware tier thresholds (RAM in GB)
readonly TIER_S_MIN=49
readonly TIER_A_MIN=33
readonly TIER_B_MIN=17

# Model resource estimates (RAM in GB) - Quantized variants for Apple Silicon
# Function to get model RAM (reflects Q4_K_M/Q5_K_M quantization)
get_model_ram() {
  local model="$1"
  case "$model" in
    # Agent Plan / Chat / Edit
    "devstral:27b") echo "14" ;;            # Q4_K_M: ~14GB
    "gpt-oss:20b") echo "10" ;;             # Q4_K_M: ~10GB
    "codestral") echo "5" ;;                 # Codestral: ~5GB (varies by quantization)
    # General purpose / Autocomplete
    "llama3.1:8b") echo "4.2" ;;            # Q5_K_M: ~4.2GB (was 5GB unquantized)
    "llama3.1:70b") echo "35" ;;            # Q4_K_M: ~35GB (was 40GB unquantized)
    "gemma2:9b") echo "5.5" ;;              # Gemma 2 9B: ~5.5GB (Q4_K_M quantized)
    # Embedding models (smaller)
    "nomic-embed-text") echo "0.3" ;;      # ~0.3GB
    # Rerank models (smaller)
    "zerank-1") echo "0.4" ;;              # ~0.4GB
    "zerank-1-small") echo "0.2" ;;         # ~0.2GB
    # Next Edit
    "instinct") echo "8" ;;                 # ~8GB (estimated)
    *) echo "0" ;;
  esac
}

# Function to get model description
get_model_desc() {
  local model="$1"
  case "$model" in
    # Agent Plan / Chat / Edit
    "devstral:27b") echo "Excellent for agent planning and reasoning" ;;
    "gpt-oss:20b") echo "Strong coding capabilities, good balance" ;;
    "codestral") echo "Excellent code generation, great for autocomplete" ;;
    # General purpose / Autocomplete
    "llama3.1:8b") echo "Fast general-purpose TypeScript assistant" ;;
    "llama3.1:70b") echo "Highest quality for complex refactoring (Tier S)" ;;
    "gemma2:9b") echo "Fast, efficient model for autocomplete and quick tasks" ;;
    # Embedding models
    "nomic-embed-text") echo "Best open embedding model for code indexing" ;;
    # Rerank models
    "zerank-1") echo "Best open reranker for search relevance" ;;
    "zerank-1-small") echo "Smaller reranker, faster processing" ;;
    # Next Edit
    "instinct") echo "Best open model for next edit predictions" ;;
    *) echo "No description" ;;
  esac
}
