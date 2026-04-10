#!/bin/bash
# setup-llama3-simple.sh - Simplified setup for llama3.1:8b + OpenCode
#
# No model selection, no warmup, no ranking - just works.
# Hardcoded to llama3.1:8b (5GB, 131K context, tool calling support)
#
# Usage: ./setup-llama3-simple.sh

set -euo pipefail

#############################################
# Configuration
#############################################

MODEL="llama3.1:8b"
CONTEXT_LENGTH=131072
OLLAMA_HOST="http://localhost:11434"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#############################################
# Helper Functions
#############################################

print_step() {
    echo -e "${BLUE}==> $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
    exit 1
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

#############################################
# Install Ollama
#############################################

install_ollama() {
    print_step "Checking Ollama installation"

    if command -v ollama &> /dev/null; then
        print_success "Ollama already installed"
        return 0
    fi

    print_info "Installing Ollama via Homebrew..."

    if ! command -v brew &> /dev/null; then
        print_error "Homebrew not found. Install from https://brew.sh first"
    fi

    brew install ollama
    print_success "Ollama installed"
}

#############################################
# Start Ollama Service
#############################################

start_ollama() {
    print_step "Starting Ollama service"

    # Check if already running
    if pgrep -x "ollama" > /dev/null; then
        print_success "Ollama already running"
        return 0
    fi

    # Start via brew services
    brew services start ollama

    # Wait for service to be ready
    print_info "Waiting for Ollama to start..."
    for i in {1..30}; do
        if curl -s "$OLLAMA_HOST" > /dev/null 2>&1; then
            print_success "Ollama service ready"
            return 0
        fi
        sleep 1
    done

    print_error "Ollama failed to start"
}

#############################################
# Pull Model
#############################################

pull_model() {
    print_step "Pulling $MODEL (5GB download)"

    # Check if model already exists (capture output first to avoid SIGPIPE with pipefail)
    local models
    models=$(ollama list)
    if echo "$models" | grep -q "$MODEL"; then
        print_success "Model already downloaded"
        return 0
    fi

    print_info "Downloading $MODEL..."
    ollama pull "$MODEL"
    print_success "Model downloaded"
}

#############################################
# Create Custom Model with Optimized Parameters
#############################################

create_custom_model() {
    print_step "Creating optimized model"

    local custom_name="llama3-coding"

    # Check if custom model already exists (capture output first to avoid SIGPIPE)
    local models
    models=$(ollama list)
    if echo "$models" | grep -q "$custom_name"; then
        print_success "Custom model already exists"
        return 0
    fi

    print_info "Creating $custom_name with optimized parameters..."

    # Create temporary Modelfile
    local modelfile="/tmp/Modelfile.llama3"
    cat > "$modelfile" << EOF
FROM ${MODEL}

# Set full context window (131K tokens)
PARAMETER num_ctx ${CONTEXT_LENGTH}

# Optimize for code generation
PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER top_k 40

# System prompt optimized for coding
SYSTEM """
You are a helpful AI coding assistant. You provide clear, accurate, and well-documented code solutions.
Focus on code quality, best practices, and security.
"""
EOF

    # Create custom model
    if ollama create "$custom_name" -f "$modelfile"; then
        print_success "Custom model created: $custom_name"
        rm "$modelfile"
    else
        print_error "Failed to create custom model"
        rm "$modelfile"
    fi
}

#############################################
# Configure OpenCode
#############################################

configure_opencode() {
    print_step "Configuring OpenCode"

    local config_file="$HOME/.config/opencode/opencode.json"
    local custom_name="llama3-coding"

    # Create config directory
    mkdir -p "$(dirname "$config_file")"

    # Backup existing config if present
    if [[ -f "$config_file" ]]; then
        cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
        print_info "Existing config backed up"
    fi

    # Write OpenCode config using custom model
    cat > "$config_file" << EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "ollama/$custom_name",
  "provider": {
    "ollama": {
      "name": "Ollama",
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "${OLLAMA_HOST}/v1"
      },
      "models": {
        "$MODEL": {
          "name": "$MODEL"
        },
        "$custom_name": {
          "name": "$custom_name:latest"
        }
      }
    }
  }
}
EOF

    print_success "OpenCode configured"
}

#############################################
# Verify Setup
#############################################

verify_setup() {
    print_step "Verifying setup"

    local custom_name="llama3-coding"

    # Check Ollama is running
    if ! curl -s "$OLLAMA_HOST" > /dev/null 2>&1; then
        print_error "Ollama service not responding"
    fi

    # Get model list once (avoid SIGPIPE with pipefail)
    local models
    models=$(ollama list)

    # Check base model exists
    if ! echo "$models" | grep -q "$MODEL"; then
        print_error "Base model $MODEL not found"
    fi

    # Check custom model exists
    if ! echo "$models" | grep -q "$custom_name"; then
        print_error "Custom model $custom_name not found"
    fi

    # Test custom model with simple prompt
    print_info "Testing custom model..."
    local test_response
    test_response=$(ollama run "$custom_name" "Reply with just 'ok'" 2>&1 | head -1)

    print_success "Setup verified"
}

#############################################
# Main
#############################################

main() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Simple Llama3.1 Setup for OpenCode${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Model:   $MODEL"
    echo "Context: $(printf "%'d" $CONTEXT_LENGTH) tokens"
    echo "Tools:   ✓ Function calling supported"
    echo ""

    install_ollama
    start_ollama
    pull_model
    create_custom_model
    configure_opencode
    verify_setup

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Setup Complete!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Open your IDE (VS Code, JetBrains, etc.)"
    echo "  2. Install OpenCode extension if not already installed"
    echo "  3. Start coding - OpenCode will use llama3-coding"
    echo ""
    echo "Test the custom model:"
    echo "  ollama run llama3-coding"
    echo ""
    echo "Model parameters:"
    echo "  • Base: $MODEL"
    echo "  • Custom: llama3-coding (optimized for coding)"
    echo "  • Context: $(printf "%'d" $CONTEXT_LENGTH) tokens"
    echo "  • Temperature: 0.7, Top-P: 0.9, Top-K: 40"
    echo ""
}

main
