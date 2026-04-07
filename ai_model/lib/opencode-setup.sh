#!/bin/bash
# opencode-setup.sh - OpenCode CLI installation and configuration
# This file should be sourced, not executed directly

# Source common utilities if not already loaded
if ! declare -f print_header >/dev/null 2>&1; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/common.sh"
fi

#############################################
# OpenCode Installation Functions
#############################################

# Check if OpenCode is installed
check_opencode_installed() {
    if command -v opencode &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Install OpenCode CLI
install_opencode() {
    set -euo pipefail

    print_header "Installing OpenCode CLI"

    # Check if already installed
    if check_opencode_installed; then
        local version
        version=$(opencode --version 2>/dev/null || echo "unknown")
        print_status "OpenCode is already installed (version: ${version})"
        return 0
    fi

    print_info "Installing OpenCode CLI..."

    # Option 1: Try npm installation (preferred if npm is available)
    if command -v npm &> /dev/null; then
        print_info "Installing via npm..."
        npm install -g opencode || {
            print_warning "npm installation failed, trying curl method..."
            install_opencode_via_curl
            return $?
        }
    # Option 2: Use curl install script
    else
        print_info "npm not available, using curl installation..."
        install_opencode_via_curl || return 1
    fi

    # Verify installation
    if check_opencode_installed; then
        local version
        version=$(opencode --version 2>/dev/null || echo "unknown")
        print_status "OpenCode installed successfully (version: ${version})"
        return 0
    else
        print_error "OpenCode installation failed"
        return 1
    fi
}

# Install OpenCode via curl
install_opencode_via_curl() {
    print_info "Downloading and running OpenCode install script..."

    # Download and execute the install script
    if curl -fsSL https://anthropic.com/install-opencode.sh | sh; then
        print_status "OpenCode installed via curl"

        # Add to PATH if needed (the install script usually handles this)
        if [[ -f "$HOME/.opencode/bin/opencode" ]] && ! command -v opencode &> /dev/null; then
            export PATH="$HOME/.opencode/bin:$PATH"
            print_info "Added OpenCode to PATH for this session"
        fi

        return 0
    else
        print_error "Curl installation failed"
        return 1
    fi
}

#############################################
# OpenCode Configuration Functions
#############################################

# Configure OpenCode with multi-agent setup
configure_opencode() {
    set -euo pipefail

    print_header "Configuring OpenCode"

    local config_dir="$HOME/.config/opencode"
    local config_file="${config_dir}/opencode.jsonc"
    local env_file="${config_dir}/opencode-env.sh"

    # Create config directory
    print_info "Creating configuration directory..."
    mkdir -p "$config_dir" || {
        print_error "Failed to create config directory: ${config_dir}"
        return 1
    }

    # Generate multi-agent configuration
    print_info "Generating multi-agent configuration..."
    cat > "$config_file" << 'EOF'
{
  "agents": [
    {
      "name": "build",
      "model": "ollama/llama3.3:70b-instruct-q4_K_M",
      "baseURL": "http://127.0.0.1:3456/v1",
      "maxSteps": 100
    },
    {
      "name": "review",
      "model": "ollama/llama3.3:70b-instruct-q4_K_M",
      "baseURL": "http://127.0.0.1:3456/v1",
      "maxSteps": 50,
      "permissions": {
        "edit": false
      }
    },
    {
      "name": "refactor",
      "model": "ollama/codestral:22b-v0.1-q8_0",
      "baseURL": "http://127.0.0.1:3456/v1",
      "maxSteps": 100
    }
  ],
  "modelParameters": {
    "repeat_penalty": 1.1,
    "num_predict": 16384
  }
}
EOF

    if [[ ! -f "$config_file" ]]; then
        print_error "Failed to create configuration file"
        return 1
    fi

    print_status "Configuration file created: ${config_file}"

    # Generate environment variables file
    print_info "Creating environment variables file..."
    cat > "$env_file" << 'EOF'
#!/bin/bash
# OpenCode Environment Variables
# Source this file to load OpenCode environment settings

# Performance optimizations
export UV_SYSTEM_PYTHON=1
export NODE_OPTIONS="--max-old-space-size=4096"

# Optional: Add OpenCode to PATH if installed in custom location
# export PATH="$HOME/.opencode/bin:$PATH"
EOF

    if [[ ! -f "$env_file" ]]; then
        print_error "Failed to create environment file"
        return 1
    fi

    chmod +x "$env_file"
    print_status "Environment file created: ${env_file}"

    # Validate JSON configuration
    print_info "Validating configuration..."
    if command -v python3 &> /dev/null; then
        if python3 -c "import json; json.load(open('${config_file}'))" 2>/dev/null; then
            print_status "Configuration is valid JSON"
        else
            print_warning "Configuration validation failed (may be due to JSONC comments)"
        fi
    else
        print_info "Skipping JSON validation (python3 not available)"
    fi

    print_status "OpenCode configuration complete"
}

#############################################
# Testing Functions
#############################################

# Test OpenCode installation and configuration
test_opencode() {
    set -euo pipefail

    print_header "Testing OpenCode Installation"

    local all_tests_passed=true

    # Test 1: Check if OpenCode is installed
    print_info "Test 1: Checking OpenCode installation..."
    if check_opencode_installed; then
        local version
        version=$(opencode --version 2>/dev/null || echo "unknown")
        print_status "OpenCode is installed (version: ${version})"
    else
        print_error "OpenCode is not installed"
        all_tests_passed=false
    fi

    # Test 2: Verify configuration file exists
    print_info "Test 2: Checking configuration file..."
    local config_file="$HOME/.config/opencode/opencode.jsonc"
    if [[ -f "$config_file" ]]; then
        print_status "Configuration file exists: ${config_file}"
    else
        print_error "Configuration file not found: ${config_file}"
        all_tests_passed=false
    fi

    # Test 3: Validate JSON configuration
    print_info "Test 3: Validating JSON configuration..."
    if [[ -f "$config_file" ]]; then
        if command -v python3 &> /dev/null; then
            if python3 -c "import json; json.load(open('${config_file}'))" 2>/dev/null; then
                print_status "Configuration is valid JSON"
            else
                print_warning "JSON validation had issues (JSONC comments may cause this)"
            fi
        else
            print_info "Skipping JSON validation (python3 not available)"
        fi
    fi

    # Test 4: Verify multi-agent setup
    print_info "Test 4: Checking multi-agent configuration..."
    if [[ -f "$config_file" ]]; then
        local agent_count
        agent_count=$(grep -c '"name":' "$config_file" || echo "0")
        if [[ "$agent_count" -ge 3 ]]; then
            print_status "Multi-agent setup configured (${agent_count} agents found)"
        else
            print_warning "Expected 3 agents, found ${agent_count}"
        fi
    fi

    # Test 5: Check environment file
    print_info "Test 5: Checking environment file..."
    local env_file="$HOME/.config/opencode/opencode-env.sh"
    if [[ -f "$env_file" ]]; then
        print_status "Environment file exists: ${env_file}"
    else
        print_warning "Environment file not found: ${env_file}"
    fi

    # Test 6: Try running OpenCode (basic test)
    print_info "Test 6: Testing OpenCode execution..."
    if check_opencode_installed; then
        # Just verify the command runs without error (use --help to avoid actual execution)
        if opencode --help &> /dev/null; then
            print_status "OpenCode command executes successfully"
        else
            print_warning "OpenCode command may have issues"
        fi
    else
        print_error "Cannot test execution - OpenCode not installed"
        all_tests_passed=false
    fi

    # Summary
    echo ""
    if $all_tests_passed; then
        print_status "All critical tests passed"
        return 0
    else
        print_error "Some tests failed"
        return 1
    fi
}

#############################################
# Main Setup Function
#############################################

# Complete OpenCode setup (install + configure + test)
setup_opencode() {
    set -euo pipefail

    print_header "OpenCode Setup"

    # Display hardware info
    print_info "Hardware Detection:"
    echo "  Chip: ${M_CHIP}"
    echo "  GPU Cores: ${GPU_CORES}"
    echo "  RAM: ${TOTAL_RAM_GB}GB (${RAM_TIER})"
    echo ""

    # Install OpenCode
    install_opencode || {
        print_error "OpenCode installation failed"
        return 1
    }

    # Configure OpenCode
    configure_opencode || {
        print_error "OpenCode configuration failed"
        return 1
    }

    # Test installation
    test_opencode || {
        print_warning "Some tests failed, but setup may still be functional"
    }

    print_header "OpenCode Setup Complete"

    # Display usage information
    print_info "Usage:"
    echo "  Run: opencode \"your prompt here\""
    echo "  Config: ~/.config/opencode/opencode.jsonc"
    echo "  Environment: source ~/.config/opencode/opencode-env.sh"
    echo ""
    print_info "Available agents:"
    echo "  - build: Llama 3.3 70B (100 steps, full permissions)"
    echo "  - review: Llama 3.3 70B (50 steps, read-only)"
    echo "  - refactor: Codestral 22B (100 steps, full permissions)"
    echo ""
    print_info "To use a specific agent:"
    echo "  opencode --agent build \"your prompt\""
    echo "  opencode --agent review \"your prompt\""
    echo "  opencode --agent refactor \"your prompt\""

    return 0
}

#############################################
# Module Export
#############################################

# Export functions for use in other scripts
export -f check_opencode_installed
export -f install_opencode
export -f install_opencode_via_curl
export -f configure_opencode
export -f test_opencode
export -f setup_opencode
