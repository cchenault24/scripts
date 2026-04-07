#!/bin/bash
#
# Ollama build and configuration
#

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

build_ollama() {
    print_header "Building Ollama from latest commit"

    # Check if already built
    if [ -f "$OLLAMA_BUILD_DIR/ollama" ]; then
        print_status "Ollama already built"
        "$OLLAMA_BUILD_DIR/ollama" --version
        print_info "To rebuild, remove: $OLLAMA_BUILD_DIR"
        return 0
    fi

    if [ -d "$OLLAMA_BUILD_DIR" ]; then
        print_warning "Removing incomplete build directory: $OLLAMA_BUILD_DIR"
        rm -rf "$OLLAMA_BUILD_DIR"
    fi

    print_info "Cloning latest Ollama from main branch..."
    git clone --depth 1 https://github.com/ollama/ollama.git "$OLLAMA_BUILD_DIR"
    cd "$OLLAMA_BUILD_DIR"

    print_info "Installing build dependencies..."
    go install github.com/tkrajina/typescriptify-golang-structs/tscriptify@latest

    # Ensure Go bin is in PATH
    export PATH="$PATH:$(go env GOPATH)/bin"

    # Detect CPU count for parallel compilation
    NUM_CPUS=$(sysctl -n hw.ncpu)

    print_info "Building Ollama with Apple Silicon optimizations..."
    print_info "Enabling: Metal GPU, Accelerate Framework, Native CPU optimizations"
    print_info "Additional: LTO, Frame Pointer Optimization, Parallel Build (${NUM_CPUS} cores)"
    print_info "This may take 5-10 minutes..."
    echo ""

    # Set build environment for maximum Apple Silicon performance
    export CGO_ENABLED=1
    export GOARCH=arm64
    export GOMAXPROCS=$NUM_CPUS

    # Aggressive CGO optimizations
    # -O3: Maximum optimization level
    # -march=native: Use all available CPU features
    # -mtune=native: Tune for this specific CPU
    # -flto: Link Time Optimization for cross-module optimization
    # -fomit-frame-pointer: Free up register for better performance
    # -DNDEBUG: Disable debug assertions
    export CGO_CFLAGS="-O3 -march=native -mtune=native -flto -fomit-frame-pointer -DNDEBUG"
    export CGO_LDFLAGS="-flto -framework Metal -framework Foundation -framework Accelerate"

    # Generate C++ components with Metal support
    go generate ./... || {
        print_warning "go generate had some warnings, continuing..."
    }

    # Build with optimizations
    # -p: Parallel compilation using all CPU cores
    # -trimpath: Remove absolute paths for reproducible builds
    # -ldflags="-s -w": Strip debug info and symbol table
    # -ldflags="-linkmode=external": Use external linker for better LTO
    go build -p $NUM_CPUS -trimpath -ldflags="-s -w -linkmode=external" .

    print_status "Ollama built successfully"
    "$OLLAMA_BUILD_DIR/ollama" --version

    echo ""
}

start_ollama_server() {
    local auto_start="${1:-true}"

    if [ "$auto_start" != "true" ]; then
        return 0
    fi

    print_header "Starting Ollama Server"

    # Create log directory
    LOG_DIR="$HOME/.local/var/log"
    mkdir -p "$LOG_DIR"

    # Check if port is already in use
    if lsof -ti:$PORT >/dev/null 2>&1; then
        print_warning "Port $PORT is already in use"
        print_info "Killing existing process..."
        lsof -ti:$PORT | xargs kill -9
        sleep 2
    fi

    print_info "Starting Ollama server on port $PORT..."
    print_info "Log file: $LOG_DIR/ollama-server.log"
    print_info "Performance: Keep-alive enabled, all GPU layers, flash attention"
    echo ""

    # Start Ollama in background with performance optimizations
    # OLLAMA_HOST: Bind to specific port
    # OLLAMA_KEEP_ALIVE=-1: Keep models in memory indefinitely
    # OLLAMA_NUM_GPU=999: Offload all layers to GPU
    # OLLAMA_MAX_LOADED_MODELS=1: Focus memory on single model for best performance
    # OLLAMA_FLASH_ATTENTION=1: Enable flash attention for faster inference
    OLLAMA_HOST=127.0.0.1:$PORT \
    OLLAMA_KEEP_ALIVE=-1 \
    OLLAMA_NUM_GPU=999 \
    OLLAMA_MAX_LOADED_MODELS=1 \
    OLLAMA_FLASH_ATTENTION=1 \
    nohup "$OLLAMA_BUILD_DIR/ollama" serve \
        > "$LOG_DIR/ollama-server.log" 2>&1 &

    SERVER_PID=$!
    echo "$SERVER_PID" > "$HOME/.local/var/ollama-server.pid"

    print_status "Ollama server started (PID: $SERVER_PID)"
    print_info "Waiting for server to be ready..."

    # Wait for health check (up to 60 seconds)
    TIMEOUT=60
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        if curl -s -f "http://127.0.0.1:$PORT/api/tags" >/dev/null 2>&1; then
            print_status "Ollama server is ready!"
            echo ""
            return 0
        fi
        sleep 1
        ELAPSED=$((ELAPSED + 1))
    done

    print_warning "Server did not respond within ${TIMEOUT}s"
    print_info "Check logs: $LOG_DIR/ollama-server.log"
    return 1
}

pull_and_optimize_model() {
    local model_name="$1"
    local context_size="$2"

    print_header "Model Setup: $model_name"

    print_info "Checking if model is already available..."

    # Set OLLAMA_HOST for the CLI commands
    export OLLAMA_HOST="127.0.0.1:$PORT"

    # Check if base model exists
    MODEL_EXISTS=false
    if OLLAMA_HOST="127.0.0.1:$PORT" "$OLLAMA_BUILD_DIR/ollama" list 2>/dev/null | grep -q "^$model_name"; then
        MODEL_EXISTS=true
        print_status "Model $model_name already installed"
        print_info "Skipping download..."
    else
        # Estimate size based on model name
        MODEL_SIZE="unknown size"
        case "$model_name" in
            *e2b*q4*)  MODEL_SIZE="~7GB" ;;
            *e2b*q8*)  MODEL_SIZE="~8GB" ;;
            *e4b*q4*)  MODEL_SIZE="~10GB" ;;
            *e4b*q8*)  MODEL_SIZE="~12GB" ;;
            *26b*q4*)  MODEL_SIZE="~18GB" ;;
            *26b*q8*)  MODEL_SIZE="~28GB" ;;
            *31b*q4*)  MODEL_SIZE="~20GB" ;;
            *31b*q8*)  MODEL_SIZE="~34GB" ;;
        esac

        print_info "Pulling model $model_name ($MODEL_SIZE)..."
        print_info "This may take 10-30 minutes depending on your connection"
        echo ""

        if OLLAMA_HOST="127.0.0.1:$PORT" "$OLLAMA_BUILD_DIR/ollama" pull "$model_name"; then
            echo ""
            print_status "Model $model_name pulled successfully"
            MODEL_EXISTS=true
        else
            echo ""
            print_error "Failed to pull model"
            print_info "You can pull it manually later with:"
            print_info "  OLLAMA_HOST=127.0.0.1:$PORT $OLLAMA_BUILD_DIR/ollama pull $model_name"
            return 1
        fi
    fi

    # Create or recreate optimized model (always run this, even if base model existed)
    if [ "$MODEL_EXISTS" = true ]; then
        echo ""
        print_info "Creating optimized model with $context_size token context..."
        MODEL_SUFFIX=$(echo "$model_name" | grep -q "26b\|31b" && echo "256k" || echo "128k")
        OPTIMIZED_MODEL="${model_name}-${MODEL_SUFFIX}"

        # Check if optimized model already exists
        if OLLAMA_HOST="127.0.0.1:$PORT" "$OLLAMA_BUILD_DIR/ollama" list 2>/dev/null | grep -q "^$OPTIMIZED_MODEL"; then
            print_info "Optimized model already exists, recreating with latest settings..."
        fi

        cat > /tmp/modelfile-$$ << EOF
FROM $model_name
PARAMETER num_ctx $context_size
PARAMETER temperature 0.7
PARAMETER top_k 64
PARAMETER top_p 0.95
EOF

        if OLLAMA_HOST="127.0.0.1:$PORT" "$OLLAMA_BUILD_DIR/ollama" create "$OPTIMIZED_MODEL" -f /tmp/modelfile-$$ >/dev/null 2>&1; then
            rm -f /tmp/modelfile-$$
            print_status "Created optimized model: $OPTIMIZED_MODEL"
            export OLLAMA_MODEL="$OPTIMIZED_MODEL"

            # Update OpenCode config to use optimized model
            CONFIG_FILE="$HOME/.config/opencode/opencode.jsonc"
            if [ -f "$CONFIG_FILE" ]; then
                print_info "Updating OpenCode config to use optimized model..."
                # Update the model references in the config
                sed -i.bak "s|\"${model_name}\":|\"$OPTIMIZED_MODEL\":|g" "$CONFIG_FILE"
                sed -i.bak "s|ollama/${model_name}|ollama/$OPTIMIZED_MODEL|g" "$CONFIG_FILE"
                rm -f "$CONFIG_FILE.bak"
                print_status "Config updated to use: $OPTIMIZED_MODEL"
            fi
        else
            rm -f /tmp/modelfile-$$
            print_warning "Could not create optimized model, using base model"
            export OLLAMA_MODEL="$model_name"
        fi
    fi

    echo ""
}
