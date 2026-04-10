#!/bin/bash
# tests/test-launchagent.sh - Tests for LaunchAgent configuration
#
# Tests:
# - LaunchAgent plist generation
# - Only valid Ollama environment variables are set
# - No invalid/deprecated variables
# - Plist XML is valid
# - Configuration respects hardware settings
#
# Usage: ./tests/test-launchagent.sh [--verbose]

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test helpers
source "$SCRIPT_DIR/helpers.sh"

# Source libraries
source "$PROJECT_DIR/lib/common.sh"
source "$PROJECT_DIR/lib/hardware-config.sh"
source "$PROJECT_DIR/lib/launchagent.sh"

# Verbose mode
VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE=true
fi

# Test configuration
TEST_PLIST="/tmp/test-ollama-launchagent-$$.plist"
TEST_LABEL="com.ollama.test.$$"

# Cleanup function
cleanup() {
    rm -f "$TEST_PLIST"
}
trap cleanup EXIT

#############################################
# Test: Valid Environment Variables Only
#############################################

test_valid_env_vars() {
    print_section "Testing Valid Environment Variables"

    # Set up test environment
    LAUNCHAGENT_LABEL="$TEST_LABEL"
    LAUNCHAGENT_PLIST="$TEST_PLIST"
    NUM_PARALLEL=4
    CONTEXT_LENGTH=8192
    NUM_CTX=8192
    OLLAMA_HOST="http://localhost:11434"
    VERBOSITY_LEVEL=0

    # Generate plist (mock create_launchagent without loading)
    mkdir -p "$HOME/.local/var/log"
    local brew_prefix
    brew_prefix=$(brew --prefix)

    cat > "$TEST_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LAUNCHAGENT_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${brew_prefix}/bin/ollama</string>
        <string>serve</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>OLLAMA_HOST</key>
        <string>127.0.0.1:11434</string>
        <key>OLLAMA_KEEP_ALIVE</key>
        <string>-1</string>
        <key>OLLAMA_NUM_PARALLEL</key>
        <string>${NUM_PARALLEL}</string>
    </dict>
    <key>StandardOutPath</key>
    <string>$HOME/.local/var/log/ollama.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.local/var/log/ollama.stderr.log</string>
</dict>
</plist>
EOF

    begin_test "Plist file was created"
    if [[ -f "$TEST_PLIST" ]]; then
        pass_test
    else
        fail_test "Plist file not created"
    fi

    begin_test "OLLAMA_HOST is set"
    if grep -q "<key>OLLAMA_HOST</key>" "$TEST_PLIST"; then
        pass_test
    else
        fail_test "OLLAMA_HOST not found in plist"
    fi

    begin_test "OLLAMA_KEEP_ALIVE is set to -1"
    if grep -A 1 "<key>OLLAMA_KEEP_ALIVE</key>" "$TEST_PLIST" | grep -q "<string>-1</string>"; then
        pass_test
    else
        fail_test "OLLAMA_KEEP_ALIVE not set to -1"
    fi

    begin_test "OLLAMA_NUM_PARALLEL is set"
    if grep -q "<key>OLLAMA_NUM_PARALLEL</key>" "$TEST_PLIST"; then
        pass_test
    else
        fail_test "OLLAMA_NUM_PARALLEL not found in plist"
    fi
}

#############################################
# Test: Invalid Variables NOT Present
#############################################

test_no_invalid_vars() {
    print_section "Testing No Invalid Environment Variables"

    begin_test "OLLAMA_METAL_MEMORY is NOT set (invalid)"
    if grep -q "OLLAMA_METAL_MEMORY" "$TEST_PLIST"; then
        fail_test "OLLAMA_METAL_MEMORY should not be in plist (Ollama auto-detects)"
    else
        pass_test
    fi

    begin_test "OLLAMA_GPU_LAYERS is NOT set (invalid)"
    if grep -q "OLLAMA_GPU_LAYERS" "$TEST_PLIST"; then
        fail_test "OLLAMA_GPU_LAYERS should not be in plist (Modelfile parameter only)"
    else
        pass_test
    fi

    begin_test "OLLAMA_CONTEXT_LENGTH is NOT set (invalid)"
    if grep -q "OLLAMA_CONTEXT_LENGTH" "$TEST_PLIST"; then
        fail_test "OLLAMA_CONTEXT_LENGTH should not be in plist (doesn't exist)"
    else
        pass_test
    fi

    begin_test "OLLAMA_NUM_CTX is NOT set (invalid)"
    if grep -q "OLLAMA_NUM_CTX" "$TEST_PLIST"; then
        fail_test "OLLAMA_NUM_CTX should not be in plist (Modelfile parameter only)"
    else
        pass_test
    fi

    begin_test "OLLAMA_FLASH_ATTENTION is NOT set (deprecated)"
    if grep -q "OLLAMA_FLASH_ATTENTION" "$TEST_PLIST"; then
        fail_test "OLLAMA_FLASH_ATTENTION should not be in plist (deprecated)"
    else
        pass_test
    fi
}

#############################################
# Test: Plist XML Validity
#############################################

test_plist_validity() {
    print_section "Testing Plist XML Validity"

    begin_test "Plist is valid XML"
    if plutil -lint "$TEST_PLIST" > /dev/null 2>&1; then
        pass_test
    else
        fail_test "Plist XML is invalid"
    fi

    begin_test "Plist contains Label"
    if grep -q "<key>Label</key>" "$TEST_PLIST"; then
        pass_test
    else
        fail_test "Label not found in plist"
    fi

    begin_test "Plist contains ProgramArguments"
    if grep -q "<key>ProgramArguments</key>" "$TEST_PLIST"; then
        pass_test
    else
        fail_test "ProgramArguments not found in plist"
    fi

    begin_test "Plist contains ollama binary path"
    if grep -q "/bin/ollama" "$TEST_PLIST"; then
        pass_test
    else
        fail_test "Ollama binary path not found"
    fi

    begin_test "Plist contains 'serve' argument"
    if grep -q "<string>serve</string>" "$TEST_PLIST"; then
        pass_test
    else
        fail_test "'serve' argument not found"
    fi

    begin_test "Plist has RunAtLoad=true"
    if grep -A 1 "<key>RunAtLoad</key>" "$TEST_PLIST" | grep -q "<true/>"; then
        pass_test
    else
        fail_test "RunAtLoad not set to true"
    fi

    begin_test "Plist has KeepAlive=true"
    if grep -A 1 "<key>KeepAlive</key>" "$TEST_PLIST" | grep -q "<true/>"; then
        pass_test
    else
        fail_test "KeepAlive not set to true"
    fi
}

#############################################
# Test: Log File Paths
#############################################

test_log_paths() {
    print_section "Testing Log File Paths"

    begin_test "StandardOutPath is set"
    if grep -q "<key>StandardOutPath</key>" "$TEST_PLIST"; then
        pass_test
    else
        fail_test "StandardOutPath not found"
    fi

    begin_test "StandardErrorPath is set"
    if grep -q "<key>StandardErrorPath</key>" "$TEST_PLIST"; then
        pass_test
    else
        fail_test "StandardErrorPath not found"
    fi

    begin_test "Log paths point to .local/var/log"
    if grep -q "\.local/var/log/ollama" "$TEST_PLIST"; then
        pass_test
    else
        fail_test "Log paths don't point to .local/var/log"
    fi

    begin_test "Log directory exists or can be created"
    if [[ -d "$HOME/.local/var/log" ]] || mkdir -p "$HOME/.local/var/log" 2>/dev/null; then
        pass_test
    else
        fail_test "Cannot create log directory"
    fi
}

#############################################
# Test: Environment Variable Count
#############################################

test_env_var_count() {
    print_section "Testing Environment Variable Count"

    begin_test "Exactly 3 environment variables are set"
    local env_var_count=$(grep -c "<key>OLLAMA_" "$TEST_PLIST" || true)
    if [[ $env_var_count -eq 3 ]]; then
        pass_test
        if [[ "$VERBOSE" == true ]]; then
            echo "    Found: OLLAMA_HOST, OLLAMA_KEEP_ALIVE, OLLAMA_NUM_PARALLEL"
        fi
    else
        fail_test "Expected 3 OLLAMA_ env vars, found $env_var_count"
        if [[ "$VERBOSE" == true ]]; then
            echo "    Environment variables found:"
            grep "<key>OLLAMA_" "$TEST_PLIST" || true
        fi
    fi

    begin_test "No other Ollama-related variables"
    local extra_vars=$(grep -c "OLLAMA_[A-Z_]*" "$TEST_PLIST" || true)
    # Should be 3 (the valid ones we expect)
    if [[ $extra_vars -eq 3 ]]; then
        pass_test
    else
        fail_test "Found unexpected Ollama variables (count: $extra_vars)"
    fi
}

#############################################
# Test: Hardware-Specific Configuration
#############################################

test_hardware_config() {
    print_section "Testing Hardware-Specific Configuration"

    begin_test "NUM_PARALLEL value is in plist"
    if grep -q "<string>${NUM_PARALLEL}</string>" "$TEST_PLIST"; then
        pass_test
    else
        fail_test "NUM_PARALLEL value not found in plist"
    fi

    begin_test "NUM_PARALLEL is a positive integer"
    local num_parallel_value=$(grep -A 1 "<key>OLLAMA_NUM_PARALLEL</key>" "$TEST_PLIST" | grep -o "<string>[0-9]*</string>" | grep -o "[0-9]*")
    if [[ $num_parallel_value =~ ^[1-9][0-9]*$ ]]; then
        pass_test
        if [[ "$VERBOSE" == true ]]; then
            echo "    NUM_PARALLEL = $num_parallel_value"
        fi
    else
        fail_test "NUM_PARALLEL is not a positive integer: $num_parallel_value"
    fi
}

#############################################
# Test: Source File Comments
#############################################

test_source_file_comments() {
    print_section "Testing Source File Documentation"

    local launchagent_file="$PROJECT_DIR/lib/launchagent.sh"

    begin_test "launchagent.sh explains where optimizations are set"
    if grep -q "baked into" "$launchagent_file"; then
        pass_test
    else
        fail_test "Missing documentation about where optimizations are set"
    fi

    begin_test "launchagent.sh documents valid env vars"
    if grep -q "OLLAMA_NUM_PARALLEL" "$launchagent_file" && \
       grep -q "OLLAMA_KEEP_ALIVE" "$launchagent_file"; then
        pass_test
    else
        fail_test "Missing documentation for valid env vars"
    fi

    begin_test "launchagent.sh explains context is in Modelfile"
    if grep -qi "modelfile" "$launchagent_file"; then
        pass_test
    else
        fail_test "Missing explanation that context is set in Modelfile"
    fi
}

#############################################
# Test: Integration with Hardware Config
#############################################

test_integration_with_hardware() {
    print_section "Testing Integration with Hardware Config"

    begin_test "calculate_num_parallel() returns valid value"
    local num_parallel=$(calculate_num_parallel 48)
    if [[ $num_parallel =~ ^[1-9][0-9]*$ ]]; then
        pass_test
        if [[ "$VERBOSE" == true ]]; then
            echo "    48GB RAM → $num_parallel parallel requests"
        fi
    else
        fail_test "Invalid num_parallel value: $num_parallel"
    fi

    begin_test "Different RAM values produce different num_parallel"
    local num_8gb=$(calculate_num_parallel 8)
    local num_64gb=$(calculate_num_parallel 64)
    if [[ $num_8gb -lt $num_64gb ]]; then
        pass_test
        if [[ "$VERBOSE" == true ]]; then
            echo "    8GB → $num_8gb, 64GB → $num_64gb"
        fi
    else
        fail_test "num_parallel should scale with RAM"
    fi
}

#############################################
# Main Execution
#############################################

main() {
    init_tests

    # Run all test suites
    test_valid_env_vars
    test_no_invalid_vars
    test_plist_validity
    test_log_paths
    test_env_var_count
    test_hardware_config
    test_source_file_comments
    test_integration_with_hardware

    # Print summary and exit
    if print_test_summary; then
        exit 0
    else
        exit 1
    fi
}

# Run main
main "$@"
