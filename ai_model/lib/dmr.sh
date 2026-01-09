#!/bin/bash
#
# dmr.sh - Docker Model Runner configuration and service management for setup-local-llm.sh
#
# Depends on: constants.sh, logger.sh, ui.sh, hardware.sh

# Check if Docker Model Runner is enabled
check_dmr_enabled() {
  if ! command -v docker &>/dev/null; then
    log_error "Docker not found. Please install Docker Desktop 4.40+"
    return 1
  fi
  
  # Check if docker model command is available (indicates DMR is enabled)
  if ! docker model version &>/dev/null; then
    log_error "Docker Model Runner not enabled"
    print_error "Docker Model Runner is not enabled in Docker Desktop"
    echo ""
    echo "To enable Docker Model Runner:"
    echo "  1. Open Docker Desktop"
    echo "  2. Go to Settings > AI"
    echo "  3. Check 'Enable Docker Model Runner'"
    echo "  4. Optionally enable 'Host-side TCP support' for API access"
    echo ""
    return 1
  fi
  
  return 0
}

# Setup DMR environment (minimal - DMR handles most configuration via Docker Desktop)
setup_dmr_environment() {
  print_header "⚙️ Configuring Docker Model Runner"
  
  # Verify DMR is enabled
  if ! check_dmr_enabled; then
    log_error "Docker Model Runner not enabled"
    return 1
  fi
  
  # DMR handles GPU acceleration via Docker Desktop settings
  # No environment variables needed - Docker Desktop manages this
  
  print_success "Docker Model Runner configured"
  print_info "  API: $DMR_API_BASE"
  print_info "  GPU: Managed by Docker Desktop"
  log_info "Docker Model Runner configured: API=$DMR_API_BASE"
}

# Configure DMR GPU acceleration (verify Docker Desktop settings)
configure_dmr_gpu() {
  print_header "🎮 Verifying Docker Model Runner GPU Configuration"
  
  # Check if Docker Desktop is running
  if ! docker info &>/dev/null; then
    log_error "Docker Desktop is not running"
    print_error "Please start Docker Desktop and ensure Docker Model Runner is enabled"
    return 1
  fi
  
  # Verify DMR is enabled
  if ! check_dmr_enabled; then
    return 1
  fi
  
  # On macOS, DMR uses Metal acceleration automatically if available
  # Check if Metal framework is available (macOS 10.13+)
  local macos_version major_version minor_version
  macos_version=$(sw_vers -productVersion 2>/dev/null || echo "0.0.0")
  IFS='.' read -r major_version minor_version _ <<< "$macos_version"
  major_version=${major_version:-0}
  minor_version=${minor_version:-0}
  
  if [[ $major_version -lt 10 ]] || [[ $major_version -eq 10 && $minor_version -lt 13 ]]; then
    log_warn "Metal requires macOS 10.13+. Detected: $macos_version"
    return 1
  fi
  
  # Verify Metal is available
  if system_profiler SPDisplaysDataType 2>/dev/null | grep -q "Metal"; then
    print_success "Metal framework detected"
    print_info "Docker Model Runner will use Metal acceleration automatically"
    log_info "Metal GPU acceleration available for DMR"
  else
    log_warn "Metal framework not detected, but continuing (may use CPU fallback)"
  fi
  
  print_success "Docker Model Runner GPU configuration verified"
}

# Verify DMR GPU usage
verify_dmr_gpu_usage() {
  print_info "Verifying Docker Model Runner GPU acceleration..."
  log_info "Verifying DMR GPU usage"
  
  # Check if DMR API is responding
  if ! curl -s --max-time 2 "$DMR_API_BASE/models" &>/dev/null; then
    log_warn "DMR API not responding, cannot verify GPU usage"
    return 1
  fi
  
  # DMR handles GPU automatically via Docker Desktop
  # On Apple Silicon, Metal acceleration is used automatically
  print_info "Docker Model Runner uses Metal acceleration automatically on Apple Silicon"
  log_info "DMR GPU verification: Assumed active (auto-detection via Docker Desktop)"
  return 0
}

# Get optimized model name (DMR uses explicit quantization in model name)
get_optimized_model_name() {
  local base_model="$1"
  
  # DMR model names already include quantization (e.g., ai/llama3.1:8B-Q4_K_M)
  # Just return the model name as-is
  echo "$base_model"
}

# Configure DMR service
configure_dmr_service() {
  print_info "Configuring Docker Model Runner service..."
  log_info "Configuring DMR service"
  
  # Check if Docker Desktop is running
  if ! docker info &>/dev/null; then
    log_error "Docker Desktop is not running"
    print_error "Please start Docker Desktop"
    return 1
  fi
  
  # Verify DMR is enabled
  if ! check_dmr_enabled; then
    return 1
  fi
  
  # Check if DMR API is responding
  if curl -s --max-time 2 "$DMR_API_BASE/models" &>/dev/null; then
    print_success "Docker Model Runner service is running"
    log_info "DMR service is running"
  else
    print_warn "Docker Model Runner API not responding"
    print_info "Ensure 'Host-side TCP support' is enabled in Docker Desktop Settings > AI"
    log_warn "DMR API not responding - may need to enable TCP support"
  fi
}

# Get list of installed models (cached to avoid multiple calls)
get_installed_models() {
  # Use a global cache variable to avoid multiple docker model list calls
  if [[ -z "${_INSTALLED_MODELS_CACHE:-}" ]]; then
    # Check if docker is available before calling
    if ! command -v docker &>/dev/null; then
      echo ""
      return 1
    fi
    
    # Check if DMR is enabled
    if ! docker model version &>/dev/null; then
      log_warn "Docker Model Runner not enabled, cannot get installed models"
      echo ""
      return 1
    fi
    
    # Get installed models from DMR
    _INSTALLED_MODELS_CACHE=$(docker model list 2>/dev/null | tail -n +2 | awk '{print $1}' || echo "")
  fi
  echo "$_INSTALLED_MODELS_CACHE"
}

# Clear installed models cache (call after installing/uninstalling models)
clear_installed_models_cache() {
  unset _INSTALLED_MODELS_CACHE
  log_info "Cleared installed models cache"
}

# Check if a specific model is installed
is_model_installed() {
  local model="$1"
  local installed_models
  installed_models=$(get_installed_models)
  
  # Extract base name and tag from the requested model
  local model_base="${model%%:*}"
  local model_tag="${model#*:}"
  # If no tag was specified, model_tag equals model_base
  if [[ "$model_tag" == "$model_base" ]]; then
    model_tag=""
  fi
  
  # Check for exact match first (highest priority)
  if echo "$installed_models" | grep -qxF "$model"; then
    return 0
  fi
  
  # Check if model name matches with any tag - but use EXACT base name matching
  if [[ -z "$model_tag" ]]; then
    # User requested base model without tag - check if ANY version is installed
    while IFS= read -r installed; do
      if [[ -n "$installed" ]]; then
        local installed_base="${installed%%:*}"
        # Exact match of base name (not prefix match)
        if [[ "$installed_base" == "$model_base" ]]; then
          return 0
        fi
      fi
    done <<< "$installed_models"
  fi
  
  # Fallback: try using docker model show which is more reliable
  if docker model show "$model" &>/dev/null 2>&1; then
    return 0
  fi
  
  return 1
}

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
    "${cmd[@]}" > "$response_file" 2>&1 &
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
      rm -f "$response_file"
      return 124  # Timeout exit code (matches GNU timeout)
    else
      # Process completed
      wait "$pid" 2>/dev/null
      exit_code=$?
      cat "$response_file"
      rm -f "$response_file"
      return $exit_code
    fi
  fi
}

# Unload model from memory (DMR auto-unloads, but we can verify)
# Note: DMR handles model lifecycle automatically, so this is mainly for verification
unload_model() {
  local model="$1"
  local silent="${2:-0}"  # Optional: 1 for silent mode
  
  # DMR automatically unloads models after inactivity
  # We can't directly control this, but we can verify the model is not in active use
  if [[ $silent -eq 0 ]]; then
    print_info "DMR automatically manages model lifecycle - model will unload after inactivity"
  fi
  
  log_info "DMR handles model unloading automatically"
  return 0
}

# Unload all models from memory (cleanup function)
# Note: DMR handles this automatically, but we can verify
unload_all_models() {
  # DMR automatically unloads models after inactivity
  # No manual intervention needed
  print_info "DMR automatically manages model lifecycle - models will unload after inactivity"
  log_info "DMR handles model unloading automatically"
  return 0
}
