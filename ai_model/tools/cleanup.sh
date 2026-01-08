#!/bin/bash
#
# cleanup.sh - Memory cleanup utility for local LLM models
#
# Unloads models from memory to free up RAM and prevent memory warnings

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/.local-llm-setup"
LOG_FILE="$STATE_DIR/cleanup.log"

# Colors
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

print_header() {
  echo ""
  echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${CYAN}$1${NC}"
  echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo ""
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
  echo -e "${BLUE}ℹ $1${NC}"
}

print_warn() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
  echo -e "${RED}✗ $1${NC}"
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-n}"
  local choice
  while true; do
    echo -e "${YELLOW}$prompt${NC} [y/n] (default: $default): "
    read -r choice
    choice=${choice:-$default}
    case "$choice" in
      [Yy]|[Yy][Ee][Ss]) return 0 ;;
      [Nn]|[Nn][Oo]) return 1 ;;
      *) echo "Please answer yes or no." ;;
    esac
  done
}

# Get memory usage (macOS)
get_memory_info() {
  if [[ "$(uname)" == "Darwin" ]]; then
    local vm_stat_output
    vm_stat_output=$(vm_stat 2>/dev/null || echo "")
    if [[ -n "$vm_stat_output" ]]; then
      local free_pages
      free_pages=$(echo "$vm_stat_output" | grep "Pages free" | awk '{print $3}' | sed 's/\.//' || echo "0")
      local page_size
      page_size=$(pagesize 2>/dev/null || echo "4096")
      if [[ -n "$free_pages" ]] && [[ "$free_pages" =~ ^[0-9]+$ ]]; then
        local free_mb
        free_mb=$((free_pages * page_size / 1024 / 1024))
        echo "$free_mb"
      else
        echo "0"
      fi
    else
      echo "0"
    fi
  else
    echo "0"
  fi
}

# Unload model from memory using Ollama API
unload_model() {
  local model="$1"
  local silent="${2:-0}"  # Optional: 1 for silent mode
  
  # Check if model is actually loaded
  if ! ollama ps 2>/dev/null | grep -q "^${model}"; then
    return 0  # Model not loaded, nothing to do
  fi
  
  if [[ $silent -eq 0 ]]; then
    print_info "Unloading $model from memory..."
  fi
  
  # Use Ollama API to unload the model by setting keep_alive to 0
  # This is the proper way to unload a model according to Ollama docs
  local api_response
  api_response=$(curl -s --max-time 10 -X POST http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"$model\", \"prompt\": \"\", \"keep_alive\": 0}" 2>/dev/null || echo "")
  
  # Wait for the model to unload (Ollama needs a moment)
  sleep 3
  
  # Retry if still loaded (sometimes takes a moment)
  local retries=0
  while [[ $retries -lt 3 ]] && ollama ps 2>/dev/null | grep -q "^${model}"; do
    sleep 1
    ((retries++))
    # Try again with a minimal request
    curl -s --max-time 5 -X POST http://localhost:11434/api/generate \
      -H "Content-Type: application/json" \
      -d "{\"model\": \"$model\", \"prompt\": \"\", \"keep_alive\": 0}" >/dev/null 2>&1 || true
  done
  
  # Verify model is unloaded
  if ollama ps 2>/dev/null | grep -q "^${model}"; then
    if [[ $silent -eq 0 ]]; then
      print_warn "Model $model may still be in memory"
    fi
    return 1
  else
    if [[ $silent -eq 0 ]]; then
      print_success "Model $model unloaded"
    fi
    return 0
  fi
}

# Unload all models from memory
unload_all_models() {
  local loaded_models
  loaded_models=$(ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}' || echo "")
  
  if [[ -z "$loaded_models" ]]; then
    return 0  # No models loaded
  fi
  
  print_info "Unloading all models from memory..."
  
  while IFS= read -r model; do
    if [[ -n "$model" ]]; then
      unload_model "$model" 0  # Verbose mode
    fi
  done <<< "$loaded_models"
  
  # Final check
  sleep 2
  local remaining
  remaining=$(ollama ps 2>/dev/null | tail -n +2 | wc -l | xargs || echo "0")
  if [[ $remaining -eq 0 ]]; then
    print_success "All models unloaded"
    return 0
  else
    print_warn "$remaining model(s) may still be in memory"
    return 1
  fi
}

# List loaded models with memory usage
list_loaded_models() {
  local loaded_models
  loaded_models=$(ollama ps 2>/dev/null | tail -n +2 || echo "")
  
  if [[ -z "$loaded_models" ]]; then
    print_info "No models currently loaded in memory"
    return 1
  fi
  
  echo ""
  echo "Currently loaded models:"
  echo "$loaded_models" | while IFS= read -r line; do
    if [[ -n "$line" ]]; then
      echo "  • $line"
    fi
  done
  echo ""
  return 0
}

# Main cleanup flow
main() {
  clear
  print_header "🧹 Memory Cleanup Utility"
  
  # Check Ollama
  if ! command -v ollama &>/dev/null; then
    print_error "Ollama not found"
    exit 1
  fi
  
  if ! curl -s http://localhost:11434/api/tags &>/dev/null; then
    print_error "Ollama service is not running"
    print_info "Start with: brew services start ollama"
    exit 1
  fi
  
  # Show memory before cleanup
  local mem_before
  mem_before=$(get_memory_info)
  if [[ "$mem_before" != "0" ]]; then
    print_info "Available memory before cleanup: ~${mem_before}MB"
  fi
  
  # List loaded models
  if ! list_loaded_models; then
    print_success "No cleanup needed - no models are loaded"
    exit 0
  fi
  
  # Ask what to do
  echo ""
  echo "Options:"
  echo "  1) Unload all models"
  echo "  2) Unload specific model"
  echo "  3) Cancel"
  echo ""
  
  local choice
  read -p "Select option (1-3): " choice || choice="3"
  
  case "$choice" in
    1)
      echo ""
      if prompt_yes_no "Unload all models from memory?" "y"; then
        if unload_all_models; then
          # Show memory after cleanup
          sleep 2
          local mem_after
          mem_after=$(get_memory_info)
          if [[ "$mem_after" != "0" ]] && [[ "$mem_before" != "0" ]]; then
            local mem_freed
            mem_freed=$((mem_after - mem_before))
            if [[ $mem_freed -gt 0 ]]; then
              print_success "Freed approximately ${mem_freed}MB of memory"
            fi
            print_info "Available memory after cleanup: ~${mem_after}MB"
          fi
        fi
      else
        print_info "Cleanup cancelled"
      fi
      ;;
    2)
      # Get list of loaded models
      local models_list
      models_list=$(ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}' || echo "")
      
      if [[ -z "$models_list" ]]; then
        print_warn "No models loaded"
        exit 0
      fi
      
      echo ""
      echo "Select model to unload:"
      local index=1
      local model_array=()
      while IFS= read -r model; do
        if [[ -n "$model" ]]; then
          echo "  $index) $model"
          model_array+=("$model")
          ((index++))
        fi
      done <<< "$models_list"
      echo ""
      
      local model_choice
      read -p "Select model (1-$((index-1))): " model_choice || model_choice=""
      
      if [[ -n "$model_choice" ]] && [[ "$model_choice" =~ ^[0-9]+$ ]] && [[ $model_choice -ge 1 ]] && [[ $model_choice -lt $index ]]; then
        local selected_model="${model_array[$((model_choice-1))]}"
        if unload_model "$selected_model" 0; then
          print_success "Model $selected_model unloaded"
        fi
      else
        print_error "Invalid selection"
      fi
      ;;
    3)
      print_info "Cleanup cancelled"
      exit 0
      ;;
    *)
      print_error "Invalid option"
      exit 1
      ;;
  esac
  
  echo ""
  print_success "Cleanup complete!"
}

main "$@"
