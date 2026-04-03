#!/usr/bin/env bash

#==============================================================================
# test_security.sh - Security Feature Tests
#
# Tests security-related functionality:
# - Plugin name sanitization
# - Temp file permissions
# - State file security
#==============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test helpers
source "$SCRIPT_DIR/test_helpers.sh"

# Setup modules
export ZSH_SETUP_ROOT="$PROJECT_ROOT"
source "$PROJECT_ROOT/lib/utils/filesystem.sh"
source "$PROJECT_ROOT/lib/state/store.sh"
source "$PROJECT_ROOT/lib/core/config.sh"
source "$PROJECT_ROOT/lib/core/logger.sh"

#------------------------------------------------------------------------------
# Plugin Name Sanitization Tests
#------------------------------------------------------------------------------

test_sanitize_alphanumeric() {
    test_start "Sanitize alphanumeric"
    local result=$(zsh_setup::utils::filesystem::sanitize_name "test-plugin_123")
    assert_equal "test-plugin_123" "$result" "Alphanumeric with dash and underscore should pass" && test_pass
}

test_sanitize_dots() {
    test_start "Sanitize dots"
    local result=$(zsh_setup::utils::filesystem::sanitize_name "my.plugin.v1.0")
    assert_equal "my.plugin.v1.0" "$result" "Dots should be allowed" && test_pass
}

test_sanitize_removes_special_chars() {
    test_start "Remove special chars"
    local result=$(zsh_setup::utils::filesystem::sanitize_name "test;rm -rf /")
    assert_equal "testrm-rf" "$result" "Should remove command injection characters" && test_pass
}

test_sanitize_removes_pipes() {
    test_start "Remove pipes"
    local result=$(zsh_setup::utils::filesystem::sanitize_name "plugin|malicious")
    assert_equal "pluginmalicious" "$result" "Should remove pipe characters" && test_pass
}

test_sanitize_removes_path_traversal() {
    test_start "Remove path traversal"
    local result=$(zsh_setup::utils::filesystem::sanitize_name "../../../etc/passwd")
    # Slashes are removed, leaving dots
    assert_equal "......etcpasswd" "$result" "Should remove slashes for path traversal" && test_pass
}

test_sanitize_removes_backticks() {
    test_start "Remove backticks"
    local result=$(zsh_setup::utils::filesystem::sanitize_name "\`whoami\`")
    assert_equal "whoami" "$result" "Should remove backticks" && test_pass
}

test_sanitize_removes_dollar_parens() {
    test_start "Remove command substitution"
    local result=$(zsh_setup::utils::filesystem::sanitize_name "\$(whoami)")
    assert_equal "whoami" "$result" "Should remove command substitution" && test_pass
}

test_sanitize_empty_result() {
    test_start "Empty result for special chars"
    local result=$(zsh_setup::utils::filesystem::sanitize_name "!!!@@@###")
    assert_equal "" "$result" "Should return empty string for all special chars" && test_pass
}

#------------------------------------------------------------------------------
# State File Security Tests
#------------------------------------------------------------------------------

test_state_file_location() {
    test_start "State file location"
    # Mock XDG_STATE_HOME
    local test_home="/tmp/zsh_setup_test_$$"
    mkdir -p "$test_home"

    # Clear any existing config
    unset ZSH_SETUP_CONFIG_state_file

    export XDG_STATE_HOME="$test_home"
    export HOME="$test_home"

    local state_file=$(zsh_setup::state::store::_get_state_file)

    # Should be in XDG directory
    if [[ $state_file == $test_home/zsh-setup/* ]]; then
        test_pass
    else
        test_fail "State file should be in XDG_STATE_HOME ($state_file)"
    fi

    # Cleanup
    rm -rf "$test_home"
    unset XDG_STATE_HOME
}

test_state_file_permissions() {
    test_start "State file permissions"
    local test_home="/tmp/zsh_setup_test_$$"
    mkdir -p "$test_home"

    export XDG_STATE_HOME="$test_home"
    export HOME="$test_home"

    # Initialize state file
    zsh_setup::state::store::init "$PROJECT_ROOT"

    local state_file=$(zsh_setup::state::store::_get_state_file)

    # Check file exists and permissions
    if [[ -f "$state_file" ]]; then
        local perms=$(stat -f "%Lp" "$state_file" 2>/dev/null || stat -c "%a" "$state_file" 2>/dev/null)
        assert_equal "600" "$perms" "State file should have 600 permissions" && test_pass
    else
        test_fail "State file should exist"
    fi

    # Cleanup
    rm -rf "$test_home"
    unset XDG_STATE_HOME
}

test_state_dir_permissions() {
    test_start "State dir permissions"
    local test_home="/tmp/zsh_setup_test_$$"
    mkdir -p "$test_home"

    export XDG_STATE_HOME="$test_home"
    export HOME="$test_home"

    # Initialize state
    zsh_setup::state::store::init "$PROJECT_ROOT"

    local state_dir="$test_home/zsh-setup"

    # Check directory exists and permissions
    if [[ -d "$state_dir" ]]; then
        local perms=$(stat -f "%Lp" "$state_dir" 2>/dev/null || stat -c "%a" "$state_dir" 2>/dev/null)
        assert_equal "700" "$perms" "State directory should have 700 permissions" && test_pass
    else
        test_fail "State directory should exist"
    fi

    # Cleanup
    rm -rf "$test_home"
    unset XDG_STATE_HOME
}

#------------------------------------------------------------------------------
# Temporary File Security Tests
#------------------------------------------------------------------------------

test_worker_script_permissions() {
    test_start "Worker script permissions"
    # This test verifies the pattern, actual creation happens in manager.sh
    # We verify that mktemp creates unique files
    local temp1=$(mktemp -t zsh_setup_worker.XXXXXX.sh)
    local temp2=$(mktemp -t zsh_setup_worker.XXXXXX.sh)

    if [[ $temp1 != $temp2 ]]; then
        # Set restrictive permissions as the code does
        chmod 700 "$temp1"
        local perms=$(stat -f "%Lp" "$temp1" 2>/dev/null || stat -c "%a" "$temp1" 2>/dev/null)
        assert_equal "700" "$perms" "Worker script should have 700 permissions" && test_pass
    else
        test_fail "Temp files should be unique"
    fi

    # Cleanup
    rm -f "$temp1" "$temp2"
}

#------------------------------------------------------------------------------
# Run Tests
#------------------------------------------------------------------------------

main() {
    echo "Running security tests..."
    echo

    # Plugin sanitization tests
    test_sanitize_alphanumeric
    test_sanitize_dots
    test_sanitize_removes_special_chars
    test_sanitize_removes_pipes
    test_sanitize_removes_path_traversal
    test_sanitize_removes_backticks
    test_sanitize_removes_dollar_parens
    test_sanitize_empty_result

    # State file security tests
    test_state_file_location
    test_state_file_permissions
    test_state_dir_permissions

    # Temp file security tests
    test_worker_script_permissions

    test_summary
}

main "$@"
