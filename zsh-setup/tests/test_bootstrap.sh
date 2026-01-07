#!/usr/bin/env bash

#==============================================================================
# test_bootstrap.sh - Bootstrap Module Tests
#
# Tests for bootstrap module loading
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

test_bootstrap_module_loading() {
    test_start "Bootstrap module loading"
    
    # Load bootstrap
    source "$ZSH_SETUP_ROOT/lib/core/bootstrap.sh" || {
        test_fail "Failed to load bootstrap"
        return 1
    }
    
    # Test module loading
    assert_success "zsh_setup::core::bootstrap::load_module core::config" \
        "Should load core::config module"
    
    assert_success "zsh_setup::core::bootstrap::load_module core::logger" \
        "Should load core::logger module"
    
    # Test that modules are marked as loaded
    assert_success "zsh_setup::core::bootstrap::is_loaded core::config" \
        "core::config should be marked as loaded"
    
    test_pass
}

test_bootstrap_duplicate_prevention() {
    test_start "Bootstrap duplicate prevention"
    
    # Load a module twice
    zsh_setup::core::bootstrap::load_module core::config
    local first_load=$?
    
    zsh_setup::core::bootstrap::load_module core::config
    local second_load=$?
    
    assert_equal "0" "$first_load" "First load should succeed"
    assert_equal "0" "$second_load" "Second load should succeed (no error on duplicate)"
    
    test_pass
}

# Run tests
test_setup
test_bootstrap_module_loading
test_bootstrap_duplicate_prevention
test_cleanup
