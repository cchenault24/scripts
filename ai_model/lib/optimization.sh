#!/bin/bash
#
# optimization.sh - Phase 1 optimization functions for setup-local-llm.sh
#
# Implements:
# - Smart model loading/unloading with usage tracking
# - Memory pressure detection and auto-unload
# - Dynamic context window sizing
# - Adaptive temperature calculation
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

# Enhanced tune_model with Phase 1 optimizations
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
