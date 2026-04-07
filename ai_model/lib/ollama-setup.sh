#!/bin/bash
# ollama-setup.sh - Install and manage Ollama with Apple Silicon optimizations
# This file should be sourced, not executed directly

# Source common utilities if not already loaded
if ! declare -f print_header >/dev/null 2>&1; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/common.sh"
fi

# Source model security functions (required for input validation)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/model-families.sh"

#############################################
# Installation Configuration
#############################################
export OLLAMA_PORT="31434"  # High port to avoid conflicts (unlikely to conflict with dev tools)

# Runtime configuration
export OLLAMA_HOST="127.0.0.1:$OLLAMA_PORT"
export OLLAMA_KEEP_ALIVE=-1           # Keep models loaded
export OLLAMA_NUM_GPU=999             # All layers to GPU
export OLLAMA_MAX_LOADED_MODELS=1     # Focus on single model
export OLLAMA_FLASH_ATTENTION=1       # Fast attention

# Apple Silicon specific optimizations (dynamically detected)
# Detect hardware specs
DETECTED_P_CORES=$(detect_p_cores)
DETECTED_TOTAL_CORES=$(detect_total_cores)
DETECTED_OPTIMAL_VRAM=$(calculate_optimal_vram)

export OLLAMA_NUM_THREAD="${OLLAMA_NUM_THREAD:-$DETECTED_P_CORES}"  # Match P-core count (auto-detected)
export GOMAXPROCS="${GOMAXPROCS:-$DETECTED_TOTAL_CORES}"             # Total cores (auto-detected)
export OLLAMA_USE_MMAP=1                                             # Memory-mapped I/O for faster model loading
export OLLAMA_MAX_VRAM="${OLLAMA_MAX_VRAM:-$DETECTED_OPTIMAL_VRAM}" # Auto-calculated from RAM

# Metal optimization (disable validation in production for speed)
export MTL_SHADER_VALIDATION=0        # Disable Metal shader validation
export MTL_DEBUG_LAYER=0              # Disable Metal debug overhead

# PID and log file locations
OLLAMA_PID_FILE="$HOME/.local/var/ollama-server.pid"
OLLAMA_LOG_FILE="$HOME/.local/var/log/ollama-server.log"

#############################################
# Installation Function
#############################################

# Install Ollama via Homebrew
install_ollama() {
    set -euo pipefail

    print_header "Installing Ollama via Homebrew"

    # Check if Homebrew is installed
    if ! command -v brew &> /dev/null; then
        print_error "Homebrew is not installed"
        print_info "Install Homebrew from: https://brew.sh"
        return 1
    fi

    print_info "Homebrew version: $(brew --version | head -1)"

    # Check if Ollama is already installed
    if command -v ollama &> /dev/null; then
        local installed_version
        installed_version=$(ollama --version 2>&1 | head -1 || echo "unknown")
        print_status "Ollama is already installed: $installed_version"
        print_info "Location: $(which ollama)"

        # Ask if user wants to upgrade
        if [[ "${UNATTENDED:-false}" != "true" ]]; then
            read -p "Upgrade to latest version? (y/N): " upgrade
            if [[ "$upgrade" == "y" || "$upgrade" == "Y" ]]; then
                print_info "Upgrading Ollama..."
                if brew upgrade ollama 2>&1 | tee "$OLLAMA_LOG_FILE.install"; then
                    print_status "Ollama upgraded successfully"
                else
                    print_warning "Upgrade had issues, but Ollama may still work"
                fi
            fi
        else
            print_info "Unattended mode: Skipping upgrade check"
        fi

        return 0
    fi

    # Install Ollama
    print_info "Installing Ollama..."
    if brew install ollama 2>&1 | tee "$OLLAMA_LOG_FILE.install"; then
        print_status "Ollama installed successfully"
    else
        print_error "Failed to install Ollama"
        return 1
    fi

    # Verify installation
    if ! command -v ollama &> /dev/null; then
        print_error "Ollama command not found after installation"
        return 1
    fi

    local installed_version
    installed_version=$(ollama --version 2>&1 | head -1)
    print_status "Installed version: $installed_version"
    print_status "Location: $(which ollama)"

    print_status "Ollama installation complete"
}

#############################################
# Server Management Functions
#############################################

# Start Ollama server with optimal runtime flags
start_ollama_server() {
    set -euo pipefail

    print_header "Starting Ollama Server"

    # Check for flock availability (required for safe PID file locking)
    if ! command -v flock &> /dev/null; then
        print_warning "flock not found - installing automatically..."

        # Check if Homebrew is available
        if ! command -v brew &> /dev/null; then
            print_error "Homebrew is required to install flock"
            print_info "Install Homebrew first: https://brew.sh"
            return 1
        fi

        # Auto-install flock
        if brew install flock; then
            print_status "flock installed successfully"
        else
            print_error "Failed to install flock"
            print_info "Try manually: brew install flock"
            return 1
        fi
    fi

    local lock_file="${OLLAMA_PID_FILE}.lock"

    # Acquire exclusive lock to prevent race conditions
    {
        flock -x -n 200 || {
            print_error "Another instance is managing the server"
            return 1
        }

        # Now safely check and manage PID (protected by lock)
        if [[ -f "$OLLAMA_PID_FILE" ]]; then
            local old_pid
            old_pid=$(cat "$OLLAMA_PID_FILE")
            if ps -p "$old_pid" > /dev/null 2>&1; then
                print_warning "Ollama server is already running (PID: $old_pid)"
                print_info "Use stop_ollama_server to stop it first"
                return 0
            else
                print_warning "Removing stale PID file"
                rm -f "$OLLAMA_PID_FILE"
            fi
        fi

        # Check if Ollama is installed
        if ! command -v ollama &> /dev/null; then
            print_error "Ollama is not installed"
            print_info "Run install_ollama first"
            return 1
        fi

        # Ensure directories exist
        mkdir -p ~/.local/var
        mkdir -p ~/.local/var/log

        print_info "Server configuration:"
        print_info "  Host: $OLLAMA_HOST"
        print_info "  Keep alive: $OLLAMA_KEEP_ALIVE"
        print_info "  GPU layers: $OLLAMA_NUM_GPU"
        print_info "  Max loaded models: $OLLAMA_MAX_LOADED_MODELS"
        print_info "  Flash attention: $OLLAMA_FLASH_ATTENTION"
        print_info "  Log file: $OLLAMA_LOG_FILE"

        # Start server in background
        print_info "Starting server..."
        nohup ollama serve > "$OLLAMA_LOG_FILE" 2>&1 &
        local pid=$!

        # Save PID
        echo "$pid" > "$OLLAMA_PID_FILE"
        print_status "Server started (PID: $pid)"

        # Wait for server to be ready
        print_info "Waiting for server to be ready..."
        local max_attempts=30
        local attempt=0

        while [[ $attempt -lt $max_attempts ]]; do
            if curl -s "http://127.0.0.1:$OLLAMA_PORT/api/tags" > /dev/null 2>&1; then
                print_status "Server is ready and responding"
                print_info "Health check: http://127.0.0.1:$OLLAMA_PORT/api/tags"
                return 0
            fi

            # Check if process is still running
            if ! ps -p "$pid" > /dev/null 2>&1; then
                print_error "Server process died unexpectedly"
                print_info "Check logs at: $OLLAMA_LOG_FILE"
                rm -f "$OLLAMA_PID_FILE"
                return 1
            fi

            sleep 1
            ((attempt++))
        done

        print_error "Server failed to respond after $max_attempts seconds"
        print_info "Check logs at: $OLLAMA_LOG_FILE"
        return 1

    } 200>"$lock_file"
}

# Stop Ollama server gracefully
stop_ollama_server() {
    set -euo pipefail

    print_header "Stopping Ollama Server"

    # Check if PID file exists
    if [[ ! -f "$OLLAMA_PID_FILE" ]]; then
        print_warning "No PID file found, server may not be running"
        return 0
    fi

    local pid
    pid=$(cat "$OLLAMA_PID_FILE")

    # Check if process is running
    if ! ps -p "$pid" > /dev/null 2>&1; then
        print_warning "Server process (PID: $pid) is not running"
        rm -f "$OLLAMA_PID_FILE"
        return 0
    fi

    print_info "Sending SIGTERM to process $pid..."
    kill -TERM "$pid" 2>/dev/null || true

    # Wait up to 5 seconds for graceful shutdown
    local countdown=5
    while [[ $countdown -gt 0 ]]; do
        if ! ps -p "$pid" > /dev/null 2>&1; then
            print_status "Server stopped gracefully"
            rm -f "$OLLAMA_PID_FILE"
            return 0
        fi
        sleep 1
        ((countdown--))
    done

    # Force kill if still running
    if ps -p "$pid" > /dev/null 2>&1; then
        print_warning "Server did not stop gracefully, forcing shutdown..."
        kill -KILL "$pid" 2>/dev/null || true
        sleep 1

        if ps -p "$pid" > /dev/null 2>&1; then
            print_error "Failed to stop server process"
            return 1
        fi
    fi

    print_status "Server stopped (forced)"
    rm -f "$OLLAMA_PID_FILE"
}

# Get server status
ollama_status() {
    print_header "Ollama Server Status"

    # Check installation
    if command -v ollama &> /dev/null; then
        local version
        version=$(ollama --version 2>&1 | head -1)
        print_status "Ollama installed: $version"
        print_status "Location: $(which ollama)"
    else
        print_warning "Ollama not installed"
    fi

    # Check server process
    if [[ -f "$OLLAMA_PID_FILE" ]]; then
        local pid
        pid=$(cat "$OLLAMA_PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            print_status "Server: Running (PID: $pid)"

            # Try to get model list
            if curl -s "http://127.0.0.1:$OLLAMA_PORT/api/tags" > /dev/null 2>&1; then
                print_status "Health check: Responding at http://127.0.0.1:$OLLAMA_PORT"
            else
                print_warning "Health check: Process running but not responding"
            fi
        else
            print_warning "Server: Not running (stale PID file)"
            rm -f "$OLLAMA_PID_FILE"
        fi
    else
        print_warning "Server: Not running"
    fi

    # Check log file
    if [[ -f "$OLLAMA_LOG_FILE" ]]; then
        local log_size
        log_size=$(du -h "$OLLAMA_LOG_FILE" | cut -f1)
        print_info "Log file: $OLLAMA_LOG_FILE ($log_size)"
    fi
}

#############################################
# Model Management Functions
#############################################

# Pull and optimize a model
pull_model() {
    set -euo pipefail

    local model="${1:-}"
    local context_size="${2:-128000}"

    if [[ -z "$model" ]]; then
        print_error "Usage: pull_model <model_name> [context_size]"
        print_info "Example: pull_model codellama:7b 128000"
        return 1
    fi

    # Security: Validate model name format to prevent command injection
    if ! is_valid_model_name "$model"; then
        print_error "Invalid model name format: $model"
        print_info "Model names must contain only alphanumeric characters, dots, dashes, underscores, and colons"
        print_info "Maximum length: 100 characters"
        return 1
    fi

    print_header "Pulling Model: $model"

    # Check if server is running
    if [[ ! -f "$OLLAMA_PID_FILE" ]] || ! ps -p "$(cat "$OLLAMA_PID_FILE")" > /dev/null 2>&1; then
        print_error "Ollama server is not running"
        print_info "Start the server first with: start_ollama_server"
        return 1
    fi

    # Check if Ollama is installed
    if ! command -v ollama &> /dev/null; then
        print_error "Ollama is not installed"
        return 1
    fi

    print_info "Pulling base model: $model"
    print_info "Target context size: $context_size"

    # Pull the model
    if ollama pull "$model"; then
        print_status "Model pulled successfully: $model"
    else
        print_error "Failed to pull model: $model"
        return 1
    fi

    # Display model info
    print_info "Model is ready to use"
    print_info "The model will use num_ctx parameter for context size"
    print_info "Example usage:"
    print_info "  ollama run $model"

    print_status "Model setup complete"
}

# List installed models
list_models() {
    print_header "Installed Models"

    # Check if server is running
    if [[ ! -f "$OLLAMA_PID_FILE" ]] || ! ps -p "$(cat "$OLLAMA_PID_FILE")" > /dev/null 2>&1; then
        print_error "Ollama server is not running"
        print_info "Start the server first with: start_ollama_server"
        return 1
    fi

    # Check if Ollama is installed
    if ! command -v ollama &> /dev/null; then
        print_error "Ollama is not installed"
        return 1
    fi

    ollama list
}

#############################################
# Export Functions
#############################################

# Make functions available when sourced
export -f install_ollama
export -f start_ollama_server
export -f stop_ollama_server
export -f ollama_status
export -f pull_model
export -f list_models
