#!/bin/bash
#
# setup-local-llm.sh - Production-grade VS Code + Continue.dev Local LLM Setup
#
# Installs and configures Ollama with hardware-aware auto-tuning for VS Code
# integration via Continue.dev. Optimized for React+TypeScript+Redux-Saga+MUI stack.
#
# Requirements: macOS Apple Silicon, Homebrew, Xcode Command Line Tools
# Author: Generated for local AI coding environment
# License: MIT
#
# Compatible with bash 3.2+

# Check bash version (requires 3.2+)
if [[ "${BASH_VERSION%%.*}" -lt 3 ]] || [[ "${BASH_VERSION%%.*}" -eq 3 && "${BASH_VERSION#*.}" < 2 ]]; then
  echo "Error: This script requires bash 3.2 or later. Current version: $BASH_VERSION" >&2
  exit 1
fi

set -euo pipefail

# Script metadata
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
STATE_DIR="$HOME/.local-llm-setup"
STATE_FILE="$STATE_DIR/state.json"
LOG_FILE="$STATE_DIR/setup.log"

# Colors for output
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Approved models (no DeepSeek)
readonly APPROVED_MODELS=(
  "qwen2.5-coder:14b"
  "llama3.1:8b"
  "llama3.1:70b"
  "codestral:22b"
  "qwen2.5-coder:7b"
)

# Model resource estimates (RAM in GB) - bash 3.2 compatible (no associative arrays)
# Function to get model RAM
get_model_ram() {
  local model="$1"
  case "$model" in
    "qwen2.5-coder:7b") echo "4.5" ;;
    "llama3.1:8b") echo "5" ;;
    "qwen2.5-coder:14b") echo "9" ;;
    "codestral:22b") echo "14" ;;
    "llama3.1:70b") echo "40" ;;
    *) echo "0" ;;
  esac
}

# Function to get model description
get_model_desc() {
  local model="$1"
  case "$model" in
    "qwen2.5-coder:14b") echo "Best balance of quality and speed for React/TypeScript development" ;;
    "llama3.1:8b") echo "Fast, general-purpose coding assistant with good TypeScript support" ;;
    "llama3.1:70b") echo "Highest quality for complex refactoring and architecture (Tier S only)" ;;
    "codestral:22b") echo "Excellent code generation and explanation capabilities" ;;
    "qwen2.5-coder:7b") echo "Lightweight, fast autocomplete and simple edits" ;;
    *) echo "No description" ;;
  esac
}

# Hardware tier thresholds (RAM in GB)
readonly TIER_S_MIN=48
readonly TIER_A_MIN=32
readonly TIER_B_MIN=16

# Logging functions
log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
}

log_info() {
  log "INFO" "$@"
}

log_warn() {
  log "WARN" "$@"
  echo -e "${YELLOW}⚠ $*${NC}" >&2
}

log_error() {
  log "ERROR" "$@"
  echo -e "${RED}✗ $*${NC}" >&2
}

log_success() {
  log "SUCCESS" "$@"
  echo -e "${GREEN}✓ $*${NC}"
}

print_header() {
  echo ""
  echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${CYAN}$1${NC}"
  echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo ""
}

print_info() {
  echo -e "${BLUE}ℹ $1${NC}"
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
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

prompt_choice() {
  local prompt="$1"
  local default="$2"
  local choice
  echo -e "${YELLOW}$prompt${NC}"
  read -p "Choice [${default}]: " choice
  echo "${choice:-$default}"
}

# State management
save_state() {
  mkdir -p "$STATE_DIR"
  local state_json=$(cat <<EOF
{
  "hardware_tier": "${HARDWARE_TIER:-}",
  "selected_models": $(printf '%s\n' "${SELECTED_MODELS[@]}" | jq -R . | jq -s .),
  "installed_models": $(printf '%s\n' "${INSTALLED_MODELS[@]}" | jq -R . | jq -s .),
  "continue_profiles": $(printf '%s\n' "${CONTINUE_PROFILES[@]}" | jq -R . | jq -s .),
  "vscode_extensions_installed": ${VSCODE_EXTENSIONS_INSTALLED:-false},
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  )
  echo "$state_json" > "$STATE_FILE"
  log_info "State saved to $STATE_FILE"
}

load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    log_info "Loading state from $STATE_FILE"
    # Parse JSON state (basic parsing, assumes jq available or manual parsing)
    if command -v jq &>/dev/null; then
      HARDWARE_TIER=$(jq -r '.hardware_tier // ""' "$STATE_FILE" 2>/dev/null || echo "")
      # bash 3.2 compatible: use while read instead of readarray
      SELECTED_MODELS=()
      while IFS= read -r line; do
        [[ -n "$line" ]] && SELECTED_MODELS+=("$line")
      done < <(jq -r '.selected_models[]? // empty' "$STATE_FILE" 2>/dev/null || echo "")
      INSTALLED_MODELS=()
      while IFS= read -r line; do
        [[ -n "$line" ]] && INSTALLED_MODELS+=("$line")
      done < <(jq -r '.installed_models[]? // empty' "$STATE_FILE" 2>/dev/null || echo "")
    fi
  fi
}

# Hardware detection
detect_hardware() {
  print_header "🔍 Hardware Detection"
  
  # CPU architecture
  local cpu_brand=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
  local cpu_arch=$(uname -m)
  local cpu_cores=$(sysctl -n hw.physicalcpu 2>/dev/null || echo "0")
  
  # RAM detection
  local ram_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
  local ram_gb=$((ram_bytes / 1024 / 1024 / 1024))
  
  # Disk space
  local disk_available=$(df -h "$HOME" | awk 'NR==2 {print $4}' | sed 's/[^0-9.]//g' || echo "0")
  
  print_info "CPU: $cpu_brand"
  print_info "Architecture: $cpu_arch"
  print_info "Cores: $cpu_cores"
  print_info "RAM: ${ram_gb}GB"
  print_info "Available Disk: ${disk_available}GB"
  
  # Classify tier
  if [[ $ram_gb -ge $TIER_S_MIN ]]; then
    HARDWARE_TIER="S"
    TIER_LABEL="Tier S (≥48GB RAM)"
  elif [[ $ram_gb -ge $TIER_A_MIN ]]; then
    HARDWARE_TIER="A"
    TIER_LABEL="Tier A (32-47GB RAM)"
  elif [[ $ram_gb -ge $TIER_B_MIN ]]; then
    HARDWARE_TIER="B"
    TIER_LABEL="Tier B (16-31GB RAM)"
  else
    HARDWARE_TIER="C"
    TIER_LABEL="Tier C (<16GB RAM)"
  fi
  
  log_info "Hardware tier: $HARDWARE_TIER ($TIER_LABEL)"
  print_success "Detected: $TIER_LABEL"
  
  # Store hardware info
  CPU_ARCH="$cpu_arch"
  CPU_CORES="$cpu_cores"
  RAM_GB="$ram_gb"
  DISK_AVAILABLE="$disk_available"
  
  # Validate Apple Silicon
  if [[ "$cpu_arch" != "arm64" ]]; then
    log_error "This script is optimized for Apple Silicon (arm64). Detected: $cpu_arch"
    exit 1
  fi
}

# Prerequisites check
check_prerequisites() {
  print_header "🔧 Prerequisites Check"
  
  # macOS version
  local macos_version=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
  print_info "macOS Version: $macos_version"
  
  # Homebrew
  if ! command -v brew &>/dev/null; then
    log_error "Homebrew not found. Please install from https://brew.sh"
    exit 1
  fi
  print_success "Homebrew found"
  
  # Xcode Command Line Tools
  if ! xcode-select -p &>/dev/null; then
    log_error "Xcode Command Line Tools not found. Install with: xcode-select --install"
    exit 1
  fi
  print_success "Xcode Command Line Tools found"
  
  # Ollama check
  if command -v ollama &>/dev/null; then
    local ollama_version=$(ollama --version 2>/dev/null | head -n 1 || echo "unknown")
    print_success "Ollama found: $ollama_version"
    
    # Check if Ollama service is running
    if curl -s http://localhost:11434/api/tags &>/dev/null; then
      print_success "Ollama service is running"
    else
      print_info "Starting Ollama service..."
      brew services start ollama 2>/dev/null || ollama serve > /dev/null 2>&1 &
      sleep 5
      if curl -s http://localhost:11434/api/tags &>/dev/null; then
        print_success "Ollama service started"
      else
        log_error "Failed to start Ollama service"
        exit 1
      fi
    fi
  else
    print_info "Installing Ollama..."
    if brew install ollama; then
      print_success "Ollama installed"
      brew services start ollama
      sleep 5
    else
      log_error "Failed to install Ollama"
      exit 1
    fi
  fi
  
  # VS Code check (optional)
  if command -v code &>/dev/null; then
    print_success "VS Code CLI found"
    VSCODE_AVAILABLE=true
  else
    print_warn "VS Code CLI not found. Extension installation will be skipped."
    VSCODE_AVAILABLE=false
  fi
  
  # jq check (for JSON parsing)
  if ! command -v jq &>/dev/null; then
    print_info "Installing jq for JSON processing..."
    brew install jq || {
      log_warn "jq installation failed. Some features may be limited."
    }
  fi
}

# Model eligibility check
is_model_eligible() {
  local model="$1"
  local tier="$2"
  
  case "$tier" in
    S) return 0 ;; # All models allowed
    A) [[ "$model" != "llama3.1:70b" ]] ;; # Exclude 70b
    B) [[ "$model" != "llama3.1:70b" && "$model" != "codestral:22b" ]] ;; # Exclude 70b and 22b
    C) [[ "$model" == "qwen2.5-coder:7b" || "$model" == "llama3.1:8b" ]] ;; # Only 7b and 8b
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
  
  # Check if model is already installed locally
  if ollama list 2>/dev/null | grep -q "^${model}"; then
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
  # So we'll do a lightweight format validation during prompt phase
  # Full validation will happen during installation
  if [[ "$model" =~ ^[a-zA-Z0-9._-]+(:[a-zA-Z0-9._-]+)?$ ]]; then
    print_success "Model name format is valid: $model"
    print_info "Model availability will be verified during installation."
    return 0
  else
    print_error "Invalid model name format. Expected format: modelname:tag or modelname"
    print_info "Example: codellama:13b or llama3.1:8b"
    return 1
  fi
  
  # If we get here, model validation failed
  print_error "Model $model not found in Ollama library"
  print_info "Tip: Check available models at https://ollama.com/library"
  print_info "Or run 'ollama list' to see locally installed models"
  return 1
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
  
  echo -e "${CYAN}Select models from the recommended list, or choose a custom model. Models are auto-tuned based on your hardware tier.${NC}"
  echo ""
  
  SELECTED_MODELS=()
  local eligible_models=()
  local model_index=1
  
  # Build eligible models list
  for model in "${APPROVED_MODELS[@]}"; do
    if is_model_eligible "$model" "$HARDWARE_TIER"; then
      eligible_models+=("$model")
    fi
  done
  
  # Display models with eligibility
  echo "Available models for $TIER_LABEL:"
  echo ""
  
  for model in "${APPROVED_MODELS[@]}"; do
    # Get model info using functions (bash 3.2 compatible)
    local ram=$(get_model_ram "$model")
    local desc=$(get_model_desc "$model")
    local eligible=false
    
    if is_model_eligible "$model" "$HARDWARE_TIER"; then
      eligible=true
      echo -e "  ${GREEN}✓${NC} $model"
    else
      echo -e "  ${RED}✗${NC} $model ${YELLOW}(not eligible for $TIER_LABEL)${NC}"
    fi
    
    echo "     RAM: ~${ram}GB | $desc"
    echo ""
  done
  
  # Default selection
  local default_primary="qwen2.5-coder:14b"
  local default_secondary="llama3.1:8b"
  
  # Check if defaults are eligible
  if ! is_model_eligible "$default_primary" "$HARDWARE_TIER"; then
    default_primary="llama3.1:8b"
  fi
  if ! is_model_eligible "$default_secondary" "$HARDWARE_TIER"; then
    default_secondary="qwen2.5-coder:7b"
  fi
  
  echo -e "${CYAN}Recommended defaults for $TIER_LABEL:${NC}"
  echo "  Primary: $default_primary"
  echo "  Secondary: $default_secondary"
  echo ""
  
  # Interactive selection
  if prompt_yes_no "Use recommended models?" "y"; then
    SELECTED_MODELS=("$default_primary" "$default_secondary")
    # Remove duplicates (bash 3.2 compatible)
    local unique_models=()
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
    SELECTED_MODELS=("${unique_models[@]}")
  else
    echo ""
    echo "Select models (enter numbers, comma-separated, 'all' for all eligible, or 'c' for custom):"
    # bash 3.2 compatible: use counter instead of array indices
    local i=0
    for model in "${eligible_models[@]}"; do
      echo "  $((i+1))) $model"
      ((i++))
    done
    echo -e "  ${CYAN}c) Enter custom model name${NC}"
    echo ""
    
    local choice
    read -p "Your selection: " choice
    
    if [[ "$choice" == "all" ]]; then
      SELECTED_MODELS=("${eligible_models[@]}")
    elif [[ "$choice" == "c" || "$choice" == "C" ]]; then
      # Handle custom model selection
      while true; do
        echo ""
        read -p "Enter custom model name (e.g., codellama:13b): " custom_model
        custom_model=$(echo "$custom_model" | xargs) # trim whitespace
        
        if [[ -z "$custom_model" ]]; then
          print_warning "Model name cannot be empty. Try again or press Ctrl+C to cancel."
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
      
      # Also allow selecting from approved list in addition to custom
      if prompt_yes_no "Also select from recommended models?" "y"; then
        echo ""
        echo "Select additional models (enter numbers, comma-separated):"
        local i=0
        for model in "${eligible_models[@]}"; do
          echo "  $((i+1))) $model"
          ((i++))
        done
        echo ""
        
        local additional_choice
        read -p "Your selection: " additional_choice
        
        IFS=',' read -ra additional_choices <<< "$additional_choice"
        for c in "${additional_choices[@]}"; do
          c=$(echo "$c" | xargs) # trim
          if [[ "$c" =~ ^[0-9]+$ ]] && [[ $c -ge 1 && $c -le ${#eligible_models[@]} ]]; then
            SELECTED_MODELS+=("${eligible_models[$((c-1))]}")
          fi
        done
      fi
    else
      IFS=',' read -ra choices <<< "$choice"
      for c in "${choices[@]}"; do
        c=$(echo "$c" | xargs) # trim
        if [[ "$c" =~ ^[0-9]+$ ]] && [[ $c -ge 1 && $c -le ${#eligible_models[@]} ]]; then
          SELECTED_MODELS+=("${eligible_models[$((c-1))]}")
        fi
      done
    fi
    
    # Remove duplicates (bash 3.2 compatible)
    local unique_models=()
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
    SELECTED_MODELS=("${unique_models[@]}")
  fi
  
  # Validate selection
  if [[ ${#SELECTED_MODELS[@]} -eq 0 ]]; then
    log_error "No models selected"
    exit 1
  fi
  
  # Warn about large models
  for model in "${SELECTED_MODELS[@]}"; do
    # Check if this is a custom model (not in approved list)
    if ! is_approved_model "$model"; then
      # Custom model - show generic warning
      print_warning "Custom model $model selected - RAM requirements unknown"
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
tune_model() {
  local model="$1"
  local tier="$2"
  local role="${3:-coding}"
  
  local context_size
  local max_tokens
  local temperature
  local top_p
  local keep_alive
  
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
  "keep_alive": "$keep_alive"
}
EOF
}

# Install model
install_model() {
  local model="$1"
  
  print_info "Installing $model..."
  log_info "Installing model: $model"
  
  # Check if already installed
  if ollama list 2>/dev/null | grep -q "^${model}"; then
    print_success "$model already installed, skipping download"
    INSTALLED_MODELS+=("$model")
    return 0
  fi
  
  # Download model
  if ollama pull "$model" 2>&1 | tee -a "$LOG_FILE"; then
    print_success "$model installed"
    INSTALLED_MODELS+=("$model")
    return 0
  else
    log_error "Failed to install $model"
    return 1
  fi
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

# Validate model
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

# Generate Continue.dev config
generate_continue_config() {
  print_header "📝 Generating Continue.dev Configuration"
  
  local continue_dir="$HOME/.continue"
  local config_file="$continue_dir/config.json"
  
  mkdir -p "$continue_dir"
  
  # Determine model assignments by role
  local coding_model="${SELECTED_MODELS[0]}"
  local review_model=""
  local docs_model=""
  local analysis_model=""
  local autocomplete_model=""
  
  # Assign models to roles
  for model in "${SELECTED_MODELS[@]}"; do
    if [[ -z "$review_model" && "$model" != "$coding_model" ]]; then
      review_model="$model"
    fi
    if [[ -z "$docs_model" && "$model" == "llama3.1:8b" ]]; then
      docs_model="$model"
    fi
    if [[ -z "$analysis_model" && ("$model" == "llama3.1:70b" || "$model" == "qwen2.5-coder:14b") ]]; then
      analysis_model="$model"
    fi
    if [[ -z "$autocomplete_model" && ("$model" == "qwen2.5-coder:7b" || "$model" == "llama3.1:8b") ]]; then
      autocomplete_model="$model"
    fi
  done
  
  # Defaults
  review_model="${review_model:-$coding_model}"
  docs_model="${docs_model:-$coding_model}"
  analysis_model="${analysis_model:-$coding_model}"
  autocomplete_model="${autocomplete_model:-$coding_model}"
  
  # Get tuning parameters (extract values from JSON)
  local coding_tune=$(tune_model "$coding_model" "$HARDWARE_TIER" "coding")
  local review_tune=$(tune_model "$review_model" "$HARDWARE_TIER" "code-review")
  local docs_tune=$(tune_model "$docs_model" "$HARDWARE_TIER" "documentation")
  local analysis_tune=$(tune_model "$analysis_model" "$HARDWARE_TIER" "deep-analysis")
  
  # Extract values using jq if available, otherwise use grep
  local coding_ctx coding_temp review_temp docs_temp analysis_temp
  
  if command -v jq &>/dev/null; then
    coding_ctx=$(echo "$coding_tune" | jq -r '.context_size')
    coding_temp=$(echo "$coding_tune" | jq -r '.temperature')
    review_temp=$(echo "$review_tune" | jq -r '.temperature')
    docs_temp=$(echo "$docs_tune" | jq -r '.temperature')
    analysis_temp=$(echo "$analysis_tune" | jq -r '.temperature')
  else
    coding_ctx=$(echo "$coding_tune" | grep -o '"context_size": [0-9]*' | grep -o '[0-9]*' || echo "16384")
    coding_temp=$(echo "$coding_tune" | grep -o '"temperature": [0-9.]*' | grep -o '[0-9.]*' || echo "0.7")
    review_temp=$(echo "$review_tune" | grep -o '"temperature": [0-9.]*' | grep -o '[0-9.]*' || echo "0.3")
    docs_temp=$(echo "$docs_tune" | grep -o '"temperature": [0-9.]*' | grep -o '[0-9.]*' || echo "0.5")
    analysis_temp=$(echo "$analysis_tune" | grep -o '"temperature": [0-9.]*' | grep -o '[0-9.]*' || echo "0.6")
  fi
  
  # System prompts for stack-specific guidance (escape for JSON)
  local coding_system="You are an expert React + TypeScript developer specializing in:\\n- React with TypeScript (strict typing, no 'any')\\n- Redux + Redux-Saga (side effects in sagas, typed selectors)\\n- Material UI (MUI) with theme-first styling\\n- AG Grid with typed column definitions\\n- OpenLayers with proper lifecycle management\\n\\nWhen writing code:\\n- Use strict TypeScript with generics and discriminated unions\\n- Keep side effects in sagas, not components\\n- Use typed selectors and normalized Redux state\\n- Follow Redux-Saga patterns: cancellation, error handling, takeLatest/takeEvery\\n- Use MUI sx prop with theme tokens, avoid inline styles\\n- Memoize AG Grid renderers and use typed column defs\\n- Manage OpenLayers map state and event listeners properly\\n- Prefer incremental refactors over broad rewrites\\n- Request relevant files first, propose minimal diffs, explain risks"
  
  local review_system="You are a senior code reviewer focusing on:\\n- Correctness and edge cases\\n- Redux-Saga lifecycle and error handling\\n- MUI accessibility and theme usage\\n- AG Grid performance and memoization\\n- OpenLayers lifecycle cleanup and event listener safety\\n- TypeScript type safety (avoid 'any')\\n- React best practices and performance\\n\\nProvide actionable, specific feedback with code examples."
  
  local docs_system="You are a technical documentation specialist. Generate clear, concise documentation for:\\n- React components and hooks\\n- Redux actions, reducers, and sagas\\n- TypeScript types and interfaces\\n- API integrations\\n- Architecture decisions\\n\\nFocus on clarity, examples, and maintainability."
  
  local analysis_system="You are an architecture and refactoring expert. Analyze codebases for:\\n- Multi-file refactoring opportunities\\n- Architecture improvements\\n- Performance optimizations\\n- Type safety enhancements\\n- Redux state normalization\\n- Saga pattern improvements\\n\\nProvide comprehensive analysis with minimal, low-risk refactoring plans."
  
  # Generate config JSON
  local config_json=$(cat <<EOF
{
  "models": [
    {
      "title": "Coding Assistant",
      "provider": "ollama",
      "model": "$coding_model",
      "apiBase": "http://localhost:11434",
      "contextLength": ${coding_ctx:-16384},
      "temperature": ${coding_temp:-0.7},
      "systemMessage": "$coding_system"
    },
    {
      "title": "Code Review",
      "provider": "ollama",
      "model": "$review_model",
      "apiBase": "http://localhost:11434",
      "contextLength": ${coding_ctx:-16384},
      "temperature": ${review_temp:-0.3},
      "systemMessage": "$review_system"
    },
    {
      "title": "Documentation",
      "provider": "ollama",
      "model": "$docs_model",
      "apiBase": "http://localhost:11434",
      "contextLength": ${coding_ctx:-16384},
      "temperature": ${docs_temp:-0.5},
      "systemMessage": "$docs_system"
    },
    {
      "title": "Deep Analysis",
      "provider": "ollama",
      "model": "$analysis_model",
      "apiBase": "http://localhost:11434",
      "contextLength": ${coding_ctx:-16384},
      "temperature": ${analysis_temp:-0.6},
      "systemMessage": "$analysis_system"
    }
  ],
  "customCommands": [],
  "tabAutocompleteModel": {
    "title": "Fast Autocomplete",
    "provider": "ollama",
    "model": "$autocomplete_model",
    "apiBase": "http://localhost:11434"
  },
  "allowAnonymousTelemetry": false,
  "embeddingsProvider": {
    "provider": "ollama",
    "model": "$coding_model",
    "apiBase": "http://localhost:11434"
  },
  "contextProviders": [
    {
      "name": "codebase",
      "params": {}
    },
    {
      "name": "github",
      "params": {}
    }
  ]
}
EOF
  )
  
  # Write config
  echo "$config_json" > "$config_file"
  print_success "Continue.dev config generated: $config_file"
  log_info "Continue.dev config written to $config_file"
  
  CONTINUE_PROFILES=("coding" "code-review" "documentation" "deep-analysis")
}

# VS Code extensions
setup_vscode_extensions() {
  local should_install="${1:-false}"
  
  print_header "🔌 VS Code Extensions"
  
  if [[ "$VSCODE_AVAILABLE" != "true" ]]; then
    print_warn "VS Code CLI not available. Skipping extension installation."
    return 0
  fi
  
  # Recommended extensions
  local extensions=(
    "Continue.continue"
    "dbaeumer.vscode-eslint"
    "esbenp.prettier-vscode"
    "pranaygp.vscode-css-peek"
    "ms-vscode.vscode-typescript-next"
    "dsznajder.es7-react-js-snippets"
    "formulahendry.auto-rename-tag"
    "christian-kohler.path-intellisense"
    "ms-vscode.vscode-json"
    "esc5221.clipboard-diff-patch"
  )
  
  if [[ "$should_install" == "true" ]]; then
    local installed=0
    local skipped=0
    for ext in "${extensions[@]}"; do
      # Check if extension is already installed
      if code --list-extensions 2>/dev/null | grep -q "^${ext}$"; then
        print_info "$ext already installed, skipping"
        ((skipped++))
        continue
      fi
      
      # Install only if not already installed
      # Capture install output and exit code separately
      # This prevents tee failures from masking successful installs
      local install_output install_exit_code
      install_output=$(code --install-extension "$ext" 2>&1)
      install_exit_code=$?
      
      # Log output to file, but don't echo to stdout to avoid duplicates
      echo "$install_output" >> "$LOG_FILE" 2>/dev/null || true
      
      if [ $install_exit_code -eq 0 ]; then
        print_success "$ext installed"
        ((installed++))
      else
        log_warn "Failed to install $ext"
        # Show error output for failed installs
        if [[ -n "$install_output" ]]; then
          echo "$install_output" | sed 's/^/  /'
        fi
      fi
    done
    
    if [[ $installed -gt 0 ]]; then
      print_success "Installed $installed new extension(s)"
    fi
    if [[ $skipped -gt 0 ]]; then
      print_info "Skipped $skipped already installed extension(s)"
    fi
    VSCODE_EXTENSIONS_INSTALLED=true
  else
    print_info "Skipping extension installation"
    VSCODE_EXTENSIONS_INSTALLED=false
  fi
  
  # Generate recommendations file
  local vscode_dir="$SCRIPT_DIR/vscode"
  mkdir -p "$vscode_dir"
  
  local extensions_json=$(cat <<EOF
{
  "recommendations": [
$(printf '    "%s",\n' "${extensions[@]}" | sed '$s/,$//')
  ]
}
EOF
  )
  
  echo "$extensions_json" > "$vscode_dir/extensions.json"
  print_success "Extension recommendations saved to $vscode_dir/extensions.json"
}

# Generate VS Code settings
generate_vscode_settings() {
  print_header "⚙️ Generating VS Code Settings"
  
  local vscode_dir="$SCRIPT_DIR/vscode"
  mkdir -p "$vscode_dir"
  
  local settings_json=$(cat <<'EOF'
{
  "typescript.preferences.strictNullChecks": true,
  "typescript.preferences.noImplicitAny": true,
  "typescript.suggest.autoImports": true,
  "typescript.updateImportsOnFileMove.enabled": "always",
  "javascript.preferences.strictNullChecks": true,
  "javascript.preferences.noImplicitAny": true,
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": "explicit",
    "source.organizeImports": "explicit"
  },
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "[typescript]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[typescriptreact]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[javascript]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[javascriptreact]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "files.associations": {
    "*.tsx": "typescriptreact",
    "*.ts": "typescript"
  },
  "search.exclude": {
    "**/node_modules": true,
    "**/dist": true,
    "**/build": true
  },
  "files.exclude": {
    "**/.git": true,
    "**/.DS_Store": true
  }
}
EOF
  )
  
  echo "$settings_json" > "$vscode_dir/settings.json"
  print_success "VS Code settings saved to $vscode_dir/settings.json"
  log_info "VS Code settings written"
}

# Copy and merge VS Code settings to current project
copy_vscode_settings() {
  local source_settings="$SCRIPT_DIR/vscode/settings.json"
  local target_dir=".vscode"
  local target_settings="$target_dir/settings.json"
  
  if [[ ! -f "$source_settings" ]]; then
    log_warn "Source VS Code settings not found: $source_settings"
    return 0
  fi
  
  # Create .vscode directory if it doesn't exist
  mkdir -p "$target_dir"
  
  if [[ -f "$target_settings" ]]; then
    # Merge existing settings with new settings
    if command -v jq &>/dev/null; then
      # Deep merge: new settings take precedence, but existing settings are preserved
      # jq * operator merges right into left, so [1] * [0] gives precedence to [1] (new settings)
      local merged=$(jq -s '.[1] * .[0]' "$target_settings" "$source_settings" 2>/dev/null || echo "")
      if [[ $? -eq 0 && -n "$merged" ]]; then
        echo "$merged" > "$target_settings"
        print_success "VS Code settings merged into $target_settings"
        log_info "VS Code settings merged (existing file found)"
      else
        # Fallback: backup and copy
        local backup="$target_settings.backup-$(date +%Y%m%d-%H%M%S)"
        cp "$target_settings" "$backup"
        cp "$source_settings" "$target_settings"
        print_warn "VS Code settings copied (merge failed, backup saved to $backup)"
        log_warn "VS Code settings merge failed, used copy with backup"
      fi
    else
      # No jq available: backup and copy
      local backup="$target_settings.backup-$(date +%Y%m%d-%H%M%S)"
      cp "$target_settings" "$backup"
      cp "$source_settings" "$target_settings"
      print_warn "VS Code settings copied (jq not available for merge, backup saved to $backup)"
      log_warn "VS Code settings copied without merge (jq not available)"
    fi
  else
    # No existing file, just copy
    cp "$source_settings" "$target_settings"
    print_success "VS Code settings copied to $target_settings"
    log_info "VS Code settings copied to project"
  fi
}

# Get friendly name for VS Code extension
get_extension_name() {
  local ext_id="$1"
  case "$ext_id" in
    "Continue.continue") echo "Continue.dev" ;;
    "dbaeumer.vscode-eslint") echo "ESLint" ;;
    "esbenp.prettier-vscode") echo "Prettier" ;;
    "pranaygp.vscode-css-peek") echo "CSS Peek" ;;
    "ms-vscode.vscode-typescript-next") echo "TypeScript" ;;
    "dsznajder.es7-react-js-snippets") echo "ES7+ React/Redux/React-Native snippets" ;;
    "formulahendry.auto-rename-tag") echo "Auto Rename Tag" ;;
    "christian-kohler.path-intellisense") echo "Path IntelliSense" ;;
    "ms-vscode.vscode-json") echo "JSON" ;;
    "esc5221.clipboard-diff-patch") echo "Clipboard Diff Patch" ;;
    *) echo "$ext_id" ;;
  esac
}

# Prompt for VS Code extensions (separated from installation)
prompt_vscode_extensions() {
  if [[ "$VSCODE_AVAILABLE" != "true" ]]; then
    return 1
  fi
  
  # Recommended extensions
  local extensions=(
    "Continue.continue"
    "dbaeumer.vscode-eslint"
    "esbenp.prettier-vscode"
    "pranaygp.vscode-css-peek"
    "ms-vscode.vscode-typescript-next"
    "dsznajder.es7-react-js-snippets"
    "formulahendry.auto-rename-tag"
    "christian-kohler.path-intellisense"
    "ms-vscode.vscode-json"
    "esc5221.clipboard-diff-patch"
  )
  
  echo "Recommended VS Code extensions for React+TypeScript+Redux-Saga stack:"
  echo ""
  for ext in "${extensions[@]}"; do
    local friendly_name=$(get_extension_name "$ext")
    local status=""
    # Check if extension is already installed
    if code --list-extensions 2>/dev/null | grep -q "^${ext}$"; then
      status=" - Installed"
    fi
    echo "  • $friendly_name ($ext)$status"
  done
  echo ""
  
  if prompt_yes_no "Install recommended extensions?" "y"; then
    return 0
  else
    return 1
  fi
}

# Main installation flow
main() {
  clear
  print_header "🚀 VS Code + Continue.dev Local LLM Setup"
  
  # Initialize
  mkdir -p "$STATE_DIR"
  INSTALLED_MODELS=()
  CONTINUE_PROFILES=()
  VSCODE_EXTENSIONS_INSTALLED=false
  
  # ============================================
  # PHASE 1: Collect all user responses first
  # ============================================
  print_header "📋 Configuration"
  echo -e "${CYAN}Please answer the following questions. All installations will begin after you've completed all prompts.${NC}"
  echo ""
  
  # Load previous state if resuming
  local resume_installation=false
  if [[ -f "$STATE_FILE" ]]; then
    if prompt_yes_no "Previous installation detected. Resume?" "y"; then
      resume_installation=true
      load_state
    fi
  fi
  
  # Detection and checks (no prompts, just detection)
  detect_hardware
  check_prerequisites
  
  # Model selection (contains prompts)
  if [[ "$resume_installation" != "true" ]]; then
    select_models
  fi
  
  # Prompt for VS Code extensions
  local install_vscode_extensions=false
  if prompt_vscode_extensions; then
    install_vscode_extensions=true
  fi
  
  # ============================================
  # PHASE 2: Begin all installations/setup
  # ============================================
  print_header "🚀 Starting Installation"
  echo -e "${CYAN}All configurations collected. Beginning installations and setup...${NC}"
  echo ""
  
  # Install models
  print_header "📥 Installing Models"
  print_info "This may take 10-30 minutes depending on your connection..."
  echo ""
  
  local failed_models=()
  for model in "${SELECTED_MODELS[@]}"; do
    if install_model "$model"; then
      if validate_model "$model"; then
        print_success "$model ready"
      else
        log_warn "$model installed but validation failed"
        failed_models+=("$model")
      fi
    else
      failed_models+=("$model")
    fi
  done
  
  # Generate configurations
  generate_continue_config
  setup_vscode_extensions "$install_vscode_extensions"
  generate_vscode_settings
  copy_vscode_settings
  
  # Save state
  save_state
  
  # Final summary
  print_header "✅ Setup Complete!"
  
  echo -e "${GREEN}${BOLD}Installation Summary:${NC}"
  echo ""
  echo -e "  ${CYAN}Hardware Tier:${NC} $TIER_LABEL"
  echo -e "  ${CYAN}Selected Models:${NC} ${SELECTED_MODELS[*]}"
  echo -e "  ${CYAN}Installed Models:${NC} ${INSTALLED_MODELS[*]}"
  echo -e "  ${CYAN}Continue.dev Profiles:${NC} ${CONTINUE_PROFILES[*]}"
  echo ""
  
  if [[ ${#failed_models[@]} -gt 0 ]]; then
    echo -e "${YELLOW}⚠ Failed/Skipped Models:${NC} ${failed_models[*]}"
    echo ""
  fi
  
  echo -e "${YELLOW}${BOLD}📋 Next Steps:${NC}"
  echo ""
  if [[ "$VSCODE_EXTENSIONS_INSTALLED" == "true" ]]; then
    echo "  1. Restart VS Code to activate Continue.dev extension"
  else
    echo "  1. Install Continue.dev extension in VS Code (if not already installed)"
    echo "  2. Restart VS Code"
  fi
  echo ""
  echo "  Continue.dev will automatically use the generated config at:"
  echo "  ~/.continue/config.json"
  echo ""
  if [[ -f ".vscode/settings.json" ]]; then
    echo "  ✓ VS Code settings automatically copied/merged to .vscode/settings.json"
  fi
  echo ""
  
  echo -e "${BLUE}${BOLD}📄 Documentation:${NC}"
  echo "  See README.md for detailed usage and troubleshooting"
  echo ""
  
  log_success "Setup completed successfully"
}

# Run main
main "$@"
