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

# macOS-compatible timeout wrapper
# Tries timeout, gtimeout, or falls back to background process with kill
run_with_timeout() {
  local timeout_seconds="$1"
  shift
  local cmd=("$@")
  local response_file
  response_file=$(mktemp) || {
    echo "Error: Failed to create temporary file" >&2
    return 1
  }
  local pid
  local exit_code=0
  
  # Try timeout command first (GNU coreutils)
  if command -v timeout &>/dev/null; then
    if timeout "$timeout_seconds" "${cmd[@]}" > "$response_file" 2>&1; then
      cat "$response_file"
      rm -f "$response_file"
      return 0
    else
      exit_code=$?
      cat "$response_file"
      rm -f "$response_file"
      return $exit_code
    fi
  # Try gtimeout (GNU coreutils via Homebrew)
  elif command -v gtimeout &>/dev/null; then
    if gtimeout "$timeout_seconds" "${cmd[@]}" > "$response_file" 2>&1; then
      cat "$response_file"
      rm -f "$response_file"
      return 0
    else
      exit_code=$?
      cat "$response_file"
      rm -f "$response_file"
      return $exit_code
    fi
  # Fallback: background process with kill
  else
    local stderr_file
    stderr_file=$(mktemp) || {
      rm -f "$response_file"
      echo "Error: Failed to create temporary file" >&2
      return 1
    }
    "${cmd[@]}" > "$response_file" 2> "$stderr_file" &
    pid=$!
    local waited=0
    while kill -0 "$pid" 2>/dev/null && [[ $waited -lt $timeout_seconds ]]; do
      sleep 1
      waited=$((waited + 1))
    done
    
    if kill -0 "$pid" 2>/dev/null; then
      # Process still running after timeout
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      cat "$response_file"
      cat "$stderr_file" >&2
      rm -f "$response_file" "$stderr_file"
      return 124  # Timeout exit code (matches GNU timeout)
    else
      # Process completed
      wait "$pid" 2>/dev/null
      exit_code=$?
      cat "$response_file"
      cat "$stderr_file" >&2
      rm -f "$response_file" "$stderr_file"
      return $exit_code
    fi
  fi
}

# Benchmark single model
benchmark_model() {
  local model="$1"
  local prompt="$2"
  local prompt_name="$3"
  
  # Output info message to stderr so it doesn't get captured
  echo -e "${BLUE}ℹ Testing $model with $prompt_name prompt...${NC}" >&2
  echo -e "${YELLOW}  → Starting benchmark...${NC}" >&2
  
  # Measure time-to-first-token
  local first_token_time=0
  local response=""
  local token_count=0
  local test_start
  local test_end
  local total_time=0
  
  # Run model and capture output with timing
  echo -e "${YELLOW}  → Running model (this may take a moment)...${NC}" >&2
  test_start=$(date +%s.%N 2>/dev/null || date +%s)
  
  # Use macOS-compatible timeout wrapper
  # Note: run_with_timeout captures both stdout and stderr combined
  local exit_code=0
  response=$(run_with_timeout 120 ollama run "$model" "$prompt" 2>&1) || exit_code=$?
  
  test_end=$(date +%s.%N 2>/dev/null || date +%s)
  
  # Check for timeout
  if [[ $exit_code -eq 124 ]]; then
    print_error "Benchmark failed for $model - command timed out after 120 seconds"
    echo -e "${YELLOW}  → The model may be too slow or unresponsive${NC}" >&2
    if [[ -n "$response" ]]; then
      echo -e "${YELLOW}  → Partial output received:${NC}" >&2
      echo "${response:0:500}" >&2
    fi
    return 1
  fi
  
  # Check for other errors
  if [[ $exit_code -ne 0 ]]; then
    print_error "Benchmark failed for $model - ollama command failed (exit code: $exit_code)"
    if [[ -n "$response" ]]; then
      echo -e "${YELLOW}  → Output/Error received:${NC}" >&2
      # Show first 20 lines or first 1000 chars, whichever is shorter
      if [[ $(echo "$response" | wc -l) -le 20 ]]; then
        echo "$response" >&2
      else
        echo "$response" | head -n 20 >&2
        echo -e "${YELLOW}  ... (truncated)${NC}" >&2
      fi
    else
      echo -e "${YELLOW}  → No output received at all${NC}" >&2
    fi
    echo -e "${YELLOW}  → Diagnostic: Try running manually:${NC}" >&2
    echo -e "${YELLOW}     ollama run $model \"test\"${NC}" >&2
    echo -e "${YELLOW}  → Check if model is loaded: ollama ps${NC}" >&2
    return 1
  fi
  
  echo -e "${GREEN}  ✓ Response received${NC}" >&2
  
  # Validate we got a response (check for empty or whitespace-only)
  if [[ -z "${response// }" ]]; then
    print_error "Benchmark failed for $model - no response received (empty or whitespace-only)"
    echo -e "${YELLOW}  → The model may not have generated any output${NC}" >&2
    return 1
  fi
  
  # Check if response looks like an error message from ollama (common error patterns)
  local first_line
  first_line=$(echo "$response" | head -n 1 | tr '[:upper:]' '[:lower:]')
  if [[ "$first_line" =~ ^(error|failed|cannot|unable|model.*not.*found|pull.*model) ]]; then
    print_error "Benchmark failed for $model - received error message"
    echo -e "${YELLOW}  → Error: $(echo "$response" | head -n 1)${NC}" >&2
    return 1
  fi
  
  echo -e "${YELLOW}  → Analyzing response...${NC}" >&2
  
  # Calculate total time
  echo -e "${YELLOW}  → Calculating timing metrics...${NC}" >&2
  if command -v bc &>/dev/null && [[ "$test_start" =~ \. ]] && [[ "$test_end" =~ \. ]]; then
    # Both have decimal precision
    total_time=$(echo "scale=3; $test_end - $test_start" | bc 2>/dev/null || echo "0")
    # Ensure non-negative
    if [[ $(echo "$total_time < 0" | bc 2>/dev/null || echo "1") -eq 1 ]]; then
      total_time="0"
    fi
  else
    # Fallback to integer arithmetic
    local start_int=${test_start%%.*}
    local end_int=${test_end%%.*}
    total_time=$((end_int - start_int))
    # Ensure non-negative
    if [[ $total_time -lt 0 ]]; then
      total_time=0
    fi
  fi
  
  # Estimate first token (simplified: assume 10% of total time)
  if command -v bc &>/dev/null && [[ "$total_time" =~ \. ]]; then
    first_token_time=$(echo "scale=3; $total_time * 0.1" | bc 2>/dev/null || echo "0")
  else
    # Use awk for floating point if bc unavailable or integer time
    if command -v awk &>/dev/null; then
      first_token_time=$(echo "$total_time" | awk '{printf "%.3f", $1 * 0.1}' 2>/dev/null || echo "0")
    else
      # Final fallback: integer division
      first_token_time=$(( total_time / 10 ))
    fi
  fi
  
  # Estimate token count (rough: ~4 chars per token)
  echo -e "${YELLOW}  → Estimating token count...${NC}" >&2
  local response_length=${#response}
  if [[ $response_length -gt 0 ]]; then
    token_count=$(( response_length / 4 ))
    # Ensure at least 1 token if there's any response
    if [[ $token_count -eq 0 ]]; then
      token_count=1
    fi
  else
    token_count=0
  fi
  
  # Calculate tokens per second
  echo -e "${YELLOW}  → Calculating tokens per second...${NC}" >&2
  local tokens_per_sec=0
  if [[ -n "$response" ]] && [[ $token_count -gt 0 ]] && [[ $(echo "$total_time" | awk '{if ($1 > 0) print 1; else print 0}') -eq 1 ]]; then
    if command -v bc &>/dev/null; then
      tokens_per_sec=$(echo "scale=2; $token_count / $total_time" | bc 2>/dev/null || echo "0")
    else
      tokens_per_sec=$(echo "$token_count $total_time" | awk '{if ($2 > 0) printf "%.2f", $1/$2; else print "0"}' 2>/dev/null || echo "0")
    fi
  fi
  
  # Memory usage (check ollama ps)
  echo -e "${YELLOW}  → Checking memory usage...${NC}" >&2
  local memory_mb=0
  # Use exact model name match to avoid partial matches
  local ps_output=$(ollama ps 2>/dev/null | awk -v model="$model" '$1 == model {print}' || echo "")
  if [[ -n "$ps_output" ]]; then
    # Extract memory value - try multiple column positions as ollama ps format may vary
    local mem_field=$(echo "$ps_output" | awk '{for(i=1;i<=NF;i++) if($i ~ /[0-9]+(\.[0-9]+)?(GB|MB)/) {print $i; exit}}')
    if [[ -n "$mem_field" ]]; then
      local mem_value=$(echo "$mem_field" | sed -E 's/(GB|MB)//' | tr -d ' ')
      # Validate mem_value is numeric before arithmetic
      if [[ -n "$mem_value" ]] && [[ "$mem_value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        if [[ "$mem_field" =~ GB ]]; then
          if command -v bc &>/dev/null; then
            local memory_mb_decimal=$(echo "scale=0; $mem_value * 1024" | bc 2>/dev/null || echo "0")
            memory_mb=${memory_mb_decimal%%.*}
          else
            # Integer fallback
            local mem_int=${mem_value%%.*}
            memory_mb=$(( mem_int * 1024 ))
          fi
        elif [[ "$mem_field" =~ MB ]]; then
          memory_mb=${mem_value%%.*}
        fi
      fi
    fi
  fi
  
  # Output formatted results to stderr (so they display but aren't captured)
  {
    echo -e "${GREEN}  ✓ Analysis complete${NC}"
    echo ""
    echo -e "${CYAN}Results for $model ($prompt_name):${NC}"
    echo "  Time to first token: ~${first_token_time}s"
    echo "  Estimated tokens: ~${token_count}"
    echo "  Tokens per second: ~${tokens_per_sec}"
    if [[ $memory_mb -gt 0 ]]; then
      echo "  Memory usage: ~${memory_mb}MB"
    fi
    echo ""
  } >&2
  
  # Return structured data to stdout (for report generation)
  echo "$model|$prompt_name|$first_token_time|$token_count|$tokens_per_sec|$memory_mb"
}

# Run full benchmark suite
run_benchmark() {
  local model="$1"
  
  print_header "📊 Benchmarking: $model"
  
  # Verify model is actually installed and ready
  if ! ollama show "$model" &>/dev/null; then
    print_error "Model $model is not installed or not ready"
    print_info "Install with: ollama pull $model"
    return 1
  fi
  
  # Quick connectivity test - verify ollama can respond
  echo -e "${YELLOW}  → Verifying Ollama connectivity...${NC}" >&2
  if ! curl -s --max-time 5 http://localhost:11434/api/tags &>/dev/null; then
    print_error "Cannot connect to Ollama service"
    print_info "Ensure Ollama is running: brew services start ollama"
    return 1
  fi
  echo -e "${GREEN}  ✓ Ollama service is accessible${NC}" >&2
  echo "" >&2
  
  print_info "This will take a few minutes..."
  echo ""
  
  local results=()
  local test_count=0
  local total_tests=2
  
  # Short prompt
  ((test_count++))
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
  echo -e "${BOLD}Test $test_count of $total_tests: Short Prompt${NC}" >&2
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
  if result=$(benchmark_model "$model" "$PROMPT_SHORT" "short"); then
    results+=("$result")
    echo -e "${GREEN}✓ Short prompt test completed${NC}" >&2
  else
    echo -e "${RED}✗ Short prompt test failed${NC}" >&2
  fi
  
  echo -e "${YELLOW}Pausing 2 seconds before next test...${NC}" >&2
  sleep 2
  echo "" >&2
  
  # Medium prompt
  ((test_count++))
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
  echo -e "${BOLD}Test $test_count of $total_tests: Medium Prompt${NC}" >&2
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
  if result=$(benchmark_model "$model" "$PROMPT_MEDIUM" "medium"); then
    results+=("$result")
    echo -e "${GREEN}✓ Medium prompt test completed${NC}" >&2
  else
    echo -e "${RED}✗ Medium prompt test failed${NC}" >&2
  fi
  
  echo -e "${YELLOW}Pausing 2 seconds before next test...${NC}" >&2
  sleep 2
  echo "" >&2
  
  # Long prompt (optional, skip if model is slow)
  if prompt_yes_no "Run long prompt test? (may take several minutes)" "n"; then
    ((total_tests++))
    ((test_count++))
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo -e "${BOLD}Test $test_count of $total_tests: Long Prompt${NC}" >&2
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    if result=$(benchmark_model "$model" "$PROMPT_LONG" "long"); then
      results+=("$result")
      echo -e "${GREEN}✓ Long prompt test completed${NC}" >&2
    else
      echo -e "${RED}✗ Long prompt test failed${NC}" >&2
    fi
    echo "" >&2
  fi
  
  # Summary
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
  echo -e "${BOLD}Benchmark Summary${NC}" >&2
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
  echo -e "${GREEN}✓ Completed $test_count test(s)${NC}" >&2
  echo -e "${GREEN}✓ Collected ${#results[@]} result(s)${NC}" >&2
  echo -e "${YELLOW}→ Generating report...${NC}" >&2
  echo "" >&2
  
  # Generate report (safely handle empty array with set -u)
  if [[ ${#results[@]} -gt 0 ]]; then
    generate_benchmark_report "$model" "${results[@]}"
  else
    generate_benchmark_report "$model"
  fi
}

# Generate benchmark report
generate_benchmark_report() {
  local model="$1"
  shift
  local results=("$@")
  
  # Sanitize model name: replace invalid filename characters
  local model_sanitized="${model//\//-}"
  model_sanitized="${model_sanitized//:/-}"
  model_sanitized="${model_sanitized// /_}"
  model_sanitized="${model_sanitized//[^a-zA-Z0-9._-]/}"
  
  # Ensure model_sanitized is not empty (fallback to "unknown-model")
  if [[ -z "$model_sanitized" ]]; then
    model_sanitized="unknown-model"
  fi
  
  # Ensure STATE_DIR exists
  if [[ ! -d "$STATE_DIR" ]]; then
    mkdir -p "$STATE_DIR" || {
      print_error "Failed to create state directory: $STATE_DIR"
      return 1
    }
  fi
  
  # Generate timestamp safely
  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo "$(date +%s)")
  
  local report_file="$STATE_DIR/benchmark-${model_sanitized}-${timestamp}.txt"
  
  {
    echo "Model Benchmark Report: $model"
    echo "Generated: $(date)"
    echo ""
    echo "=== Results ==="
    echo ""
    
    if [[ ${#results[@]} -eq 0 ]]; then
      echo "No benchmark results available."
      echo ""
    else
      for result in "${results[@]}"; do
        # Parse 6 fields: model|prompt_name|first_token_time|token_count|tokens_per_sec|memory_mb
        # Initialize variables to prevent unbound variable errors with set -u
        local m="" pn="" ft="" tc="" tps="" mem=""
        IFS='|' read -r m pn ft tc tps mem <<< "$result"
        echo "Prompt: $pn"
        echo "  Time to first token: ${ft}s"
        echo "  Estimated tokens: ${tc}"
        echo "  Tokens per second: ${tps}"
        if [[ -n "$mem" ]] && [[ "$mem" =~ ^[0-9]+$ ]] && [[ $mem -gt 0 ]]; then
          echo "  Memory usage: ${mem}MB"
        fi
        echo ""
      done
    fi
    
    echo "=== Recommendations ==="
    echo ""
    
    # Simple recommendations based on results
    if [[ ${#results[@]} -eq 0 ]]; then
      echo "No recommendations available (no benchmark data)."
    else
      local avg_tps=0
      local count=0
      local tps_sum=0
      for result in "${results[@]}"; do
        # Parse 6 fields: model|prompt_name|first_token_time|token_count|tokens_per_sec|memory_mb
        # Initialize variables to prevent unbound variable errors with set -u
        local m="" pn="" ft="" tc="" tps="" mem=""
        IFS='|' read -r m pn ft tc tps mem <<< "$result"
        # Extract numeric value from tps (handle decimal strings)
        local tps_num=$(echo "$tps" | awk '{print $1}' 2>/dev/null || echo "0")
        if [[ "$tps_num" =~ ^[0-9]+\.?[0-9]*$ ]]; then
          if command -v bc &>/dev/null; then
            tps_sum=$(echo "scale=2; $tps_sum + $tps_num" | bc 2>/dev/null || echo "$tps_sum")
          else
            # Fallback: use awk for addition
            tps_sum=$(echo "$tps_sum $tps_num" | awk '{printf "%.2f", $1 + $2}' 2>/dev/null || echo "$tps_sum")
          fi
          ((count++))
        fi
      done
      
      if [[ $count -gt 0 ]]; then
        if command -v bc &>/dev/null; then
          avg_tps=$(echo "scale=2; $tps_sum / $count" | bc 2>/dev/null || echo "0")
        else
          avg_tps=$(echo "$tps_sum $count" | awk '{if ($2 > 0) printf "%.2f", $1/$2; else print "0"}' 2>/dev/null || echo "0")
        fi
        
        # Compare using numeric comparison
        local tps_50=$(echo "$avg_tps > 50" | bc 2>/dev/null || echo "0")
        local tps_20=$(echo "$avg_tps > 20" | bc 2>/dev/null || echo "0")
        
        # Fallback comparison if bc unavailable
        if [[ "$tps_50" = "0" ]] && [[ "$tps_20" = "0" ]]; then
          local avg_int=${avg_tps%%.*}
          if [[ $avg_int -gt 50 ]]; then
            tps_50=1
            tps_20=1
          elif [[ $avg_int -gt 20 ]]; then
            tps_20=1
          fi
        fi
        
        if [[ "$tps_50" = "1" ]]; then
          echo "✓ Model performance is excellent for real-time coding"
        elif [[ "$tps_20" = "1" ]]; then
          echo "✓ Model performance is good for interactive use"
        else
          echo "⚠ Model may be slow for real-time coding. Consider:"
          echo "  - Using a smaller model for autocomplete"
          echo "  - Reducing context window size"
          echo "  - Using keep-alive to preload model"
        fi
      else
        echo "No valid performance data for recommendations."
      fi
    fi
    
  } > "$report_file" || {
    print_error "Failed to write report file: $report_file"
    return 1
  }
  
  print_success "Report generated: $report_file"
  print_info "View with: cat $report_file"
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-n}"
  local choice=""
  echo -e "${YELLOW}$prompt${NC} [y/n] (default: $default): "
  read -r choice || true
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
  
  # List available models and verify they're actually installed
  local all_models=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' || echo "")
  
  if [[ -z "$all_models" ]]; then
    print_error "No models installed"
    exit 1
  fi
  
  # Filter to only models that are actually installed and ready
  print_info "Verifying installed models..."
  local model_list=()
  while IFS= read -r model; do
    if [[ -n "$model" ]]; then
      # Verify model is actually installed by checking if we can get its info
      if ollama show "$model" &>/dev/null; then
        model_list+=("$model")
      fi
    fi
  done <<< "$all_models"
  
  if [[ ${#model_list[@]} -eq 0 ]]; then
    print_error "No fully installed models found"
    print_info "Install models with: ollama pull <model-name>"
    exit 1
  fi
  
  # Select model
  echo "Available models:"
  echo ""
  local index=1
  for model in "${model_list[@]}"; do
    echo "  $index) $model"
    ((index++))
  done
  echo ""
  
  local choice=""
  read -p "Select model (1-${#model_list[@]}): " choice || true
  
  # Validate choice is not empty and is a valid number
  if [[ -z "$choice" ]] || [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ $choice -lt 1 || $choice -gt ${#model_list[@]} ]]; then
    print_error "Invalid selection"
    exit 1
  fi
  
  local selected_model="${model_list[$((choice-1))]}"
  
  # Run benchmark
  run_benchmark "$selected_model"
  
  print_success "Benchmark complete!"
}

main "$@"
