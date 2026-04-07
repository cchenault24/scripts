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

# Setup Continue.dev configuration
setup_continue() {
    set -euo pipefail

    print_header "Setting up Continue.dev Configuration"

    local config_dir="$HOME/.continue"
    local config_file="$config_dir/config.json"

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

    # Create the config file
    print_info "Creating Continue.dev config.json..."
    cat > "$config_file" <<'EOF'
{
  "models": [
    {
      "title": "Llama 3.3 70B",
      "provider": "ollama",
      "model": "llama3.3:70b-instruct-q4_K_M",
      "apiBase": "http://127.0.0.1:31434"
    },
    {
      "title": "Codestral 22B (Code)",
      "provider": "ollama",
      "model": "codestral:22b-v0.1-q8_0",
      "apiBase": "http://127.0.0.1:31434"
    },
    {
      "title": "Gemma 4 31B",
      "provider": "ollama",
      "model": "gemma4:31b-it-q8_0",
      "apiBase": "http://127.0.0.1:31434"
    },
    {
      "title": "Phi 4 14B",
      "provider": "ollama",
      "model": "phi4:14b-q8_0",
      "apiBase": "http://127.0.0.1:31434"
    }
  ],
  "tabAutocompleteModel": {
    "title": "Fast Autocomplete",
    "provider": "ollama",
    "model": "llama3.2:3b-instruct-q8_0",
    "apiBase": "http://127.0.0.1:31434"
  }
}
EOF

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
            return 1
        fi
    else
        print_warning "Python3 not found, skipping JSON validation"
    fi

    print_status "Continue.dev configuration created successfully"
    print_info "Config location: $config_file"
    echo ""
    print_info "Configuration includes:"
    echo "  • Llama 3.3 70B (General purpose)"
    echo "  • Codestral 22B (Code-focused)"
    echo "  • Gemma 4 31B (Google's model)"
    echo "  • Phi 4 14B (Microsoft's model)"
    echo "  • Llama 3.2 3B (Fast autocomplete)"
    echo ""

    # Check IDE installation status
    check_continue_installed || true

    print_status "Continue.dev setup complete!"
    echo ""
    print_info "Next steps:"
    echo "  1. Install Continue.dev extension in your IDE (if not already installed)"
    echo "  2. Ensure Ollama is running on port 3456"
    echo "  3. Restart your IDE to load the new configuration"
}

#############################################
# Main Execution
#############################################

# If script is executed directly (not sourced), run setup
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_continue
fi
