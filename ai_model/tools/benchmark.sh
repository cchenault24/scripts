#!/bin/bash
#
# benchmark.sh - Benchmark tool for local LLM models
#
# Tests model performance: time-to-first-token, tokens-per-second, memory usage

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/.local-llm-setup"
LOG_FILE="$STATE_DIR/benchmark.log"
DEBUG_LOG="/Users/chenaultfamily/Documents/coding/scripts/.cursor/debug.log"

# Debug logging helper
debug_log() {
  local hypothesis_id="$1"
  local location="$2"
  local message="$3"
  local data="$4"
  local timestamp=$(date +%s)000
  echo "{\"id\":\"log_${timestamp}_$$\",\"timestamp\":$timestamp,\"location\":\"$location\",\"message\":\"$message\",\"data\":$data,\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"$hypothesis_id\"}" >> "$DEBUG_LOG" 2>/dev/null || true
}

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
  local response_file=$(mktemp)
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
    local stderr_file=$(mktemp)
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
  
  print_info "Testing $model with $prompt_name prompt..."
  
  # Measure time-to-first-token
  local first_token_time=0
  local response=""
  local token_count=0
  local test_start
  local test_end
  local total_time=0
  
  # Run model and capture output with timing
  test_start=$(date +%s.%N 2>/dev/null || date +%s)
  
  # Use macOS-compatible timeout wrapper
  if ! response=$(run_with_timeout 120 ollama run "$model" "$prompt" 2>&1); then
    print_error "Benchmark failed for $model - ollama command failed"
    return 1
  fi
  
  test_end=$(date +%s.%N 2>/dev/null || date +%s)
  
  # Validate we got a response
  if [[ -z "$response" ]]; then
    print_error "Benchmark failed for $model - no response received"
    return 1
  fi
  
  # Calculate total time
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
  
  # Check if model exists by checking first column of ollama list output
  if ! ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -q "^${model}$"; then
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
  
  # #region agent log
  local results_preview=""
  for i in "${!results[@]}"; do
    results_preview="${results_preview}result_${i}:${results[$i]};"
  done
  local state_dir_exists="no"
  [[ -d "$STATE_DIR" ]] && state_dir_exists="yes"
  debug_log "A" "benchmark.sh:257" "generate_benchmark_report entry" "{\"model\":\"$model\",\"results_count\":${#results[@]},\"results_preview\":\"$results_preview\",\"state_dir\":\"$STATE_DIR\",\"state_dir_exists\":\"$state_dir_exists\"}"
  # #endregion
  
  # Sanitize model name: replace invalid filename characters
  local model_sanitized="${model//\//-}"
  model_sanitized="${model_sanitized//:/-}"
  model_sanitized="${model_sanitized// /_}"
  model_sanitized="${model_sanitized//[^a-zA-Z0-9._-]/}"
  # #region agent log
  debug_log "B" "benchmark.sh:262" "model name sanitization" "{\"model\":\"$model\",\"model_sanitized\":\"$model_sanitized\"}"
  # #endregion
  
  # Ensure STATE_DIR exists
  if [[ ! -d "$STATE_DIR" ]]; then
    mkdir -p "$STATE_DIR" || {
      print_error "Failed to create state directory: $STATE_DIR"
      return 1
    }
  fi
  
  local report_file="$STATE_DIR/benchmark-${model_sanitized}-$(date +%Y%m%d-%H%M%S).txt"
  # #region agent log
  debug_log "A" "benchmark.sh:265" "report_file path constructed" "{\"report_file\":\"$report_file\",\"report_file_escaped\":\"$(printf '%q' \"$report_file\")\"}"
  # #endregion
  
  # #region agent log
  local parent_dir=$(dirname "$report_file")
  local parent_dir_exists="no"
  [[ -d "$parent_dir" ]] && parent_dir_exists="yes"
  debug_log "C" "benchmark.sh:268" "before file redirection" "{\"report_file\":\"$report_file\",\"parent_dir\":\"$parent_dir\",\"parent_dir_exists\":\"$parent_dir_exists\"}"
  # #endregion
  
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
        # #region agent log
        local result_first_line=$(echo "$result" | head -n1)
        local result_last_line=$(echo "$result" | tail -n1)
        local result_line_count=$(echo "$result" | wc -l | tr -d ' ')
        debug_log "D" "benchmark.sh:312" "parsing result" "{\"result_line_count\":$result_line_count,\"result_first_line\":\"$result_first_line\",\"result_last_line\":\"$result_last_line\",\"result_contains_pipe\":\"$(echo \"$result\" | grep -q '|' && echo 'yes' || echo 'no')\"}"
        # #endregion
        # Parse 6 fields: model|prompt_name|first_token_time|token_count|tokens_per_sec|memory_mb
        IFS='|' read -r m pn ft tc tps mem <<< "$result"
        # #region agent log
        debug_log "D" "benchmark.sh:320" "after parsing result" "{\"m\":\"$m\",\"pn\":\"$pn\",\"ft\":\"$ft\",\"tc\":\"$tc\",\"tps\":\"$tps\",\"mem\":\"$mem\"}"
        # #endregion
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
    
  } > "$report_file"
  
  # #region agent log
  local file_exists="no"
  local file_size=0
  if [[ -f "$report_file" ]]; then
    file_exists="yes"
    file_size=$(stat -f%z "$report_file" 2>/dev/null || stat -c%s "$report_file" 2>/dev/null || echo "0")
  fi
  debug_log "A" "benchmark.sh:310" "after file redirection" "{\"report_file\":\"$report_file\",\"file_exists\":\"$file_exists\",\"file_size\":$file_size,\"redirection_exit_code\":$?}"
  # #endregion
  
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
