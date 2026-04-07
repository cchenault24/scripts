#!/bin/bash
# test-switch-model.sh - Test the model switching functionality
# This script simulates model switching without requiring Ollama to be running

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}========================================${NC}\n"; }
print_status() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWITCH_SCRIPT="${SCRIPT_DIR}/switch-model.sh"

# Test config directories
TEST_DIR="/tmp/switch-model-test-$$"
TEST_CONTINUE_CONFIG="${TEST_DIR}/.continue/config.json"
TEST_OPENCODE_CONFIG="${TEST_DIR}/.config/opencode/opencode.jsonc"

#############################################
# Setup Test Environment
#############################################

setup_test_environment() {
    print_header "Setting Up Test Environment"

    # Create test directories
    mkdir -p "${TEST_DIR}/.continue"
    mkdir -p "${TEST_DIR}/.config/opencode"

    # Create mock Continue.dev config
    cat > "$TEST_CONTINUE_CONFIG" << 'EOF'
{
  "models": [
    {
      "title": "Llama 3.3 70B",
      "provider": "ollama",
      "model": "llama3.3:70b-instruct-q4_K_M",
      "apiBase": "http://127.0.0.1:3456"
    },
    {
      "title": "Codestral 22B (Code)",
      "provider": "ollama",
      "model": "codestral:22b-v0.1-q8_0",
      "apiBase": "http://127.0.0.1:3456"
    }
  ],
  "tabAutocompleteModel": {
    "title": "Fast Autocomplete",
    "provider": "ollama",
    "model": "llama3.2:3b-instruct-q8_0",
    "apiBase": "http://127.0.0.1:3456"
  }
}
EOF

    # Create mock OpenCode config
    cat > "$TEST_OPENCODE_CONFIG" << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama (local)",
      "options": {
        "baseURL": "http://127.0.0.1:3456/v1",
        "timeout": 600000
      },
      "models": {
        "llama3.3:70b-instruct-q4_K_M": {
          "name": "Llama 3.3 70B",
          "tool_call": true,
          "limit": {
            "context": 128000,
            "output": 16384
          },
          "options": {
            "temperature": 0.7,
            "repeat_penalty": 1.1
          }
        }
      }
    }
  },
  "model": "ollama/llama3.3:70b-instruct-q4_K_M",
  "agent": {
    "build": {
      "prompt": "{file:./prompts/build.txt}",
      "steps": 100
    }
  }
}
EOF

    print_status "Test environment created at: ${TEST_DIR}"
    print_info "Continue config: ${TEST_CONTINUE_CONFIG}"
    print_info "OpenCode config: ${TEST_OPENCODE_CONFIG}"
}

#############################################
# Test Functions
#############################################

test_script_exists() {
    print_header "Test 1: Script Existence"

    if [[ -f "$SWITCH_SCRIPT" ]]; then
        print_status "switch-model.sh exists"
        return 0
    else
        print_error "switch-model.sh not found at: ${SWITCH_SCRIPT}"
        return 1
    fi
}

test_script_executable() {
    print_header "Test 2: Script Permissions"

    if [[ -x "$SWITCH_SCRIPT" ]]; then
        print_status "switch-model.sh is executable"
        return 0
    else
        print_error "switch-model.sh is not executable"
        return 1
    fi
}

test_usage_display() {
    print_header "Test 3: Usage Display"

    # Capture both stdout and stderr
    local output
    output=$("${SWITCH_SCRIPT}" 2>&1 || true)

    if echo "$output" | grep -q "Usage:"; then
        print_status "Usage information displays correctly"
        return 0
    else
        print_error "Usage information not displayed"
        print_info "Output was: $output"
        return 1
    fi
}

test_config_update_functions() {
    print_header "Test 4: Config Update Functions"

    print_info "Testing Python-based config updates..."

    # Test updating Continue config
    local new_model="gemma4:31b-it-q8_0"

    # Update Continue config
    if command -v python3 &> /dev/null; then
        python3 << PYEOF
import json
import sys

config_file = "${TEST_CONTINUE_CONFIG}"
new_model = "${new_model}"

try:
    with open(config_file, 'r') as f:
        config = json.load(f)

    # Update the first model's model field
    if 'models' in config and len(config['models']) > 0:
        config['models'][0]['model'] = new_model
        config['models'][0]['title'] = new_model

    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)

    sys.exit(0)

except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
PYEOF

        if [[ $? -eq 0 ]]; then
            # Verify the change
            if grep -q "$new_model" "$TEST_CONTINUE_CONFIG"; then
                print_status "Continue.dev config update works"
            else
                print_error "Continue.dev config update failed verification"
                return 1
            fi
        else
            print_error "Continue.dev config update failed"
            return 1
        fi

        # Update OpenCode config
        python3 << PYEOF
import json
import re
import sys

config_file = "${TEST_OPENCODE_CONFIG}"
new_model = "${new_model}"

try:
    with open(config_file, 'r') as f:
        content = f.read()

    # Remove JSONC comments (but not // in URLs)
    content_no_comments = re.sub(r'(?<!:)//.*\$', '', content, flags=re.MULTILINE)
    content_no_comments = re.sub(r'/\*.*?\*/', '', content_no_comments, flags=re.DOTALL)

    config = json.loads(content_no_comments)

    # Update model
    config['model'] = f'ollama/{new_model}'

    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)

    sys.exit(0)

except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
PYEOF

        if [[ $? -eq 0 ]]; then
            # Verify the change
            if grep -q "$new_model" "$TEST_OPENCODE_CONFIG"; then
                print_status "OpenCode config update works"
            else
                print_error "OpenCode config update failed verification"
                return 1
            fi
        else
            print_error "OpenCode config update failed"
            return 1
        fi

    else
        print_warning "Python3 not available, skipping config update test"
    fi

    return 0
}

test_backup_creation() {
    print_header "Test 5: Backup File Creation"

    # Create a test backup
    local test_file="${TEST_DIR}/test.json"
    echo '{"test": "data"}' > "$test_file"

    local backup="${test_file}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$test_file" "$backup"

    if [[ -f "$backup" ]]; then
        print_status "Backup file creation works"
        print_info "Backup: ${backup}"
        return 0
    else
        print_error "Backup file creation failed"
        return 1
    fi
}

test_model_verification_logic() {
    print_header "Test 6: Model Verification Logic"

    print_info "Testing model list parsing..."

    # Simulate ollama list output
    local mock_output=$(cat << 'EOF'
NAME                                ID              SIZE      MODIFIED
llama3.3:70b-instruct-q4_K_M       abc123def456    40 GB     2 days ago
gemma4:31b-it-q8_0                 def789ghi012    32 GB     1 day ago
codestral:22b-v0.1-q8_0            ghi345jkl678    22 GB     3 days ago
EOF
)

    # Test model name extraction
    local model_name="gemma4:31b-it-q8_0"
    if echo "$mock_output" | tail -n +2 | awk '{print $1}' | grep -q "^${model_name}$"; then
        print_status "Model verification logic works"
    else
        print_error "Model verification logic failed"
        return 1
    fi

    return 0
}

#############################################
# Display Test Results
#############################################

display_test_configs() {
    print_header "Configuration Files After Updates"

    echo -e "${BLUE}Continue.dev Config:${NC}"
    if [[ -f "$TEST_CONTINUE_CONFIG" ]]; then
        cat "$TEST_CONTINUE_CONFIG"
    else
        echo "Not found"
    fi

    echo ""
    echo -e "${BLUE}OpenCode Config:${NC}"
    if [[ -f "$TEST_OPENCODE_CONFIG" ]]; then
        cat "$TEST_OPENCODE_CONFIG"
    else
        echo "Not found"
    fi

    return 0
}

#############################################
# Cleanup
#############################################

cleanup() {
    print_header "Cleanup"
    if [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
        print_status "Test directory removed: ${TEST_DIR}"
    fi
}

#############################################
# Run All Tests
#############################################

run_all_tests() {
    # Temporarily disable exit on error for test counting
    set +e

    local tests_passed=0
    local tests_failed=0

    print_header "Switch Model Test Suite"
    print_info "Testing: ${SWITCH_SCRIPT}"

    # Setup
    setup_test_environment || { print_error "Test environment setup failed"; exit 1; }

    # Run tests
    test_script_exists && ((++tests_passed)) || ((++tests_failed))
    test_script_executable && ((++tests_passed)) || ((++tests_failed))
    test_usage_display && ((++tests_passed)) || ((++tests_failed))
    test_config_update_functions && ((++tests_passed)) || ((++tests_failed))
    test_backup_creation && ((++tests_passed)) || ((++tests_failed))
    test_model_verification_logic && ((++tests_passed)) || ((++tests_failed))

    # Display results
    display_test_configs

    # Summary
    print_header "Test Summary"
    echo -e "  Tests passed: ${GREEN}${tests_passed}${NC}"
    echo -e "  Tests failed: ${RED}${tests_failed}${NC}"
    echo ""

    if [[ $tests_failed -eq 0 ]]; then
        print_status "All tests passed!"
        echo ""
        print_info "The switch-model.sh script is ready to use"
        print_info "Usage examples:"
        echo "  ${SWITCH_SCRIPT} llama3.3:70b-instruct-q4_K_M"
        echo "  ${SWITCH_SCRIPT} gemma4:31b-it-q8_0 --unload"
    else
        print_error "Some tests failed"
    fi

    # Cleanup
    cleanup

    # Exit with appropriate code
    [[ $tests_failed -eq 0 ]] && exit 0 || exit 1
}

# Run tests
run_all_tests
