#!/bin/bash
# continue-setup.sh - Configure Continue.dev for JetBrains and VS Code
# This file can be sourced or executed directly

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common utilities if not already loaded
if ! declare -f print_header >/dev/null 2>&1; then
    if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
        source "$SCRIPT_DIR/common.sh"
    else
        # Fallback print functions if common.sh is not available
        print_header() { echo -e "\n========================================\n$1\n========================================\n"; }
        print_info() { echo "ℹ $1"; }
        print_status() { echo "✓ $1"; }
        print_warning() { echo "⚠ $1"; }
        print_error() { echo "✗ $1"; }
    fi
fi

#############################################
# IDE Detection Functions
#############################################

# Detect installed IDEs
detect_ides() {
    local found_ides=()

    # Check for JetBrains IDEs
    if [[ -d "$HOME/Library/Application Support/JetBrains" ]]; then
        found_ides+=("JetBrains")
    fi

    # Check for VS Code
    if [[ -d "$HOME/Library/Application Support/Code" ]]; then
        found_ides+=("VSCode")
    fi

    echo "${found_ides[@]}"
}

# Check if Continue.dev is installed in JetBrains
check_jetbrains_continue() {
    local jetbrains_dir="$HOME/Library/Application Support/JetBrains"

    if [[ ! -d "$jetbrains_dir" ]]; then
        return 1
    fi

    # Look for Continue plugin in any JetBrains IDE directory
    # Plugin directory pattern: {IDE_VERSION}/plugins/continue* or similar
    if find "$jetbrains_dir" -type d -name "*continue*" -o -name "*Continue*" 2>/dev/null | grep -q .; then
        return 0
    fi

    return 1
}

# Check if Continue.dev is installed in VS Code
check_vscode_continue() {
    local vscode_extensions="$HOME/.vscode/extensions"

    if [[ ! -d "$vscode_extensions" ]]; then
        return 1
    fi

    # Look for Continue extension directory
    if find "$vscode_extensions" -type d -name "continue.*" 2>/dev/null | grep -q .; then
        return 0
    fi

    return 1
}

# Check if Continue.dev extension is installed
check_continue_installed() {
    local ides=($(detect_ides))
    local installed=false
    local not_installed=()

    if [[ ${#ides[@]} -eq 0 ]]; then
        print_warning "No supported IDEs detected (JetBrains or VS Code)"
        return 1
    fi

    print_info "Checking for Continue.dev extension..."

    for ide in "${ides[@]}"; do
        if [[ "$ide" == "JetBrains" ]]; then
            if check_jetbrains_continue; then
                print_status "Continue.dev found in JetBrains"
                installed=true
            else
                not_installed+=("JetBrains")
            fi
        elif [[ "$ide" == "VSCode" ]]; then
            if check_vscode_continue; then
                print_status "Continue.dev found in VS Code"
                installed=true
            else
                not_installed+=("VSCode")
            fi
        fi
    done

    # Print installation instructions if not installed in any detected IDE
    if [[ ${#not_installed[@]} -gt 0 ]]; then
        echo ""
        print_warning "Continue.dev Extension Not Found in: ${not_installed[*]}"
        echo ""
        echo "To install Continue.dev:"
        echo ""

        for ide in "${not_installed[@]}"; do
            if [[ "$ide" == "JetBrains" ]]; then
                echo "  JetBrains:"
                echo "    1. Open your JetBrains IDE (IntelliJ, PyCharm, WebStorm, etc.)"
                echo "    2. Go to Settings/Preferences → Plugins"
                echo "    3. Search for 'Continue'"
                echo "    4. Click Install"
                echo ""
            elif [[ "$ide" == "VSCode" ]]; then
                echo "  VS Code:"
                echo "    1. Open VS Code"
                echo "    2. Go to Extensions (⇧⌘X or Ctrl+Shift+X)"
                echo "    3. Search for 'Continue'"
                echo "    4. Click Install"
                echo ""
            fi
        done

        echo "Extension URL: https://www.continue.dev/install"
        echo ""

        if [[ "$installed" == false ]]; then
            return 1
        fi
    fi

    return 0
}

#############################################
# Continue.dev Configuration
#############################################

# Get installed Ollama models dynamically
get_installed_models() {
    local ollama_url="${1:-http://127.0.0.1:31434}"

    # Query Ollama API for installed models
    if ! curl -s "${ollama_url}/api/tags" 2>/dev/null; then
        print_warning "Could not fetch models from Ollama (is it running?)"
        return 1
    fi
}

# Generate Continue config with installed models
generate_continue_config() {
    local ollama_url="${1:-http://127.0.0.1:31434}"

    # Ensure URL has http:// prefix
    if [[ ! "$ollama_url" =~ ^https?:// ]]; then
        ollama_url="http://${ollama_url}"
    fi

    # Continue.dev requires the OpenAI-compatible /v1 endpoint
    local continue_url="${ollama_url}/v1"

    print_info "Detecting installed models..." >&2

    # Fetch models from Ollama
    local models_json
    models_json=$(curl -s "${ollama_url}/api/tags" 2>/dev/null || echo '{"models":[]}')

    # Parse model names using python (more reliable than jq/sed)
    local model_list
    model_list=$(python3 -c "
import json, sys
data = json.loads('''${models_json}''')
for model in data.get('models', []):
    print(model['name'])
" 2>/dev/null || echo "")

    if [[ -z "$model_list" ]]; then
        print_warning "No models found, creating default config" >&2
        # Use the model from OLLAMA_MODEL if set
        if [[ -n "${OLLAMA_MODEL:-}" ]]; then
            model_list="$OLLAMA_MODEL"
        else
            print_error "No models available and OLLAMA_MODEL not set" >&2
            return 1
        fi
    fi

    # Build models JSON array
    local models_json_array="["
    local first=true
    local autocomplete_model=""

    while IFS= read -r model_name; do
        [[ -z "$model_name" ]] && continue

        # Determine title based on model family
        local title="$model_name"
        if [[ "$model_name" =~ llama ]]; then
            title="Llama (${model_name##*:})"
        elif [[ "$model_name" =~ codestral ]]; then
            title="Codestral (Code)"
        elif [[ "$model_name" =~ gemma ]]; then
            title="Gemma (${model_name##*:})"
        elif [[ "$model_name" =~ phi ]]; then
            title="Phi (${model_name##*:})"
        elif [[ "$model_name" =~ qwen ]]; then
            title="Qwen (${model_name##*:})"
        fi

        # Use smaller models for autocomplete
        if [[ "$model_name" =~ (1b|2b|3b) ]] && [[ -z "$autocomplete_model" ]]; then
            autocomplete_model="$model_name"
        fi

        # Add to models array
        if [[ "$first" == "true" ]]; then
            first=false
        else
            models_json_array+=","
        fi

        models_json_array+=$(cat <<EOF

    {
      "title": "$title",
      "provider": "ollama",
      "model": "$model_name",
      "apiUrl": "$continue_url"
    }
EOF
)
    done <<< "$model_list"

    models_json_array+=$'\n  ]'

    # Autocomplete model section
    local autocomplete_section=""
    if [[ -n "$autocomplete_model" ]]; then
        autocomplete_section=$(cat <<EOF
,
  "tabAutocompleteModel": {
    "title": "Fast Autocomplete",
    "provider": "ollama",
    "model": "$autocomplete_model",
    "apiUrl": "$continue_url"
  }
EOF
)
    fi

    # Generate full config
    cat <<EOF
{
  "models": ${models_json_array}${autocomplete_section},
  "embeddingsProvider": {
    "provider": "ollama",
    "model": "nomic-embed-text",
    "apiUrl": "$continue_url"
  },
  "reranker": {
    "name": "free-trial"
  },
  "contextProviders": [
    {
      "name": "code",
      "params": {}
    },
    {
      "name": "docs",
      "params": {}
    },
    {
      "name": "diff",
      "params": {}
    },
    {
      "name": "terminal",
      "params": {}
    },
    {
      "name": "problems",
      "params": {}
    },
    {
      "name": "folder",
      "params": {}
    },
    {
      "name": "codebase",
      "params": {}
    }
  ],
  "slashCommands": [
    {
      "name": "edit",
      "description": "Edit selected code"
    },
    {
      "name": "comment",
      "description": "Write comments for the selected code"
    },
    {
      "name": "share",
      "description": "Export the current chat session to markdown"
    },
    {
      "name": "cmd",
      "description": "Generate a shell command"
    },
    {
      "name": "commit",
      "description": "Generate a commit message"
    }
  ]
}
EOF
}

# Setup Continue.dev configuration
setup_continue() {
    set -euo pipefail

    print_header "Setting up Continue.dev Configuration"

    local config_dir="$HOME/.continue"
    local config_file="$config_dir/config.json"
    # Use PORT from environment/ollama-setup.sh, or default to 31434
    local port="${PORT:-31434}"
    local ollama_url="http://127.0.0.1:${port}"

    # Ensure OLLAMA_HOST is set for model detection
    export OLLAMA_HOST="127.0.0.1:${port}"

    # Create config directory if it doesn't exist
    if [[ ! -d "$config_dir" ]]; then
        print_info "Creating Continue.dev config directory..."
        mkdir -p "$config_dir" || {
            print_error "Failed to create directory: $config_dir"
            return 1
        }
    fi

    # Backup existing config if it exists
    if [[ -f "$config_file" ]]; then
        local backup_file="$config_file.backup.$(date +%Y%m%d_%H%M%S)"
        print_warning "Existing config found, backing up to: $backup_file"
        cp "$config_file" "$backup_file" || {
            print_error "Failed to backup existing config"
            return 1
        }
    fi

    # Generate dynamic config based on installed models
    print_info "Generating config from installed models..."
    if ! generate_continue_config "$ollama_url" > "$config_file"; then
        print_error "Failed to generate config"
        return 1
    fi

    if [[ ! -f "$config_file" ]]; then
        print_error "Failed to create config file"
        return 1
    fi

    # Validate JSON
    print_info "Validating JSON configuration..."
    if command -v python3 &> /dev/null; then
        if python3 -c "import json; json.load(open('$config_file'))" 2>/dev/null; then
            print_status "Configuration file is valid JSON"
        else
            print_error "Configuration file contains invalid JSON"
            cat "$config_file"
            return 1
        fi
    else
        print_warning "Python3 not found, skipping JSON validation"
    fi

    # Show installed models
    print_status "Continue.dev configuration created successfully"
    print_info "Config location: $config_file"
    echo ""
    print_info "Configured models:"
    python3 -c "
import json
with open('$config_file') as f:
    config = json.load(f)
    for model in config.get('models', []):
        print(f\"  • {model['title']}\")
    if 'tabAutocompleteModel' in config:
        print(f\"  • {config['tabAutocompleteModel']['title']} (autocomplete)\")
" 2>/dev/null || echo "  (Could not parse config)"
    echo ""

    # Check IDE installation status
    check_continue_installed || true

    print_status "Continue.dev setup complete!"
    echo ""
    print_info "Next steps:"
    echo "  1. Install Continue.dev extension in your IDE (if not already installed)"
    echo "  2. Ensure Ollama is running on port 31434 (http://127.0.0.1:31434)"
    echo "  3. Restart your IDE to load the new configuration"
}

#############################################
# Main Execution
#############################################

# If script is executed directly (not sourced), run setup
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_continue
fi
