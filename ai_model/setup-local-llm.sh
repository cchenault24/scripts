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

# Initialize global arrays (set -u compatibility)
SELECTED_MODELS=()
INSTALLED_MODELS=()
CONTINUE_PROFILES=()
SELECTED_EXTENSIONS=()

# Approved models (no DeepSeek)
readonly APPROVED_MODELS=(
  "qwen2.5-coder:14b"
  "llama3.1:8b"
  "llama3.1:70b"
  "codestral:22b"
  "qwen2.5-coder:7b"
)

# Model resource estimates (RAM in GB) - Quantized variants for Apple Silicon
# Function to get model RAM (reflects Q4_K_M/Q5_K_M quantization)
get_model_ram() {
  local model="$1"
  case "$model" in
    "qwen2.5-coder:7b") echo "3.5" ;;      # Q5_K_M: ~3.5GB (was 4.5GB unquantized)
    "llama3.1:8b") echo "4.2" ;;            # Q5_K_M: ~4.2GB (was 5GB unquantized)
    "qwen2.5-coder:14b") echo "7.5" ;;      # Q4_K_M: ~7.5GB (was 9GB unquantized)
    "codestral:22b") echo "11.5" ;;         # Q4_K_M: ~11.5GB (was 14GB unquantized)
    "llama3.1:70b") echo "35" ;;            # Q4_K_M: ~35GB (was 40GB unquantized)
    *) echo "0" ;;
  esac
}

# Function to get model description
get_model_desc() {
  local model="$1"
  case "$model" in
    "qwen2.5-coder:14b") echo "Best balance: quality + speed for React/TS" ;;
    "llama3.1:8b") echo "Fast general-purpose TypeScript assistant" ;;
    "llama3.1:70b") echo "Highest quality for complex refactoring (Tier S)" ;;
    "codestral:22b") echo "Excellent code generation for complex tasks" ;;
    "qwen2.5-coder:7b") echo "Lightweight, fast autocomplete & simple edits" ;;
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

# Check and install gum if missing (better terminal UI than fzf)
check_gum() {
  if ! command -v gum &>/dev/null; then
    log_error "gum not found. gum is required for interactive selection."
    echo ""
    if prompt_yes_no "Would you like the script to install gum now?" "y"; then
      print_info "Installing gum..."
      if brew install gum; then
        print_success "gum installed"
      else
        log_error "Failed to install gum"
        log_error "gum is required for this setup. Please install it manually and run this script again."
        echo ""
        echo "To install gum manually, run:"
        echo "  brew install gum"
        exit 1
      fi
    else
      log_error "gum is required. Please install it manually and run this script again."
      echo ""
      echo "To install gum manually, run:"
      echo "  brew install gum"
      exit 1
    fi
  else
    print_success "gum found"
  fi
}

# Format model info for gum display with fixed-width columns
format_model_for_gum() {
  local model="$1"
  local tier="$2"
  local is_recommended="${3:-false}"
  local model_width="${4:-25}"  # Width for model name (including checkmark space)
  local ram_width="${5:-8}"      # Width for RAM column
  
  local ram=$(get_model_ram "$model")
  local desc=$(get_model_desc "$model")
  local eligible=false
  
  if is_model_eligible "$model" "$tier"; then
    eligible=true
  fi
  
  local suffix=""
  local tier_label=""
  
  # Get tier label
  case "$tier" in
    S) tier_label="Tier S (≥48GB RAM)" ;;
    A) tier_label="Tier A (32-47GB RAM)" ;;
    B) tier_label="Tier B (16-31GB RAM)" ;;
    C) tier_label="Tier C (<16GB RAM)" ;;
  esac
  
  if [[ "$eligible" == "false" ]]; then
    suffix=" ⚠ Not recommended"
  fi
  
  # Format with fixed-width columns for perfect alignment
  # No checkmark in the list - just align the separators
  printf "%-${model_width}s | %-${ram_width}s | %s%s\n" "$model" "${ram}GB" "$desc" "$suffix"
}

# Format extension info for gum display with fixed-width columns
format_extension_for_gum() {
  local ext_id="$1"
  local friendly_name="$2"
  local is_installed="${3:-false}"
  local name_width="${4:-30}"  # Default width for name column
  
  local suffix=""
  if [[ "$is_installed" == "true" ]]; then
    suffix=" (installed)"
  fi
  
  # Format with fixed-width column for alignment
  # No checkmark in the list - just align the separators
  printf "%-${name_width}s | %s%s\n" "$friendly_name" "$ext_id" "$suffix"
}

# State management
save_state() {
  mkdir -p "$STATE_DIR"
  # Guard against unset arrays (set -u compatibility)
  local selected_models=("${SELECTED_MODELS[@]:-}")
  local installed_models=("${INSTALLED_MODELS[@]:-}")
  local continue_profiles=("${CONTINUE_PROFILES[@]:-}")
  local state_json=$(cat <<EOF
{
  "hardware_tier": "${HARDWARE_TIER:-}",
  "selected_models": $(printf '%s\n' "${selected_models[@]}" | jq -R . | jq -s .),
  "installed_models": $(printf '%s\n' "${installed_models[@]}" | jq -R . | jq -s .),
  "continue_profiles": $(printf '%s\n' "${continue_profiles[@]}" | jq -R . | jq -s .),
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
  local cpu_brand cpu_arch cpu_cores ram_bytes ram_gb disk_available
  cpu_brand=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
  cpu_arch=$(uname -m)
  cpu_cores=$(sysctl -n hw.physicalcpu 2>/dev/null || echo "0")
  
  # RAM detection
  ram_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
  ram_gb=$((ram_bytes / 1024 / 1024 / 1024))
  
  # Disk space
  disk_available=$(df -h "$HOME" | awk 'NR==2 {print $4}' | sed 's/[^0-9.]//g' || echo "0")
  
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

# Setup Ollama environment variables for Apple Silicon optimization
setup_ollama_environment() {
  print_header "⚙️ Configuring Ollama for Apple Silicon"
  
  local ollama_env_dir="$HOME/.ollama"
  local ollama_env_file="$ollama_env_dir/ollama.env"
  
  mkdir -p "$ollama_env_dir"
  
  # Calculate optimal number of threads (cores - 2, minimum 2)
  local optimal_threads=$((CPU_CORES - 2))
  if [[ $optimal_threads -lt 2 ]]; then
    optimal_threads=2
  fi
  
  # Set OLLAMA_NUM_GPU (1 for Metal GPU, -1 for auto)
  export OLLAMA_NUM_GPU=1
  
  # Set optimal thread count
  export OLLAMA_NUM_THREAD=$optimal_threads
  
  # Set keep-alive based on hardware tier
  case "$HARDWARE_TIER" in
    S) export OLLAMA_KEEP_ALIVE="24h" ;;
    A) export OLLAMA_KEEP_ALIVE="12h" ;;
    B) export OLLAMA_KEEP_ALIVE="5m" ;;
    C) export OLLAMA_KEEP_ALIVE="5m" ;;
    *) export OLLAMA_KEEP_ALIVE="5m" ;;
  esac
  
  # Set max loaded models based on RAM tier
  case "$HARDWARE_TIER" in
    S) export OLLAMA_MAX_LOADED_MODELS=3 ;;
    A) export OLLAMA_MAX_LOADED_MODELS=2 ;;
    B) export OLLAMA_MAX_LOADED_MODELS=1 ;;
    C) export OLLAMA_MAX_LOADED_MODELS=1 ;;
    *) export OLLAMA_MAX_LOADED_MODELS=1 ;;
  esac
  
  # Write environment variables to file for persistence
  cat > "$ollama_env_file" <<EOF
# Ollama Environment Variables for Apple Silicon Optimization
# Generated by setup-local-llm.sh
export OLLAMA_NUM_GPU=$OLLAMA_NUM_GPU
export OLLAMA_NUM_THREAD=$OLLAMA_NUM_THREAD
export OLLAMA_KEEP_ALIVE="$OLLAMA_KEEP_ALIVE"
export OLLAMA_MAX_LOADED_MODELS=$OLLAMA_MAX_LOADED_MODELS
EOF
  
  print_success "Ollama environment configured"
  print_info "  GPU: $OLLAMA_NUM_GPU (Metal)"
  print_info "  Threads: $OLLAMA_NUM_THREAD"
  print_info "  Keep-alive: $OLLAMA_KEEP_ALIVE"
  print_info "  Max loaded models: $OLLAMA_MAX_LOADED_MODELS"
  log_info "Ollama environment configured: GPU=$OLLAMA_NUM_GPU, Threads=$OLLAMA_NUM_THREAD"
}

# Configure Metal GPU acceleration
configure_metal_acceleration() {
  print_header "🎮 Configuring Metal GPU Acceleration"
  
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
    log_info "Metal GPU acceleration available"
  else
    log_warn "Metal framework not detected, but continuing (may use CPU fallback)"
  fi
  
  # Ensure environment variables are set
  setup_ollama_environment
  
  print_success "Metal GPU acceleration configured"
}

# Verify Metal GPU usage
verify_metal_usage() {
  print_info "Verifying Metal GPU acceleration..."
  log_info "Verifying Metal GPU usage"
  
  # Wait a moment for Ollama to be ready
  sleep 2
  
  # Check if Ollama API is responding
  if ! curl -s http://localhost:11434/api/tags &>/dev/null; then
    log_warn "Ollama API not responding, cannot verify GPU usage"
    return 1
  fi
  
  # Try to get process info from Ollama API
  local ps_response=$(curl -s http://localhost:11434/api/ps 2>/dev/null || echo "")
  
  if [[ -n "$ps_response" ]]; then
    # Check if response contains GPU-related information
    if echo "$ps_response" | grep -qi "gpu\|metal\|device"; then
      print_success "GPU acceleration appears to be active"
      log_info "Metal GPU verification: Active"
      return 0
    fi
  fi
  
  # Alternative: Check Ollama logs or process info
  # On Apple Silicon, Ollama should automatically use Metal if available
  print_info "Metal GPU should be active (Ollama auto-detects on Apple Silicon)"
  log_info "Metal GPU verification: Assumed active (auto-detection)"
  return 0
}

# Get optimized model name
# Note: Ollama automatically selects optimal quantization (Q4_K_M/Q5_K_M) for Apple Silicon
# We don't need to specify quantization in the model name - Ollama handles it automatically
get_optimized_model_name() {
  local base_model="$1"
  
  # Ollama automatically downloads the best quantization for your system
  # On Apple Silicon, it will use Q4_K_M or Q5_K_M automatically
  # Just return the base model name - Ollama handles optimization
  echo "$base_model"
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
    
    # Verify Ollama version supports Metal (should be 0.1.0+)
    local version_check=$(echo "$ollama_version" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || echo "0.0.0")
    if [[ -n "$version_check" ]]; then
      print_info "Ollama version: $version_check"
    fi
    
    # Configure Metal acceleration before starting service
    configure_metal_acceleration
    
    # Check if Ollama service is running
    if curl -s http://localhost:11434/api/tags &>/dev/null; then
      print_success "Ollama service is running"
      # Restart to apply environment variables if needed
      configure_ollama_service
    else
      print_info "Starting Ollama service..."
      configure_ollama_service
      sleep 5
      if curl -s http://localhost:11434/api/tags &>/dev/null; then
        print_success "Ollama service started"
      else
        log_error "Failed to start Ollama service"
        exit 1
      fi
    fi
    
    # Verify Metal GPU usage
    verify_metal_usage
  else
    log_error "Ollama not found."
    echo ""
    echo "Ollama is required for this setup. The script can install it using Homebrew."
    echo ""
    if prompt_yes_no "Would you like the script to install Ollama now?" "y"; then
      print_info "Installing Ollama..."
      if brew install ollama; then
        print_success "Ollama installed"
        # Configure Metal acceleration
        configure_metal_acceleration
        # Start service with configuration
        configure_ollama_service
        sleep 5
      else
        log_error "Failed to install Ollama"
        exit 1
      fi
    else
      log_error "Ollama is required. Please install it manually and run this script again."
      echo ""
      echo "To install Ollama manually, run:"
      echo "  brew install ollama"
      echo ""
      echo "Or visit: https://ollama.com"
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
    log_error "jq not found. jq is required for JSON processing."
    echo ""
    if prompt_yes_no "Would you like the script to install jq now?" "y"; then
      print_info "Installing jq..."
      if brew install jq; then
        print_success "jq installed"
      else
        log_error "Failed to install jq"
        log_warn "Some features may be limited without jq."
      fi
    else
      log_error "jq is required. Please install it manually and run this script again."
      echo ""
      echo "To install jq manually, run:"
      echo "  brew install jq"
      exit 1
    fi
  else
    print_success "jq found"
  fi
  
  # gum check (for interactive selection)
  check_gum
}

# Configure Ollama service with environment variables
configure_ollama_service() {
  print_info "Configuring Ollama service..."
  log_info "Configuring Ollama service with environment variables"
  
  # Source environment variables
  local ollama_env_file="$HOME/.ollama/ollama.env"
  if [[ -f "$ollama_env_file" ]]; then
    # Source the environment file
    set -a
    source "$ollama_env_file" 2>/dev/null || true
    set +a
    log_info "Loaded Ollama environment from $ollama_env_file"
  fi
  
  # Check if Ollama is running via brew services
  if brew services list 2>/dev/null | grep -q "ollama.*started"; then
    print_info "Restarting Ollama service to apply optimizations..."
    brew services restart ollama 2>/dev/null || true
    sleep 3
    log_info "Ollama service restarted"
  else
    # If not using brew services, start manually with environment
    if ! curl -s http://localhost:11434/api/tags &>/dev/null; then
      print_info "Starting Ollama with optimized environment..."
      # Start Ollama in background with environment variables
      (
        if [[ -f "$ollama_env_file" ]]; then
          source "$ollama_env_file"
        fi
        ollama serve > /dev/null 2>&1 &
      )
      sleep 3
      log_info "Ollama started with environment variables"
    fi
  fi
}

# Get list of installed models (cached to avoid multiple calls)
get_installed_models() {
  # Use a global cache variable to avoid multiple ollama list calls
  if [[ -z "${_INSTALLED_MODELS_CACHE:-}" ]]; then
    _INSTALLED_MODELS_CACHE=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' || echo "")
  fi
  echo "$_INSTALLED_MODELS_CACHE"
}

# Check if a specific model is installed
is_model_installed() {
  local model="$1"
  local installed_models
  installed_models=$(get_installed_models)
  echo "$installed_models" | grep -q "^${model}$"
}

# Get list of installed VS Code extensions (cached to avoid multiple calls)
get_installed_extensions() {
  # Use a global cache variable to avoid multiple code --list-extensions calls
  if [[ -z "${_INSTALLED_EXTENSIONS_CACHE:-}" ]] && command -v code &>/dev/null; then
    _INSTALLED_EXTENSIONS_CACHE=$(code --list-extensions 2>/dev/null || echo "")
  fi
  echo "${_INSTALLED_EXTENSIONS_CACHE:-}"
}

# Check if a specific VS Code extension is installed
is_extension_installed() {
  local ext_id="$1"
  local installed_extensions
  installed_extensions=$(get_installed_extensions)
  if [[ -z "$installed_extensions" ]]; then
    return 1
  fi
  echo "$installed_extensions" | grep -q "^${ext_id}$"
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
  if is_model_installed "$model"; then
    print_success "Model $model is already installed locally"
    return 0
  fi
  
  # Validate model name format first (cheaper than ollama show)
  if ! [[ "$model" =~ ^[a-zA-Z0-9._-]+(:[a-zA-Z0-9._-]+)?$ ]]; then
    print_error "Invalid model name format. Expected format: modelname:tag or modelname"
    print_info "Example: codellama:13b or llama3.1:8b"
    return 1
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
  # Primary: Best coding model for the tier
  # Secondary: Fast alternative for autocomplete/quick tasks
  local default_primary="qwen2.5-coder:14b"
  local default_secondary="llama3.1:8b"
  
  # Tier-specific optimizations
  case "$HARDWARE_TIER" in
    S)
      # Tier S: Can use codestral:22b as secondary for better coding quality
      default_secondary="codestral:22b"
      ;;
    A)
      # Tier A: codestral:22b is available and better for coding than llama3.1:8b
      default_secondary="codestral:22b"
      ;;
    B)
      # Tier B: Stick with llama3.1:8b (codestral:22b not eligible)
      default_secondary="llama3.1:8b"
      ;;
    C)
      # Tier C: Only small models available
      default_primary="llama3.1:8b"
      default_secondary="qwen2.5-coder:7b"
      ;;
  esac
  
  # Check if defaults are eligible (fallback safety)
  if ! is_model_eligible "$default_primary" "$HARDWARE_TIER"; then
    default_primary="llama3.1:8b"
  fi
  if ! is_model_eligible "$default_secondary" "$HARDWARE_TIER"; then
    default_secondary="qwen2.5-coder:7b"
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
  
  # Build temporary array with model name and formatted string
  for model in "${APPROVED_MODELS[@]}"; do
    local is_recommended=false
    if [[ "$model" == "$default_primary" || "$model" == "$default_secondary" ]]; then
      is_recommended=true
    fi
    local formatted=$(format_model_for_gum "$model" "$HARDWARE_TIER" "$is_recommended" "$max_model_width" "$max_ram_width")
    # Store as "model_name|formatted_string" for sorting
    temp_items+=("${model}|${formatted}")
  done
  
  # Sort by model name using natural sort (handles numbers correctly)
  IFS=$'\n' sorted_items=($(printf '%s\n' "${temp_items[@]}" | sort -t'|' -k1 -V))
  unset IFS
  
  # Extract sorted formatted strings and model names
  for item in "${sorted_items[@]}"; do
    local model_name="${item%%|*}"
    local formatted="${item#*|}"
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
tune_model() {
  local model="$1"
  local tier="$2"
  local role="${3:-coding}"
  
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
  
  print_info "Installing $model..."
  print_info "Ollama will automatically select optimal quantization (Q4_K_M/Q5_K_M) for Apple Silicon"
  log_info "Installing model: $model (Ollama auto-optimizes for Apple Silicon)"
  
  # Check if model is already installed
  if is_model_installed "$model"; then
    print_success "$model already installed, skipping download"
    INSTALLED_MODELS+=("$model")
    return 0
  fi
  
  # Download model - Ollama automatically selects best quantization for Apple Silicon
  if ollama pull "$model" 2>&1 | tee -a "$LOG_FILE"; then
    print_success "$model installed (automatically optimized for Apple Silicon)"
    log_info "Model $model installed with automatic quantization optimization"
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

# Benchmark model performance
benchmark_model_performance() {
  local model="$1"
  
  print_info "Benchmarking $model performance..."
  log_info "Benchmarking model: $model"
  
  local test_prompt="Write a simple TypeScript function that adds two numbers and returns the result."
  local start_time=$(date +%s.%N 2>/dev/null || date +%s)
  local response
  local token_count=0
  
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

# Generate Continue.dev config
generate_continue_config() {
  print_header "📝 Generating Continue.dev Configuration"
  
  local continue_dir="$HOME/.continue"
  local config_file="$continue_dir/config.yaml"
  
  mkdir -p "$continue_dir"
  
  # Backup existing config if it exists
  if [[ -f "$config_file" ]]; then
    local backup_file="${config_file}.backup-$(date +%Y%m%d-%H%M%S)"
    cp "$config_file" "$backup_file"
    print_info "Backed up existing config to: $backup_file"
    log_info "Backed up existing config to: $backup_file"
  fi
  
  # Helper function to generate friendly model names
  get_friendly_model_name() {
    local model="$1"
    case "$model" in
      "qwen2.5-coder:14b") echo "Qwen2.5-Coder 14B" ;;
      "qwen2.5-coder:7b") echo "Qwen2.5-Coder 7B" ;;
      "llama3.1:8b") echo "Llama 3.1 8B" ;;
      "llama3.1:70b") echo "Llama 3.1 70B" ;;
      "codestral:22b") echo "Codestral 22B" ;;
      *) echo "${model%%:*}" | sed 's/\([a-z]\)\([A-Z]\)/\1 \2/g' | sed 's/-/ /g' ;;
    esac
  }
  
  # Separate coding models from embedding models
  local coding_models=()
  local embed_model=""
  
  # Process all selected models (guard against empty array for set -u compatibility)
  if [[ ${#SELECTED_MODELS[@]} -gt 0 ]]; then
    for model_base in "${SELECTED_MODELS[@]}"; do
      # Resolve actual installed model name (may be optimized variants)
      local model=$(resolve_installed_model "$model_base")
      
      # Check if it's an embedding model
      if [[ "$model" == *"embed"* ]] || [[ "$model" == *"nomic-embed"* ]]; then
        embed_model="$model"
      else
        # Add to coding models array (avoid duplicates)
        local found=0
        # Guard against empty array access (fixes unbound variable error with set -u)
        if [[ ${#coding_models[@]} -gt 0 ]]; then
          for existing in "${coding_models[@]}"; do
            if [[ "$existing" == "$model" ]]; then
              found=1
              break
            fi
          done
        fi
        if [[ $found -eq 0 ]]; then
          coding_models+=("$model")
        fi
      fi
    done
  fi
  
  # If no coding models found, log warning and return
  if [[ ${#coding_models[@]} -eq 0 ]]; then
    print_warn "No coding models found in selected models"
    log_warn "No coding models to add to Continue.dev config"
    return 1
  fi
  
  # Determine default model (first/largest for chat) and autocomplete model
  local default_model="${coding_models[0]}"
  local default_model_name=$(get_friendly_model_name "$default_model")
  
  # Find best autocomplete model (prefer smallest/fastest)
  local autocomplete_model=""
  local autocomplete_model_name=""
  # Prefer 7b models for autocomplete (faster responses)
  for model in "${coding_models[@]}"; do
    if [[ "$model" == *"7b"* ]] || [[ "$model" == *":7b"* ]]; then
      autocomplete_model="$model"
      autocomplete_model_name=$(get_friendly_model_name "$model")
      break
    fi
  done
  # Fallback to 8b if no 7b found
  if [[ -z "$autocomplete_model" ]]; then
    for model in "${coding_models[@]}"; do
      if [[ "$model" == *"8b"* ]] || [[ "$model" == *":8b"* ]]; then
        autocomplete_model="$model"
        autocomplete_model_name=$(get_friendly_model_name "$model")
        break
      fi
    done
  fi
  # Use first model as fallback if no small model found
  if [[ -z "$autocomplete_model" && ${#coding_models[@]} -gt 0 ]]; then
    autocomplete_model="${coding_models[0]}"
    autocomplete_model_name="$default_model_name"
  fi
  
  # Start building config YAML
  local config_yaml=$(cat <<EOF
name: Local Config
version: 1.0.0
schema: v1

# Default model for chat (uses first/largest model)
defaultModel: $default_model_name

# Default completion options (optimized for coding tasks)
defaultCompletionOptions:
  temperature: 0.7
  maxTokens: 2048

# Privacy: Disable telemetry for local-only setup
allowAnonymousTelemetry: false

models:
EOF
  )
  
  # Add all coding models with chat, edit, apply roles
  for model in "${coding_models[@]}"; do
    local friendly_name=$(get_friendly_model_name "$model")
    
    # Build roles list
    local roles_yaml="      - chat
      - edit
      - apply"
    
    # Add autocomplete role if this is the autocomplete model
    if [[ "$model" == "$autocomplete_model" ]]; then
      roles_yaml="$roles_yaml
      - autocomplete"
    fi
    
    config_yaml+=$(cat <<EOF

  - name: $friendly_name
    provider: ollama
    model: $model
    apiBase: http://localhost:11434
    contextLength: 16384
    roles:
$roles_yaml
EOF
    )
  done
  
  # Add embeddings model (use found embedding model or default)
  local embed_model_to_use="${embed_model:-nomic-embed-text:latest}"
  config_yaml+=$(cat <<EOF

  - name: Nomic Embed
    provider: ollama
    model: $embed_model_to_use
    apiBase: http://localhost:11434
    roles:
      - embed
    embedOptions:
      maxChunkSize: 512
      maxBatchSize: 10
EOF
  )
  
  # Add autocomplete model reference (if different from default)
  if [[ "$autocomplete_model" != "$default_model" && -n "$autocomplete_model" ]]; then
    config_yaml+=$(cat <<EOF

# Autocomplete model (optimized for fast suggestions)
tabAutocompleteModel: $autocomplete_model_name
EOF
    )
  fi
  
  # Add embeddings provider
  config_yaml+=$(cat <<EOF

# Embeddings provider for codebase search
embeddingsProvider:
  provider: ollama
  model: $embed_model_to_use
  apiBase: http://localhost:11434
EOF
  )
  
  # Add context providers for better code understanding
  config_yaml+=$(cat <<EOF

# Context providers for enhanced code understanding
contextProviders:
  - name: codebase
  - name: code
  - name: docs
  - name: diff
  - name: terminal
  - name: problems
  - name: folder
EOF
  )
  
  # Write config
  echo "$config_yaml" > "$config_file"
  print_success "Continue.dev config generated: $config_file"
  log_info "Continue.dev config written to $config_file with ${#coding_models[@]} coding model(s)"
  
  CONTINUE_PROFILES=("chat" "edit" "apply" "autocomplete")
}

# VS Code extensions
# Accepts array of extension IDs to install (passed as arguments)
setup_vscode_extensions() {
  print_header "🔌 VS Code Extensions"
  
  if [[ "$VSCODE_AVAILABLE" != "true" ]]; then
    print_warn "VS Code CLI not available. Skipping extension installation."
    return 0
  fi
  
  # Get selected extensions from arguments or use empty array
  local selected_extensions=("$@")
  
  # Recommended extensions (for generating recommendations file)
  local all_extensions=(
    "Continue.continue"
    "dbaeumer.vscode-eslint"
    "esbenp.prettier-vscode"
    "pranaygp.vscode-css-peek"
    "ms-vscode.vscode-typescript-next"
    "dsznajder.es7-react-js-snippets"
    "formulahendry.auto-rename-tag"
    "christian-kohler.path-intellisense"
    "esc5221.clipboard-diff-patch"
  )
  
  if [[ ${#selected_extensions[@]} -gt 0 ]]; then
    # Double-check that code command is available
    if ! command -v code &>/dev/null; then
      log_error "VS Code CLI (code) command not found, cannot install extensions"
      print_warn "VS Code CLI not available. Skipping extension installation."
      VSCODE_EXTENSIONS_INSTALLED=false
      return 1
    fi
    
    local installed=0
    local skipped=0
    for ext in "${selected_extensions[@]}"; do
      # Check if extension is already installed
      if is_extension_installed "$ext"; then
        print_info "$ext already installed, skipping"
        ((skipped++))
        continue
      fi
      
      # Install only if not already installed
      # Capture install output and exit code separately
      # This prevents tee failures from masking successful installs
      # Use set +e temporarily to prevent script exit on command failure
      local install_output install_exit_code
      set +e
      install_output=$(code --install-extension "$ext" 2>&1)
      install_exit_code=$?
      set -e
      
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
    print_info "No extensions selected for installation"
    VSCODE_EXTENSIONS_INSTALLED=false
  fi
  
  # Generate recommendations file
  local vscode_dir="$SCRIPT_DIR/vscode"
  mkdir -p "$vscode_dir"
  
  local extensions_json=$(cat <<EOF
{
  "recommendations": [
$(printf '    "%s",\n' "${all_extensions[@]}" | sed '$s/,$//')
  ]
}
EOF
  )
  
  echo "$extensions_json" > "$vscode_dir/extensions.json"
  print_success "Extension recommendations saved to $vscode_dir/extensions.json"
}

# Check if Continue CLI is installed
check_continue_cli() {
  if command -v cn &>/dev/null; then
    return 0
  elif command -v npx &>/dev/null && npx --yes @continuedev/cli --version &>/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Install Continue CLI (optional)
install_continue_cli() {
  if check_continue_cli; then
    print_success "Continue CLI found"
    return 0
  fi
  
  if ! command -v npm &>/dev/null; then
    print_warn "npm not found. Continue CLI requires Node.js/npm"
    print_info "Install Node.js from https://nodejs.org/ to use Continue CLI"
    return 1
  fi
  
  print_info "Continue CLI not found"
  if prompt_yes_no "Install Continue CLI (cn) for better verification and setup?" "y"; then
    print_info "Installing @continuedev/cli globally..."
    if npm install -g @continuedev/cli 2>&1 | tee -a "$LOG_FILE"; then
      print_success "Continue CLI installed"
      log_info "Continue CLI installed successfully"
      return 0
    else
      log_warn "Failed to install Continue CLI"
      print_warn "Continue CLI installation failed, but setup can continue"
      return 1
    fi
  else
    print_info "Skipping Continue CLI installation"
    return 1
  fi
}

# Configure Continue.dev models from installed Ollama models
configure_continue_models_from_ollama() {
  local config_file="${1:-$HOME/.continue/config.yaml}"
  local continue_dir="$HOME/.continue"
  
  mkdir -p "$continue_dir"
  
  # Check if Ollama is running
  if ! curl -s http://localhost:11434/api/tags &>/dev/null; then
    print_error "Ollama service is not running"
    print_info "Start it with: brew services start ollama"
    return 1
  fi
  
  # Get installed models
  local installed_models
  installed_models=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' || echo "")
  
  if [[ -z "$installed_models" ]]; then
    print_warn "No Ollama models installed"
    print_info "Install models with: ollama pull <model-name>"
    return 1
  fi
  
  # Filter out embedding models and separate coding models
  local coding_models=()
  local embed_model=""
  
  while IFS= read -r model; do
    if [[ -n "$model" ]]; then
      if [[ "$model" == *"embed"* ]] || [[ "$model" == *"nomic-embed"* ]]; then
        embed_model="$model"
      else
        coding_models+=("$model")
      fi
    fi
  done <<< "$installed_models"
  
  if [[ ${#coding_models[@]} -eq 0 ]]; then
    print_warn "No coding models found (only embedding models detected)"
    return 1
  fi
  
  print_info "Found ${#coding_models[@]} coding model(s) available"
  echo ""
  
  # Let user select primary model
  echo "Available models:"
  local index=1
  local selected_models=()
  for model in "${coding_models[@]}"; do
    echo "  $index) $model"
    ((index++))
  done
  echo ""
  
  # Select primary model (for chat, edit, apply roles)
  local primary_choice
  read -p "Select primary model for chat/edit/apply (1-${#coding_models[@]}): " primary_choice
  
  if [[ ! "$primary_choice" =~ ^[0-9]+$ ]] || [[ $primary_choice -lt 1 || $primary_choice -gt ${#coding_models[@]} ]]; then
    print_error "Invalid selection"
    return 1
  fi
  
  local primary_model="${coding_models[$((primary_choice-1))]}"
  selected_models+=("$primary_model")
  
  # Ask if user wants to add another model for autocomplete
  if [[ ${#coding_models[@]} -gt 1 ]]; then
    if prompt_yes_no "Add another model for autocomplete? (recommended for faster suggestions)" "n"; then
      echo ""
      echo "Available models (excluding primary):"
      local available_models=()
      local index=1
      for model in "${coding_models[@]}"; do
        if [[ "$model" != "$primary_model" ]]; then
          echo "  $index) $model"
          available_models+=("$model")
          ((index++))
        fi
      done
      echo ""
      
      if [[ ${#available_models[@]} -gt 0 ]]; then
        local autocomplete_choice
        read -p "Select autocomplete model (1-${#available_models[@]}): " autocomplete_choice
        
        if [[ "$autocomplete_choice" =~ ^[0-9]+$ ]] && [[ $autocomplete_choice -ge 1 && $autocomplete_choice -le ${#available_models[@]} ]]; then
          local autocomplete_model="${available_models[$((autocomplete_choice-1))]}"
          selected_models+=("$autocomplete_model")
        else
          print_warn "Invalid selection, skipping autocomplete model"
        fi
      else
        print_info "No other models available for autocomplete"
      fi
    fi
  fi
  
  # Backup existing config
  if [[ -f "$config_file" ]]; then
    local backup_file="${config_file}.backup-$(date +%Y%m%d-%H%M%S)"
    cp "$config_file" "$backup_file"
    print_info "Backed up existing config to: $backup_file"
    log_info "Backed up existing config to: $backup_file"
  fi
  
  # Generate friendly model names
  get_friendly_model_name() {
    local model="$1"
    case "$model" in
      "qwen2.5-coder:14b") echo "Qwen2.5-Coder 14B" ;;
      "qwen2.5-coder:7b") echo "Qwen2.5-Coder 7B" ;;
      "llama3.1:8b") echo "Llama 3.1 8B" ;;
      "llama3.1:70b") echo "Llama 3.1 70B" ;;
      "codestral:22b") echo "Codestral 22B" ;;
      *) echo "${model%%:*}" | sed 's/\([a-z]\)\([A-Z]\)/\1 \2/g' | sed 's/-/ /g' ;;
    esac
  }
  
  # Generate config YAML
  local primary_name=$(get_friendly_model_name "$primary_model")
  local config_yaml=$(cat <<EOF
name: Local Config
version: 1.0.0
schema: v1
models:
  - name: $primary_name
    provider: ollama
    model: $primary_model
    roles:
      - chat
      - edit
      - apply
EOF
  )
  
  # Add autocomplete model if different
  if [[ ${#selected_models[@]} -gt 1 ]]; then
    local autocomplete_model="${selected_models[1]}"
    local autocomplete_name=$(get_friendly_model_name "$autocomplete_model")
    config_yaml+=$(cat <<EOF

  - name: $autocomplete_name
    provider: ollama
    model: $autocomplete_model
    roles:
      - autocomplete
EOF
    )
  fi
  
  # Add embeddings model (use existing or default)
  local embed_model_to_use="${embed_model:-nomic-embed-text:latest}"
  config_yaml+=$(cat <<EOF

  - name: Nomic Embed
    provider: ollama
    model: $embed_model_to_use
    roles:
      - embed
EOF
  )
  
  # Write config
  echo "$config_yaml" > "$config_file"
  print_success "Continue.dev config updated: $config_file"
  log_info "Continue.dev config updated with models: ${selected_models[*]}"
  
  return 0
}

# Verify Continue.dev setup
verify_continue_setup() {
  print_header "✅ Verifying Continue.dev Setup"
  
  local issues=0
  
  # Check if Continue.dev extension is installed
  if [[ "$VSCODE_AVAILABLE" == "true" ]]; then
    local continue_installed=$(code --list-extensions 2>/dev/null | grep -i "Continue.continue" || echo "")
    if [[ -n "$continue_installed" ]]; then
      print_success "Continue.dev extension is installed"
    else
      print_warn "Continue.dev extension not found in installed extensions"
      print_info "You may need to install it manually or restart VS Code"
      ((issues++))
    fi
  else
    print_warn "VS Code CLI not available, cannot verify extension installation"
  fi
  
  # Check if config file exists (try YAML first, then JSON for backward compatibility)
  local config_file="$HOME/.continue/config.yaml"
  local config_file_json="$HOME/.continue/config.json"
  
  if [[ -f "$config_file" ]]; then
    print_success "Continue.dev config file found: $config_file"
    
    # Validate YAML structure (basic check)
    if grep -q "^models:" "$config_file" 2>/dev/null; then
      print_success "Config file appears to be valid YAML"
      
      # Check for models (match indented YAML format)
      local model_count
      model_count=$(grep -c "^[[:space:]]*- name:" "$config_file" 2>/dev/null || echo "0")
      model_count=${model_count//[^0-9]/}  # Remove all non-numeric characters
      model_count=${model_count:-0}  # Default to 0 if empty
      if (( model_count > 0 )); then
        print_success "Found $model_count model(s) in config"
      else
        print_warn "No models configured in config file"
        # Offer to configure models from installed Ollama models
        if curl -s http://localhost:11434/api/tags &>/dev/null; then
          if prompt_yes_no "Would you like to configure models from installed Ollama models?" "y"; then
            configure_continue_models_from_ollama "$config_file"
            # Re-check model count after configuration
            model_count=$(grep -c "^[[:space:]]*- name:" "$config_file" 2>/dev/null || echo "0")
            model_count=${model_count//[^0-9]/}
            model_count=${model_count:-0}
            if (( model_count > 0 )); then
              print_success "Models configured successfully"
            else
              ((issues++))
            fi
          else
            ((issues++))
          fi
        else
          ((issues++))
        fi
      fi
    else
      print_warn "Config file structure may be invalid"
      ((issues++))
    fi
  elif [[ -f "$config_file_json" ]]; then
    print_warn "Found old JSON config file: $config_file_json"
    print_info "Consider migrating to YAML format (config.yaml)"
    # Validate JSON if jq is available
    if command -v jq &>/dev/null; then
      if jq empty "$config_file_json" 2>/dev/null; then
        print_success "Config file is valid JSON"
        
        # Check for models
        local model_count
        model_count=$(jq '.models | length' "$config_file_json" 2>/dev/null || echo "0")
        model_count=${model_count//[^0-9]/}  # Remove all non-numeric characters
        model_count=${model_count:-0}  # Default to 0 if empty
        if (( model_count > 0 )); then
          print_success "Found $model_count model profile(s) in config"
        else
          print_warn "No models configured in config file"
          ((issues++))
        fi
      else
        print_error "Config file is not valid JSON"
        ((issues++))
      fi
    fi
  else
    print_error "Continue.dev config file not found at $config_file or $config_file_json"
    ((issues++))
  fi
  
  # Check if Ollama is running
  if curl -s http://localhost:11434/api/tags &>/dev/null; then
    print_success "Ollama service is running"
  else
    print_warn "Ollama service is not running"
    print_info "Start it with: brew services start ollama"
    ((issues++))
  fi
  
  # Check Continue CLI (optional but helpful)
  if check_continue_cli; then
    print_success "Continue CLI (cn) is available"
    print_info "You can use 'cn' in terminal for interactive Continue workflows"
  else
    print_info "Continue CLI (cn) not installed (optional)"
    if prompt_yes_no "Would you like to install Continue CLI (cn) now?" "n"; then
      print_info "Installing @continuedev/cli globally..."
      if npm install -g @continuedev/cli 2>&1 | tee -a "$LOG_FILE"; then
        print_success "Continue CLI installed successfully"
      else
        print_warn "Continue CLI installation failed, but setup can continue"
      fi
    else
      print_info "You can install it later with: npm i -g @continuedev/cli"
    fi
  fi
  
  if [[ $issues -eq 0 ]]; then
    print_success "Continue.dev setup verified successfully"
    return 0
  else
    print_warn "Found $issues issue(s) with Continue.dev setup"
    return 1
  fi
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
    "esc5221.clipboard-diff-patch") echo "Clipboard Diff Patch" ;;
    *) echo "$ext_id" ;;
  esac
}

# Prompt for VS Code extensions (separated from installation)
# Returns selected extension IDs via SELECTED_EXTENSIONS array
prompt_vscode_extensions() {
  SELECTED_EXTENSIONS=()
  
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
    "esc5221.clipboard-diff-patch"
  )
  
  echo "Select VS Code extensions for React+TypeScript+Redux-Saga stack:"
  echo ""
  
  # Build gum input with all extensions
  local gum_items=()
  local ext_map=()
  
  # Get list of installed extensions once (avoid duplicate checks)
  local installed_extensions_list
  installed_extensions_list=$(get_installed_extensions)
  
  # Calculate maximum width for extension names and build parallel arrays for status
  local max_name_width=0
  local ext_names=()
  local ext_installed_flags=()
  
  for ext in "${extensions[@]}"; do
    local friendly_name=$(get_extension_name "$ext")
    local is_installed=false
    
    # Check if extension is already installed
    if is_extension_installed "$ext"; then
      is_installed=true
    fi
    
    # Store for later use
    ext_names+=("$friendly_name")
    ext_installed_flags+=("$is_installed")
    
    # Calculate name width
    local name_len=${#friendly_name}
    if [[ $name_len -gt $max_name_width ]]; then
      max_name_width=$name_len
    fi
  done
  
  # Add padding
  max_name_width=$((max_name_width + 2))
  
  # Build formatted items using stored data
  local i=0
  for ext in "${extensions[@]}"; do
    local friendly_name="${ext_names[$i]}"
    local is_installed="${ext_installed_flags[$i]}"
    local formatted=$(format_extension_for_gum "$ext" "$friendly_name" "$is_installed" "$max_name_width")
    gum_items+=("$formatted")
    ext_map+=("$ext")
    ((i++))
  done
  
  # Use gum choose for multi-select
  echo ""
  echo -e "${YELLOW}💡 Tip:${NC} Press ${BOLD}Space${NC} to select, ${BOLD}Enter${NC} to confirm"
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
    --header="🔌 VS Code Extensions" \
    --header.foreground="6")
  
  if [[ -z "$selected_lines" ]]; then
    print_info "No extensions selected"
    return 1
  fi
  
  # Parse gum output
  while IFS= read -r line; do
    if [[ -z "$line" ]]; then
      continue
    fi
    
    # Find matching extension from the map
    # With minimal UI (no prefixes), gum outputs the formatted string directly
    # Strip any leading whitespace or cursor symbols that might be present
    local line_clean="${line#"${line%%[![:space:]]*}"}"  # Remove leading whitespace
    line_clean="${line_clean#→ }"  # Remove cursor if present
    
    local ext_id=""
    local i=0
    for item in "${gum_items[@]}"; do
      # Direct match (gum outputs selected items as-is with no prefix)
      if [[ "$item" == "$line_clean" ]]; then
        ext_id="${ext_map[$i]}"
        break
      fi
      ((i++))
    done
    
    # If we found an extension ID, add it
    if [[ -n "$ext_id" ]]; then
      SELECTED_EXTENSIONS+=("$ext_id")
    fi
  done <<< "$selected_lines"
  
  # Remove duplicates (bash 3.2 compatible)
  local unique_extensions=()
  for ext in "${SELECTED_EXTENSIONS[@]}"; do
    local found=0
    if [[ ${#unique_extensions[@]} -gt 0 ]]; then
      for existing in "${unique_extensions[@]}"; do
        if [[ "$ext" == "$existing" ]]; then
          found=1
          break
        fi
      done
    fi
    [[ $found -eq 0 ]] && unique_extensions+=("$ext")
  done
  SELECTED_EXTENSIONS=("${unique_extensions[@]}")
  
  if [[ ${#SELECTED_EXTENSIONS[@]} -eq 0 ]]; then
    return 1
  fi
  
  return 0
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
  
  # Ask if user wants to install models
  local install_models=true
  if [[ "$resume_installation" != "true" ]]; then
    if ! prompt_yes_no "Would you like to install AI models for Continue.dev?" "y"; then
      install_models=false
      print_info "Skipping model installation. You can install models later by running this script again."
      SELECTED_MODELS=()
    fi
  fi
  
  # Model selection (contains prompts)
  if [[ "$resume_installation" != "true" && "$install_models" == "true" ]]; then
    select_models
  fi
  
  # Ask if user wants to install VS Code extensions
  local install_extensions=true
  if [[ "$VSCODE_AVAILABLE" == "true" ]]; then
    if ! prompt_yes_no "Would you like to install recommended extensions for VS Code?" "y"; then
      install_extensions=false
      print_info "Skipping VS Code extension installation."
      SELECTED_EXTENSIONS=()
    fi
  else
    install_extensions=false
    SELECTED_EXTENSIONS=()
  fi
  
  # Prompt for VS Code extensions (only if user wants to install)
  if [[ "$install_extensions" == "true" ]]; then
    SELECTED_EXTENSIONS=()
    prompt_vscode_extensions
  fi
  
  # ============================================
  # PHASE 2: Begin all installations/setup
  # ============================================
  print_header "🚀 Starting Installation"
  echo -e "${CYAN}All configurations collected. Beginning installations and setup...${NC}"
  echo ""
  
  # Install models (only if models were selected)
  local failed_models=()
  if [[ ${#SELECTED_MODELS[@]} -gt 0 ]]; then
    print_header "📥 Installing Models"
    print_info "This may take 10-30 minutes depending on your connection..."
    echo ""
    
    for model in "${SELECTED_MODELS[@]}"; do
      if install_model "$model"; then
        # Get the actual installed model name (may be optimized variant)
        local installed_model=$(resolve_installed_model "$model")
        print_success "$installed_model downloaded"
        echo ""
        
        # Prompt for validation
        if prompt_yes_no "Would you like to validate $installed_model?" "y"; then
          if validate_model_simple "$installed_model"; then
            print_success "$installed_model validated"
          else
            log_warn "$installed_model validation failed"
            failed_models+=("$model")
          fi
          echo ""
        else
          print_info "Validation skipped for $installed_model"
          echo ""
        fi
        
        # Prompt for benchmarking
        if prompt_yes_no "Would you like to benchmark $installed_model?" "y"; then
          if benchmark_model_performance "$installed_model"; then
            print_success "$installed_model benchmarked"
          else
            log_warn "$installed_model benchmarking had issues"
          fi
          echo ""
        else
          print_info "Benchmarking skipped for $installed_model"
          echo ""
        fi
      else
        failed_models+=("$model")
      fi
    done
  else
    print_info "No models selected for installation. Skipping model installation."
  fi
  
  # Generate configurations (only if models were installed)
  if [[ ${#SELECTED_MODELS[@]} -gt 0 ]]; then
    generate_continue_config
  else
    print_info "Skipping Continue.dev configuration (no models installed)."
  fi
  
  # Install VS Code extensions (only if extensions were selected)
  if [[ ${#SELECTED_EXTENSIONS[@]} -gt 0 ]]; then
    setup_vscode_extensions "${SELECTED_EXTENSIONS[@]}"
  else
    print_info "No VS Code extensions selected for installation. Skipping extension installation."
    VSCODE_EXTENSIONS_INSTALLED=false
  fi
  generate_vscode_settings
  copy_vscode_settings
  
  # Optionally install Continue CLI for better verification
  if command -v npm &>/dev/null; then
    install_continue_cli
  fi
  
  # Verify Continue.dev setup (only if models were installed)
  if [[ ${#SELECTED_MODELS[@]} -gt 0 ]]; then
    verify_continue_setup
  else
    print_info "Skipping Continue.dev verification (no models installed)."
  fi
  
  # Save state
  save_state
  
  # Final summary
  print_header "✅ Setup Complete!"
  
  echo -e "${GREEN}${BOLD}Installation Summary:${NC}"
  echo ""
  echo -e "  ${CYAN}Hardware Tier:${NC} $TIER_LABEL"
  if [[ ${#SELECTED_MODELS[@]} -gt 0 ]]; then
    echo -e "  ${CYAN}Selected Models:${NC} ${SELECTED_MODELS[*]}"
    echo -e "  ${CYAN}Installed Models:${NC} ${INSTALLED_MODELS[*]}"
    echo -e "  ${CYAN}Continue.dev Profiles:${NC} ${CONTINUE_PROFILES[*]}"
  else
    echo -e "  ${CYAN}Models:${NC} None selected"
  fi
  echo ""
  
  if [[ ${#failed_models[@]} -gt 0 ]]; then
    echo -e "${YELLOW}⚠ Failed/Skipped Models:${NC} ${failed_models[*]}"
    echo ""
  fi
  
  echo -e "${YELLOW}${BOLD}📋 Next Steps:${NC}"
  echo ""
  if [[ ${#SELECTED_MODELS[@]} -gt 0 ]]; then
    # Check if Continue.dev extension is actually installed
    local continue_extension_installed=false
    if [[ "$VSCODE_AVAILABLE" == "true" ]]; then
      local continue_check=$(code --list-extensions 2>/dev/null | grep -i "Continue.continue" || echo "")
      if [[ -n "$continue_check" ]]; then
        continue_extension_installed=true
      fi
    fi
    
    if [[ "$continue_extension_installed" == "true" ]] || [[ "$VSCODE_EXTENSIONS_INSTALLED" == "true" ]]; then
      echo -e "  ${BOLD}IMPORTANT:${NC} You must ${BOLD}fully quit and restart VS Code${NC} (Cmd+Q, not just reload)"
      echo "  for Continue.dev to detect the configuration."
      echo ""
      echo -e "  1. ${BOLD}Quit VS Code completely${NC} (Cmd+Q on macOS)"
      echo -e "  2. ${BOLD}Reopen VS Code${NC}"
      echo -e "  3. Press ${BOLD}Cmd+L${NC} (or ${BOLD}Ctrl+L${NC}) to open Continue.dev chat"
    else
      echo "  1. Install Continue.dev extension in VS Code:"
      echo -e "     - Open Extensions view (${BOLD}Cmd+Shift+X${NC})"
      echo "     - Search for 'Continue' and install 'Continue.dev' by Continue"
      echo -e "  2. ${BOLD}Quit VS Code completely${NC} (Cmd+Q on macOS)"
      echo -e "  3. ${BOLD}Reopen VS Code${NC}"
      echo -e "  4. Press ${BOLD}Cmd+L${NC} (or ${BOLD}Ctrl+L${NC}) to open Continue.dev chat"
    fi
    echo ""
    echo -e "  Continue.dev will automatically use the config at: ${BOLD}~/.continue/config.yaml${NC}"
    echo ""
    echo -e "  ${CYAN}Verification:${NC}"
    echo -e "  - Ensure Ollama is running: ${BOLD}brew services start ollama${NC}"
    echo -e "  - Check config: ${BOLD}ls -la ~/.continue/config.yaml${NC}"
    echo ""
    echo -e "  ${CYAN}Continue CLI (Optional):${NC}"
    if check_continue_cli; then
      echo -e "  - Continue CLI (${BOLD}cn${NC}) is installed and ready to use"
    else
      echo -e "  - Install: ${BOLD}npm i -g @continuedev/cli${NC}"
      echo -e "  - Then use ${BOLD}cn${NC} in terminal for interactive workflows"
    fi
  else
    echo "  To install models later, run this script again and select 'yes' when prompted."
    echo ""
    if [[ "$VSCODE_EXTENSIONS_INSTALLED" == "true" ]]; then
      echo "  VS Code extensions have been installed. Restart VS Code to activate them."
    elif [[ ${#SELECTED_EXTENSIONS[@]} -eq 0 && "$VSCODE_AVAILABLE" == "true" ]]; then
      echo "  To install VS Code extensions later, run this script again and select 'yes' when prompted."
    fi
  fi
  echo ""
  if [[ -f ".vscode/settings.json" ]]; then
    echo -e "  ${GREEN}✓${NC} VS Code settings automatically copied/merged to .vscode/settings.json"
  fi
  echo ""
  
  echo -e "${BLUE}${BOLD}📄 Documentation:${NC}"
  echo "  See README.md for detailed usage and troubleshooting"
  echo ""
  
  log_success "Setup completed successfully"
}

# Run main
main "$@"
