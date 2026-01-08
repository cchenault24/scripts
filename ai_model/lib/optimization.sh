#!/bin/bash
#
# optimization.sh - Optimization functions for setup-local-llm.sh
#
# Core Optimizations:
# - Smart model loading/unloading with usage tracking
# - Memory pressure detection and auto-unload
# - Dynamic context window sizing
# - Adaptive temperature calculation
# - Multi-model orchestration (model router/dispatcher)
# - GPU layer optimization and testing
# - Smart request queuing with prioritization
# - Performance profiling and monitoring
#
# Advanced Optimizations:
# - Model fusion/ensemble (combine multiple models for better results)
# - Context compression (summarize context when approaching limits)
# - Prompt optimization (analyze and improve prompt effectiveness)
# - Enhanced batch processing (efficient multi-request handling)
#
# Depends on: constants.sh, logger.sh, ui.sh, hardware.sh, ollama.sh, models.sh

# Usage tracking state file
USAGE_TRACKING_FILE="$STATE_DIR/model_usage.json"

# Initialize usage tracking
init_usage_tracking() {
  if [[ ! -f "$USAGE_TRACKING_FILE" ]]; then
    mkdir -p "$STATE_DIR"
    echo '{}' > "$USAGE_TRACKING_FILE"
    log_info "Initialized model usage tracking"
  fi
}

# Track model usage (call this when a model is used)
track_model_usage() {
  local model="$1"
  local timestamp=$(date +%s)
  
  init_usage_tracking
  
  # Use jq if available for JSON manipulation, otherwise use simple text manipulation
  if command -v jq &>/dev/null; then
    # Read current usage data
    local current_data
    current_data=$(cat "$USAGE_TRACKING_FILE" 2>/dev/null || echo '{}')
    
    # Update usage count and last used timestamp
    local updated_data
    updated_data=$(echo "$current_data" | jq --arg model "$model" --arg ts "$timestamp" \
      '. + {($model): {count: ((.[$model].count // 0) + 1), last_used: ($ts | tonumber)}}' 2>/dev/null || echo '{}')
    
    echo "$updated_data" > "$USAGE_TRACKING_FILE"
  else
    # Fallback: simple text-based tracking (model:count:timestamp format)
    local usage_line="${model}:1:${timestamp}"
    if grep -q "^${model}:" "$USAGE_TRACKING_FILE" 2>/dev/null; then
      # Update existing entry
      local old_line
      old_line=$(grep "^${model}:" "$USAGE_TRACKING_FILE" | head -n 1)
      local old_count="${old_line#*:}"
      old_count="${old_count%%:*}"
      local new_count=$((old_count + 1))
      sed -i.bak "s|^${model}:.*|${model}:${new_count}:${timestamp}|" "$USAGE_TRACKING_FILE" 2>/dev/null || true
      rm -f "${USAGE_TRACKING_FILE}.bak" 2>/dev/null || true
    else
      # Add new entry
      echo "$usage_line" >> "$USAGE_TRACKING_FILE"
    fi
  fi
  
  log_info "Tracked usage for model: $model"
}

# Get model usage frequency (returns count of uses in last 24 hours)
get_model_usage_frequency() {
  local model="$1"
  local current_time=$(date +%s)
  local one_day_ago=$((current_time - 86400))
  
  if [[ ! -f "$USAGE_TRACKING_FILE" ]]; then
    echo "0"
    return
  fi
  
  if command -v jq &>/dev/null; then
    local count
    count=$(jq -r --arg model "$model" '.[$model].count // 0' "$USAGE_TRACKING_FILE" 2>/dev/null || echo "0")
    local last_used
    last_used=$(jq -r --arg model "$model" '.[$model].last_used // 0' "$USAGE_TRACKING_FILE" 2>/dev/null || echo "0")
    
    # Only count if used in last 24 hours
    if [[ $last_used -gt $one_day_ago ]]; then
      echo "$count"
    else
      echo "0"
    fi
  else
    # Fallback: text-based parsing
    local usage_line
    usage_line=$(grep "^${model}:" "$USAGE_TRACKING_FILE" 2>/dev/null | head -n 1)
    if [[ -n "$usage_line" ]]; then
      local timestamp="${usage_line##*:}"
      if [[ $timestamp -gt $one_day_ago ]]; then
        local count="${usage_line#*:}"
        count="${count%%:*}"
        echo "${count:-0}"
      else
        echo "0"
      fi
    else
      echo "0"
    fi
  fi
}

# Smart model loading: Load model if not loaded, considering usage patterns
smart_load_model() {
  local model="$1"
  local force="${2:-0}"  # Optional: 1 to force load even if memory pressure
  
  # Check if model is already loaded
  if ollama ps 2>/dev/null | grep -q "^${model}"; then
    log_info "Model $model is already loaded"
    return 0
  fi
  
  # Check memory pressure before loading (unless forced)
  if [[ $force -eq 0 ]]; then
    if check_memory_pressure; then
      print_warn "Memory pressure detected. Attempting to free memory before loading $model..."
      
      # Try to unload least-used models first
      if ! smart_unload_idle_models "$model"; then
        print_warn "Could not free enough memory. Loading $model anyway (may cause issues)"
      fi
    fi
  fi
  
  # Load the model (Ollama will load it on first use, but we can preload)
  print_info "Loading model $model..."
  log_info "Smart loading model: $model"
  
  # Preload model by making a minimal request
  local preload_response
  preload_response=$(curl -s --max-time 30 -X POST http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"$model\", \"prompt\": \"test\", \"stream\": false, \"keep_alive\": \"5m\"}" 2>/dev/null || echo "")
  
  if [[ -n "$preload_response" ]]; then
    track_model_usage "$model"
    print_success "Model $model loaded"
    return 0
  else
    log_warn "Model $model preload failed (will load on first use)"
    return 1
  fi
}

# Smart model unloading: Unload idle models based on usage patterns
smart_unload_idle_models() {
  local keep_model="${1:-}"  # Optional: model to keep loaded
  local unloaded_count=0
  
  # Get currently loaded models
  local loaded_models
  loaded_models=$(ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}' || echo "")
  
  if [[ -z "$loaded_models" ]]; then
    return 0  # No models loaded
  fi
  
  # Sort models by usage frequency (least used first)
  local models_to_unload=()
  while IFS= read -r model; do
    if [[ -n "$model" ]] && [[ "$model" != "$keep_model" ]]; then
      local frequency
      frequency=$(get_model_usage_frequency "$model")
      models_to_unload+=("${frequency}:${model}")
    fi
  done <<< "$loaded_models"
  
  # Sort by frequency (ascending - least used first)
  IFS=$'\n' sorted_models=($(printf '%s\n' "${models_to_unload[@]}" | sort -t: -k1 -n))
  unset IFS
  
  # Unload least-used models first
  for entry in "${sorted_models[@]}"; do
    local model="${entry#*:}"
    if unload_model "$model" 1; then  # Silent mode
      ((unloaded_count++))
      log_info "Unloaded idle model: $model"
    fi
  done
  
  if [[ $unloaded_count -gt 0 ]]; then
    print_info "Unloaded $unloaded_count idle model(s) to free memory"
  fi
  
  return 0
}

# Check memory pressure (returns 0 if pressure detected, 1 if OK)
check_memory_pressure() {
  local pressure_threshold="${1:-85}"  # Default: 85% memory usage threshold
  local available_ram_gb
  
  # Get available RAM (macOS)
  if command -v vm_stat &>/dev/null; then
    # Calculate available memory from vm_stat
    local page_size
    page_size=$(vm_stat | grep "page size" | awk '{print $8}' | sed 's/[^0-9]//g')
    local free_pages
    free_pages=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/[^0-9]//g')
    local inactive_pages
    inactive_pages=$(vm_stat | grep "Pages inactive" | awk '{print $3}' | sed 's/[^0-9]//g')
    
    # Calculate available memory in bytes
    local available_bytes
    if [[ -n "$page_size" ]] && [[ -n "$free_pages" ]] && [[ -n "$inactive_pages" ]]; then
      available_bytes=$(( (free_pages + inactive_pages) * page_size ))
      available_ram_gb=$(( available_bytes / 1024 / 1024 / 1024 ))
    else
      # Fallback: use sysctl
      local ram_bytes
      ram_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
      local ram_gb=$((ram_bytes / 1024 / 1024 / 1024))
      # Estimate available as 50% (conservative)
      available_ram_gb=$((ram_gb / 2))
    fi
  else
    # Fallback: estimate from total RAM
    local ram_bytes
    ram_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
    local ram_gb=$((ram_bytes / 1024 / 1024 / 1024))
    available_ram_gb=$((ram_gb / 2))  # Conservative estimate
  fi
  
  # Get currently loaded models and their RAM usage
  local loaded_models
  loaded_models=$(ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}' || echo "")
  
  local total_model_ram=0
  while IFS= read -r model; do
    if [[ -n "$model" ]]; then
      local model_ram
      model_ram=$(get_model_ram "$model")
      # Convert to integer for comparison
      local model_ram_int
      model_ram_int=$(echo "$model_ram" | awk '{if ($1+0 == $1) printf "%.0f", $1; else print "0"}')
      if [[ "$model_ram_int" =~ ^[0-9]+$ ]]; then
        total_model_ram=$((total_model_ram + model_ram_int))
      fi
    fi
  done <<< "$loaded_models"
  
  # Calculate memory pressure percentage
  local pressure_percent=0
  if [[ $available_ram_gb -gt 0 ]]; then
    # Estimate total RAM from available + used
    local estimated_total=$((available_ram_gb + total_model_ram))
    if [[ $estimated_total -gt 0 ]]; then
      local used_percent
      used_percent=$(( (total_model_ram * 100) / estimated_total ))
      pressure_percent=$used_percent
    fi
  fi
  
  # Check against threshold
  if [[ $pressure_percent -ge $pressure_threshold ]]; then
    log_warn "Memory pressure detected: ${pressure_percent}% RAM used by models (threshold: ${pressure_threshold}%)"
    return 0  # Pressure detected
  else
    log_info "Memory OK: ${pressure_percent}% RAM used by models"
    return 1  # No pressure
  fi
}

# Monitor memory pressure continuously (background process)
monitor_memory_pressure() {
  local check_interval="${1:-60}"  # Default: check every 60 seconds
  local pressure_threshold="${2:-85}"
  
  print_info "Starting memory pressure monitoring (checking every ${check_interval}s)"
  log_info "Memory pressure monitoring started"
  
  while true; do
    sleep "$check_interval"
    
    if check_memory_pressure "$pressure_threshold"; then
      # Memory pressure detected - unload idle models
      print_warn "Memory pressure detected - unloading idle models..."
      smart_unload_idle_models
    fi
  done
}

# Calculate optimal context window size based on task complexity
calculate_optimal_context() {
  local base_context="$1"  # Base context from tier (e.g., 32768 for Tier S)
  local task_type="${2:-general}"  # Task type: simple, moderate, complex, refactoring
  local prompt_length="${3:-0}"  # Estimated prompt length in tokens (optional)
  
  local optimal_context="$base_context"
  
  # Adjust based on task type
  case "$task_type" in
    simple|autocomplete)
      # Reduce context for simple tasks (faster responses)
      optimal_context=$((base_context / 4))
      # Minimum 2K context
      if [[ $optimal_context -lt 2048 ]]; then
        optimal_context=2048
      fi
      ;;
    moderate|general)
      # Use 50% of base context for moderate tasks
      optimal_context=$((base_context / 2))
      ;;
    complex|analysis)
      # Use full base context for complex tasks
      optimal_context="$base_context"
      ;;
    refactoring|multi-file)
      # Use 125% of base context for refactoring (if tier allows)
      optimal_context=$((base_context + base_context / 4))
      # Cap at 32K (Ollama's typical max)
      if [[ $optimal_context -gt 32768 ]]; then
        optimal_context=32768
      fi
      ;;
    *)
      # Default: use base context
      optimal_context="$base_context"
      ;;
  esac
  
  # Adjust based on prompt length if provided
  if [[ $prompt_length -gt 0 ]]; then
    # Ensure context is at least 2x prompt length for good results
    local min_context=$((prompt_length * 2))
    if [[ $optimal_context -lt $min_context ]]; then
      optimal_context="$min_context"
    fi
    # Cap at base context maximum
    if [[ $optimal_context -gt $base_context ]]; then
      optimal_context="$base_context"
    fi
  fi
  
  # Round to nearest 1024 for efficiency
  optimal_context=$(( (optimal_context / 1024) * 1024 ))
  
  log_info "Calculated optimal context: $optimal_context (base: $base_context, task: $task_type)"
  echo "$optimal_context"
}

# Calculate adaptive temperature based on task type and complexity
calculate_adaptive_temperature() {
  local base_temperature="${1:-0.7}"  # Base temperature from role
  local task_type="${2:-general}"  # Task type
  local determinism_required="${3:-0}"  # 1 if deterministic output required, 0 otherwise
  
  local adaptive_temp="$base_temperature"
  
  # Adjust based on task type
  case "$task_type" in
    code-review|testing|debugging)
      # Lower temperature for review/testing (more deterministic)
      if command -v bc &>/dev/null; then
        adaptive_temp=$(echo "$base_temperature * 0.6" | bc -l 2>/dev/null || echo "$base_temperature")
        # Ensure minimum 0.1
        adaptive_temp=$(echo "if ($adaptive_temp < 0.1) 0.1 else $adaptive_temp" | bc -l 2>/dev/null || echo "$adaptive_temp")
      else
        # Integer fallback: multiply by 0.6 (approximate)
        local base_int=${base_temperature%%.*}
        local base_dec="${base_temperature#*.}"
        base_dec="${base_dec:0:1}"  # First decimal digit
        adaptive_temp=$((base_int * 6 / 10))
        if [[ $adaptive_temp -lt 1 ]]; then
          adaptive_temp="0.1"
        else
          adaptive_temp="${adaptive_temp}.${base_dec}"
        fi
      fi
      ;;
    creative|coding|generation)
      # Slightly higher for creative tasks
      if command -v bc &>/dev/null; then
        adaptive_temp=$(echo "$base_temperature * 1.1" | bc -l 2>/dev/null || echo "$base_temperature")
        # Cap at 1.0
        adaptive_temp=$(echo "if ($adaptive_temp > 1.0) 1.0 else $adaptive_temp" | bc -l 2>/dev/null || echo "$adaptive_temp")
      else
        # Integer fallback: multiply by 1.1 (approximate)
        local base_int=${base_temperature%%.*}
        local base_dec="${base_temperature#*.}"
        base_dec="${base_dec:0:1}"  # First decimal digit
        adaptive_temp=$((base_int * 11 / 10))
        if [[ $adaptive_temp -gt 10 ]]; then
          adaptive_temp="1.0"
        else
          adaptive_temp="${adaptive_temp}.${base_dec}"
        fi
      fi
      ;;
    documentation|explanation)
      # Moderate temperature for documentation
      adaptive_temp="$base_temperature"
      ;;
    *)
      # Default: use base temperature
      adaptive_temp="$base_temperature"
      ;;
  esac
  
  # Override if determinism is explicitly required
  if [[ $determinism_required -eq 1 ]]; then
    adaptive_temp="0.1"
  fi
  
  # Round to 2 decimal places
  if command -v bc &>/dev/null; then
    adaptive_temp=$(printf "%.2f" "$adaptive_temp" 2>/dev/null || echo "$adaptive_temp")
  fi
  
  log_info "Calculated adaptive temperature: $adaptive_temp (base: $base_temperature, task: $task_type)"
  echo "$adaptive_temp"
}

# Enhanced tune_model with dynamic optimizations
tune_model_optimized() {
  local model="$1"
  local tier="$2"
  local role="${3:-coding}"
  local task_type="${4:-general}"  # New: task type for dynamic optimization
  local prompt_length="${5:-0}"  # New: estimated prompt length
  
  # Get base parameters from original tune_model (disable optimizations to avoid circular call)
  local base_params
  base_params=$(tune_model "$model" "$tier" "$role" "0")
  
  # Extract base context from tier
  local base_context
  case "$tier" in
    S) base_context=32768 ;;
    A) base_context=16384 ;;
    B) base_context=8192 ;;
    C) base_context=4096 ;;
    *) base_context=8192 ;;
  esac
  
  # Calculate optimal context dynamically
  local optimal_context
  optimal_context=$(calculate_optimal_context "$base_context" "$task_type" "$prompt_length")
  
  # Extract base temperature from role
  local base_temperature
  case "$role" in
    coding) base_temperature=0.7 ;;
    code-review) base_temperature=0.3 ;;
    documentation) base_temperature=0.5 ;;
    deep-analysis) base_temperature=0.6 ;;
    *) base_temperature=0.7 ;;
  esac
  
  # Calculate adaptive temperature
  local adaptive_temp
  adaptive_temp=$(calculate_adaptive_temperature "$base_temperature" "$task_type" 0)
  
  # Extract other parameters from base_params (using jq if available, or parsing)
  local max_tokens keep_alive num_gpu num_thread top_p
  
  if command -v jq &>/dev/null; then
    max_tokens=$(echo "$base_params" | jq -r '.max_tokens // 2048')
    keep_alive=$(echo "$base_params" | jq -r '.keep_alive // "5m"')
    num_gpu=$(echo "$base_params" | jq -r '.num_gpu // 1')
    num_thread=$(echo "$base_params" | jq -r '.num_thread // 4')
    top_p=$(echo "$base_params" | jq -r '.top_p // 0.9')
  else
    # Fallback parsing (basic extraction)
    max_tokens=$(echo "$base_params" | grep -o '"max_tokens": [0-9]*' | grep -o '[0-9]*' || echo "2048")
    keep_alive=$(echo "$base_params" | grep -o '"keep_alive": "[^"]*"' | cut -d'"' -f4 || echo "5m")
    num_gpu=$(echo "$base_params" | grep -o '"num_gpu": [0-9]*' | grep -o '[0-9]*' || echo "1")
    num_thread=$(echo "$base_params" | grep -o '"num_thread": [0-9]*' | grep -o '[0-9]*' || echo "4")
    top_p=$(echo "$base_params" | grep -o '"top_p": [0-9.]*' | grep -o '[0-9.]*' || echo "0.9")
  fi
  
  # Adjust max_tokens based on context (proportional)
  local adjusted_max_tokens
  adjusted_max_tokens=$((optimal_context / 8))
  # Ensure reasonable bounds
  if [[ $adjusted_max_tokens -lt 512 ]]; then
    adjusted_max_tokens=512
  elif [[ $adjusted_max_tokens -gt 4096 ]]; then
    adjusted_max_tokens=4096
  fi
  
  # Return optimized parameters as JSON
  cat <<EOF
{
  "context_size": $optimal_context,
  "max_tokens": $adjusted_max_tokens,
  "temperature": $adaptive_temp,
  "top_p": $top_p,
  "keep_alive": "$keep_alive",
  "num_gpu": $num_gpu,
  "num_thread": $num_thread,
  "task_type": "$task_type",
  "optimized": true
}
EOF
}

# ============================================================================
# Multi-Model Orchestration
# ============================================================================

# Model router: Select optimal model for a given task
route_task_to_model() {
  local task_type="${1:-general}"  # Task type: autocomplete, coding, refactoring, analysis, etc.
  local prompt_length="${2:-0}"  # Estimated prompt length in tokens
  local tier="${3:-$HARDWARE_TIER}"  # Hardware tier (defaults to detected tier)
  
  # Get installed models
  local installed_models
  installed_models=$(get_installed_models)
  
  if [[ -z "$installed_models" ]]; then
    log_error "No models installed for routing"
    echo ""
    return 1
  fi
  
  # Model selection strategy based on task type
  local selected_model=""
  
  case "$task_type" in
    autocomplete|simple|quick)
      # Use smallest, fastest model for autocomplete
      # Priority: qwen2.5-coder:7b > llama3.1:8b > others
      if echo "$installed_models" | grep -q "^qwen2.5-coder:7b$"; then
        selected_model="qwen2.5-coder:7b"
      elif echo "$installed_models" | grep -q "^llama3.1:8b$"; then
        selected_model="llama3.1:8b"
      else
        # Fallback: smallest available model
        selected_model=$(echo "$installed_models" | head -n 1)
      fi
      ;;
    coding|generation|moderate)
      # Use balanced model for coding tasks
      # Priority: qwen2.5-coder:14b > codestral:22b > llama3.1:8b
      if echo "$installed_models" | grep -q "^qwen2.5-coder:14b$"; then
        selected_model="qwen2.5-coder:14b"
      elif echo "$installed_models" | grep -q "^codestral:22b$"; then
        selected_model="codestral:22b"
      elif echo "$installed_models" | grep -q "^llama3.1:8b$"; then
        selected_model="llama3.1:8b"
      else
        selected_model=$(echo "$installed_models" | head -n 1)
      fi
      ;;
    refactoring|complex|multi-file|analysis)
      # Use largest available model for complex tasks
      # Priority: llama3.1:70b > codestral:22b > qwen2.5-coder:14b
      if echo "$installed_models" | grep -q "^llama3.1:70b$" && [[ "$tier" == "S" ]]; then
        selected_model="llama3.1:70b"
      elif echo "$installed_models" | grep -q "^codestral:22b$"; then
        selected_model="codestral:22b"
      elif echo "$installed_models" | grep -q "^qwen2.5-coder:14b$"; then
        selected_model="qwen2.5-coder:14b"
      else
        # Fallback: largest available model
        selected_model=$(echo "$installed_models" | tail -n 1)
      fi
      ;;
    code-review|testing|debugging)
      # Use balanced model with good reasoning
      # Priority: codestral:22b > qwen2.5-coder:14b > llama3.1:8b
      if echo "$installed_models" | grep -q "^codestral:22b$"; then
        selected_model="codestral:22b"
      elif echo "$installed_models" | grep -q "^qwen2.5-coder:14b$"; then
        selected_model="qwen2.5-coder:14b"
      elif echo "$installed_models" | grep -q "^llama3.1:8b$"; then
        selected_model="llama3.1:8b"
      else
        selected_model=$(echo "$installed_models" | head -n 1)
      fi
      ;;
    *)
      # Default: use most frequently used model or balanced model
      local most_used=""
      local max_freq=0
      while IFS= read -r model; do
        if [[ -n "$model" ]]; then
          local freq
          freq=$(get_model_usage_frequency "$model")
          if [[ $freq -gt $max_freq ]]; then
            max_freq=$freq
            most_used="$model"
          fi
        fi
      done <<< "$installed_models"
      
      if [[ -n "$most_used" ]]; then
        selected_model="$most_used"
      else
        # Fallback: use first available model
        selected_model=$(echo "$installed_models" | head -n 1)
      fi
      ;;
  esac
  
  if [[ -z "$selected_model" ]]; then
    log_error "Failed to route task to model"
    echo ""
    return 1
  fi
  
  log_info "Routed task type '$task_type' to model: $selected_model"
  echo "$selected_model"
}

# Execute task with optimal model selection
execute_task_with_routing() {
  local task_type="${1:-general}"
  local prompt="${2:-}"
  local role="${3:-coding}"
  
  if [[ -z "$prompt" ]]; then
    log_error "No prompt provided for task execution"
    return 1
  fi
  
  # Route to optimal model
  local model
  model=$(route_task_to_model "$task_type" 0)
  
  if [[ -z "$model" ]]; then
    log_error "Failed to select model for task"
    return 1
  fi
  
  # Ensure model is loaded
  if ! smart_load_model "$model" 0; then
    log_warn "Model $model failed to load, attempting anyway"
  fi
  
  # Get optimized parameters
  local tier="${HARDWARE_TIER:-B}"
  local params
  params=$(tune_model_optimized "$model" "$tier" "$role" "$task_type" 0)
  
  # Extract parameters (simplified - would need proper JSON parsing in production)
  local context_size max_tokens temperature
  if command -v jq &>/dev/null; then
    context_size=$(echo "$params" | jq -r '.context_size // 8192')
    max_tokens=$(echo "$params" | jq -r '.max_tokens // 2048')
    temperature=$(echo "$params" | jq -r '.temperature // 0.7')
  else
    context_size=$(echo "$params" | grep -o '"context_size": [0-9]*' | grep -o '[0-9]*' || echo "8192")
    max_tokens=$(echo "$params" | grep -o '"max_tokens": [0-9]*' | grep -o '[0-9]*' || echo "2048")
    temperature=$(echo "$params" | grep -o '"temperature": [0-9.]*' | grep -o '[0-9.]*' || echo "0.7")
  fi
  
  # Track usage
  track_model_usage "$model"
  
  # Execute via Ollama API
  log_info "Executing task with model $model (task_type: $task_type)"
  
  local response
  response=$(curl -s --max-time 300 -X POST http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"$model\", \"prompt\": \"$prompt\", \"stream\": false, \"options\": {\"num_ctx\": $context_size, \"num_predict\": $max_tokens, \"temperature\": $temperature}}" 2>/dev/null || echo "")
  
  if [[ -n "$response" ]]; then
    # Extract response text (simplified - would need proper JSON parsing)
    if command -v jq &>/dev/null; then
      echo "$response" | jq -r '.response // .' 2>/dev/null || echo "$response"
    else
      echo "$response"
    fi
    return 0
  else
    log_error "Task execution failed"
    return 1
  fi
}

# ============================================================================
# GPU Layer Optimization
# ============================================================================

# Performance metrics storage
PERFORMANCE_METRICS_FILE="$STATE_DIR/performance_metrics.json"

# Initialize performance metrics tracking
init_performance_metrics() {
  if [[ ! -f "$PERFORMANCE_METRICS_FILE" ]]; then
    mkdir -p "$STATE_DIR"
    echo '{}' > "$PERFORMANCE_METRICS_FILE"
    log_info "Initialized performance metrics tracking"
  fi
}

# Benchmark model with specific GPU layer configuration
benchmark_gpu_layers() {
  local model="$1"
  local gpu_layers="${2:-}"  # Number of GPU layers to test (empty = auto)
  local test_prompt="${3:-Write a simple TypeScript function that adds two numbers.}"
  
  if [[ -z "$model" ]]; then
    log_error "Model name required for GPU layer benchmarking"
    return 1
  fi
  
  print_info "Benchmarking GPU layers for $model..."
  log_info "GPU layer benchmark: model=$model, gpu_layers=${gpu_layers:-auto}"
  
  # Ensure model is loaded
  if ! smart_load_model "$model" 0; then
    log_warn "Model $model failed to load for benchmarking"
  fi
  
  # Test prompt
  local start_time
  start_time=$(date +%s.%N 2>/dev/null || date +%s)
  
  # Build API request with GPU layer configuration if specified
  local api_payload
  if [[ -n "$gpu_layers" ]] && [[ "$gpu_layers" =~ ^[0-9]+$ ]]; then
    api_payload="{\"model\": \"$model\", \"prompt\": \"$test_prompt\", \"stream\": false, \"options\": {\"num_gpu\": $gpu_layers}}"
  else
    api_payload="{\"model\": \"$model\", \"prompt\": \"$test_prompt\", \"stream\": false}"
  fi
  
  local response
  response=$(curl -s --max-time 60 -X POST http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d "$api_payload" 2>/dev/null || echo "")
  
  local end_time
  end_time=$(date +%s.%N 2>/dev/null || date +%s)
  
  # Calculate duration
  local duration=0
  if command -v bc &>/dev/null && [[ "$start_time" =~ \. ]] && [[ "$end_time" =~ \. ]]; then
    duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
  else
    local start_int=${start_time%%.*}
    local end_int=${end_time%%.*}
    duration=$((end_int - start_int))
  fi
  
  # Extract response length for token estimation
  local response_length=0
  if command -v jq &>/dev/null; then
    response_length=$(echo "$response" | jq -r '.response | length' 2>/dev/null || echo "0")
  else
    response_length=${#response}
  fi
  
  # Estimate tokens (rough: ~4 chars per token)
  local tokens=0
  if [[ $response_length -gt 0 ]]; then
    if command -v bc &>/dev/null; then
      tokens=$(echo "$response_length / 4" | bc 2>/dev/null || echo "0")
    else
      tokens=$((response_length / 4))
    fi
  fi
  
  # Calculate tokens per second
  local tokens_per_sec=0
  if command -v bc &>/dev/null && [[ $(echo "$duration > 0" | bc 2>/dev/null || echo "0") -eq 1 ]] && [[ $tokens -gt 0 ]]; then
    tokens_per_sec=$(echo "scale=2; $tokens / $duration" | bc 2>/dev/null || echo "0")
  elif [[ ${duration%%.*} -gt 0 ]] && [[ $tokens -gt 0 ]]; then
    local duration_int=${duration%%.*}
    tokens_per_sec=$((tokens / duration_int))
  fi
  
  # Store metrics
  init_performance_metrics
  local metrics_entry
  if command -v jq &>/dev/null; then
    local current_metrics
    current_metrics=$(cat "$PERFORMANCE_METRICS_FILE" 2>/dev/null || echo '{}')
    local timestamp=$(date +%s)
    metrics_entry=$(echo "$current_metrics" | jq --arg model "$model" \
      --arg gpu_layers "${gpu_layers:-auto}" \
      --argjson duration "$duration" \
      --argjson tokens "$tokens" \
      --argjson tokens_per_sec "$tokens_per_sec" \
      --argjson timestamp "$timestamp" \
      '. + {($model): {gpu_layers: $gpu_layers, duration: $duration, tokens: $tokens, tokens_per_sec: $tokens_per_sec, timestamp: $timestamp}}' 2>/dev/null || echo '{}')
    echo "$metrics_entry" > "$PERFORMANCE_METRICS_FILE"
  fi
  
  # Display results
  print_success "GPU layer benchmark complete"
  print_info "  Model: $model"
  print_info "  GPU layers: ${gpu_layers:-auto}"
  print_info "  Duration: ${duration}s"
  print_info "  Tokens/sec: ~${tokens_per_sec}"
  
  log_info "GPU benchmark: $model, layers=${gpu_layers:-auto}, duration=${duration}s, tokens/sec=${tokens_per_sec}"
  
  echo "$tokens_per_sec"
}

# Find optimal GPU layer configuration for a model
optimize_gpu_layers() {
  local model="$1"
  local max_layers="${2:-99}"  # Maximum GPU layers to test (default: 99, which is effectively all)
  
  if [[ -z "$model" ]]; then
    log_error "Model name required for GPU optimization"
    return 1
  fi
  
  print_header "🎮 Optimizing GPU Layers for $model"
  
  # Test different GPU layer configurations
  # On Apple Silicon, we typically want to use all available layers
  # But we can test a few configurations to find the sweet spot
  
  local best_layers="auto"
  local best_performance=0
  
  # Test configurations: auto, then specific layer counts if needed
  local test_configs=("auto")
  
  # For Apple Silicon, test a few specific configurations
  # Most models benefit from using all GPU layers, but we can test
  if [[ "$CPU_ARCH" == "arm64" ]]; then
    # Test common configurations for Apple Silicon
    # Note: Actual layer counts depend on model size
    # We'll test a few reasonable values
    local model_ram
    model_ram=$(get_model_ram "$model")
    local model_ram_int
    model_ram_int=$(echo "$model_ram" | awk '{if ($1+0 == $1) printf "%.0f", $1; else print "0"}')
    
    # For larger models, test fewer GPU layers (may need CPU fallback)
    if [[ $model_ram_int -gt 20 ]]; then
      test_configs=("auto" "80" "60" "40")
    elif [[ $model_ram_int -gt 10 ]]; then
      test_configs=("auto" "60" "40" "20")
    else
      test_configs=("auto" "40" "20" "10")
    fi
  fi
  
  print_info "Testing GPU layer configurations..."
  
  for config in "${test_configs[@]}"; do
    if [[ "$config" == "auto" ]] || [[ $config -le $max_layers ]]; then
      print_info "Testing with ${config} GPU layers..."
      local performance
      performance=$(benchmark_gpu_layers "$model" "$config" 2>/dev/null || echo "0")
      
      # Convert to integer for comparison
      local perf_int
      perf_int=$(echo "$performance" | awk '{if ($1+0 == $1) printf "%.0f", $1; else print "0"}')
      
      if [[ "$perf_int" =~ ^[0-9]+$ ]] && [[ $perf_int -gt $best_performance ]]; then
        best_performance=$perf_int
        best_layers="$config"
      fi
      
      # Small delay between tests
      sleep 2
    fi
  done
  
  if [[ "$best_layers" != "auto" ]] && [[ $best_performance -gt 0 ]]; then
    print_success "Optimal GPU layers: $best_layers (performance: ~${best_performance} tokens/sec)"
    log_info "Optimal GPU layers for $model: $best_layers"
    echo "$best_layers"
  else
    print_info "Auto GPU layer configuration is optimal"
    log_info "Auto GPU layer configuration is optimal for $model"
    echo "auto"
  fi
}

# ============================================================================
# Request Queuing
# ============================================================================

# Request queue state file
REQUEST_QUEUE_FILE="$STATE_DIR/request_queue.json"
REQUEST_QUEUE_LOCK="$STATE_DIR/request_queue.lock"

# Initialize request queue
init_request_queue() {
  if [[ ! -f "$REQUEST_QUEUE_FILE" ]]; then
    mkdir -p "$STATE_DIR"
    echo '{"queue": [], "processing": []}' > "$REQUEST_QUEUE_FILE"
    log_info "Initialized request queue"
  fi
}

# Add request to queue
queue_request() {
  local prompt="$1"
  local task_type="${2:-general}"
  local priority="${3:-5}"  # Priority: 1 (highest) to 10 (lowest)
  local role="${4:-coding}"
  
  if [[ -z "$prompt" ]]; then
    log_error "Cannot queue empty prompt"
    return 1
  fi
  
  init_request_queue
  
  # Generate unique request ID
  local request_id
  if command -v uuidgen &>/dev/null; then
    request_id=$(date +%s)-$(uuidgen 2>/dev/null | cut -d'-' -f1 || echo "$$")
  else
    # Fallback: use timestamp + process ID + random number
    request_id=$(date +%s)-$$-$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d ' ' || echo "$RANDOM")
  fi
  
  local timestamp=$(date +%s)
  
  # Add to queue with priority
  if command -v jq &>/dev/null; then
    local current_queue
    current_queue=$(cat "$REQUEST_QUEUE_FILE" 2>/dev/null || echo '{"queue": [], "processing": []}')
    local updated_queue
    updated_queue=$(echo "$current_queue" | jq --arg id "$request_id" \
      --arg prompt "$prompt" \
      --arg task_type "$task_type" \
      --arg role "$role" \
      --argjson priority "$priority" \
      --argjson timestamp "$timestamp" \
      '.queue += [{"id": $id, "prompt": $prompt, "task_type": $task_type, "role": $role, "priority": $priority, "timestamp": $timestamp}]' 2>/dev/null || echo "$current_queue")
    echo "$updated_queue" > "$REQUEST_QUEUE_FILE"
  else
    # Fallback: simple text-based queue
    echo "${request_id}|${priority}|${timestamp}|${task_type}|${role}|${prompt}" >> "$REQUEST_QUEUE_FILE"
  fi
  
  log_info "Queued request: $request_id (priority: $priority, task_type: $task_type)"
  echo "$request_id"
}

# Process queued requests (batch processing)
process_request_queue() {
  local batch_size="${1:-5}"  # Number of requests to process in batch
  local max_wait="${2:-10}"  # Maximum seconds to wait for batch formation
  
  init_request_queue
  
  # Simple lock mechanism (file-based)
  if [[ -f "$REQUEST_QUEUE_LOCK" ]]; then
    local lock_age
    lock_age=$(($(date +%s) - $(stat -f %m "$REQUEST_QUEUE_LOCK" 2>/dev/null || echo "0")))
    # Remove stale locks (older than 5 minutes)
    if [[ $lock_age -gt 300 ]]; then
      rm -f "$REQUEST_QUEUE_LOCK"
    else
      log_info "Request queue is being processed by another process"
      return 0
    fi
  fi
  
  touch "$REQUEST_QUEUE_LOCK"
  
  # Get queued requests
  local requests_to_process=()
  
  if command -v jq &>/dev/null; then
    local queue_data
    queue_data=$(cat "$REQUEST_QUEUE_FILE" 2>/dev/null || echo '{"queue": [], "processing": []}')
    local queue_length
    queue_length=$(echo "$queue_data" | jq '.queue | length' 2>/dev/null || echo "0")
    
    if [[ $queue_length -eq 0 ]]; then
      rm -f "$REQUEST_QUEUE_LOCK"
      return 0  # No requests in queue
    fi
    
    # Sort by priority (lower number = higher priority) and get top N
    local sorted_requests
    sorted_requests=$(echo "$queue_data" | jq -c '.queue | sort_by(.priority) | .[0:'$batch_size']' 2>/dev/null || echo "[]")
    
    # Process each request
    echo "$sorted_requests" | jq -r '.[] | "\(.id)|\(.prompt)|\(.task_type)|\(.role)"' 2>/dev/null | while IFS='|' read -r id prompt task_type role; do
      if [[ -n "$id" ]] && [[ -n "$prompt" ]]; then
        # Execute request
        local response
        response=$(execute_task_with_routing "$task_type" "$prompt" "$role" 2>/dev/null || echo "")
        
        # Remove from queue
        queue_data=$(echo "$queue_data" | jq --arg id "$id" '.queue = (.queue | map(select(.id != $id)))' 2>/dev/null || echo "$queue_data")
        echo "$queue_data" > "$REQUEST_QUEUE_FILE"
        
        log_info "Processed queued request: $id"
      fi
    done
  else
    # Fallback: simple text-based processing
    # Sort by priority and process
    local sorted_requests
    sorted_requests=$(grep -v "^$" "$REQUEST_QUEUE_FILE" 2>/dev/null | sort -t'|' -k2 -n | head -n "$batch_size" || echo "")
    
    while IFS='|' read -r id priority timestamp task_type role prompt; do
      if [[ -n "$id" ]] && [[ -n "$prompt" ]]; then
        execute_task_with_routing "$task_type" "$prompt" "$role" >/dev/null 2>&1
        # Remove from queue (simple grep -v)
        grep -v "^${id}|" "$REQUEST_QUEUE_FILE" > "${REQUEST_QUEUE_FILE}.tmp" 2>/dev/null && mv "${REQUEST_QUEUE_FILE}.tmp" "$REQUEST_QUEUE_FILE" 2>/dev/null || true
        log_info "Processed queued request: $id"
      fi
    done <<< "$sorted_requests"
  fi
  
  rm -f "$REQUEST_QUEUE_LOCK"
  return 0
}

# Get queue status
get_queue_status() {
  init_request_queue
  
  if command -v jq &>/dev/null; then
    local queue_data
    queue_data=$(cat "$REQUEST_QUEUE_FILE" 2>/dev/null || echo '{"queue": [], "processing": []}')
    local queue_length
    queue_length=$(echo "$queue_data" | jq '.queue | length' 2>/dev/null || echo "0")
    echo "$queue_length"
  else
    # Fallback: count lines
    local queue_length
    queue_length=$(grep -c "^[^|]*|" "$REQUEST_QUEUE_FILE" 2>/dev/null || echo "0")
    echo "$queue_length"
  fi
}

# ============================================================================
# Performance Profiling
# ============================================================================

# Track performance metrics for a model request
track_performance() {
  local model="$1"
  local task_type="${2:-general}"
  local duration="${3:-0}"  # Duration in seconds
  local tokens="${4:-0}"  # Number of tokens generated
  local success="${5:-1}"  # 1 for success, 0 for failure
  
  init_performance_metrics
  
  local timestamp=$(date +%s)
  local tokens_per_sec=0
  
  if command -v bc &>/dev/null && [[ $(echo "$duration > 0" | bc 2>/dev/null || echo "0") -eq 1 ]] && [[ $tokens -gt 0 ]]; then
    tokens_per_sec=$(echo "scale=2; $tokens / $duration" | bc 2>/dev/null || echo "0")
  elif [[ ${duration%%.*} -gt 0 ]] && [[ $tokens -gt 0 ]]; then
    local duration_int=${duration%%.*}
    tokens_per_sec=$((tokens / duration_int))
  fi
  
  if command -v jq &>/dev/null; then
    local current_metrics
    current_metrics=$(cat "$PERFORMANCE_METRICS_FILE" 2>/dev/null || echo '{}')
    local model_key="${model}_${task_type}"
    local updated_metrics
    updated_metrics=$(echo "$current_metrics" | jq --arg key "$model_key" \
      --argjson duration "$duration" \
      --argjson tokens "$tokens" \
      --argjson tokens_per_sec "$tokens_per_sec" \
      --argjson success "$success" \
      --argjson timestamp "$timestamp" \
      '. + {($key): {duration: $duration, tokens: $tokens, tokens_per_sec: $tokens_per_sec, success: ($success == 1), timestamp: $timestamp}}' 2>/dev/null || echo "$current_metrics")
    echo "$updated_metrics" > "$PERFORMANCE_METRICS_FILE"
  fi
  
  log_info "Performance tracked: $model, task=$task_type, duration=${duration}s, tokens/sec=${tokens_per_sec}"
}

# Get performance statistics for a model
get_performance_stats() {
  local model="${1:-}"
  local task_type="${2:-}"
  
  init_performance_metrics
  
  if [[ ! -f "$PERFORMANCE_METRICS_FILE" ]]; then
    echo "{}"
    return 0
  fi
  
  if command -v jq &>/dev/null; then
    local metrics
    metrics=$(cat "$PERFORMANCE_METRICS_FILE" 2>/dev/null || echo '{}')
    
    if [[ -n "$model" ]] && [[ -n "$task_type" ]]; then
      # Get specific model+task stats
      local key="${model}_${task_type}"
      echo "$metrics" | jq --arg key "$key" '.[$key] // {}' 2>/dev/null || echo "{}"
    elif [[ -n "$model" ]]; then
      # Get all stats for a model
      echo "$metrics" | jq --arg model "$model" 'to_entries | map(select(.key | startswith($model))) | from_entries' 2>/dev/null || echo "{}"
    else
      # Get all stats
      echo "$metrics"
    fi
  else
    # Fallback: return raw file
    cat "$PERFORMANCE_METRICS_FILE" 2>/dev/null || echo "{}"
  fi
}

# Generate performance report
generate_performance_report() {
  local output_file="${1:-$STATE_DIR/performance_report.txt}"
  
  print_header "📊 Performance Report"
  
  init_performance_metrics
  
  local report_content=""
  report_content+="Performance Report - Generated: $(date)\n"
  report_content+="==========================================\n\n"
  
  if command -v jq &>/dev/null; then
    local metrics
    metrics=$(cat "$PERFORMANCE_METRICS_FILE" 2>/dev/null || echo '{}')
    
    # Get all model-task combinations
    echo "$metrics" | jq -r 'to_entries[] | "\(.key)|\(.value.duration // 0)|\(.value.tokens // 0)|\(.value.tokens_per_sec // 0)|\(.value.success // false)"' 2>/dev/null | while IFS='|' read -r key duration tokens tokens_per_sec success; do
      if [[ -n "$key" ]]; then
        report_content+="Model/Task: $key\n"
        report_content+="  Duration: ${duration}s\n"
        report_content+="  Tokens: $tokens\n"
        report_content+="  Tokens/sec: ${tokens_per_sec}\n"
        report_content+="  Success: $success\n\n"
      fi
    done
  else
    report_content+="Performance metrics available (jq required for detailed parsing)\n"
  fi
  
  # Write to file
  echo -e "$report_content" > "$output_file"
  print_success "Performance report saved to: $output_file"
  log_info "Performance report generated: $output_file"
  
  # Also display summary
  echo -e "$report_content"
}

# ============================================================================
# Advanced Optimizations
# ============================================================================

# ============================================================================
# Model Fusion/Ensemble
# ============================================================================

# Execute prompt with multiple models and combine results
execute_ensemble() {
  local prompt="$1"
  local task_type="${2:-general}"
  local models="${3:-}"  # Comma-separated list of models, or empty for auto-selection
  local strategy="${4:-weighted}"  # Strategy: weighted, majority, best, average
  
  if [[ -z "$prompt" ]]; then
    log_error "Cannot execute ensemble with empty prompt"
    return 1
  fi
  
  # Auto-select models if not provided
  if [[ -z "$models" ]]; then
    local installed_models
    installed_models=$(get_installed_models)
    
    # Select 2-3 models based on task type
    case "$task_type" in
      autocomplete|simple|quick)
        # Use 2 small, fast models
        models=$(echo "$installed_models" | head -n 2 | tr '\n' ',' | sed 's/,$//')
        ;;
      coding|generation|moderate)
        # Use 2-3 balanced models
        models=$(echo "$installed_models" | head -n 3 | tr '\n' ',' | sed 's/,$//')
        ;;
      refactoring|complex|analysis)
        # Use 2-3 models including at least one large model
        models=$(echo "$installed_models" | tr '\n' ',' | sed 's/,$//')
        ;;
      *)
        # Default: use first 2 models
        models=$(echo "$installed_models" | head -n 2 | tr '\n' ',' | sed 's/,$//')
        ;;
    esac
  fi
  
  if [[ -z "$models" ]]; then
    log_error "No models available for ensemble"
    return 1
  fi
  
  print_info "Executing ensemble with models: $models (strategy: $strategy)"
  log_info "Ensemble execution: models=$models, task_type=$task_type, strategy=$strategy"
  
  # Split models into array
  IFS=',' read -ra MODEL_ARRAY <<< "$models"
  local model_count=${#MODEL_ARRAY[@]}
  
  if [[ $model_count -eq 0 ]]; then
    log_error "No valid models in ensemble"
    return 1
  fi
  
  # Execute with each model in parallel (simulated - sequential for now)
  local responses=()
  local durations=()
  local model_index=0
  
  for model in "${MODEL_ARRAY[@]}"; do
    model=$(echo "$model" | xargs)  # Trim whitespace
    if [[ -z "$model" ]]; then
      continue
    fi
    
    print_info "Running model $((model_index + 1))/$model_count: $model"
    
    # Ensure model is loaded
    smart_load_model "$model" 0 >/dev/null 2>&1 || true
    
    # Get optimized parameters
    local tier="${HARDWARE_TIER:-B}"
    local params
    params=$(tune_model_optimized "$model" "$tier" "coding" "$task_type" 0)
    
    # Extract parameters
    local context_size max_tokens temperature
    if command -v jq &>/dev/null; then
      context_size=$(echo "$params" | jq -r '.context_size // 8192')
      max_tokens=$(echo "$params" | jq -r '.max_tokens // 2048')
      temperature=$(echo "$params" | jq -r '.temperature // 0.7')
    else
      context_size=$(echo "$params" | grep -o '"context_size": [0-9]*' | grep -o '[0-9]*' || echo "8192")
      max_tokens=$(echo "$params" | grep -o '"max_tokens": [0-9]*' | grep -o '[0-9]*' || echo "2048")
      temperature=$(echo "$params" | grep -o '"temperature": [0-9.]*' | grep -o '[0-9.]*' || echo "0.7")
    fi
    
    # Execute request
    local start_time
    start_time=$(date +%s.%N 2>/dev/null || date +%s)
    
    local response
    response=$(curl -s --max-time 300 -X POST http://localhost:11434/api/generate \
      -H "Content-Type: application/json" \
      -d "{\"model\": \"$model\", \"prompt\": \"$prompt\", \"stream\": false, \"options\": {\"num_ctx\": $context_size, \"num_predict\": $max_tokens, \"temperature\": $temperature}}" 2>/dev/null || echo "")
    
    local end_time
    end_time=$(date +%s.%N 2>/dev/null || date +%s)
    
    # Calculate duration
    local duration=0
    if command -v bc &>/dev/null && [[ "$start_time" =~ \. ]] && [[ "$end_time" =~ \. ]]; then
      duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
    else
      local start_int=${start_time%%.*}
      local end_int=${end_time%%.*}
      duration=$((end_int - start_int))
    fi
    
    # Extract response text
    local response_text=""
    if [[ -n "$response" ]]; then
      if command -v jq &>/dev/null; then
        response_text=$(echo "$response" | jq -r '.response // .' 2>/dev/null || echo "$response")
      else
        response_text="$response"
      fi
    fi
    
    if [[ -n "$response_text" ]]; then
      responses+=("$response_text")
      durations+=("$duration")
      track_model_usage "$model"
      track_performance "$model" "$task_type" "$duration" 0 1
    else
      log_warn "Model $model failed to generate response"
    fi
    
    ((model_index++))
  done
  
  # Combine responses based on strategy
  local final_response=""
  
  case "$strategy" in
    weighted)
      # Weight responses by model size/quality (larger models get more weight)
      final_response=$(combine_responses_weighted "${responses[@]}" "${MODEL_ARRAY[@]}")
      ;;
    majority)
      # Use majority voting (for code generation, use longest/most complete)
      final_response=$(combine_responses_majority "${responses[@]}")
      ;;
    best)
      # Use the response from the best-performing model
      final_response=$(combine_responses_best "${responses[@]}" "${durations[@]}" "${MODEL_ARRAY[@]}")
      ;;
    average|merge)
      # Merge responses intelligently
      final_response=$(combine_responses_merge "${responses[@]}")
      ;;
    *)
      # Default: use first successful response
      if [[ ${#responses[@]} -gt 0 ]]; then
        final_response="${responses[0]}"
      fi
      ;;
  esac
  
  if [[ -n "$final_response" ]]; then
    log_info "Ensemble execution complete (${#responses[@]}/${model_count} models succeeded)"
    echo "$final_response"
    return 0
  else
    log_error "Ensemble execution failed - no valid responses"
    return 1
  fi
}

# Combine responses with weighted voting
combine_responses_weighted() {
  local responses=("$@")
  local model_count=${#responses[@]}
  local models_start=$((model_count / 2))
  local models=("${responses[@]:$models_start}")
  
  # Simple implementation: use the longest response (often most complete)
  # In production, this could use semantic similarity, voting, etc.
  local longest=""
  local max_length=0
  
  for response in "${responses[@]:0:$models_start}"; do
    local length=${#response}
    if [[ $length -gt $max_length ]]; then
      max_length=$length
      longest="$response"
    fi
  done
  
  echo "$longest"
}

# Combine responses with majority voting
combine_responses_majority() {
  local responses=("$@")
  
  # For code/text generation, use the most complete response
  # (longest that's not just repetition)
  local best=""
  local max_length=0
  
  for response in "${responses[@]}"; do
    local length=${#response}
    # Check for repetition (simple heuristic)
    local first_100="${response:0:100}"
    local repetition_count
    repetition_count=$(echo "$response" | grep -o "$first_100" | wc -l | tr -d ' ' || echo "1")
    
    # Prefer longer responses with less repetition
    if [[ $length -gt $max_length ]] && [[ $repetition_count -lt 3 ]]; then
      max_length=$length
      best="$response"
    fi
  done
  
  echo "${best:-${responses[0]}}"
}

# Combine responses by selecting best-performing model's response
combine_responses_best() {
  local responses=("$@")
  local durations_start=$((${#responses[@]} / 3))
  local models_start=$((durations_start + ${#responses[@]} / 3))
  
  local durations=("${responses[@]:$durations_start:$((models_start - durations_start))}")
  local models=("${responses[@]:$models_start}")
  local actual_responses=("${responses[@]:0:$durations_start}")
  
  # Find fastest response (best performance)
  local best_index=0
  local best_duration=999999
  
  for i in "${!durations[@]}"; do
    local dur="${durations[$i]}"
    local dur_int
    dur_int=$(echo "$dur" | awk '{if ($1+0 == $1) printf "%.0f", $1; else print "999999"}')
    if [[ "$dur_int" =~ ^[0-9]+$ ]] && [[ $dur_int -lt $best_duration ]]; then
      best_duration=$dur_int
      best_index=$i
    fi
  done
  
  if [[ $best_index -lt ${#actual_responses[@]} ]]; then
    echo "${actual_responses[$best_index]}"
  else
    echo "${actual_responses[0]}"
  fi
}

# Merge multiple responses intelligently
combine_responses_merge() {
  local responses=("$@")
  
  # Simple merge: combine unique parts, remove duplicates
  # In production, could use semantic analysis
  local merged=""
  local seen_chunks=()
  
  for response in "${responses[@]}"; do
    # Split into sentences/lines
    while IFS= read -r line; do
      if [[ -n "$line" ]]; then
        # Check if we've seen similar content (simple substring check)
        local is_duplicate=0
        for seen in "${seen_chunks[@]}"; do
          if [[ "$line" == "$seen" ]] || [[ "$seen" == *"$line"* ]] || [[ "$line" == *"$seen"* ]]; then
            is_duplicate=1
            break
          fi
        done
        
        if [[ $is_duplicate -eq 0 ]]; then
          merged+="$line"$'\n'
          seen_chunks+=("$line")
        fi
      fi
    done <<< "$response"
  done
  
  echo "$merged"
}

# ============================================================================
# Context Compression
# ============================================================================

# Compress context when approaching limits
compress_context() {
  local context="$1"
  local max_tokens="${2:-8192}"  # Maximum tokens allowed
  local compression_ratio="${3:-0.7}"  # Target compression ratio (0.7 = 70% of original)
  
  if [[ -z "$context" ]]; then
    echo ""
    return 0
  fi
  
  # Estimate token count (rough: ~4 chars per token)
  local context_length=${#context}
  local estimated_tokens=0
  if command -v bc &>/dev/null; then
    estimated_tokens=$(echo "$context_length / 4" | bc 2>/dev/null || echo "0")
  else
    estimated_tokens=$((context_length / 4))
  fi
  
  # Check if compression is needed
  if [[ $estimated_tokens -le $max_tokens ]]; then
    log_info "Context within limits ($estimated_tokens tokens), no compression needed"
    echo "$context"
    return 0
  fi
  
  print_info "Compressing context: ${estimated_tokens} tokens -> target: $((max_tokens * compression_ratio)) tokens"
  log_info "Context compression: ${estimated_tokens} tokens, max=${max_tokens}, ratio=${compression_ratio}"
  
  # Compression strategies
  local compressed_context=""
  
  # Strategy 1: Remove less relevant sections (comments, whitespace)
  compressed_context=$(compress_context_remove_noise "$context")
  
  # Strategy 2: Summarize long sections
  if [[ ${#compressed_context} -gt $((max_tokens * 4 * compression_ratio)) ]]; then
    compressed_context=$(compress_context_summarize "$compressed_context" "$max_tokens" "$compression_ratio")
  fi
  
  # Strategy 3: Truncate if still too long (keep beginning and end)
  if [[ ${#compressed_context} -gt $((max_tokens * 4)) ]]; then
    compressed_context=$(compress_context_truncate "$compressed_context" "$max_tokens")
  fi
  
  local final_length=${#compressed_context}
  local final_tokens=0
  if command -v bc &>/dev/null; then
    final_tokens=$(echo "$final_length / 4" | bc 2>/dev/null || echo "0")
  else
    final_tokens=$((final_length / 4))
  fi
  
  log_info "Context compressed: ${estimated_tokens} -> ${final_tokens} tokens"
  echo "$compressed_context"
}

# Remove noise from context (comments, excessive whitespace)
compress_context_remove_noise() {
  local context="$1"
  
  # Remove single-line comments (// comments)
  context=$(echo "$context" | sed 's|//.*$||g')
  
  # Remove multi-line comments (/* */)
  context=$(echo "$context" | sed 's|/\*.*\*/||g')
  
  # Remove excessive blank lines (more than 2 consecutive)
  context=$(echo "$context" | sed '/^$/N;/^\n$/d' | sed '/^$/N;/^\n$/d')
  
  # Remove trailing whitespace
  context=$(echo "$context" | sed 's/[[:space:]]*$//')
  
  echo "$context"
}

# Summarize long sections of context
compress_context_summarize() {
  local context="$1"
  local max_tokens="$2"
  local ratio="$3"
  local target_length=$((max_tokens * 4 * $(echo "$ratio" | awk '{printf "%.0f", $1 * 100}') / 100))
  
  # Split into logical sections (by function, class, etc.)
  # Simple implementation: split by double newlines or function/class definitions
  
  # Keep first and last sections, summarize middle
  local lines
  lines=$(echo "$context" | wc -l | tr -d ' ')
  local keep_lines=$((lines / 4))  # Keep first and last 25%
  
  if [[ $lines -gt $((keep_lines * 2)) ]]; then
    local first_part
    first_part=$(echo "$context" | head -n "$keep_lines")
    local last_part
    last_part=$(echo "$context" | tail -n "$keep_lines")
    local middle_part
    middle_part=$(echo "$context" | sed -n "$((keep_lines + 1)),$((lines - keep_lines))p")
    
    # Summarize middle part (keep structure, remove details)
    local summarized_middle
    summarized_middle=$(echo "$middle_part" | grep -E "^(function|class|interface|type|const|let|var|export)" | head -n 20)
    
    context="${first_part}"$'\n'"... [${#middle_part} chars summarized to ${#summarized_middle} chars] ..."$'\n'"${last_part}"
  fi
  
  echo "$context"
}

# Truncate context intelligently (keep beginning and end)
compress_context_truncate() {
  local context="$1"
  local max_tokens="$2"
  local max_chars=$((max_tokens * 4))
  
  if [[ ${#context} -le $max_chars ]]; then
    echo "$context"
    return 0
  fi
  
  # Keep first 40% and last 40%, remove middle 20%
  local keep_chars=$((max_chars * 40 / 100))
  local first_part="${context:0:$keep_chars}"
  local last_part="${context: -$keep_chars}"
  
  echo "${first_part}"$'\n'"... [truncated ${#context} chars to $max_chars] ..."$'\n'"${last_part}"
}

# ============================================================================
# Prompt Optimization
# ============================================================================

# Prompt cache and optimization state
PROMPT_CACHE_FILE="$STATE_DIR/prompt_cache.json"
PROMPT_OPTIMIZATION_FILE="$STATE_DIR/prompt_optimizations.json"

# Initialize prompt optimization
init_prompt_optimization() {
  if [[ ! -f "$PROMPT_CACHE_FILE" ]]; then
    mkdir -p "$STATE_DIR"
    echo '{}' > "$PROMPT_CACHE_FILE"
    log_info "Initialized prompt cache"
  fi
  
  if [[ ! -f "$PROMPT_OPTIMIZATION_FILE" ]]; then
    mkdir -p "$STATE_DIR"
    echo '{}' > "$PROMPT_OPTIMIZATION_FILE"
    log_info "Initialized prompt optimization tracking"
  fi
}

# Optimize a prompt based on historical performance
optimize_prompt() {
  local prompt="$1"
  local task_type="${2:-general}"
  local model="${3:-}"  # Optional: model-specific optimization
  
  if [[ -z "$prompt" ]]; then
    log_error "Cannot optimize empty prompt"
    echo ""
    return 1
  fi
  
  init_prompt_optimization
  
  # Check cache first
  local prompt_hash
  prompt_hash=$(echo -n "$prompt" | shasum -a 256 2>/dev/null | cut -d' ' -f1 || echo "$prompt")
  
  if command -v jq &>/dev/null; then
    local cached
    cached=$(jq -r --arg hash "$prompt_hash" '.[$hash] // empty' "$PROMPT_CACHE_FILE" 2>/dev/null || echo "")
    if [[ -n "$cached" ]] && [[ "$cached" != "null" ]]; then
      log_info "Using cached optimized prompt"
      echo "$cached"
      return 0
    fi
  fi
  
  # Analyze prompt and suggest optimizations
  local optimized_prompt
  optimized_prompt=$(analyze_and_optimize_prompt "$prompt" "$task_type")
  
  # Cache optimized prompt
  if command -v jq &>/dev/null; then
    local current_cache
    current_cache=$(cat "$PROMPT_CACHE_FILE" 2>/dev/null || echo '{}')
    local updated_cache
    updated_cache=$(echo "$current_cache" | jq --arg hash "$prompt_hash" --arg optimized "$optimized_prompt" \
      '. + {($hash): $optimized}' 2>/dev/null || echo "$current_cache")
    echo "$updated_cache" > "$PROMPT_CACHE_FILE"
  fi
  
  log_info "Prompt optimized for task_type: $task_type"
  echo "$optimized_prompt"
}

# Analyze prompt and apply optimizations
analyze_and_optimize_prompt() {
  local prompt="$1"
  local task_type="$2"
  local optimized="$prompt"
  
  # Optimization 1: Add task-specific context
  case "$task_type" in
    coding|generation)
      # Ensure prompt includes code context requirements
      if [[ "$prompt" != *"TypeScript"* ]] && [[ "$prompt" != *"React"* ]] && [[ "$prompt" != *"code"* ]]; then
        optimized="[Code Generation Task]\n${optimized}\n\nRequirements: Use TypeScript with strict typing, follow React best practices."
      fi
      ;;
    code-review|testing)
      # Add review checklist
      if [[ "$prompt" != *"check"* ]] && [[ "$prompt" != *"review"* ]]; then
        optimized="[Code Review Task]\n${optimized}\n\nReview for: correctness, type safety, performance, best practices."
      fi
      ;;
    refactoring|multi-file)
      # Add safety requirements
      if [[ "$prompt" != *"safe"* ]] && [[ "$prompt" != *"incremental"* ]]; then
        optimized="[Refactoring Task - Safety First]\n${optimized}\n\nRequirements: Show affected files first, propose minimal changes, preserve functionality."
      fi
      ;;
  esac
  
  # Optimization 2: Remove redundancy
  optimized=$(remove_prompt_redundancy "$optimized")
  
  # Optimization 3: Add structure for complex tasks
  if [[ "$task_type" == "complex" ]] || [[ "$task_type" == "refactoring" ]]; then
    optimized=$(structure_complex_prompt "$optimized")
  fi
  
  # Optimization 4: Ensure clarity and specificity
  optimized=$(improve_prompt_clarity "$optimized")
  
  echo "$optimized"
}

# Remove redundant phrases from prompt
remove_prompt_redundancy() {
  local prompt="$1"
  
  # Remove common redundant phrases
  prompt=$(echo "$prompt" | sed 's/please please/please/gi')
  prompt=$(echo "$prompt" | sed 's/\bvery very\b/very/gi')
  prompt=$(echo "$prompt" | sed 's/\bimportant important\b/important/gi')
  
  # Remove duplicate sentences (simple check)
  local lines
  lines=$(echo "$prompt" | grep -v '^$')
  local unique_lines=()
  local seen=()
  
  while IFS= read -r line; do
    local is_duplicate=0
    for seen_line in "${seen[@]}"; do
      if [[ "$line" == "$seen_line" ]]; then
        is_duplicate=1
        break
      fi
    done
    
    if [[ $is_duplicate -eq 0 ]]; then
      unique_lines+=("$line")
      seen+=("$line")
    fi
  done <<< "$lines"
  
  printf '%s\n' "${unique_lines[@]}"
}

# Structure complex prompts better
structure_complex_prompt() {
  local prompt="$1"
  
  # Check if already structured
  if [[ "$prompt" == *"Step 1"* ]] || [[ "$prompt" == *"1."* ]] || [[ "$prompt" == *"Task:"* ]]; then
    echo "$prompt"
    return 0
  fi
  
  # Add structure for multi-step tasks
  local structured="Task: ${prompt}\n\nSteps:\n1. Analyze requirements\n2. Identify affected components\n3. Propose solution\n4. Implement changes\n5. Verify correctness"
  
  echo "$structured"
}

# Improve prompt clarity
improve_prompt_clarity() {
  local prompt="$1"
  
  # Ensure prompt ends with clear instruction
  if [[ "$prompt" != *"?"* ]] && [[ "$prompt" != *"."* ]] && [[ "$prompt" != *"!"* ]]; then
    prompt="${prompt}."
  fi
  
  # Ensure it's not too vague
  if [[ ${#prompt} -lt 20 ]]; then
    prompt="${prompt} Please provide detailed response with examples."
  fi
  
  echo "$prompt"
}

# Track prompt performance for optimization
track_prompt_performance() {
  local prompt="$1"
  local optimized_prompt="$2"
  local task_type="$3"
  local success="${4:-1}"  # 1 for success, 0 for failure
  local duration="${5:-0}"  # Response duration
  local quality_score="${6:-0}"  # Optional quality score (0-10)
  
  init_prompt_optimization
  
  local prompt_hash
  prompt_hash=$(echo -n "$prompt" | shasum -a 256 2>/dev/null | cut -d' ' -f1 || echo "$prompt")
  
  if command -v jq &>/dev/null; then
    local current_data
    current_data=$(cat "$PROMPT_OPTIMIZATION_FILE" 2>/dev/null || echo '{}')
    local timestamp=$(date +%s)
    
    local updated_data
    updated_data=$(echo "$current_data" | jq --arg hash "$prompt_hash" \
      --arg task_type "$task_type" \
      --argjson success "$success" \
      --argjson duration "$duration" \
      --argjson quality "$quality_score" \
      --argjson timestamp "$timestamp" \
      '. + {($hash): {task_type: $task_type, success: ($success == 1), duration: $duration, quality: $quality, timestamp: $timestamp, count: ((.[$hash].count // 0) + 1)}}' 2>/dev/null || echo "$current_data")
    
    echo "$updated_data" > "$PROMPT_OPTIMIZATION_FILE"
    log_info "Tracked prompt performance: hash=$prompt_hash, success=$success"
  fi
}

# ============================================================================
# Enhanced Batch Processing
# ============================================================================

# Process multiple requests in a single batch (more efficient than queue)
process_batch_requests() {
  local requests_file="${1:-}"  # File with JSON array of requests, or stdin
  local batch_strategy="${2:-parallel}"  # parallel, sequential, smart
  
  if [[ -z "$requests_file" ]] || [[ "$requests_file" == "-" ]]; then
    # Read from stdin
    local requests_json
    requests_json=$(cat)
  else
    local requests_json
    requests_json=$(cat "$requests_file" 2>/dev/null || echo "[]")
  fi
  
  if [[ -z "$requests_json" ]] || [[ "$requests_json" == "[]" ]]; then
    log_error "No requests provided for batch processing"
    return 1
  fi
  
  print_info "Processing batch requests (strategy: $batch_strategy)"
  log_info "Batch processing: strategy=$batch_strategy, requests=$(echo "$requests_json" | jq 'length' 2>/dev/null || echo "?")"
  
  local results=()
  local request_count=0
  
  if command -v jq &>/dev/null; then
    request_count=$(echo "$requests_json" | jq 'length' 2>/dev/null || echo "0")
    
    case "$batch_strategy" in
      parallel)
        # Process all requests in parallel (simulated - sequential for now)
        echo "$requests_json" | jq -c '.[]' 2>/dev/null | while IFS= read -r request; do
          process_single_batch_request "$request"
        done
        ;;
      sequential)
        # Process requests one by one
        echo "$requests_json" | jq -c '.[]' 2>/dev/null | while IFS= read -r request; do
          process_single_batch_request "$request"
        done
        ;;
      smart)
        # Group similar requests and process together
        process_smart_batch "$requests_json"
        ;;
      *)
        # Default: sequential
        echo "$requests_json" | jq -c '.[]' 2>/dev/null | while IFS= read -r request; do
          process_single_batch_request "$request"
        done
        ;;
    esac
  else
    log_warn "jq not available, batch processing limited"
    # Fallback: process as single request
    process_single_batch_request "$requests_json"
  fi
  
  log_info "Batch processing complete: $request_count requests"
}

# Process a single request from batch
process_single_batch_request() {
  local request_json="$1"
  
  if command -v jq &>/dev/null; then
    local prompt
    prompt=$(echo "$request_json" | jq -r '.prompt // ""' 2>/dev/null)
    local task_type
    task_type=$(echo "$request_json" | jq -r '.task_type // "general"' 2>/dev/null)
    local model
    model=$(echo "$request_json" | jq -r '.model // ""' 2>/dev/null)
    local role
    role=$(echo "$request_json" | jq -r '.role // "coding"' 2>/dev/null)
    
    if [[ -z "$prompt" ]]; then
      log_warn "Skipping batch request with empty prompt"
      echo "{\"error\": \"Empty prompt\"}"
      return 1
    fi
    
    # Optimize prompt
    local optimized_prompt
    optimized_prompt=$(optimize_prompt "$prompt" "$task_type" "$model")
    
    # Route to model if not specified
    if [[ -z "$model" ]]; then
      model=$(route_task_to_model "$task_type" 0)
    fi
    
    # Execute with routing
    local response
    response=$(execute_task_with_routing "$task_type" "$optimized_prompt" "$role" 2>/dev/null || echo "")
    
    # Return result as JSON
    if command -v jq &>/dev/null; then
      echo "{\"prompt\": $(echo "$prompt" | jq -R .), \"response\": $(echo "$response" | jq -R .), \"task_type\": \"$task_type\", \"model\": \"$model\"}"
    else
      echo "{\"prompt\": \"$prompt\", \"response\": \"$response\", \"task_type\": \"$task_type\", \"model\": \"$model\"}"
    fi
  else
    log_warn "jq required for batch request processing"
    echo "{\"error\": \"jq required\"}"
    return 1
  fi
}

# Process batch with smart grouping
process_smart_batch() {
  local requests_json="$1"
  
  # Group requests by task_type and model
  if command -v jq &>/dev/null; then
    # Group by task_type
    local task_groups
    task_groups=$(echo "$requests_json" | jq -c 'group_by(.task_type)' 2>/dev/null || echo "[]")
    
    # Process each group
    echo "$task_groups" | jq -c '.[]' 2>/dev/null | while IFS= read -r group; do
      local task_type
      task_type=$(echo "$group" | jq -r '.[0].task_type // "general"' 2>/dev/null)
      local group_size
      group_size=$(echo "$group" | jq 'length' 2>/dev/null || echo "0")
      
      print_info "Processing group: $task_type ($group_size requests)"
      
      # Process group (could be optimized further)
      echo "$group" | jq -c '.[]' 2>/dev/null | while IFS= read -r request; do
        process_single_batch_request "$request"
      done
    done
  fi
}
