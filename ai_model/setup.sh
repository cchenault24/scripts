#!/bin/bash
#
# Setup Gemma 4 with Ollama + OpenCode - Modular Version
#
# Usage:
#   ./setup.sh                              # Interactive setup
#   OLLAMA_MODEL=gemma4:e4b-it-q8_0 ./setup.sh  # Skip model selection
#   BUILD_OPENCODE_FROM_SOURCE=true ./setup.sh  # Build from dev branch
#   INSTALL_EMBEDDING_MODEL=false ./setup.sh    # Skip embeddings
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all modules
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/model-selection.sh"
source "$SCRIPT_DIR/lib/ollama-setup.sh"

# Configuration
export AUTO_START="${AUTO_START:-true}"
export AUTO_START_ON_LOGIN="${AUTO_START_ON_LOGIN:-false}"
export BUILD_OPENCODE_FROM_SOURCE="${BUILD_OPENCODE_FROM_SOURCE:-false}"
export INSTALL_EMBEDDING_MODEL="${INSTALL_EMBEDDING_MODEL:-false}"

# Main setup flow
main() {
    print_header "Gemma 4 + Ollama + OpenCode Setup"

    # Step 0: Check prerequisites
    check_prerequisites

    # Step 1: Build Ollama (before model selection so we can detect installed models)
    build_ollama

    # Step 2: Model Selection (after Ollama is built so we can use it to list models)
    if [ -z "${OLLAMA_MODEL:-}" ]; then
        select_model
    else
        print_info "Using model from environment: $OLLAMA_MODEL"
        echo ""
    fi

    # Step 3: Install/Configure OpenCode
    # Call original setup script for OpenCode setup (Steps 2-3)
    # This avoids duplicating complex OpenCode setup logic
    print_info "Configuring OpenCode (calling original setup for Steps 2-3)..."
    OLLAMA_MODEL="$OLLAMA_MODEL" \
    BUILD_OPENCODE_FROM_SOURCE="$BUILD_OPENCODE_FROM_SOURCE" \
    AUTO_START="false" \
    "$SCRIPT_DIR/setup-gemma4-working.sh-opencode-only" 2>/dev/null || {
        print_warning "OpenCode setup via modular path not available yet"
        print_info "Using integrated setup..."
    }

    # Step 4: Start server and pull models
    start_ollama_server "$AUTO_START"

    if [ "$AUTO_START" = "true" ]; then
        # Determine context size
        if [[ "$OLLAMA_MODEL" == *"26b"* ]] || [[ "$OLLAMA_MODEL" == *"31b"* ]]; then
            CONTEXT_SIZE=256000
        else
            CONTEXT_SIZE=128000
        fi

        pull_and_optimize_model "$OLLAMA_MODEL" "$CONTEXT_SIZE"

        # Step 5: Install embedding model (if enabled)
        if [ "$INSTALL_EMBEDDING_MODEL" = "true" ]; then
            install_embedding_model
        fi
    fi

    # Final summary
    print_header "Setup Complete!"

    print_status "Ollama: $OLLAMA_BUILD_DIR/ollama"
    print_status "Model: $OLLAMA_MODEL"
    print_status "Server: Port $PORT"
    print_status "RAM: ${TOTAL_RAM_GB}GB"

    if [ "$INSTALL_EMBEDDING_MODEL" = "true" ]; then
        print_status "Embeddings: nomic-embed-text"
    fi

    echo ""
    print_info "Server control: $SCRIPT_DIR/llama-control.sh {start|stop|restart|status|logs|models}"
    echo ""
}

install_embedding_model() {
    print_header "Installing Embedding Model"

    EMBEDDING_MODEL="nomic-embed-text"
    export OLLAMA_HOST="127.0.0.1:$PORT"

    print_info "Checking if embedding model is already available..."

    if "$OLLAMA_BUILD_DIR/ollama" list 2>/dev/null | grep -q "$EMBEDDING_MODEL"; then
        print_status "Embedding model $EMBEDDING_MODEL already installed"
    else
        print_info "Pulling $EMBEDDING_MODEL (274MB, optimized for code/text)..."
        print_info "Use case: Semantic search for large codebases (1000+ files)"
        echo ""

        if "$OLLAMA_BUILD_DIR/ollama" pull "$EMBEDDING_MODEL"; then
            echo ""
            print_status "Embedding model installed successfully"
            print_info "Use for: Semantic code search, finding similar functions, etc."
        else
            echo ""
            print_warning "Failed to pull embedding model (optional, can skip)"
            print_info "You can install it later with:"
            print_info "  OLLAMA_HOST=127.0.0.1:$PORT $OLLAMA_BUILD_DIR/ollama pull $EMBEDDING_MODEL"
        fi
    fi

    echo ""
}

# Run main function
main
