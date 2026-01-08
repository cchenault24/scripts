#!/bin/bash
#
# models.sh - Model selection, installation, validation, and benchmarking for setup-local-llm.sh
#
# Depends on: constants.sh, logger.sh, ui.sh, hardware.sh, ollama.sh

# Model eligibility check
is_model_eligible() {
  local model="$1"
  local tier="$2"
  
  # Embedding, rerank, and next edit models are always eligible (small)
  case "$model" in
    "nomic-embed-text"|"zerank-1"|"zerank-1-small"|"instinct")
      return 0 ;;
  esac
  
  # Codestral is eligible for all tiers (moderate size, good for autocomplete)
  case "$model" in
    "codestral")
      return 0 ;;
  esac
  
  case "$tier" in
    S) return 0 ;; # All models allowed
    A) 
      # Exclude very large models (70b)
      [[ "$model" != "llama3.1:70b" ]] ;;
    B) 
      # Exclude large models (70b, 27b, 20b), but allow codestral and gemma2:9b
      [[ "$model" != "llama3.1:70b" && \
         "$model" != "devstral:27b" && \
         "$model" != "gpt-oss:20b" ]] ;;
    C) 
      # Only small models (8b, 9b, codestral)
      [[ "$model" == "llama3.1:8b" || "$model" == "gemma2:9b" || "$model" == "codestral" ]] ;;
    *) return 1 ;;
  esac
}

# Validate that a custom model exists in Ollama library
validate_model_exists() {
  local model="$1"
  
  # Basic format validation: should contain at least one colon or be a simple name
  if [[ -z "$model" ]]; then
    print_error "Model name cannot be empty"
    return 1
  fi
  
  # Sanitize model name first
  local sanitized_model
  if command -v sanitize_model_name &>/dev/null; then
    sanitized_model=$(sanitize_model_name "$model")
    if [[ -z "$sanitized_model" ]] || [[ "$sanitized_model" != "$model" ]]; then
      print_error "Model name contains invalid characters"
      return 1
    fi
  fi
  
  # Validate model name format and safety
  if command -v validate_model_name &>/dev/null; then
    if ! validate_model_name "$model"; then
      return 1
    fi
  else
    # Fallback validation
    if ! [[ "$model" =~ ^[a-zA-Z0-9._-]+(:[a-zA-Z0-9._-]+)?$ ]]; then
      print_error "Invalid model name format. Expected format: modelname:tag or modelname"
      print_info "Example: codellama:13b or llama3.1:8b"
      return 1
    fi
  fi
  
  # Check if model is already installed locally
  if is_model_installed "$model"; then
    print_success "Model $model is already installed locally"
    return 0
  fi
  
  # Quick check: try to get model info (works for locally installed models)
  print_info "Checking if model $model exists..."
  if ollama show "$model" &>/dev/null; then
    print_success "Model $model found"
    return 0
  fi
  
  # For models not yet installed, we can't verify existence without downloading
  # Format is valid, so accept it - full validation will happen during installation
  print_success "Model name format is valid: $model"
  print_info "Model availability will be verified during installation."
  return 0
}

# Check if a model is in the approved list
is_approved_model() {
  local model="$1"
  for approved in "${APPROVED_MODELS[@]}"; do
    if [[ "$model" == "$approved" ]]; then
      return 0
    fi
  done
  return 1
}

# Model selection
select_models() {
  print_header "🤖 Model Selection"
  
  echo -e "${CYAN}Select models to install. Models are auto-tuned based on your hardware tier.${NC}"
  echo ""
  
  SELECTED_MODELS=()
  
  # Default selection - optimized for coding tasks on Apple Silicon
  # Based on Continue.dev recommendations: https://docs.continue.dev/customize/models#recommended-models
  # Primary: Best coding model for the tier (Agent Plan/Chat/Edit role)
  # Secondary: Fast alternative for autocomplete/quick tasks
  local default_primary="devstral:27b"
  local default_secondary="codestral"
  
  # Tier-specific optimizations
  case "$HARDWARE_TIER" in
    S)
      # Tier S: Can use best models - Devstral 27B for primary
      if is_model_eligible "devstral:27b" "$HARDWARE_TIER"; then
        default_primary="devstral:27b"
      fi
      # Secondary: codestral for autocomplete (excellent for this role)
      default_secondary="codestral"
      ;;
    A)
      # Tier A: Use devstral:27b or gpt-oss:20b if available
      if is_model_eligible "devstral:27b" "$HARDWARE_TIER"; then
        default_primary="devstral:27b"
      elif is_model_eligible "gpt-oss:20b" "$HARDWARE_TIER"; then
        default_primary="gpt-oss:20b"
      fi
      # Secondary: codestral is excellent for autocomplete
      default_secondary="codestral"
      ;;
    B)
      # Tier B: Use codestral or llama3.1:8b (larger models not eligible)
      if is_model_eligible "codestral" "$HARDWARE_TIER"; then
        default_primary="codestral"
        default_secondary="llama3.1:8b"
      else
        default_primary="llama3.1:8b"
        default_secondary="llama3.1:8b"
      fi
      ;;
    C)
      # Tier C: Use codestral, gemma2:9b, or llama3.1:8b
      if is_model_eligible "codestral" "$HARDWARE_TIER"; then
        default_primary="codestral"
        default_secondary="llama3.1:8b"
      elif is_model_eligible "gemma2:9b" "$HARDWARE_TIER"; then
        default_primary="gemma2:9b"
        default_secondary="llama3.1:8b"
      else
        default_primary="llama3.1:8b"
        default_secondary="llama3.1:8b"
      fi
      ;;
  esac
  
  # Check if defaults are eligible (fallback safety)
  if ! is_model_eligible "$default_primary" "$HARDWARE_TIER"; then
    # Fallback to llama3.1:8b
    default_primary="llama3.1:8b"
  fi
  if ! is_model_eligible "$default_secondary" "$HARDWARE_TIER"; then
    # Fallback to llama3.1:8b
    default_secondary="llama3.1:8b"
  fi
  
  echo -e "${CYAN}Recommended for $TIER_LABEL:${NC}"
  echo -e "  ${GREEN}✓${NC} Primary: ${BOLD}$default_primary${NC}"
  echo -e "  ${GREEN}✓${NC} Secondary: ${BOLD}$default_secondary${NC}"
  echo ""
  
  # Build gum input with all models, sorted by name
  local gum_items=()
  local model_map=()
  local temp_items=()
  
  # Calculate maximum widths for alignment
  local max_model_width=0
  local max_ram_width=0
  
  for model in "${APPROVED_MODELS[@]}"; do
    local is_recommended=false
    if [[ "$model" == "$default_primary" || "$model" == "$default_secondary" ]]; then
      is_recommended=true
    fi
    
    # Calculate model name width
    local model_len=${#model}
    if [[ $model_len -gt $max_model_width ]]; then
      max_model_width=$model_len
    fi
    
    # Calculate RAM width
    local ram=$(get_model_ram "$model")
    local ram_display="${ram}GB"
    local ram_len=${#ram_display}
    if [[ $ram_len -gt $max_ram_width ]]; then
      max_ram_width=$ram_len
    fi
  done
  
  # Add padding
  max_model_width=$((max_model_width + 2))
  max_ram_width=$((max_ram_width + 1))
  
  # Build temporary array with recommended flag, model name and formatted string
  for model in "${APPROVED_MODELS[@]}"; do
    local is_recommended=false
    if [[ "$model" == "$default_primary" || "$model" == "$default_secondary" ]]; then
      is_recommended=true
    fi
    local formatted=$(format_model_for_gum "$model" "$HARDWARE_TIER" "$is_recommended" "$max_model_width" "$max_ram_width")
    # Store as "recommended_flag|model_name|formatted_string" for sorting
    # Use "A" for eligible models (no "Not recommended"), "B" for not eligible (has "Not recommended")
    # This matches the logic in format_model_for_gum which adds "Not recommended" for ineligible models
    local is_eligible=false
    if is_model_eligible "$model" "$HARDWARE_TIER"; then
      is_eligible=true
    fi
    local recommended_flag=$([[ "$is_eligible" == "true" ]] && echo "A" || echo "B")
    temp_items+=("${recommended_flag}|${model}|${formatted}")
  done
  
  # Sort by recommended first (A before B), then by model name using natural sort
  IFS=$'\n' sorted_items=($(printf '%s\n' "${temp_items[@]}" | sort -t'|' -k1,1 -k2,2V))
  unset IFS
  
  # Extract sorted formatted strings and model names
  for item in "${sorted_items[@]}"; do
    local recommended_flag="${item%%|*}"
    local remaining="${item#*|}"
    local model_name="${remaining%%|*}"
    local formatted="${remaining#*|}"
    gum_items+=("$formatted")
    model_map+=("$model_name")
  done
  
  # Add custom model option at the end
  gum_items+=("➕ Enter custom model name")
  model_map+=("CUSTOM")
  
  # Use gum choose for multi-select
  echo ""
  echo -e "${YELLOW}💡 Tip:${NC} Press ${BOLD}Space${NC} to toggle selection, ${BOLD}Enter${NC} to confirm"
  echo ""
  
  local selected_lines
  # Minimal UI: Color-based selection, no prefix symbols, compact layout
  selected_lines=$(printf '%s\n' "${gum_items[@]}" | gum choose \
    --limit=100 \
    --height=15 \
    --cursor="→ " \
    --selected-prefix="" \
    --unselected-prefix="" \
    --selected.foreground="2" \
    --selected.background="0" \
    --cursor.foreground="6" \
    --header="🤖 Select Models for $TIER_LABEL" \
    --header.foreground="6")
  
  if [[ -z "$selected_lines" ]]; then
    log_error "No models selected"
    exit 1
  fi
  
  # Parse gum output - first pass: identify selections and mark if custom input needed
  local needs_custom_input=false
  while IFS= read -r line; do
    if [[ -z "$line" ]]; then
      continue
    fi
    
    # Check if custom model option was selected - mark flag but let it fall through to model matching
    if [[ "$line" == *"Enter custom model name"* ]] || [[ "$line" == *"➕"* ]]; then
      needs_custom_input=true
      # Don't continue - let it fall through to model matching where fallback will handle it
    fi
    
    # Extract model name from formatted line
    # With minimal UI (no prefixes), gum outputs the formatted string directly
    # Strip any leading whitespace or cursor symbols that might be present
    local line_clean="${line#"${line%%[![:space:]]*}"}"  # Remove leading whitespace
    line_clean="${line_clean#→ }"  # Remove cursor if present
    
    # Find matching model from the map
    local model_name=""
    local i=0
    for item in "${gum_items[@]}"; do
      # Direct match (gum outputs selected items as-is with no prefix)
      if [[ "$item" == "$line_clean" ]]; then
        model_name="${model_map[$i]}"
        break
      fi
      ((i++))
    done
    
    # Handle CUSTOM model option - just set flag, don't read here (stdin is invalid after gum)
    if [[ -n "$model_name" ]] && [[ "$model_name" == "CUSTOM" ]]; then
      needs_custom_input=true
      continue
    elif [[ -n "$model_name" ]] && [[ "$model_name" != "CUSTOM" ]] && is_approved_model "$model_name"; then
      SELECTED_MODELS+=("$model_name")
    fi
  done <<< "$selected_lines"
  
  # Remove duplicates (bash 3.2 compatible)
  # Initialize unique_models as empty array (set -u compatibility)
  local unique_models=()
  # Guard against unset array (set -u compatibility)
  if [[ ${#SELECTED_MODELS[@]} -gt 0 ]]; then
    for model in "${SELECTED_MODELS[@]}"; do
      local found=0
      # Guard against empty array access (fixes unbound variable error with set -u)
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
  fi
  # Assign unique_models to SELECTED_MODELS
  # unique_models is always initialized as empty array above, so safe to use
  # Use a safe copy pattern that works with set -u
  SELECTED_MODELS=()
  # Copy elements one by one to avoid any set -u issues with array expansion
  local i
  for ((i=0; i<${#unique_models[@]}; i++)); do
    SELECTED_MODELS+=("${unique_models[$i]}")
  done
  
  # Handle custom model input AFTER parsing all selections (stdin is now in good state)
  # Prompt for custom model if the flag was set, regardless of whether other models were selected
  if [[ "$needs_custom_input" == "true" ]]; then
    while true; do
      echo ""
      echo -e "${YELLOW}Enter custom model name (e.g., codellama:13b):${NC} "
      read -r custom_model || {
        print_info "Custom model input cancelled"
        break
      }
      custom_model=$(echo "$custom_model" | xargs) # trim whitespace
      
      if [[ -z "$custom_model" ]]; then
        print_warn "Model name cannot be empty. Try again or press Ctrl+C to cancel."
        continue
      fi
      
      # Validate the custom model
      if validate_model_exists "$custom_model"; then
        SELECTED_MODELS+=("$custom_model")
        print_success "Custom model $custom_model added to selection"
        
        # Ask if user wants to add more custom models
        if prompt_yes_no "Add another custom model?" "n"; then
          continue
        else
          break
        fi
      else
        # Validation failed - ask if user wants to retry
        if prompt_yes_no "Would you like to try a different model name?" "y"; then
          continue
        else
          print_info "Skipping custom model selection"
          break
        fi
      fi
    done
  fi
  
  # Validate selection
  if [[ ${#SELECTED_MODELS[@]} -eq 0 ]]; then
    log_error "No models selected"
    exit 1
  fi
  
  # Warn about ineligible models
  for model in "${SELECTED_MODELS[@]}"; do
    if ! is_model_eligible "$model" "$HARDWARE_TIER"; then
      print_warn "Model $model is not recommended for $TIER_LABEL hardware"
      if ! prompt_yes_no "Continue with this model anyway?" "n"; then
        SELECTED_MODELS=($(printf '%s\n' "${SELECTED_MODELS[@]}" | grep -v "^${model}$"))
      fi
    fi
  done
  
  # Warn about large models
  for model in "${SELECTED_MODELS[@]}"; do
    # Check if this is a custom model (not in approved list)
    if ! is_approved_model "$model"; then
      # Custom model - show generic warning
      print_warn "Custom model $model selected - RAM requirements unknown"
      if ! prompt_yes_no "Ensure you have sufficient RAM for this model. Continue?" "y"; then
        SELECTED_MODELS=($(printf '%s\n' "${SELECTED_MODELS[@]}" | grep -v "^${model}$"))
      fi
    else
      # Approved model - use known RAM estimates
      local ram=$(get_model_ram "$model")
      # Convert to integer for comparison (bash doesn't handle decimals in arithmetic)
      # Use awk to safely convert decimal to integer, default to 0 if not numeric
      local ram_int=$(echo "$ram" | awk '{if ($1+0 == $1) printf "%.0f", $1; else print "0"}')
      # Ensure ram_int is numeric before comparison
      if [[ "$ram_int" =~ ^[0-9]+$ ]] && [[ $ram_int -gt 20 ]]; then
        if ! prompt_yes_no "Model $model requires ~${ram}GB RAM. Continue?" "n"; then
          SELECTED_MODELS=($(printf '%s\n' "${SELECTED_MODELS[@]}" | grep -v "^${model}$"))
        fi
      fi
    fi
  done
  
  log_info "Selected models: ${SELECTED_MODELS[*]}"
  print_success "Selected ${#SELECTED_MODELS[@]} model(s)"
}

# Auto-tune model parameters
# Supports dynamic optimizations via optional parameters
tune_model() {
  local model="$1"
  local tier="$2"
  local role="${3:-coding}"
  local use_optimizations="${4:-1}"  # Enable optimizations by default
  local task_type="${5:-general}"  # New: Task type for dynamic optimization
  local prompt_length="${6:-0}"  # New: Estimated prompt length
  
  # Use optimized tuning if available and enabled
  if [[ "$use_optimizations" == "1" ]] && command -v tune_model_optimized &>/dev/null; then
    tune_model_optimized "$model" "$tier" "$role" "$task_type" "$prompt_length"
    return
  fi
  
  # Original tuning logic (fallback)
  local context_size
  local max_tokens
  local temperature
  local top_p
  local keep_alive
  local num_gpu
  local num_thread
  
  # GPU and threading settings (from environment or calculated)
  num_gpu="${OLLAMA_NUM_GPU:-1}"
  num_thread="${OLLAMA_NUM_THREAD:-$((CPU_CORES - 2))}"
  if [[ $num_thread -lt 2 ]]; then
    num_thread=2
  fi
  
  case "$tier" in
    S)
      context_size=32768
      max_tokens=4096
      keep_alive="24h"
      ;;
    A)
      context_size=16384
      max_tokens=2048
      keep_alive="12h"
      ;;
    B)
      context_size=8192
      max_tokens=1024
      keep_alive="5m"
      ;;
    C)
      context_size=4096
      max_tokens=512
      keep_alive="5m"
      ;;
  esac
  
  # Role-specific temperature
  case "$role" in
    coding)
      temperature=0.7
      top_p=0.9
      ;;
    code-review)
      temperature=0.3
      top_p=0.95
      ;;
    documentation)
      temperature=0.5
      top_p=0.9
      ;;
    deep-analysis)
      temperature=0.6
      top_p=0.92
      ;;
    *)
      temperature=0.7
      top_p=0.9
      ;;
  esac
  
  # Return as JSON-like structure (will be used in config generation)
  cat <<EOF
{
  "context_size": $context_size,
  "max_tokens": $max_tokens,
  "temperature": $temperature,
  "top_p": $top_p,
  "keep_alive": "$keep_alive",
  "num_gpu": $num_gpu,
  "num_thread": $num_thread
}
EOF
}

# Install model
install_model() {
  local model="$1"
  
  # Validate and sanitize model name
  if ! validate_model_name "$model"; then
    log_error "Invalid model name: $model"
    return 1
  fi
  
  local sanitized_model
  sanitized_model=$(sanitize_model_name "$model")
  if [[ -z "$sanitized_model" ]] || [[ "$sanitized_model" != "$model" ]]; then
    log_error "Model name sanitization failed: $model"
    return 1
  fi
  
  print_info "Installing $sanitized_model..."
  print_info "Ollama will automatically select optimal quantization (Q4_K_M/Q5_K_M) for Apple Silicon"
  log_info "Installing model: $sanitized_model (Ollama auto-optimizes for Apple Silicon)"
  
  # Check if model is already installed
  if is_model_installed "$sanitized_model"; then
    print_success "$sanitized_model already installed, skipping download"
    INSTALLED_MODELS+=("$sanitized_model")
    # Initialize usage tracking for existing model
    if command -v init_usage_tracking &>/dev/null; then
      init_usage_tracking
    fi
    return 0
  fi
  
  # Check network connectivity before download
  if ! check_network_connectivity "https://ollama.com" 2 10 2; then
    log_error "Network connectivity check failed, cannot download model"
    print_error "Cannot download $sanitized_model: network connectivity failed"
    return 1
  fi
  
  # Download model with retry logic - Ollama automatically selects best quantization for Apple Silicon
  local download_success=false
  if command -v retry_with_backoff &>/dev/null; then
    if retry_with_backoff 3 2 "ollama pull \"$sanitized_model\" 2>&1 | tee -a \"$LOG_FILE\""; then
      download_success=true
    fi
  else
    # Fallback: direct download
    if ollama pull "$sanitized_model" 2>&1 | tee -a "$LOG_FILE"; then
      download_success=true
    fi
  fi
  
  if [[ "$download_success" == "true" ]]; then
    # Clear cache to force refresh
    if command -v clear_installed_models_cache &>/dev/null; then
      clear_installed_models_cache
    fi
    
    # Wait a moment for Ollama to update its model list (handles timing issues)
    sleep 1
    
    # Verify model is actually installed with retry logic
    local verification_attempts=0
    local max_verification_attempts=3
    local verification_success=false
    
    while [[ $verification_attempts -lt $max_verification_attempts ]]; do
      if is_model_installed "$sanitized_model"; then
        verification_success=true
        break
      fi
      verification_attempts=$((verification_attempts + 1))
      if [[ $verification_attempts -lt $max_verification_attempts ]]; then
        log_info "Model verification attempt $verification_attempts failed, retrying..."
        sleep 1
        # Clear cache again before retry
        if command -v clear_installed_models_cache &>/dev/null; then
          clear_installed_models_cache
        fi
      fi
    done
    
    if [[ "$verification_success" == "true" ]]; then
      print_success "$sanitized_model installed (automatically optimized for Apple Silicon)"
      log_info "Model $sanitized_model installed with automatic quantization optimization"
      INSTALLED_MODELS+=("$sanitized_model")
      # Initialize usage tracking for new model
      if command -v init_usage_tracking &>/dev/null; then
        init_usage_tracking
      fi
      return 0
    else
      log_error "Model download appeared successful but model is not installed: $sanitized_model"
      print_error "Installation verification failed for $sanitized_model"
      print_info "The model may still be installing. Try running: ollama list"
      return 1
    fi
  else
    log_error "Failed to install $sanitized_model after retries"
    return 1
  fi
}

# Benchmark model performance
benchmark_model_performance() {
  local model="$1"
  
  print_info "Benchmarking $model performance..."
  log_info "Benchmarking model: $model"
  
  # Use smart loading if available
  if command -v smart_load_model &>/dev/null; then
    smart_load_model "$model" 0
  fi
  
  local test_prompt="Write a simple TypeScript function that adds two numbers and returns the result."
  local start_time=$(date +%s.%N 2>/dev/null || date +%s)
  local response
  local token_count=0
  
  # Track model usage
  if command -v track_model_usage &>/dev/null; then
    track_model_usage "$model"
  fi
  
  # Run model and capture response
  response=$(run_with_timeout 60 ollama run "$model" "$test_prompt" 2>&1)
  local end_time=$(date +%s.%N 2>/dev/null || date +%s)
  
  # Calculate duration (handle both formats)
  local duration
  if [[ "$start_time" =~ \. ]] && command -v bc &>/dev/null; then
    duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
  else
    # Fallback to integer arithmetic
    local start_int=${start_time%%.*}
    local end_int=${end_time%%.*}
    duration=$((end_int - start_int))
  fi
  
  # Estimate token count (rough: ~4 chars per token)
  if [[ -n "$response" ]]; then
    if command -v bc &>/dev/null; then
      token_count=$(echo "${#response} / 4" | bc 2>/dev/null || echo "0")
    else
      token_count=$(( ${#response} / 4 ))
    fi
  fi
  
  # Calculate tokens per second
  local tokens_per_sec=0
  # Use bc for floating point comparison if available, otherwise use integer comparison
  local duration_check=0
  if command -v bc &>/dev/null; then
    duration_check=$(echo "$duration > 0" | bc 2>/dev/null || echo "0")
  else
    # Integer comparison fallback
    local duration_int=${duration%%.*}
    if [[ $duration_int -gt 0 ]]; then
      duration_check=1
    fi
  fi
  
  if [[ $duration_check -eq 1 ]] && [[ $token_count -gt 0 ]]; then
    if command -v bc &>/dev/null; then
      tokens_per_sec=$(echo "scale=2; $token_count / $duration" | bc 2>/dev/null || echo "0")
    else
      # Integer division fallback
      local duration_int=${duration%%.*}
      tokens_per_sec=$(( token_count / duration_int ))
    fi
  fi
  
  # Check GPU usage via Ollama API
  local gpu_active=false
  local ps_response=$(curl -s http://localhost:11434/api/ps 2>/dev/null || echo "")
  # Detect CPU architecture if not already set (for fallback checks)
  local cpu_arch="${CPU_ARCH:-$(uname -m)}"
  
  if [[ -n "$ps_response" ]]; then
    # Try JSON parsing if jq is available
    if command -v jq &>/dev/null; then
      # Check for GPU-related fields in JSON response
      if echo "$ps_response" | jq -e '.models[]? | select(.gpu_layers != null or .gpu_layers > 0)' &>/dev/null; then
        gpu_active=true
      elif echo "$ps_response" | jq -e '.[]? | select(.gpu_layers != null or .gpu_layers > 0)' &>/dev/null; then
        gpu_active=true
      fi
    fi
    
    # Fallback: keyword search in response
    if [[ "$gpu_active" == "false" ]]; then
      if echo "$ps_response" | grep -qiE "gpu|metal|device|accelerat"; then
        gpu_active=true
      fi
    fi
  fi
  
  # Alternative: Check environment variables (OLLAMA_NUM_GPU > 0 indicates GPU should be used)
  if [[ "$gpu_active" == "false" ]] && [[ -n "${OLLAMA_NUM_GPU:-}" ]] && [[ "${OLLAMA_NUM_GPU}" -gt 0 ]]; then
    # On Apple Silicon, if OLLAMA_NUM_GPU is set, assume GPU is active
    if [[ "$cpu_arch" == "arm64" ]]; then
      gpu_active=true
    fi
  fi
  
  # On Apple Silicon, if Metal is available and Ollama is running, assume GPU is active
  if [[ "$gpu_active" == "false" ]] && [[ "$cpu_arch" == "arm64" ]]; then
    if system_profiler SPDisplaysDataType 2>/dev/null | grep -q "Metal"; then
      # Metal is available, and Ollama auto-detects it on Apple Silicon
      gpu_active=true
    fi
  fi
  
  # Display results
  if [[ -n "$response" && ${#response} -gt 10 ]]; then
    print_success "$model benchmark complete"
    print_info "  Response time: ${duration}s"
    if [[ $token_count -gt 0 ]]; then
      print_info "  Estimated tokens: ~$token_count"
      # Use bc for floating point comparison if available, otherwise use integer comparison
      local tokens_per_sec_check=0
      if command -v bc &>/dev/null; then
        tokens_per_sec_check=$(echo "$tokens_per_sec > 0" | bc 2>/dev/null || echo "0")
      else
        # Integer comparison fallback
        local tokens_per_sec_int=${tokens_per_sec%%.*}
        if [[ $tokens_per_sec_int -gt 0 ]]; then
          tokens_per_sec_check=1
        fi
      fi
      if [[ $tokens_per_sec_check -eq 1 ]]; then
        print_info "  Tokens/sec: ~${tokens_per_sec}"
      fi
    fi
    if [[ "$gpu_active" == "true" ]]; then
      print_info "  GPU acceleration: Active"
    else
      print_info "  GPU acceleration: Not verified (may still be active)"
    fi
    log_info "Model $model benchmark: ${duration}s, ~${tokens_per_sec} tokens/sec"
    return 0
  fi
  
  return 1
}

# Validate model (simple validation without benchmarking)
validate_model_simple() {
  local model="$1"
  
  print_info "Validating $model..."
  log_info "Validating model: $model"
  
  # Use smart loading if available
  if command -v smart_load_model &>/dev/null; then
    smart_load_model "$model" 0
  fi
  
  local test_prompt="Write a simple TypeScript function that adds two numbers."
  local start_time=$(date +%s)
  local response
  
  # Track model usage
  if command -v track_model_usage &>/dev/null; then
    track_model_usage "$model"
  fi
  
  # Test with timeout
  if response=$(run_with_timeout 30 ollama run "$model" "$test_prompt" 2>&1 | head -n 5); then
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [[ -n "$response" && ${#response} -gt 10 ]]; then
      print_success "$model validated (response time: ${duration}s)"
      log_info "Model $model validation successful (${duration}s)"
      return 0
    fi
  fi
  
  # Retry once
  log_warn "Validation failed for $model, retrying..."
  sleep 2
  
  if response=$(run_with_timeout 30 ollama run "$model" "$test_prompt" 2>&1 | head -n 5); then
    if [[ -n "$response" && ${#response} -gt 10 ]]; then
      print_success "$model validated (retry successful)"
      return 0
    fi
  fi
  
  log_error "Validation failed for $model after retry"
  return 1
}

# Validate model (includes benchmarking for backward compatibility)
validate_model() {
  local model="$1"
  
  print_info "Validating $model..."
  log_info "Validating model: $model"
  
  local test_prompt="Write a simple TypeScript function that adds two numbers."
  local start_time=$(date +%s)
  local response
  
  # Test with timeout
  if response=$(run_with_timeout 30 ollama run "$model" "$test_prompt" 2>&1 | head -n 5); then
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [[ -n "$response" && ${#response} -gt 10 ]]; then
      print_success "$model validated (response time: ${duration}s)"
      log_info "Model $model validation successful (${duration}s)"
      
      # Quick performance check
      print_info "Running quick performance check..."
      if benchmark_model_performance "$model"; then
        log_info "Model $model performance check passed"
      else
        log_warn "Model $model performance check had issues, but validation passed"
      fi
      
      return 0
    fi
  fi
  
  # Retry once
  log_warn "Validation failed for $model, retrying..."
  sleep 2
  
  if response=$(run_with_timeout 30 ollama run "$model" "$test_prompt" 2>&1 | head -n 5); then
    if [[ -n "$response" && ${#response} -gt 10 ]]; then
      print_success "$model validated (retry successful)"
      return 0
    fi
  fi
  
  log_error "Validation failed for $model after retry"
  return 1
}

# Resolve actual installed model name
# Ollama uses base model names - quantization is handled internally
resolve_installed_model() {
  local model="$1"
  
  # Check if model is installed
  if is_model_installed "$model"; then
    echo "$model"
    return 0
  fi
  
  # Check in INSTALLED_MODELS array
  for installed in "${INSTALLED_MODELS[@]}"; do
    if [[ "$installed" == "$model" ]]; then
      echo "$installed"
      return 0
    fi
    # Check if base name matches (handles any variants)
    local installed_base="${installed%%:*}"
    local model_base="${model%%:*}"
    if [[ "$installed_base" == "$model_base" ]]; then
      echo "$installed"
      return 0
    fi
  done
  
  # Fallback: return model name (Ollama will handle it)
  echo "$model"
}
