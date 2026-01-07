#!/usr/bin/env bash

#==============================================================================
# test_install_workflow.sh - Installation Workflow Integration Test
#
# End-to-end test for installation workflow
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

test_install_workflow() {
    test_start "Installation workflow (dry-run)"
    
    # Run install in dry-run mode
    local output=$("$ZSH_SETUP_ROOT/bin/zsh-setup" install --dry-run --skip-ohmyzsh --skip-plugins 2>&1)
    local exit_code=$?
    
    # Check that dry-run completed without errors
    assert_equal "0" "$exit_code" "Dry-run should complete successfully"
    assert_contains "$output" "DRY-RUN" "Should indicate dry-run mode"
    
    test_pass
}

# Run tests
test_setup
test_install_workflow
test_cleanup
