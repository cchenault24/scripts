#!/usr/bin/env bash

#==============================================================================
# state_manager.sh - JSON-based State Management for Zsh Setup
#
# Provides functions for managing installation state across scripts using JSON
#==============================================================================

# State file location
STATE_FILE="${ZSH_SETUP_STATE_FILE:-/tmp/zsh_setup_state.json}"

#------------------------------------------------------------------------------
# State Management Functions
#------------------------------------------------------------------------------

# Initialize state file
init_state() {
    local script_dir="${1:-}"
    mkdir -p "$(dirname "$STATE_FILE")"
    
    cat >"$STATE_FILE" <<EOF
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
}

# Read state from JSON file
read_state() {
    if [[ ! -f "$STATE_FILE" ]]; then
        init_state "${SCRIPT_DIR:-}"
    fi
    
    # Use jq if available, otherwise use python
    if command -v jq &>/dev/null; then
        jq -r "$1" "$STATE_FILE" 2>/dev/null || echo ""
    elif command -v python3 &>/dev/null; then
        python3 -c "import json, sys; 
try:
    with open('$STATE_FILE', 'r') as f:
        data = json.load(f)
    result = data
    for key in '$1'.strip('.').split('.'):
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
" 2>/dev/null || echo ""
    else
        # Fallback: basic grep/sed parsing (limited)
        case "$1" in
            ".installed_plugins[]")
                grep -o '"installed_plugins":\s*\[[^]]*\]' "$STATE_FILE" 2>/dev/null | \
                    grep -o '"[^"]*"' | tr -d '"' | grep -v -E '^(installed_plugins|\[|\])$' || true
                ;;
            ".failed_plugins[]")
                grep -o '"failed_plugins":\s*\[[^]]*\]' "$STATE_FILE" 2>/dev/null | \
                    grep -o '"[^"]*"' | tr -d '"' | grep -v -E '^(failed_plugins|\[|\])$' || true
                ;;
            *)
                echo ""
                ;;
        esac
    fi
}

# Write state to JSON file
write_state() {
    local key="$1"
    local value="$2"
    
    if command -v jq &>/dev/null; then
        # Use jq for safe JSON manipulation
        local temp_file=$(mktemp)
        jq "$key = $value" "$STATE_FILE" > "$temp_file" && mv "$temp_file" "$STATE_FILE"
    elif command -v python3 &>/dev/null; then
        # Use python for JSON manipulation
        python3 <<PYTHON_SCRIPT
import json
import sys

try:
    with open('$STATE_FILE', 'r') as f:
        data = json.load(f)
    
    # Parse the key path (e.g., ".installed_plugins" -> ["installed_plugins"])
    key_path = '$key'.strip('.').split('.')
    
    # Navigate to the target and set value
    target = data
    for k in key_path[:-1]:
        if k not in target:
            target[k] = {}
        target = target[k]
    
    # Parse value as JSON
    import ast
    try:
        parsed_value = json.loads('$value')
    except:
        # If not valid JSON, treat as string
        parsed_value = '$value'
    
    target[key_path[-1]] = parsed_value
    
    with open('$STATE_FILE', 'w') as f:
        json.dump(data, f, indent=2)
except Exception as e:
    print(f"Error updating state: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    else
        # Fallback: basic sed-based manipulation (very limited)
        echo "Warning: jq or python3 not available, state updates may be limited" >&2
    fi
}

# Add plugin to installed list with version tracking
add_installed_plugin() {
    local plugin_name="$1"
    local method="${2:-unknown}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local version="${3:-unknown}"
    
    # Read current installed plugins
    local current_plugins
    if command -v jq &>/dev/null; then
        current_plugins=$(jq -r '.installed_plugins[]' "$STATE_FILE" 2>/dev/null | tr '\n' '|')
    else
        current_plugins=$(read_state ".installed_plugins[]" | tr '\n' '|')
    fi
    
    # Check if already added
    if echo "$current_plugins" | grep -q "|$plugin_name|" || echo "$current_plugins" | grep -q "^$plugin_name|"; then
        return 0
    fi
    
    # Add to installed plugins
    if command -v jq &>/dev/null; then
        jq --arg plugin "$plugin_name" '.installed_plugins += [$plugin]' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    elif command -v python3 &>/dev/null; then
        python3 <<PYTHON_SCRIPT
import json
with open('$STATE_FILE', 'r') as f:
    data = json.load(f)
if '$plugin_name' not in data['installed_plugins']:
    data['installed_plugins'].append('$plugin_name')
with open('$STATE_FILE', 'w') as f:
    json.dump(data, f, indent=2)
PYTHON_SCRIPT
    fi
    
    # Add to installation order
    if command -v jq &>/dev/null; then
        jq --arg plugin "$plugin_name" --arg method "$method" --arg ts "$timestamp" --arg version "$version" \
           '.installation_order += [{"plugin": $plugin, "method": $method, "timestamp": $ts, "version": $version}]' \
           "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    elif command -v python3 &>/dev/null; then
        python3 <<PYTHON_SCRIPT
import json
from datetime import datetime
with open('$STATE_FILE', 'r') as f:
    data = json.load(f)
data['installation_order'].append({
    "plugin": '$plugin_name',
    "method": '$method',
    "timestamp": '$timestamp',
    "version": '$version'
})
# Update plugin version tracking
if 'plugins' not in data:
    data['plugins'] = {}
if '$plugin_name' not in data['plugins']:
    data['plugins']['$plugin_name'] = {}
data['plugins']['$plugin_name']['version'] = '$version'
data['plugins']['$plugin_name']['last_checked'] = '$timestamp'
with open('$STATE_FILE', 'w') as f:
    json.dump(data, f, indent=2)
PYTHON_SCRIPT
    fi
}

# Update plugin version
update_plugin_version() {
    local plugin_name="$1"
    local version="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    if command -v jq &>/dev/null; then
        jq --arg plugin "$plugin_name" --arg version "$version" --arg ts "$timestamp" \
           '.plugins[$plugin].version = $version | .plugins[$plugin].last_checked = $ts' \
           "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    elif command -v python3 &>/dev/null; then
        python3 <<PYTHON_SCRIPT
import json
with open('$STATE_FILE', 'r') as f:
    data = json.load(f)
if 'plugins' not in data:
    data['plugins'] = {}
if '$plugin_name' not in data['plugins']:
    data['plugins']['$plugin_name'] = {}
data['plugins']['$plugin_name']['version'] = '$version'
data['plugins']['$plugin_name']['last_checked'] = '$timestamp'
with open('$STATE_FILE', 'w') as f:
    json.dump(data, f, indent=2)
PYTHON_SCRIPT
    fi
}

# Get plugin version from state
get_plugin_version_from_state() {
    local plugin_name="$1"
    
    if command -v jq &>/dev/null; then
        jq -r ".plugins[\"$plugin_name\"].version // empty" "$STATE_FILE" 2>/dev/null
    elif command -v python3 &>/dev/null; then
        python3 -c "import json; data = json.load(open('$STATE_FILE')); print(data.get('plugins', {}).get('$plugin_name', {}).get('version', ''))" 2>/dev/null
    fi
}

# Add plugin to failed list
add_failed_plugin() {
    local plugin_name="$1"
    local method="${2:-unknown}"
    local error="${3:-}"
    
    if command -v jq &>/dev/null; then
        jq --arg plugin "$plugin_name" '.failed_plugins += [$plugin]' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    elif command -v python3 &>/dev/null; then
        python3 <<PYTHON_SCRIPT
import json
with open('$STATE_FILE', 'r') as f:
    data = json.load(f)
if '$plugin_name' not in data['failed_plugins']:
    data['failed_plugins'].append('$plugin_name')
with open('$STATE_FILE', 'w') as f:
    json.dump(data, f, indent=2)
PYTHON_SCRIPT
    fi
}

# Get installed plugins as array
get_installed_plugins() {
    read_state ".installed_plugins[]"
}

# Get failed plugins as array
get_failed_plugins() {
    read_state ".failed_plugins[]"
}

# Export installed plugins to environment variable (for backward compatibility)
export_installed_plugins() {
    local plugins=()
    while IFS= read -r plugin; do
        [[ -n "$plugin" ]] && plugins+=("$plugin")
    done < <(get_installed_plugins)
    
    # Export as array for scripts that still use the old method
    if [[ ${#plugins[@]} -gt 0 ]]; then
        printf '%s\n' "${plugins[@]}"
    fi
}

# Clear state file
clear_state() {
    rm -f "$STATE_FILE"
}

# Get state file path
get_state_file() {
    echo "$STATE_FILE"
}
