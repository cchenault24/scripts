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

# Role-based model arrays (filtered from Ollama, excluding Chinese/Russian models)
# Based on Continue.dev recommendations: https://docs.continue.dev/customize/models#recommended-models
# All models listed here are available via Ollama

# Agent Plan / Chat / Edit models - For complex coding tasks, refactoring, and agent planning
readonly AGENT_CHAT_EDIT_MODELS=(
  "llama3.3:70b"         # 70B - Similar to Llama 3.1 405B
  "llama3.1:70b"         # 70B - Highest quality for complex refactoring
  "codestral:22b"        # 22B - Code generation
  "granite-code:20b"     # 20B - IBM Granite code model
  "starcoder2:15b"       # 15B - StarCoder2 code model
  "phi4:14b"             # 14B - State-of-the-art open model
  "llama3.1:8b"          # 8B - Fast general-purpose
  "codegemma:7b"         # 7B - CodeGemma code model
)

# Autocomplete models - Fast, lightweight models for real-time code suggestions
readonly AUTOCOMPLETE_MODELS=(
  "codestral:22b"        # 22B - Designed for code generation, excellent autocomplete
  "starcoder2:7b"        # 7B - StarCoder2 for autocomplete
  "codegemma:7b"         # 7B - CodeGemma for autocomplete
  "granite-code:8b"      # 8B - IBM Granite code model
  "llama3.1:8b"          # 8B - Fast general-purpose
  "starcoder2:3b"        # 3B - Small StarCoder2
  "llama3.2:3b"          # 3B - Small and fast
  "phi4:14b"             # 14B - State-of-the-art open model
)

# Embed models - For code indexing and semantic search
readonly EMBED_MODELS=(
  "nomic-embed-text"     # Best open embedding model, large token context window
  "mxbai-embed-large"    # State-of-the-art large embedding from mixedbread.ai
  "snowflake-arctic-embed2" # Frontier embedding, multilingual support
  "granite-embedding"    # IBM Granite, multilingual
  "all-minilm"           # Very small, sentence-level datasets
)

# Rerank models - For improving search relevance
readonly RERANK_MODELS=(
)

# Next Edit models - For predicting the next edit
readonly NEXT_EDIT_MODELS=(
  "llama3.3:70b"         # 70B - Similar to Llama 3.1 405B
  "granite-code:20b"     # 20B - IBM Granite code model
  "starcoder2:15b"       # 15B - StarCoder2 code model
  "phi4:14b"             # 14B - State-of-the-art open model
  "codestral:22b"        # 22B - Code generation
  "llama3.1:8b"          # 8B - Fast general-purpose
  "codegemma:7b"         # 7B - CodeGemma code model
  "starcoder2:7b"        # 7B - StarCoder2 code model
)

# Combined approved models array (for backward compatibility)
# Handle empty arrays safely for set -u compatibility
# Build array conditionally to avoid unbound variable errors with empty RERANK_MODELS
APPROVED_MODELS_TEMP=(
  "${AGENT_CHAT_EDIT_MODELS[@]}"
  "${AUTOCOMPLETE_MODELS[@]}"
  "${EMBED_MODELS[@]}"
)
# Only add RERANK_MODELS if it has elements
if [[ ${#RERANK_MODELS[@]} -gt 0 ]]; then
  APPROVED_MODELS_TEMP+=("${RERANK_MODELS[@]}")
fi
APPROVED_MODELS_TEMP+=("${NEXT_EDIT_MODELS[@]}")
readonly APPROVED_MODELS=("${APPROVED_MODELS_TEMP[@]}")
unset APPROVED_MODELS_TEMP

# Hardware tier thresholds (RAM in GB)
readonly TIER_S_MIN=49
readonly TIER_A_MIN=33
readonly TIER_B_MIN=17

# Model resource estimates (RAM in GB) - Quantized variants for Apple Silicon
# Function to get model RAM (reflects Q4_K_M/Q5_K_M quantization)
get_model_ram() {
  local model="$1"
  case "$model" in
    # Agent Plan / Chat / Edit - Large models (100B+)
    "devstral-2:123b") echo "60" ;;         # Q4_K_M: ~60GB
    "gpt-oss:120b") echo "55" ;;           # Q4_K_M: ~55GB
    # Agent Plan / Chat / Edit - Medium-large models (20-70B)
    "llama3.1:70b") echo "35" ;;          # Q4_K_M: ~35GB
    "llama3.3:70b") echo "35" ;;          # Q4_K_M: ~35GB
    "codestral:22b") echo "11" ;;        # Q4_K_M: ~11GB
    "granite-code:20b") echo "10" ;;    # Q4_K_M: ~10GB
    "starcoder2:15b") echo "7.5" ;;     # Q4_K_M: ~7.5GB
    # Agent Plan / Chat / Edit - Medium models (8-14B)
    "phi4:14b") echo "7" ;;              # Q4_K_M: ~7GB
    "llama3.1:8b") echo "4.2" ;;         # Q5_K_M: ~4.2GB
    "codegemma:7b") echo "3.5" ;;        # Q4_K_M: ~3.5GB
    # Autocomplete models
    "codestral:22b") echo "11" ;;       # Q4_K_M: ~11GB
    "starcoder2:7b") echo "3.5" ;;      # Q4_K_M: ~3.5GB
    "codegemma:7b") echo "3.5" ;;       # Q4_K_M: ~3.5GB
    "granite-code:8b") echo "4" ;;      # Q4_K_M: ~4GB
    "llama3.1:8b") echo "4.2" ;;        # Q5_K_M: ~4.2GB
    "starcoder2:3b") echo "1.5" ;;      # Q4_K_M: ~1.5GB
    "llama3.2:3b") echo "1.5" ;;        # Q4_K_M: ~1.5GB
    "phi4:14b") echo "7" ;;             # Q4_K_M: ~7GB
    # Embedding models
    "nomic-embed-text") echo "0.3" ;;  # ~0.3GB
    "mxbai-embed-large") echo "0.2" ;;  # ~0.2GB (varies by size)
    "snowflake-arctic-embed2") echo "0.3" ;; # ~0.3GB (varies by size)
    "granite-embedding") echo "0.17" ;; # ~0.17GB (varies by size)
    "all-minilm") echo "0.02" ;;        # ~0.02GB (varies by size)
    # Next Edit models
    "llama3.3:70b") echo "35" ;;        # Q4_K_M: ~35GB
    "granite-code:20b") echo "10" ;;    # Q4_K_M: ~10GB
    "starcoder2:15b") echo "7.5" ;;     # Q4_K_M: ~7.5GB
    "phi4:14b") echo "7" ;;             # Q4_K_M: ~7GB
    "codestral:22b") echo "11" ;;       # Q4_K_M: ~11GB
    "llama3.1:8b") echo "4.2" ;;        # Q5_K_M: ~4.2GB
    "codegemma:7b") echo "3.5" ;;       # Q4_K_M: ~3.5GB
    "starcoder2:7b") echo "3.5" ;;      # Q4_K_M: ~3.5GB
    # Legacy models (for backward compatibility)
    "devstral:27b") echo "14" ;;       # Q4_K_M: ~14GB
    "codestral") echo "5" ;;           # ~5GB (varies by quantization)
    "gemma2:9b") echo "5.5" ;;         # Q4_K_M: ~5.5GB
    *) echo "0" ;;
  esac
}

# Function to get model description
get_model_desc() {
  local model="$1"
  case "$model" in
    # Agent Plan / Chat / Edit - Large models
    "devstral-2:123b") echo "123B - Best for agent planning, tool use, codebase exploration" ;;
    "gpt-oss:120b") echo "120B - Powerful reasoning and agentic tasks (Tier S)" ;;
    # Agent Plan / Chat / Edit - Medium-large models
    "llama3.1:70b") echo "70B - Highest quality for complex refactoring (Tier S)" ;;
    "llama3.3:70b") echo "70B - Similar to Llama 3.1 405B (Tier S)" ;;
    "codestral:22b") echo "22B - Excellent code generation" ;;
    "granite-code:20b") echo "20B - IBM Granite code model" ;;
    "starcoder2:15b") echo "15B - StarCoder2 code model" ;;
    # Agent Plan / Chat / Edit - Medium models
    "phi4:14b") echo "14B - State-of-the-art open model" ;;
    "llama3.1:8b") echo "8B - Fast general-purpose TypeScript assistant" ;;
    "codegemma:7b") echo "7B - CodeGemma code model" ;;
    # Autocomplete models
    "codestral:22b") echo "22B - Designed for code generation, excellent autocomplete" ;;
    "starcoder2:7b") echo "7B - StarCoder2 for autocomplete" ;;
    "codegemma:7b") echo "7B - CodeGemma for autocomplete" ;;
    "granite-code:8b") echo "8B - IBM Granite code model" ;;
    "llama3.1:8b") echo "8B - Fast general-purpose for autocomplete" ;;
    "starcoder2:3b") echo "3B - Small StarCoder2" ;;
    "llama3.2:3b") echo "3B - Small and fast for autocomplete" ;;
    "phi4:14b") echo "14B - State-of-the-art open model" ;;
    # Embedding models
    "nomic-embed-text") echo "Best open embedding model for code indexing" ;;
    "mxbai-embed-large") echo "State-of-the-art large embedding from mixedbread.ai" ;;
    "snowflake-arctic-embed2") echo "Frontier embedding, multilingual support" ;;
    "granite-embedding") echo "IBM Granite, multilingual" ;;
    "all-minilm") echo "Very small, sentence-level datasets" ;;
    # Next Edit models
    "llama3.3:70b") echo "70B - Similar to Llama 3.1 405B" ;;
    "granite-code:20b") echo "20B - IBM Granite code model" ;;
    "starcoder2:15b") echo "15B - StarCoder2 code model" ;;
    "phi4:14b") echo "14B - State-of-the-art open model" ;;
    "codestral:22b") echo "22B - Code generation" ;;
    "llama3.1:8b") echo "8B - Fast general-purpose" ;;
    "codegemma:7b") echo "7B - CodeGemma code model" ;;
    "starcoder2:7b") echo "7B - StarCoder2 code model" ;;
    # Legacy models (for backward compatibility)
    "devstral:27b") echo "27B - Excellent for agent planning and reasoning" ;;
    "codestral") echo "Excellent code generation, great for autocomplete" ;;
    "gemma2:9b") echo "9B - Fast, efficient model for autocomplete and quick tasks" ;;
    *) echo "No description" ;;
  esac
}

# Function to get model role(s)
get_model_role() {
  local model="$1"
  local roles=()
  
  # Check Agent Plan/Chat/Edit models
  for m in "${AGENT_CHAT_EDIT_MODELS[@]}"; do
    if [[ "$m" == "$model" ]]; then
      roles+=("agent_chat_edit")
      break
    fi
  done
  
  # Check Autocomplete models
  for m in "${AUTOCOMPLETE_MODELS[@]}"; do
    if [[ "$m" == "$model" ]]; then
      roles+=("autocomplete")
      break
    fi
  done
  
  # Check Embed models
  for m in "${EMBED_MODELS[@]}"; do
    if [[ "$m" == "$model" ]]; then
      roles+=("embed")
      break
    fi
  done
  
  # Check Rerank models
  if [[ ${#RERANK_MODELS[@]} -gt 0 ]]; then
    for m in "${RERANK_MODELS[@]}"; do
      if [[ "$m" == "$model" ]]; then
        roles+=("rerank")
        break
      fi
    done
  fi
  
  # Check Next Edit models
  for m in "${NEXT_EDIT_MODELS[@]}"; do
    if [[ "$m" == "$model" ]]; then
      roles+=("next_edit")
      break
    fi
  done
  
  # Return roles as space-separated string (empty if no roles found)
  if [[ ${#roles[@]} -gt 0 ]]; then
    echo "${roles[*]}"
  fi
}

# Function to get models for a specific role
get_models_for_role() {
  local role="$1"
  case "$role" in
    "agent_chat_edit"|"agent"|"chat"|"edit")
      echo "${AGENT_CHAT_EDIT_MODELS[@]}" ;;
    "autocomplete")
      echo "${AUTOCOMPLETE_MODELS[@]}" ;;
    "embed")
      echo "${EMBED_MODELS[@]}" ;;
    "rerank")
      if [[ ${#RERANK_MODELS[@]} -gt 0 ]]; then
        echo "${RERANK_MODELS[@]}"
      fi
      ;;
    "next_edit"|"next")
      echo "${NEXT_EDIT_MODELS[@]}" ;;
    *)
      echo "" ;;
  esac
}

# Function to get default model for a role based on tier
# Recommendations are based on hardware tier eligibility:
# Tier S (≥49GB): All models including 70B
# Tier A (33-48GB): Models up to 22B (excludes 70B)
# Tier B (17-32GB): Models up to 20B (excludes 70B and 22B+)
# Tier C (<17GB): Models 8B and below only
get_default_model_for_role() {
  local role="$1"
  local tier="$2"
  
  case "$role" in
    "agent_chat_edit"|"agent"|"chat"|"edit")
      case "$tier" in
        S) 
          # Tier S: Best model - 70B
          echo "llama3.3:70b" ;;
        A) 
          # Tier A: Best available - 22B (codestral:22b is largest eligible)
          echo "codestral:22b" ;;
        B) 
          # Tier B: Best available - 20B (granite-code:20b is largest eligible, excludes 22B+)
          echo "granite-code:20b" ;;
        C) 
          # Tier C: Best available - 8B (largest eligible)
          echo "llama3.1:8b" ;;
        *) 
          echo "llama3.1:8b" ;;
      esac ;;
    "autocomplete")
      case "$tier" in
        S) 
          # Tier S: Best autocomplete - 22B
          echo "codestral:22b" ;;
        A) 
          # Tier A: Best autocomplete - 22B
          echo "codestral:22b" ;;
        B) 
          # Tier B: Best autocomplete - 14B phi4 (excludes 22B+, but allows 14B)
          echo "phi4:14b" ;;
        C) 
          # Tier C: Smallest/fastest - 3B
          echo "starcoder2:3b" ;;
        *) 
          echo "llama3.1:8b" ;;
      esac ;;
    "embed")
      # Embedding models are small and available for all tiers
      echo "nomic-embed-text" ;;
    "rerank")
      # No rerank models in current list
      echo "" ;;
    "next_edit"|"next")
      case "$tier" in
        S) 
          # Tier S: Best next edit - 70B
          echo "llama3.3:70b" ;;
        A) 
          # Tier A: Best next edit - 22B
          echo "codestral:22b" ;;
        B) 
          # Tier B: Best next edit - 15B (excludes 22B+)
          echo "starcoder2:15b" ;;
        C) 
          # Tier C: Best next edit - 8B
          echo "llama3.1:8b" ;;
        *) 
          echo "llama3.1:8b" ;;
      esac ;;
    *)
      echo "llama3.1:8b" ;;
  esac
}

# Calculate total RAM for selected models (accounting for duplicates)
# Models can be reused across roles, so we only count unique models
calculate_total_ram() {
  local models=("$@")
  local total_ram=0
  
  # Track unique models (same model can be used for multiple roles)
  local unique_models=()
  for model in "${models[@]}"; do
    if [[ -z "$model" ]]; then
      continue
    fi
    local found=0
    if [[ ${#unique_models[@]} -gt 0 ]]; then
      for existing in "${unique_models[@]}"; do
        if [[ "$model" == "$existing" ]]; then
          found=1
          break
        fi
      done
    fi
    [[ $found -eq 0 ]] && unique_models+=("$model")
  done
  
  # Sum RAM for unique models only
  if [[ ${#unique_models[@]} -gt 0 ]]; then
    for model in "${unique_models[@]}"; do
      local ram=$(get_model_ram "$model")
      # Use awk for floating point addition
      if command -v awk &>/dev/null && [[ "$ram" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        total_ram=$(echo "$total_ram $ram" | awk '{printf "%.1f", $1 + $2}')
      else
        # Fallback: convert to integers
        local ram_int=$(echo "$ram" | awk '{if ($1+0 == $1) printf "%.0f", $1; else print "0"}')
        local total_int=$(echo "$total_ram" | awk '{if ($1+0 == $1) printf "%.0f", $1; else print "0"}')
        total_ram=$((total_int + ram_int))
      fi
    done
  fi
  
  echo "$total_ram"
}

# Get maximum recommended RAM for a tier (leaves room for system)
get_tier_max_ram() {
  local tier="$1"
  case "$tier" in
    S) echo "45" ;;  # Leave ~4GB for system on 49GB+ systems
    A) echo "30" ;;  # Leave ~3GB for system on 33GB+ systems
    B) echo "14" ;;  # Leave ~3GB for system on 17GB+ systems
    C) echo "12" ;;  # Leave ~4GB for system on 16GB systems
    *) echo "12" ;;
  esac
}

# Get unique models from an array (remove duplicates)
get_unique_models() {
  local models=("$@")
  local unique_models=()
  
  for model in "${models[@]}"; do
    if [[ -z "$model" ]]; then
      continue
    fi
    local found=0
    if [[ ${#unique_models[@]} -gt 0 ]]; then
      for existing in "${unique_models[@]}"; do
        if [[ "$model" == "$existing" ]]; then
          found=1
          break
        fi
      done
    fi
    [[ $found -eq 0 ]] && unique_models+=("$model")
  done
  
  # Return space-separated string (empty if no unique models)
  if [[ ${#unique_models[@]} -gt 0 ]]; then
    echo "${unique_models[@]}"
  fi
}

# Check if a model can be used for multiple roles
can_model_serve_role() {
  local model="$1"
  local role="$2"
  
  local model_roles=$(get_model_role "$model")
  case "$role" in
    "agent_chat_edit"|"agent"|"chat"|"edit")
      [[ "$model_roles" == *"agent_chat_edit"* ]] && return 0 ;;
    "autocomplete")
      [[ "$model_roles" == *"autocomplete"* ]] && return 0 ;;
    "embed")
      [[ "$model_roles" == *"embed"* ]] && return 0 ;;
    "rerank")
      [[ "$model_roles" == *"rerank"* ]] && return 0 ;;
    "next_edit"|"next")
      [[ "$model_roles" == *"next_edit"* ]] && return 0 ;;
  esac
  return 1
}
