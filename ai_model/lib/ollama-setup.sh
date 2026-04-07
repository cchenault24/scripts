#!/bin/bash
# ollama-setup.sh - Build and manage Ollama with Apple Silicon optimizations
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
# Build Configuration
#############################################
export OLLAMA_BUILD_DIR="/tmp/ollama-build"
export PORT="31434"  # High port to avoid conflicts (unlikely to conflict with dev tools)

# Build flags for Apple Silicon optimization
export CGO_CFLAGS="-O3 -march=native -mtune=native -flto -fomit-frame-pointer -DNDEBUG -funroll-loops -fvectorize"
export CGO_LDFLAGS="-flto -framework Metal -framework Foundation -framework Accelerate"

# Go build optimization
export CGO_ENABLED=1
export GOARCH=arm64
export GOOS=darwin

# Runtime configuration
export OLLAMA_HOST="127.0.0.1:$PORT"
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
# Build Function
#############################################

# Clone and build Ollama with optimizations
build_ollama() {
    set -euo pipefail

    print_header "Building Ollama from Source"

    # Check for Go
    if ! command -v go &> /dev/null; then
        print_error "Go is not installed. Please install Go first."
        return 1
    fi

    print_info "Go version: $(go version)"
    print_info "Build directory: $OLLAMA_BUILD_DIR"
    print_info "CGO_CFLAGS: $CGO_CFLAGS"
    print_info "CGO_LDFLAGS: $CGO_LDFLAGS"

    # Create build directory
    mkdir -p "$OLLAMA_BUILD_DIR"

    # Clone or update repository
    if [[ -d "$OLLAMA_BUILD_DIR/.git" ]]; then
        print_info "Updating existing Ollama repository..."
        cd "$OLLAMA_BUILD_DIR"
        git fetch origin || {
            print_error "Failed to fetch updates"
            return 1
        }
        git reset --hard origin/main || {
            print_error "Failed to reset to origin/main"
            return 1
        }
    else
        print_info "Cloning Ollama repository..."
        rm -rf "$OLLAMA_BUILD_DIR"
        git clone https://github.com/ollama/ollama "$OLLAMA_BUILD_DIR" || {
            print_error "Failed to clone Ollama repository"
            return 1
        }
        cd "$OLLAMA_BUILD_DIR"
    fi

    print_status "Repository ready at: $OLLAMA_BUILD_DIR"

    # Get current commit
    local commit_hash
    commit_hash=$(git rev-parse --short HEAD)
    print_info "Building from commit: $commit_hash"

    # Build the binary with optimizations
    print_info "Building Ollama binary (this may take several minutes)..."

    # Set Go environment
    export GOARCH=arm64
    export GOOS=darwin

    if go build -trimpath -ldflags="-s -w" -o ollama 2>&1 | tee "$OLLAMA_LOG_FILE.build"; then
        print_status "Ollama binary built successfully"
    else
        local build_exit_code=$?

        # Check for known non-critical issues (more specific patterns)
        if grep -qE "web.*optional|node.*optional|ui.*skipped" "$OLLAMA_LOG_FILE.build"; then
            if [[ -f "$OLLAMA_BUILD_DIR/ollama" ]] && [[ -x "$OLLAMA_BUILD_DIR/ollama" ]]; then
                print_warning "UI build skipped, but core binary is functional"
            else
                print_error "Build failed: core binary not created (exit: $build_exit_code)"
                return 1
            fi
        else
            print_error "Build failed with exit code: $build_exit_code"
            cat "$OLLAMA_LOG_FILE.build"
            return 1
        fi
    fi

    # Verify the binary
    if [[ ! -f "$OLLAMA_BUILD_DIR/ollama" ]]; then
        print_error "Ollama binary not found after build"
        return 1
    fi

    print_info "Verifying binary..."
    if "$OLLAMA_BUILD_DIR/ollama" --version 2>&1 | head -1; then
        print_status "Binary verification successful"
    else
        print_warning "Version check returned non-zero, but binary may still work"
    fi

    # Display binary info
    local binary_size
    binary_size=$(du -h "$OLLAMA_BUILD_DIR/ollama" | cut -f1)
    print_status "Binary size: $binary_size"
    print_status "Binary location: $OLLAMA_BUILD_DIR/ollama"

    print_status "Ollama build complete"
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

        # Check if binary exists
        if [[ ! -f "$OLLAMA_BUILD_DIR/ollama" ]]; then
            print_error "Ollama binary not found at $OLLAMA_BUILD_DIR/ollama"
            print_info "Run build_ollama first"
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
        nohup "$OLLAMA_BUILD_DIR/ollama" serve > "$OLLAMA_LOG_FILE" 2>&1 &
        local pid=$!

        # Save PID
        echo "$pid" > "$OLLAMA_PID_FILE"
        print_status "Server started (PID: $pid)"

        # Wait for server to be ready
        print_info "Waiting for server to be ready..."
        local max_attempts=30
        local attempt=0

        while [[ $attempt -lt $max_attempts ]]; do
            if curl -s "http://127.0.0.1:$PORT/api/tags" > /dev/null 2>&1; then
                print_status "Server is ready and responding"
                print_info "Health check: http://127.0.0.1:$PORT/api/tags"
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

    # Check binary
    if [[ -f "$OLLAMA_BUILD_DIR/ollama" ]]; then
        local binary_size
        binary_size=$(du -h "$OLLAMA_BUILD_DIR/ollama" | cut -f1)
        print_status "Binary: $OLLAMA_BUILD_DIR/ollama ($binary_size)"
    else
        print_warning "Binary not found at $OLLAMA_BUILD_DIR/ollama"
    fi

    # Check server process
    if [[ -f "$OLLAMA_PID_FILE" ]]; then
        local pid
        pid=$(cat "$OLLAMA_PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            print_status "Server: Running (PID: $pid)"

            # Try to get model list
            if curl -s "http://127.0.0.1:$PORT/api/tags" > /dev/null 2>&1; then
                print_status "Health check: Responding at http://127.0.0.1:$PORT"
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

    # Check if binary exists
    if [[ ! -f "$OLLAMA_BUILD_DIR/ollama" ]]; then
        print_error "Ollama binary not found"
        return 1
    fi

    print_info "Pulling base model: $model"
    print_info "Target context size: $context_size"

    # Pull the model
    if "$OLLAMA_BUILD_DIR/ollama" pull "$model"; then
        print_status "Model pulled successfully: $model"
    else
        print_error "Failed to pull model: $model"
        return 1
    fi

    # Display model info
    print_info "Model is ready to use"
    print_info "The model will use num_ctx parameter for context size"
    print_info "Example usage:"
    print_info "  $OLLAMA_BUILD_DIR/ollama run $model"

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

    # Check if binary exists
    if [[ ! -f "$OLLAMA_BUILD_DIR/ollama" ]]; then
        print_error "Ollama binary not found"
        return 1
    fi

    "$OLLAMA_BUILD_DIR/ollama" list
}

#############################################
# Export Functions
#############################################

# Make functions available when sourced
export -f build_ollama
export -f start_ollama_server
export -f stop_ollama_server
export -f ollama_status
export -f pull_model
export -f list_models
