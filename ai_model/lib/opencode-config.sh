#!/bin/bash
# lib/opencode-config.sh - OpenCode configuration generation
#
# Provides:
# - OpenCode JSON config creation
# - Provider configuration (Ollama)
# - Optional plugin installation (superpowers)

set -euo pipefail

# Configure OpenCode with Ollama provider
#
# Globals read:
#   - CUSTOM_MODEL_NAME: Name of custom model
#   - GEMMA_MODEL: Base model name
#   - OLLAMA_HOST: Ollama server URL
#   - NUM_CTX: Context length
#   - AUTO_MODE: Whether in auto mode
configure_opencode() {
    print_step "6/6" "Configuring OpenCode"

    local opencode_config="$HOME/.config/opencode/opencode.json"

    # Create config directory if it doesn't exist
    mkdir -p "$(dirname "$opencode_config")"

    # Check if config already exists
    if [[ -f "$opencode_config" ]]; then
        print_verbose "OpenCode config already exists"

        # Backup existing config
        local backup_path
        backup_path="${opencode_config}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$opencode_config" "$backup_path"
        print_verbose "Existing config backed up"
    fi

    # Ask about superpowers plugin (skip in auto mode or quiet mode)
    local install_plugin=false
    if [[ "$AUTO_MODE" != true ]] && [[ $VERBOSITY_LEVEL -ge 1 ]]; then
        echo ""
        echo -e "${BLUE}Optional: Superpowers Plugin${NC}"
        echo "The superpowers plugin adds enhanced OpenCode capabilities:"
        echo "  • Advanced workflows and skills"
        echo "  • Extended tool integrations"
        echo "  • Source: https://github.com/obra/superpowers"
        echo ""
        read -p "Install superpowers plugin? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_plugin=true
        fi
    fi

    print_verbose "Creating OpenCode configuration..."
    print_verbose "Model: ollama/$CUSTOM_MODEL_NAME"
    print_verbose "Context window: $(printf "%'d" "$NUM_CTX") tokens"

    # OpenCode uses model format: "ollama/model-name"
    # Ollama API URL needs /v1 suffix for OpenAI-compatible endpoint
    if [[ "$install_plugin" == true ]]; then
        # Config with plugin
        cat > "$opencode_config" << EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "ollama/${CUSTOM_MODEL_NAME}",
  "plugin": [
    "superpowers@git+https://github.com/obra/superpowers.git"
  ],
  "provider": {
    "ollama": {
      "name": "Ollama",
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "${OLLAMA_HOST}/v1"
      },
      "models": {
        "${GEMMA_MODEL}": {
          "name": "${GEMMA_MODEL}"
        },
        "${CUSTOM_MODEL_NAME}": {
          "name": "${CUSTOM_MODEL_NAME}:latest"
        }
      }
    }
  }
}
EOF
    else
        # Config without plugin
        cat > "$opencode_config" << EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "ollama/${CUSTOM_MODEL_NAME}",
  "provider": {
    "ollama": {
      "name": "Ollama",
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "${OLLAMA_HOST}/v1"
      },
      "models": {
        "${GEMMA_MODEL}": {
          "name": "${GEMMA_MODEL}"
        },
        "${CUSTOM_MODEL_NAME}": {
          "name": "${CUSTOM_MODEL_NAME}:latest"
        }
      }
    }
  }
}
EOF
    fi

    # Validate JSON syntax (if jq is available)
    if command -v jq &> /dev/null; then
        if ! jq empty "$opencode_config" > /dev/null 2>&1; then
            print_error "OpenCode config JSON validation failed"
            print_verbose "Config may contain syntax errors"
            exit 1
        fi
        print_verbose "OpenCode config JSON validated successfully"
    fi

    if [[ $VERBOSITY_LEVEL -ge 2 ]]; then
        print_status "OpenCode configured to use ollama/$CUSTOM_MODEL_NAME"
        print_status "Ollama endpoint: ${OLLAMA_HOST}/v1"
        print_status "Context: $(printf "%'d" "$NUM_CTX") tokens"

        if [[ "$install_plugin" == true ]]; then
            print_status "Plugin: superpowers"
        else
            print_info "No plugins configured"
        fi
    else
        print_status "OpenCode configured"
        if [[ "$install_plugin" == true ]]; then
            print_verbose "Plugin: superpowers"
        fi
    fi
}
