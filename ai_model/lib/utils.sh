#!/bin/bash
#
# utils.sh - Utility functions for validation, network checks, and error handling
#
# Depends on: constants.sh, logger.sh, ui.sh

# Check network connectivity with retry logic
check_network_connectivity() {
  local url="${1:-https://ollama.com}"
  local max_retries="${2:-3}"
  local timeout="${3:-5}"
  local retry_delay="${4:-2}"
  
  log_info "Checking network connectivity to $url"
  
  for ((i=1; i<=max_retries; i++)); do
    if curl -s --max-time "$timeout" "$url" &>/dev/null; then
      log_info "Network connectivity check passed (attempt $i/$max_retries)"
      return 0
    fi
    
    if [[ $i -lt $max_retries ]]; then
      log_warn "Network check failed (attempt $i/$max_retries), retrying in ${retry_delay}s..."
      sleep "$retry_delay"
      # Exponential backoff
      retry_delay=$((retry_delay * 2))
    fi
  done
  
  log_error "Network connectivity check failed after $max_retries attempts"
  return 1
}

# Check disk space (returns available space in GB)
get_available_disk_space() {
  local path="${1:-$HOME}"
  local available_bytes
  
  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS: use df
    available_bytes=$(df -k "$path" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    # Convert KB to GB
    if command -v bc &>/dev/null; then
      echo "scale=2; $available_bytes / 1024 / 1024" | bc 2>/dev/null || echo "0"
    else
      echo $((available_bytes / 1024 / 1024))
    fi
  else
    # Linux fallback
    available_bytes=$(df -B1 "$path" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    if command -v bc &>/dev/null; then
      echo "scale=2; $available_bytes / 1024 / 1024 / 1024" | bc 2>/dev/null || echo "0"
    else
      echo $((available_bytes / 1024 / 1024 / 1024))
    fi
  fi
}

# Validate sufficient disk space
validate_disk_space() {
  local required_gb="${1:-10}"
  local path="${2:-$HOME}"
  
  local available_gb
  available_gb=$(get_available_disk_space "$path")
  
  # Convert to integer for comparison
  local available_int
  available_int=$(echo "$available_gb" | awk '{if ($1+0 == $1) printf "%.0f", $1; else print "0"}')
  local required_int
  required_int=$(echo "$required_gb" | awk '{if ($1+0 == $1) printf "%.0f", $1; else print "0"}')
  
  if [[ "$available_int" =~ ^[0-9]+$ ]] && [[ "$required_int" =~ ^[0-9]+$ ]] && [[ $available_int -ge $required_int ]]; then
    log_info "Disk space check passed: ${available_gb}GB available (required: ${required_gb}GB)"
    return 0
  fi
  
  log_error "Insufficient disk space: ${available_gb}GB available (required: ${required_gb}GB)"
  return 1
}

# Sanitize model name (remove dangerous characters)
sanitize_model_name() {
  local model="$1"
  
  if [[ -z "$model" ]]; then
    echo ""
    return 1
  fi
  
  # Remove any characters that aren't alphanumeric, colon, dash, dot, or underscore
  # This prevents command injection
  echo "$model" | sed 's/[^a-zA-Z0-9:._-]//g'
}

# Validate model name format and safety
validate_model_name() {
  local model="$1"
  
  if [[ -z "$model" ]]; then
    print_error "Model name cannot be empty"
    return 1
  fi
  
  # Check for dangerous patterns
  local dangerous_pattern='[$`;|&()\[\]{}<>]'
  if [[ "$model" =~ $dangerous_pattern ]]; then
    print_error "Model name contains invalid characters"
    return 1
  fi
  
  # Validate format: modelname:tag or modelname
  if ! [[ "$model" =~ ^[a-zA-Z0-9._-]+(:[a-zA-Z0-9._-]+)?$ ]]; then
    print_error "Invalid model name format. Expected: modelname:tag or modelname"
    return 1
  fi
  
  return 0
}

# Retry function with exponential backoff
# NOTE: For commands with pipelines, use retry_command_with_backoff() instead
# or handle retries inline since eval doesn't preserve PIPESTATUS correctly
retry_with_backoff() {
  local max_attempts="${1:-3}"
  local base_delay="${2:-2}"
  shift 2
  
  # Support both string command (legacy) and array of arguments
  local command_str=""
  local use_eval=false
  
  if [[ $# -eq 1 ]] && [[ "$1" == *" "* ]]; then
    # Single argument with spaces - treat as command string (legacy mode)
    command_str="$1"
    use_eval=true
    log_warn "retry_with_backoff: Using legacy eval mode. For pipelines, handle retries inline."
  elif [[ $# -gt 0 ]]; then
    # Multiple arguments - use directly (preferred)
    command_str="$*"
    use_eval=false
  else
    log_error "No command provided to retry_with_backoff"
    return 1
  fi
  
  local attempt=1
  local delay="$base_delay"
  local exit_code=0
  
  while [[ $attempt -le $max_attempts ]]; do
    log_info "Attempt $attempt/$max_attempts: $command_str"
    
    if [[ "$use_eval" == "true" ]]; then
      # Legacy mode with eval (may not work correctly with pipelines)
      if eval "$command_str"; then
        log_info "Command succeeded on attempt $attempt"
        return 0
      fi
      exit_code=$?
    else
      # Direct execution (preferred)
      if "$@"; then
        log_info "Command succeeded on attempt $attempt"
        return 0
      fi
      exit_code=$?
    fi
    
    if [[ $attempt -lt $max_attempts ]]; then
      log_warn "Command failed (exit code: $exit_code), retrying in ${delay}s..."
      sleep "$delay"
      delay=$((delay * 2))  # Exponential backoff
    fi
    
    ((attempt++))
  done
  
  log_error "Command failed after $max_attempts attempts (last exit code: $exit_code)"
  return 1
}

# Retry a simple command (no pipelines) with exponential backoff
# Usage: retry_command_with_backoff max_attempts base_delay command [args...]
retry_command_with_backoff() {
  local max_attempts="${1:-3}"
  local base_delay="${2:-2}"
  shift 2
  
  if [[ $# -eq 0 ]]; then
    log_error "No command provided to retry_command_with_backoff"
    return 1
  fi
  
  local attempt=1
  local delay="$base_delay"
  local exit_code=0
  
  while [[ $attempt -le $max_attempts ]]; do
    log_info "Attempt $attempt/$max_attempts: $*"
    
    if "$@"; then
      log_info "Command succeeded on attempt $attempt"
      return 0
    fi
    exit_code=$?
    
    if [[ $attempt -lt $max_attempts ]]; then
      log_warn "Command failed (exit code: $exit_code), retrying in ${delay}s..."
      sleep "$delay"
      delay=$((delay * 2))  # Exponential backoff
    fi
    
    ((attempt++))
  done
  
  log_error "Command failed after $max_attempts attempts (last exit code: $exit_code)"
  return 1
}

# Atomic file write (write to temp, then move)
atomic_write() {
  local file_path="$1"
  local content="$2"
  
  if [[ -z "$file_path" ]]; then
    log_error "No file path provided to atomic_write"
    return 1
  fi
  
  local temp_file
  temp_file=$(mktemp "${file_path}.tmp.XXXXXX" 2>/dev/null || echo "${file_path}.tmp.$$")
  
  # Write content to temp file
  echo "$content" > "$temp_file" || {
    log_error "Failed to write to temp file: $temp_file"
    rm -f "$temp_file"
    return 1
  }
  
  # Move temp file to final location (atomic on most filesystems)
  if mv "$temp_file" "$file_path" 2>/dev/null; then
    log_info "Atomically wrote file: $file_path"
    return 0
  else
    log_error "Failed to move temp file to final location: $file_path"
    rm -f "$temp_file"
    return 1
  fi
}

# Validate file path safety
validate_file_path() {
  local path="$1"
  local must_exist="${2:-0}"  # 0 = can be new file, 1 = must exist
  
  if [[ -z "$path" ]]; then
    log_error "File path is empty"
    return 1
  fi
  
  # Check for dangerous patterns
  local dangerous_pattern='[$`;|&()\[\]{}<>]'
  if [[ "$path" =~ $dangerous_pattern ]]; then
    log_error "File path contains invalid characters: $path"
    return 1
  fi
  
  # Check if parent directory exists and is writable
  local parent_dir
  parent_dir=$(dirname "$path")
  if [[ ! -d "$parent_dir" ]]; then
    # Try to create it
    if ! mkdir -p "$parent_dir" 2>/dev/null; then
      log_error "Cannot create parent directory: $parent_dir"
      return 1
    fi
  fi
  
  # Check if directory is writable
  if [[ ! -w "$parent_dir" ]]; then
    log_error "Parent directory is not writable: $parent_dir"
    return 1
  fi
  
  # If file must exist, check it
  if [[ $must_exist -eq 1 ]] && [[ ! -f "$path" ]]; then
    log_error "File does not exist: $path"
    return 1
  fi
  
  return 0
}

# Check if port is available
check_port_available() {
  local port="$1"
  
  if [[ -z "$port" ]] || ! [[ "$port" =~ ^[0-9]+$ ]]; then
    log_error "Invalid port number: $port"
    return 1
  fi
  
  # Check if port is in use
  if lsof -i ":$port" &>/dev/null || netstat -an 2>/dev/null | grep -q ":$port.*LISTEN"; then
    log_warn "Port $port is already in use"
    return 1
  fi
  
  log_info "Port $port is available"
  return 0
}

# Estimate model download size (rough estimate in GB)
estimate_model_size() {
  local model="$1"
  local ram_estimate
  
  ram_estimate=$(get_model_ram "$model")
  
  # Model files are typically 1.2-1.5x the RAM estimate
  if command -v bc &>/dev/null; then
    echo "scale=2; $ram_estimate * 1.3" | bc 2>/dev/null || echo "$ram_estimate"
  else
    # Integer approximation
    local ram_int=${ram_estimate%%.*}
    echo $((ram_int + ram_int / 3))
  fi
}

# Progress indicator (spinner)
show_spinner() {
  local pid="$1"
  local message="${2:-Processing...}"
  local spinner_chars='|/-\'
  local i=0
  
  while kill -0 "$pid" 2>/dev/null; do
    local char="${spinner_chars:$((i % 4)):1}"
    echo -ne "\r${CYAN}${char}${NC} $message"
    sleep 0.1
    ((i++))
  done
  echo -ne "\r${GREEN}✓${NC} $message\n"
}

# Check if jq is available (cached)
_jq_available_cache=""
is_jq_available() {
  if [[ -z "$_jq_available_cache" ]]; then
    if command -v jq &>/dev/null; then
      _jq_available_cache="yes"
    else
      _jq_available_cache="no"
    fi
  fi
  
  [[ "$_jq_available_cache" == "yes" ]]
}
