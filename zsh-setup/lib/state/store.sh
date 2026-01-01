#!/usr/bin/env bash

#==============================================================================
# store.sh - State Management Interface
#
# Provides abstracted state management with JSON backend
#==============================================================================

# Load dependencies
if [[ -n "${ZSH_SETUP_ROOT:-}" ]]; then
    source "$ZSH_SETUP_ROOT/lib/core/config.sh"
    source "$ZSH_SETUP_ROOT/lib/core/logger.sh"
fi

#------------------------------------------------------------------------------
# State File Management
#------------------------------------------------------------------------------

# Get state file path
zsh_setup::state::store::_get_state_file() {
    zsh_setup::core::config::get state_file "/tmp/zsh_setup_state.json"
}

# Initialize state file
zsh_setup::state::store::init() {
    local script_dir="${1:-}"
    local state_file=$(zsh_setup::state::store::_get_state_file)
    mkdir -p "$(dirname "$state_file")"
    
    cat >"$state_file" <<EOF
{
  "installed_plugins": [],
  "failed_plugins": [],
  "installation_order": [],
  "plugins": {},
  "metadata": {
    "script_dir": "$script_dir",
    "start_time": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "version": "2.0.0"
  }
}
EOF
    
    zsh_setup::core::logger::debug "State file initialized at $state_file"
}

#------------------------------------------------------------------------------
# State Reading
#------------------------------------------------------------------------------

# Read state from JSON file
zsh_setup::state::store::read() {
    local query="$1"
    local state_file=$(zsh_setup::state::store::_get_state_file)
    
    if [[ ! -f "$state_file" ]]; then
        zsh_setup::state::store::init
    fi
    
    # Use jq if available
    if command -v jq &>/dev/null; then
        jq -r "$query" "$state_file" 2>/dev/null || echo ""
    elif command -v python3 &>/dev/null; then
        python3 <<PYTHON_SCRIPT
import json
import sys
try:
    with open('$state_file', 'r') as f:
        data = json.load(f)
    result = data
    for key in '$query'.strip('.').split('.'):
        if key.endswith('[]'):
            key = key[:-2]
            if isinstance(result, dict) and key in result:
                for item in result[key]:
                    print(item)
        elif isinstance(result, dict) and key in result:
            result = result[key]
        else:
            print('')
            sys.exit(0)
    if not isinstance(result, list):
        print(result if result else '')
except Exception:
    print('')
PYTHON_SCRIPT
    else
        # Fallback: basic grep/sed parsing
        case "$query" in
            ".installed_plugins[]")
                grep -o '"installed_plugins":\s*\[[^]]*\]' "$state_file" 2>/dev/null | \
                    grep -o '"[^"]*"' | tr -d '"' | grep -v -E '^(installed_plugins|\[|\])$' || true
                ;;
            ".failed_plugins[]")
                grep -o '"failed_plugins":\s*\[[^]]*\]' "$state_file" 2>/dev/null | \
                    grep -o '"[^"]*"' | tr -d '"' | grep -v -E '^(failed_plugins|\[|\])$' || true
                ;;
            *)
                echo ""
                ;;
        esac
    fi
}

#------------------------------------------------------------------------------
# State Writing
#------------------------------------------------------------------------------

# Add plugin to installed list
zsh_setup::state::store::add_plugin() {
    local plugin_name="$1"
    local method="${2:-unknown}"
    local version="${3:-unknown}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local state_file=$(zsh_setup::state::store::_get_state_file)
    
    # Check if already added
    local current_plugins
    if command -v jq &>/dev/null; then
        current_plugins=$(jq -r '.installed_plugins[]' "$state_file" 2>/dev/null | tr '\n' '|')
    else
        current_plugins=$(zsh_setup::state::store::read ".installed_plugins[]" | tr '\n' '|')
    fi
    
    if echo "$current_plugins" | grep -q "|$plugin_name|" || echo "$current_plugins" | grep -q "^$plugin_name|"; then
        return 0
    fi
    
    # Add to installed plugins
    if command -v jq &>/dev/null; then
        jq --arg plugin "$plugin_name" '.installed_plugins += [$plugin]' "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
    elif command -v python3 &>/dev/null; then
        python3 <<PYTHON_SCRIPT
import json
with open('$state_file', 'r') as f:
    data = json.load(f)
if '$plugin_name' not in data['installed_plugins']:
    data['installed_plugins'].append('$plugin_name')
if 'plugins' not in data:
    data['plugins'] = {}
if '$plugin_name' not in data['plugins']:
    data['plugins']['$plugin_name'] = {}
data['plugins']['$plugin_name']['version'] = '$version'
data['plugins']['$plugin_name']['method'] = '$method'
data['plugins']['$plugin_name']['last_checked'] = '$timestamp'
data['installation_order'].append({
    "plugin": '$plugin_name',
    "method": '$method',
    "timestamp": '$timestamp',
    "version": '$version'
})
with open('$state_file', 'w') as f:
    json.dump(data, f, indent=2)
PYTHON_SCRIPT
    fi
}

# Add plugin to failed list
zsh_setup::state::store::add_failed_plugin() {
    local plugin_name="$1"
    local method="${2:-unknown}"
    local error="${3:-}"
    local state_file=$(zsh_setup::state::store::_get_state_file)
    
    if command -v jq &>/dev/null; then
        jq --arg plugin "$plugin_name" '.failed_plugins += [$plugin]' "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
    elif command -v python3 &>/dev/null; then
        python3 <<PYTHON_SCRIPT
import json
with open('$state_file', 'r') as f:
    data = json.load(f)
if '$plugin_name' not in data['failed_plugins']:
    data['failed_plugins'].append('$plugin_name')
with open('$state_file', 'w') as f:
    json.dump(data, f, indent=2)
PYTHON_SCRIPT
    fi
}

# Get installed plugins
zsh_setup::state::store::get_installed_plugins() {
    zsh_setup::state::store::read ".installed_plugins[]"
}

# Get failed plugins
zsh_setup::state::store::get_failed_plugins() {
    zsh_setup::state::store::read ".failed_plugins[]"
}

# Get plugin version
zsh_setup::state::store::get_plugin_version() {
    local plugin_name="$1"
    local state_file=$(zsh_setup::state::store::_get_state_file)
    
    if command -v jq &>/dev/null; then
        jq -r ".plugins[\"$plugin_name\"].version // empty" "$state_file" 2>/dev/null
    elif command -v python3 &>/dev/null; then
        python3 -c "import json; data = json.load(open('$state_file')); print(data.get('plugins', {}).get('$plugin_name', {}).get('version', ''))" 2>/dev/null
    fi
}

# Update plugin version
zsh_setup::state::store::update_plugin_version() {
    local plugin_name="$1"
    local version="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local state_file=$(zsh_setup::state::store::_get_state_file)
    
    if command -v jq &>/dev/null; then
        jq --arg plugin "$plugin_name" --arg version "$version" --arg ts "$timestamp" \
           '.plugins[$plugin].version = $version | .plugins[$plugin].last_checked = $ts' \
           "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
    elif command -v python3 &>/dev/null; then
        python3 <<PYTHON_SCRIPT
import json
with open('$state_file', 'r') as f:
    data = json.load(f)
if 'plugins' not in data:
    data['plugins'] = {}
if '$plugin_name' not in data['plugins']:
    data['plugins']['$plugin_name'] = {}
data['plugins']['$plugin_name']['version'] = '$version'
data['plugins']['$plugin_name']['last_checked'] = '$timestamp'
with open('$state_file', 'w') as f:
    json.dump(data, f, indent=2)
PYTHON_SCRIPT
    fi
}

# Clear state file
zsh_setup::state::store::clear() {
    local state_file=$(zsh_setup::state::store::_get_state_file)
    rm -f "$state_file"
}

# Backward compatibility functions
init_state() {
    zsh_setup::state::store::init "$@"
}

get_installed_plugins() {
    zsh_setup::state::store::get_installed_plugins
}

get_failed_plugins() {
    zsh_setup::state::store::get_failed_plugins
}

add_installed_plugin() {
    zsh_setup::state::store::add_plugin "$@"
}

add_failed_plugin() {
    zsh_setup::state::store::add_failed_plugin "$@"
}

get_plugin_version_from_state() {
    zsh_setup::state::store::get_plugin_version "$@"
}

update_plugin_version() {
    zsh_setup::state::store::update_plugin_version "$@"
}

clear_state() {
    zsh_setup::state::store::clear
}

get_state_file() {
    zsh_setup::state::store::_get_state_file
}
