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

# Unload model from memory using Ollama API
unload_model() {
  local model="$1"
  local silent="${2:-0}"  # Optional: 1 for silent mode
  
  # Check if model is actually loaded
  if ! ollama ps 2>/dev/null | grep -q "^${model}"; then
    return 0  # Model not loaded, nothing to do
  fi
  
  if [[ $silent -eq 0 ]]; then
    print_info "Unloading model from memory..."
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
      print_warn "Model may still be in memory"
      print_info "You can manually unload with: ollama ps"
    fi
    return 1
  else
    if [[ $silent -eq 0 ]]; then
      print_success "Model unloaded from memory"
    fi
    return 0
  fi
}

# Unload all models from memory (cleanup function)
unload_all_models() {
  local loaded_models
  loaded_models=$(ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}' || echo "")
  
  if [[ -z "$loaded_models" ]]; then
    return 0  # No models loaded
  fi
  
  print_info "Unloading all models from memory..."
  
  while IFS= read -r model; do
    if [[ -n "$model" ]]; then
      unload_model "$model" 1  # Silent mode
    fi
  done <<< "$loaded_models"
  
  # Final check
  sleep 2
  local remaining
  remaining=$(ollama ps 2>/dev/null | tail -n +2 | wc -l | xargs || echo "0")
  if [[ $remaining -eq 0 ]]; then
    print_success "All models unloaded"
  else
    print_warn "$remaining model(s) may still be in memory"
  fi
}

# Check system resources before benchmarking
check_system_resources() {
  local model="$1"
  
  # Try to get model size info
  local model_info
  model_info=$(ollama show "$model" 2>/dev/null | grep -i "parameter\|size" || echo "")
  
  # Check available memory (macOS)
  if [[ "$(uname)" == "Darwin" ]]; then
    local free_mem
    free_mem=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
    local page_size
    page_size=$(vm_stat | grep "page size" | awk '{print $8}')
    if [[ -n "$free_mem" ]] && [[ -n "$page_size" ]]; then
      # Calculate free memory in GB (rough estimate)
      local free_gb
      free_gb=$(echo "scale=1; ($free_mem * $page_size) / 1073741824" | bc 2>/dev/null || echo "0")
      
      # Warn if less than 4GB free (models often need 2-3x their size in RAM)
      local should_warn=0
      if command -v bc &>/dev/null; then
        if [[ $(echo "$free_gb < 4" | bc 2>/dev/null || echo "0") -eq 1 ]]; then
          should_warn=1
        fi
      else
        # Fallback: check if free_gb is less than 4 (simple string comparison for integers)
        local free_int=${free_gb%%.*}
        if [[ $free_int -lt 4 ]] 2>/dev/null; then
          should_warn=1
        fi
      fi
      
      if [[ $should_warn -eq 1 ]]; then
        print_warn "Low memory: ~${free_gb}GB free (may cause errors)"
      fi
    fi
  fi
  
  # Check if model is already loaded (to avoid double-loading)
  if ollama ps 2>/dev/null | grep -q "^${model}"; then
    echo -e "Model loaded in memory" >&2
  fi
}

# Benchmark single model
benchmark_model() {
  local model="$1"
  local prompt="$2"
  local prompt_name="$3"
  
  # Output info message to stderr so it doesn't get captured
  echo -e "Prompt: $prompt" >&2
  echo "" >&2
  
  # Measure time-to-first-token
  local first_token_time=0
  local response=""
  local token_count=0
  local test_start
  local test_end
  local total_time=0
  
  # Run model and capture output with timing
  echo -e "Running..." >&2
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
    # Check for specific Ollama error messages
    if echo "$response" | grep -qi "500.*internal server error\|model runner.*unexpectedly stopped\|resource limitations"; then
      print_error "Benchmark failed for $model - Ollama model runner crashed (Error 500)"
      
      # Try to get model info to help diagnose
      local model_size_info
      model_size_info=$(ollama show "$model" 2>/dev/null | grep -iE "parameter|size|billion" | head -n 1 || echo "")
      
      echo -e "${RED}  → This usually indicates:${NC}" >&2
      echo -e "${YELLOW}     • Insufficient memory (model too large for available RAM)${NC}" >&2
      echo -e "${YELLOW}     • Model crashed due to internal error${NC}" >&2
      echo -e "${YELLOW}     • Resource exhaustion (CPU/memory)${NC}" >&2
      if [[ -n "$model_size_info" ]]; then
        echo -e "${CYAN}  → Model info: $model_size_info${NC}" >&2
        # Warn about very large models
        if echo "$model_size_info" | grep -qiE "70|65|80|90|100|billion"; then
          echo -e "${RED}  → WARNING: This is a very large model (70B+ parameters)${NC}" >&2
          echo -e "${YELLOW}  → 70B models typically need 40-50GB+ RAM to run${NC}" >&2
          echo -e "${YELLOW}  → Consider using a quantized version or smaller model${NC}" >&2
        fi
      fi
      echo "" >&2
      echo -e "${CYAN}  → Troubleshooting steps:${NC}" >&2
      echo -e "${YELLOW}     1. Check available memory:${NC}" >&2
      echo -e "${YELLOW}        free -h  (Linux) or vm_stat (macOS)${NC}" >&2
      echo -e "${YELLOW}     2. Check Ollama server logs for details:${NC}" >&2
      # Try multiple possible log locations
      local log_file=""
      local possible_locations=(
        "$HOME/.ollama/logs/server.log"
        "$HOME/Library/Logs/ollama/server.log"
        "/var/log/ollama/server.log"
      )
      
      # Add brew prefix location if available
      if command -v brew &>/dev/null; then
        local brew_prefix
        brew_prefix=$(brew --prefix 2>/dev/null || echo "")
        if [[ -n "$brew_prefix" ]]; then
          possible_locations+=("$brew_prefix/var/log/ollama/server.log")
        fi
      fi
      
      for loc in "${possible_locations[@]}"; do
        if [[ -f "$loc" ]]; then
          log_file="$loc"
          break
        fi
      done
      
      if [[ -n "$log_file" ]] && [[ -f "$log_file" ]]; then
        echo -e "${YELLOW}        tail -n 50 $log_file${NC}" >&2
        echo -e "${YELLOW}        (Last few log entries shown below)${NC}" >&2
        tail -n 10 "$log_file" 2>/dev/null | sed 's/^/        /' >&2 || true
      else
        echo -e "${YELLOW}        Log file not found in common locations${NC}" >&2
        echo -e "${YELLOW}        Try: brew services list ollama${NC}" >&2
        echo -e "${YELLOW}        Or check: journalctl -u ollama (Linux)${NC}" >&2
        # Try to get logs from ollama directly if possible
        if command -v ollama &>/dev/null; then
          echo -e "${YELLOW}        Checking ollama service status...${NC}" >&2
          brew services list 2>/dev/null | grep ollama >&2 || true
        fi
      fi
      echo -e "${YELLOW}     3. Try a smaller model or reduce context size${NC}" >&2
      echo -e "${YELLOW}     4. Restart Ollama service:${NC}" >&2
      echo -e "${YELLOW}        brew services restart ollama${NC}" >&2
      echo -e "${YELLOW}     5. Check if model is too large for your system${NC}" >&2
      if [[ -n "$response" ]]; then
        echo -e "${YELLOW}  → Full error message:${NC}" >&2
        echo "$response" | head -n 5 >&2
      fi
      
      # Suggest smaller alternatives if this is a large model
      if echo "$model" | grep -qiE "70|65|80|90|100"; then
        echo "" >&2
        echo -e "${CYAN}  → Suggested alternatives (smaller models):${NC}" >&2
        echo -e "${YELLOW}     • codestral (excellent for autocomplete)${NC}" >&2
        echo -e "${YELLOW}     • devstral:27b (27B, smaller than 70B)${NC}" >&2
        echo -e "${YELLOW}     • gpt-oss:20b (20B, smaller than 70B)${NC}" >&2
        echo -e "${YELLOW}     • llama3.1:8b (8B, much smaller than 70B)${NC}" >&2
      fi
      
      return 1
    fi
    
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
  
  # Validate we got a response (check for empty or whitespace-only)
  if [[ -z "${response// }" ]]; then
    print_error "Benchmark failed for $model - no response received (empty or whitespace-only)"
    return 1
  fi
  
  # Check if response looks like an error message from ollama (common error patterns)
  local first_line
  first_line=$(echo "$response" | head -n 1 | tr '[:upper:]' '[:lower:]')
  if [[ "$first_line" =~ ^(error|failed|cannot|unable|model.*not.*found|pull.*model) ]]; then
    print_error "Benchmark failed for $model - received error message"
    echo -e "Error: $(echo "$response" | head -n 1)" >&2
    return 1
  fi
  
  echo -e "Analyzing..." >&2
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
  local tokens_per_sec=0
  if [[ -n "$response" ]] && [[ $token_count -gt 0 ]] && [[ $(echo "$total_time" | awk '{if ($1 > 0) print 1; else print 0}') -eq 1 ]]; then
    if command -v bc &>/dev/null; then
      tokens_per_sec=$(echo "scale=2; $token_count / $total_time" | bc 2>/dev/null || echo "0")
    else
      tokens_per_sec=$(echo "$token_count $total_time" | awk '{if ($2 > 0) printf "%.2f", $1/$2; else print "0"}' 2>/dev/null || echo "0")
    fi
  fi
  
  # Memory usage (check ollama ps)
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
    echo "Results:"
    echo "  Time to first token: ~${first_token_time}s"
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
  if ! curl -s --max-time 5 http://localhost:11434/api/tags &>/dev/null; then
    print_error "Cannot connect to Ollama service"
    print_info "Ensure Ollama is running: brew services start ollama"
    return 1
  fi
  
  # Check system resources
  check_system_resources "$model"
  
  # Unload all models before starting to ensure clean state and prevent memory overflow
  print_info "Clearing memory: unloading any loaded models..."
  unload_all_models
  sleep 2  # Give time for cleanup
  echo ""
  
  # Warn about very large models before starting
  if echo "$model" | grep -qiE "70|65|80|90|100"; then
    print_warn "Large model (70B+) - requires 40-50GB+ RAM"
    if ! prompt_yes_no "Continue?" "y"; then
      print_info "Benchmark cancelled"
      return 0
    fi
    echo "" >&2
  fi
  
  print_info "This will take a few minutes..."
  echo ""
  
  local results=()
  local test_count=0
  local total_tests=2
  
  # Short prompt
  ((test_count++))
  echo -e "Test $test_count of $total_tests: Short Prompt" >&2
  echo "" >&2
  # Unload model before test to ensure clean state
  unload_model "$model" 1  # Silent mode
  if result=$(benchmark_model "$model" "$PROMPT_SHORT" "short"); then
    results+=("$result")
  else
    echo -e "Test failed" >&2
  fi
  # Unload after test to free memory
  unload_model "$model" 1  # Silent mode
  
  sleep 2
  echo "" >&2
  
  # Medium prompt
  ((test_count++))
  echo -e "Test $test_count of $total_tests: Medium Prompt" >&2
  echo "" >&2
  # Unload model before test to ensure clean state
  unload_model "$model" 1  # Silent mode
  if result=$(benchmark_model "$model" "$PROMPT_MEDIUM" "medium"); then
    results+=("$result")
  else
    echo -e "Test failed" >&2
  fi
  # Unload after test to free memory
  unload_model "$model" 1  # Silent mode
  
  sleep 2
  echo "" >&2
  
  # Long prompt (optional, skip if model is slow)
  if prompt_yes_no "Run long prompt test? (may take several minutes)" "n"; then
    ((total_tests++))
    ((test_count++))
    echo -e "Test $test_count of $total_tests: Long Prompt" >&2
    echo "" >&2
    # Unload model before test to ensure clean state
    unload_model "$model" 1  # Silent mode
    if result=$(benchmark_model "$model" "$PROMPT_LONG" "long"); then
      results+=("$result")
    else
      echo -e "Test failed" >&2
    fi
    # Unload after test to free memory
    unload_model "$model" 1  # Silent mode
    echo "" >&2
  fi
  
  # Summary
  echo "" >&2
  echo -e "Benchmark Summary:" >&2
  echo -e "  Completed $test_count test(s)" >&2
  echo -e "  Collected ${#results[@]} result(s)" >&2
  echo -e "  Generating report..." >&2
  echo "" >&2
  
  # Generate report (safely handle empty array with set -u)
  if [[ ${#results[@]} -gt 0 ]]; then
    generate_benchmark_report "$model" "${results[@]}"
  else
    generate_benchmark_report "$model"
  fi
  
  # Unload model from memory to free up resources
  echo "" >&2
  unload_model "$model"
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
  # Safely get default value (handle unset variable with set -u)
  # The ${2:-n} syntax works with set -u, but we check parameter count first to be extra safe
  local default
  if [[ $# -ge 2 ]]; then
    default="${2:-n}"  # Use provided value or 'n' as fallback
  else
    default="n"
  fi
  local choice=""
  echo -e "${YELLOW}$prompt${NC} [y/n] (default: $default): "
  read -r choice || true
  choice=${choice:-$default}
  case "$choice" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

# Global variable to track current model being benchmarked
CURRENT_BENCHMARK_MODEL=""

# Cleanup function for trap
cleanup_on_exit() {
  if [[ -n "$CURRENT_BENCHMARK_MODEL" ]]; then
    echo "" >&2
    print_info "Cleaning up: unloading model..."
    unload_model "$CURRENT_BENCHMARK_MODEL" 1  # Silent mode
  fi
}

# Main
main() {
  clear
  print_header "⚡ Local LLM Benchmark Tool"
  
  # Set up trap to cleanup on exit/interrupt
  trap cleanup_on_exit EXIT INT TERM
  
  # Check Ollama
  if ! command -v ollama &>/dev/null; then
    print_error "Ollama not found"
    print_error_with_suggestion "Ollama is required for benchmarking" "Install with: brew install ollama"
    exit 1
  fi
  
  # Check Ollama service with retry
  local ollama_available=false
  for i in {1..3}; do
    if curl -s --max-time 5 http://localhost:11434/api/tags &>/dev/null; then
      ollama_available=true
      break
    fi
    if [[ $i -lt 3 ]]; then
      print_info "Waiting for Ollama service... (attempt $i/3)"
      sleep 2
    fi
  done
  
  if [[ "$ollama_available" != "true" ]]; then
    print_error "Ollama service is not running"
    print_error_with_suggestion "Ollama service is required" "Start with: brew services start ollama"
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
  
  # Set global variable for cleanup trap
  CURRENT_BENCHMARK_MODEL="$selected_model"
  
  # Run benchmark
  run_benchmark "$selected_model"
  
  # Clear the global variable
  CURRENT_BENCHMARK_MODEL=""
  
  # Final cleanup - ensure model is unloaded
  echo ""
  print_info "Final cleanup: ensuring model is unloaded..."
  unload_model "$selected_model"
  
  print_success "Benchmark complete!"
}

main "$@"
