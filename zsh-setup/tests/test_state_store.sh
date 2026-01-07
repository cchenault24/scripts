#!/usr/bin/env bash

#==============================================================================
# test_state_store.sh - State Store Tests
#
# Tests for state management
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

test_state_store_init() {
    test_start "State store initialization"
    
    # Load state store
    source "$ZSH_SETUP_ROOT/lib/core/bootstrap.sh"
    zsh_setup::core::bootstrap::init
    zsh_setup::core::bootstrap::load_module core::state
    
    # Initialize state
    zsh_setup::state::store::init "$TEST_TMPDIR"
    
    # Check state file exists
    local state_file=$(zsh_setup::state::store::_get_state_file)
    assert_file_exists "$state_file" "State file should be created"
    
    test_pass
}

test_state_store_add_plugin() {
    test_start "State store add plugin"
    
    # Initialize state
    zsh_setup::state::store::init "$TEST_TMPDIR"
    
    # Add a plugin
    zsh_setup::state::store::add_plugin "test-plugin" "git" "abc123"
    
    # Check plugin is in installed list
    local installed=$(zsh_setup::state::store::get_installed_plugins | grep -c "test-plugin" || echo "0")
    assert_equal "1" "$installed" "Plugin should be in installed list"
    
    test_pass
}

test_state_store_get_plugin_version() {
    test_start "State store get plugin version"
    
    # Initialize and add plugin
    zsh_setup::state::store::init "$TEST_TMPDIR"
    zsh_setup::state::store::add_plugin "test-plugin" "git" "abc123"
    
    # Get version
    local version=$(zsh_setup::state::store::get_plugin_version "test-plugin")
    assert_contains "$version" "abc123" "Version should be stored correctly"
    
    test_pass
}

# Run tests
test_setup
test_state_store_init
test_state_store_add_plugin
test_state_store_get_plugin_version
test_cleanup
