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
# Based on Continue.dev recommendations: https://docs.continue.dev/customize/models#recommended-models
readonly APPROVED_MODELS=(
  # Agent Plan / Chat / Edit (Best open models)
  "qwen3-coder:30b"      # Qwen3 Coder 30B - Best for agent planning and complex coding
  "devstral:27b"         # Devstral 27B - Excellent for agent planning
  "gpt-oss:20b"          # gpt-oss 20B - Strong coding capabilities
  "qwen2.5-coder:14b"    # Qwen2.5-Coder 14B - Best balance for React/TS
  "codestral:22b"        # Codestral 22B - Excellent code generation
  # Autocomplete (Fast models)
  "qwen2.5-coder:7b"     # QwenCoder2.5 7B - Fast autocomplete
  "qwen2.5-coder:1.5b"   # QwenCoder2.5 1.5B - Ultra-fast autocomplete
  # General purpose
  "llama3.1:8b"          # Llama 3.1 8B - Fast general-purpose
  "llama3.1:70b"         # Llama 3.1 70B - Highest quality (Tier S only)
  # Embedding models
  "nomic-embed-text"     # Nomic Embed Text - Best open embedding model
  "qwen3-embedding"      # Qwen3 Embedding - Alternative embedding
  # Rerank models
  "zerank-1"             # zerank-1 - Best open reranker
  "zerank-1-small"       # zerank-1-small - Smaller reranker
  "qwen3-reranker"       # Qwen3 Reranker - Alternative reranker
  # Next Edit
  "instinct"             # Instinct - Best open model for next edit
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
    "qwen3-coder:30b") echo "15" ;;         # Q4_K_M: ~15GB
    "devstral:27b") echo "14" ;;            # Q4_K_M: ~14GB
    "gpt-oss:20b") echo "10" ;;             # Q4_K_M: ~10GB
    "qwen2.5-coder:14b") echo "7.5" ;;      # Q4_K_M: ~7.5GB (was 9GB unquantized)
    "codestral:22b") echo "11.5" ;;         # Q4_K_M: ~11.5GB (was 14GB unquantized)
    # Autocomplete
    "qwen2.5-coder:7b") echo "3.5" ;;       # Q5_K_M: ~3.5GB (was 4.5GB unquantized)
    "qwen2.5-coder:1.5b") echo "0.9" ;;     # Q5_K_M: ~0.9GB
    # General purpose
    "llama3.1:8b") echo "4.2" ;;            # Q5_K_M: ~4.2GB (was 5GB unquantized)
    "llama3.1:70b") echo "35" ;;            # Q4_K_M: ~35GB (was 40GB unquantized)
    # Embedding models (smaller)
    "nomic-embed-text") echo "0.3" ;;      # ~0.3GB
    "qwen3-embedding") echo "0.5" ;;        # ~0.5GB
    # Rerank models (smaller)
    "zerank-1") echo "0.4" ;;              # ~0.4GB
    "zerank-1-small") echo "0.2" ;;         # ~0.2GB
    "qwen3-reranker") echo "0.3" ;;         # ~0.3GB
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
    "qwen3-coder:30b") echo "Best open model for agent planning & complex coding" ;;
    "devstral:27b") echo "Excellent for agent planning and reasoning" ;;
    "gpt-oss:20b") echo "Strong coding capabilities, good balance" ;;
    "qwen2.5-coder:14b") echo "Best balance: quality + speed for React/TS" ;;
    "codestral:22b") echo "Excellent code generation for complex tasks" ;;
    # Autocomplete
    "qwen2.5-coder:7b") echo "Fast autocomplete & simple edits" ;;
    "qwen2.5-coder:1.5b") echo "Ultra-fast autocomplete (lightweight)" ;;
    # General purpose
    "llama3.1:8b") echo "Fast general-purpose TypeScript assistant" ;;
    "llama3.1:70b") echo "Highest quality for complex refactoring (Tier S)" ;;
    # Embedding models
    "nomic-embed-text") echo "Best open embedding model for code indexing" ;;
    "qwen3-embedding") echo "Alternative embedding model for semantic search" ;;
    # Rerank models
    "zerank-1") echo "Best open reranker for search relevance" ;;
    "zerank-1-small") echo "Smaller reranker, faster processing" ;;
    "qwen3-reranker") echo "Alternative reranker model" ;;
    # Next Edit
    "instinct") echo "Best open model for next edit predictions" ;;
    *) echo "No description" ;;
  esac
}
