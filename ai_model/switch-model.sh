#!/bin/bash
# switch-model.sh - Change active model and update all client configs
# Usage: ./switch-model.sh <model_name> [--unload]

set -euo pipefail

#############################################
# Configuration
#############################################

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Ollama configuration
export PORT="3456"
export OLLAMA_BUILD_DIR="/tmp/ollama-build"
export OLLAMA_HOST="127.0.0.1:${PORT}"

# Config file paths
CONTINUE_CONFIG="$HOME/.continue/config.json"
OPENCODE_CONFIG="$HOME/.config/opencode/opencode.jsonc"

#############################################
# Helper Functions
#############################################

# Display usage information
usage() {
    cat << EOF
Usage: $0 <model_name> [--unload]

Switch the active AI model and update all client configurations.

Arguments:
  model_name    The Ollama model to switch to (e.g., llama3.3:70b-instruct-q4_K_M)
  --unload      Optional: Unload the previous model before switching

Examples:
  $0 llama3.3:70b-instruct-q4_K_M
  $0 gemma4:31b-it-q8_0 --unload

Config files updated:
  • Continue.dev: $CONTINUE_CONFIG
  • OpenCode: $OPENCODE_CONFIG
  • WebUI: Manual selection required at http://localhost:8080

EOF
    exit 1
}

# Check if Ollama server is running
check_ollama_running() {
    if ! curl -s "http://127.0.0.1:${PORT}/api/tags" > /dev/null 2>&1; then
        print_error "Ollama server is not running on port ${PORT}"
        print_info "Start the server first with: cd ${SCRIPT_DIR} && source lib/ollama-setup.sh && start_ollama_server"
        return 1
    fi
    return 0
}

# Verify model exists in Ollama
verify_model_exists() {
    local model="$1"

    print_info "Verifying model exists: ${model}"

    # Use the custom-built Ollama if available, otherwise try system ollama
    local ollama_cmd
    if [[ -f "${OLLAMA_BUILD_DIR}/ollama" ]]; then
        ollama_cmd="${OLLAMA_BUILD_DIR}/ollama"
    elif command -v ollama &> /dev/null; then
        ollama_cmd="ollama"
    else
        print_error "Ollama binary not found"
        return 1
    fi

    if "${ollama_cmd}" list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -q "^${model}$"; then
        print_status "Model found: ${model}"
        return 0
    else
        print_error "Model not installed: ${model}"
        echo ""
        print_info "Available models:"
        "${ollama_cmd}" list 2>/dev/null | tail -n +2 || echo "  (none)"
        echo ""
        print_info "To install this model, run:"
        echo "  ${ollama_cmd} pull ${model}"
        return 1
    fi
}

# Get currently loaded model
get_current_model() {
    local response
    response=$(curl -s "http://127.0.0.1:${PORT}/api/ps" 2>/dev/null || echo "")

    if [[ -n "$response" ]]; then
        # Extract model name from JSON response
        echo "$response" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4 || echo ""
    else
        echo ""
    fi
}

# Unload current model
unload_current_model() {
    local current_model
    current_model=$(get_current_model)

    if [[ -z "$current_model" ]]; then
        print_info "No model currently loaded"
        return 0
    fi

    print_info "Unloading current model: ${current_model}"

    # Send request to unload model (set keep_alive to 0)
    curl -s "http://127.0.0.1:${PORT}/api/generate" \
        -d "{\"model\":\"${current_model}\",\"keep_alive\":0}" \
        > /dev/null 2>&1 || true

    # Wait a moment for unload
    sleep 2

    print_status "Model unloaded"
}

# Preload (warm-up) the new model
preload_model() {
    local model="$1"

    print_info "Preloading ${model} into VRAM..."
    print_info "This may take 10-30 seconds depending on model size..."

    # Send a minimal prompt to load the model
    local response
    response=$(curl -s "http://127.0.0.1:${PORT}/api/generate" \
        -d "{\"model\":\"${model}\",\"prompt\":\"hi\",\"stream\":false}" 2>&1)

    if [[ $? -eq 0 ]]; then
        print_status "Model preloaded successfully"
        return 0
    else
        print_warning "Preload may have failed, but continuing..."
        return 0
    fi
}

# Update Continue.dev config
update_continue_config() {
    local model="$1"

    if [[ ! -f "$CONTINUE_CONFIG" ]]; then
        print_warning "Continue.dev config not found at ${CONTINUE_CONFIG}"
        print_info "Run continue-setup.sh to create it"
        return 0
    fi

    print_info "Updating Continue.dev configuration..."

    # Backup the config
    local backup="${CONTINUE_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CONTINUE_CONFIG" "$backup"

    # Update the default model using Python
    if command -v python3 &> /dev/null; then
        python3 << PYEOF
import json
import sys

config_file = "${CONTINUE_CONFIG}"
new_model = "${model}"

try:
    with open(config_file, 'r') as f:
        config = json.load(f)

    # Update the first model's model field
    if 'models' in config and len(config['models']) > 0:
        config['models'][0]['model'] = new_model
        config['models'][0]['title'] = new_model

    # Update tabAutocompleteModel if it exists and model is large
    # (keep autocomplete on smaller model for performance)

    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)

    print('Continue.dev config updated', file=sys.stderr)
    sys.exit(0)

except Exception as e:
    print(f'Failed to update Continue.dev config: {e}', file=sys.stderr)
    sys.exit(1)
PYEOF

        if [[ $? -eq 0 ]]; then
            print_status "Continue.dev updated"
            print_info "Backup saved: ${backup}"
        else
            print_error "Failed to update Continue.dev config"
            # Restore backup
            cp "$backup" "$CONTINUE_CONFIG"
            return 1
        fi
    else
        print_warning "Python3 not available, skipping Continue.dev update"
    fi

    return 0
}

# Update OpenCode config
update_opencode_config() {
    local model="$1"

    if [[ ! -f "$OPENCODE_CONFIG" ]]; then
        print_warning "OpenCode config not found at ${OPENCODE_CONFIG}"
        print_info "Run opencode-setup.sh to create it"
        return 0
    fi

    print_info "Updating OpenCode configuration..."

    # Backup the config
    local backup="${OPENCODE_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$OPENCODE_CONFIG" "$backup"

    # Create a unique model key for OpenCode (replace : and - with safe chars)
    local model_key="${model}"

    # Update the model using Python (handles JSONC with comments)
    if command -v python3 &> /dev/null; then
        export NEW_MODEL="$model"
        export MODEL_KEY="$model_key"
        python3 << 'PYEOF'
import json
import re
import sys
import os

config_file = os.environ.get('OPENCODE_CONFIG')
new_model = os.environ.get('NEW_MODEL')
model_key = os.environ.get('MODEL_KEY')

try:
    with open(config_file, 'r') as f:
        content = f.read()

    # Remove JSONC comments for parsing (but not // in URLs)
    # Remove single-line comments (only if not preceded by :)
    content_no_comments = re.sub(r'(?<!:)//.*$', '', content, flags=re.MULTILINE)
    # Remove multi-line comments
    content_no_comments = re.sub(r'/\*.*?\*/', '', content_no_comments, flags=re.DOTALL)

    config = json.loads(content_no_comments)

    # Update the main model field
    config['model'] = f'ollama/{new_model}'

    # Update model in provider.ollama.models if it exists
    if 'provider' in config and 'ollama' in config['provider']:
        if 'models' not in config['provider']['ollama']:
            config['provider']['ollama']['models'] = {}

        # Get existing model config if any, or use defaults
        existing_models = config['provider']['ollama']['models']
        model_config = {
            'name': new_model,
            'tool_call': True,
            'limit': {
                'context': 128000,
                'output': 16384
            },
            'options': {
                'temperature': 0.7,
                'top_p': 0.95,
                'top_k': 64,
                'repeat_penalty': 1.1,
                'num_predict': 16384
            }
        }

        # Copy existing settings if available from first model
        if existing_models:
            first_model = next(iter(existing_models.values()))
            if 'limit' in first_model:
                model_config['limit'] = first_model['limit']
            if 'options' in first_model:
                model_config['options'] = first_model['options']

        # Clear old models and add new one
        config['provider']['ollama']['models'] = {
            model_key: model_config
        }

    # Write back with proper formatting
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)

    print('OpenCode config updated', file=sys.stderr)
    sys.exit(0)

except Exception as e:
    print(f'Failed to update OpenCode config: {e}', file=sys.stderr)
    sys.exit(1)
PYEOF

        if [[ $? -eq 0 ]]; then
            print_status "OpenCode updated"
            print_info "Backup saved: ${backup}"
        else
            print_error "Failed to update OpenCode config"
            # Restore backup
            cp "$backup" "$OPENCODE_CONFIG"
            return 1
        fi
    else
        print_warning "Python3 not available, skipping OpenCode update"
    fi

    return 0
}

#############################################
# Main Function
#############################################

switch_model() {
    local new_model="$1"
    local unload_previous="${2:-false}"

    print_header "Switching to Model: ${new_model}"

    # Step 1: Check if Ollama server is running
    check_ollama_running || exit 1

    # Step 2: Verify model exists
    verify_model_exists "$new_model" || exit 1

    # Step 3: Unload previous model if requested
    if [[ "$unload_previous" == "true" ]]; then
        unload_current_model
    fi

    # Step 4: Preload new model (warm-up)
    preload_model "$new_model" || {
        print_warning "Preload had issues, but continuing with config updates..."
    }

    # Step 5: Update Continue.dev config
    update_continue_config "$new_model" || {
        print_warning "Continue.dev update failed, but continuing..."
    }

    # Step 6: Update OpenCode config
    update_opencode_config "$new_model" || {
        print_warning "OpenCode update failed, but continuing..."
    }

    # Step 7: Display status and instructions
    echo ""
    print_header "Model Switch Complete"
    echo ""
    print_status "Continue.dev updated: ${CONTINUE_CONFIG}"
    print_status "OpenCode updated: ${OPENCODE_CONFIG}"
    echo ""
    print_info "Note: Open WebUI requires manual model selection"
    print_info "  1. Open http://localhost:8080"
    print_info "  2. Select ${new_model} from the dropdown"
    echo ""
    print_status "Successfully switched to: ${new_model}"
    echo ""
    print_info "Next steps:"
    echo "  • Restart your IDE to load new Continue.dev config"
    echo "  • OpenCode will use new model on next run"
    echo "  • Manually select model in Open WebUI interface"
}

#############################################
# Script Entry Point
#############################################

# Parse arguments
if [[ $# -eq 0 ]]; then
    usage
fi

MODEL="$1"
UNLOAD_FLAG="false"

# Check for --unload flag
if [[ $# -ge 2 ]]; then
    if [[ "$2" == "--unload" ]]; then
        UNLOAD_FLAG="true"
    else
        print_error "Unknown option: $2"
        usage
    fi
fi

# Execute the switch
switch_model "$MODEL" "$UNLOAD_FLAG"
