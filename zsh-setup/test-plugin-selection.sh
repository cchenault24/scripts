#!/usr/bin/env bash

#==============================================================================
# test-plugin-selection.sh - Test Plugin Selection Menu
#==============================================================================

cd "$(dirname "${BASH_SOURCE[0]}")"

export ZSH_SETUP_ROOT="$(pwd)"

echo "🔍 Testing Plugin Selection Menu"
echo "================================"
echo

# Load bootstrap
source lib/core/bootstrap.sh
zsh_setup::core::bootstrap::init

# Load required modules
zsh_setup::core::bootstrap::load_module plugins::registry
zsh_setup::core::bootstrap::load_module plugins::manager

# Load registry
zsh_setup::plugins::registry::load

echo "Plugins loaded from plugins.conf"
echo

# Check if fzf is available
if command -v fzf &>/dev/null; then
    echo "✅ fzf is installed: $(fzf --version)"
else
    echo "⚠️  fzf not found - will use basic menu"
fi
echo

# Test the selection menu
echo "Testing selection menu (press Ctrl+C to cancel):"
echo "─────────────────────────────────────────────────"
echo

result=$(zsh_setup::plugins::manager::_show_selection_menu)

echo
echo "─────────────────────────────────────────────────"
echo "Selection result:"
echo "$result"
echo
echo "Done!"
