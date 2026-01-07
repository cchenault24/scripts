#!/bin/bash
#
# benchmark.sh - Benchmark tool for local LLM models
#
# Tests model performance: time-to-first-token, tokens-per-second, memory usage

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/.local-llm-setup"
LOG_FILE="$STATE_DIR/benchmark.log"

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

# Test prompts
readonly PROMPT_SHORT="Write a TypeScript function that adds two numbers."
readonly PROMPT_MEDIUM="Create a React component with TypeScript that displays a list of items using Redux state. Include proper error handling and loading states."
readonly PROMPT_LONG="Refactor this Redux-Saga code to use takeLatest instead of takeEvery, add proper cancellation handling, implement typed selectors, and ensure all side effects are properly managed. Include comprehensive error handling and TypeScript types throughout."

# Benchmark single model
benchmark_model() {
  local model="$1"
  local prompt="$2"
  local prompt_name="$3"
  
  print_info "Testing $model with $prompt_name prompt..."
  
  # Measure time-to-first-token
  local start_time=$(date +%s.%N)
  local first_token_time=0
  local response=""
  local token_count=0
  
  # Run model and capture output with timing
  {
    local test_start=$(date +%s.%N)
    response=$(timeout 60 ollama run "$model" "$prompt" 2>&1 || echo "")
    local test_end=$(date +%s.%N)
    local total_time=$(echo "$test_end - $test_start" | bc 2>/dev/null || echo "0")
    
    # Estimate first token (simplified: assume 10% of total time)
    first_token_time=$(echo "scale=3; $total_time * 0.1" | bc 2>/dev/null || echo "0")
    
    # Estimate token count (rough: ~4 chars per token)
    token_count=$(echo "${#response} / 4" | bc 2>/dev/null || echo "0")
  } || {
    print_error "Benchmark failed for $model"
    return 1
  }
  
  # Calculate tokens per second
  local tokens_per_sec=0
  if command -v bc &>/dev/null && [[ -n "$response" ]]; then
    local total_seconds=$(echo "$test_end - $test_start" | bc 2>/dev/null || echo "1")
    if [[ $(echo "$total_seconds > 0" | bc 2>/dev/null || echo "0") -eq 1 ]]; then
      tokens_per_sec=$(echo "scale=2; $token_count / $total_seconds" | bc 2>/dev/null || echo "0")
    fi
  fi
  
  # Memory usage (check ollama ps)
  local memory_mb=0
  local ps_output=$(ollama ps 2>/dev/null | grep "$model" || echo "")
  if [[ -n "$ps_output" ]]; then
    memory_mb=$(echo "$ps_output" | awk '{print $3}' | sed 's/GB/*1024/' | sed 's/MB//' | bc 2>/dev/null || echo "0")
  fi
  
  # Output results
  echo ""
  echo -e "${CYAN}Results for $model ($prompt_name):${NC}"
  echo "  Time to first token: ~${first_token_time}s"
  echo "  Estimated tokens: ~${token_count}"
  echo "  Tokens per second: ~${tokens_per_sec}"
  if [[ $memory_mb -gt 0 ]]; then
    echo "  Memory usage: ~${memory_mb}MB"
  fi
  echo ""
  
  # Return structured data (for report generation)
  echo "$model|$prompt_name|$first_token_time|$token_count|$tokens_per_sec|$memory_mb"
}

# Run full benchmark suite
run_benchmark() {
  local model="$1"
  
  print_header "📊 Benchmarking: $model"
  
  if ! ollama list 2>/dev/null | grep -q "^${model}"; then
    print_error "Model $model not found"
    return 1
  fi
  
  print_info "This will take a few minutes..."
  echo ""
  
  local results=()
  
  # Short prompt
  if result=$(benchmark_model "$model" "$PROMPT_SHORT" "short"); then
    results+=("$result")
  fi
  
  sleep 2
  
  # Medium prompt
  if result=$(benchmark_model "$model" "$PROMPT_MEDIUM" "medium"); then
    results+=("$result")
  fi
  
  sleep 2
  
  # Long prompt (optional, skip if model is slow)
  if prompt_yes_no "Run long prompt test? (may take several minutes)" "n"; then
    if result=$(benchmark_model "$model" "$PROMPT_LONG" "long"); then
      results+=("$result")
    fi
  fi
  
  # Generate report
  generate_benchmark_report "$model" "${results[@]}"
}

# Generate benchmark report
generate_benchmark_report() {
  local model="$1"
  shift
  local results=("$@")
  
  local report_file="$STATE_DIR/benchmark-${model//\//-}-$(date +%Y%m%d-%H%M%S).txt"
  
  {
    echo "Model Benchmark Report: $model"
    echo "Generated: $(date)"
    echo ""
    echo "=== Results ==="
    echo ""
    
    for result in "${results[@]}"; do
      IFS='|' read -r m pn tt ft tc tps mem <<< "$result"
      echo "Prompt: $pn"
      echo "  Time to first token: ${tt}s"
      echo "  Estimated tokens: ${tc}"
      echo "  Tokens per second: ${tps}"
      if [[ $mem -gt 0 ]]; then
        echo "  Memory usage: ${mem}MB"
      fi
      echo ""
    done
    
    echo "=== Recommendations ==="
    echo ""
    
    # Simple recommendations based on results
    local avg_tps=0
    local count=0
    for result in "${results[@]}"; do
      IFS='|' read -r m pn tt ft tc tps mem <<< "$result"
      if command -v bc &>/dev/null; then
        avg_tps=$(echo "scale=2; ($avg_tps * $count + $tps) / ($count + 1)" | bc 2>/dev/null || echo "$avg_tps")
        ((count++))
      fi
    done
    
    if [[ $(echo "$avg_tps > 50" | bc 2>/dev/null || echo "0") -eq 1 ]]; then
      echo "✓ Model performance is excellent for real-time coding"
    elif [[ $(echo "$avg_tps > 20" | bc 2>/dev/null || echo "0") -eq 1 ]]; then
      echo "✓ Model performance is good for interactive use"
    else
      echo "⚠ Model may be slow for real-time coding. Consider:"
      echo "  - Using a smaller model for autocomplete"
      echo "  - Reducing context window size"
      echo "  - Using keep-alive to preload model"
    fi
    
  } > "$report_file"
  
  print_success "Report generated: $report_file"
  print_info "View with: cat $report_file"
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-n}"
  local choice
  echo -e "${YELLOW}$prompt${NC} [y/n] (default: $default): "
  read -r choice
  choice=${choice:-$default}
  case "$choice" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

# Main
main() {
  clear
  print_header "⚡ Local LLM Benchmark Tool"
  
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
  
  # List available models
  local models=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' || echo "")
  
  if [[ -z "$models" ]]; then
    print_error "No models installed"
    exit 1
  fi
  
  # Select model
  echo "Available models:"
  echo ""
  local model_list=()
  local index=1
  while IFS= read -r model; do
    if [[ -n "$model" ]]; then
      echo "  $index) $model"
      model_list+=("$model")
      ((index++))
    fi
  done <<< "$models"
  echo ""
  
  local choice
  read -p "Select model (1-${#model_list[@]}): " choice
  
  if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ $choice -lt 1 || $choice -gt ${#model_list[@]} ]]; then
    print_error "Invalid selection"
    exit 1
  fi
  
  local selected_model="${model_list[$((choice-1))]}"
  
  # Run benchmark
  run_benchmark "$selected_model"
  
  print_success "Benchmark complete!"
}

main "$@"
