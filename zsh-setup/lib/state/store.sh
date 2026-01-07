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
# State Caching
#------------------------------------------------------------------------------

# Cache for parsed JSON data (in-memory) - bash 3.2 compatible
ZSH_SETUP_STATE_CACHE_JSON=""
ZSH_SETUP_STATE_CACHE_FILE=""
ZSH_SETUP_STATE_CACHE_LOADED=false

# Clear state cache
zsh_setup::state::store::_clear_cache() {
    ZSH_SETUP_STATE_CACHE_JSON=""
    ZSH_SETUP_STATE_CACHE_FILE=""
    ZSH_SETUP_STATE_CACHE_LOADED=false
}

# Load state into cache
zsh_setup::state::store::_load_cache() {
    local state_file=$(zsh_setup::state::store::_get_state_file)
    
    # Check if cache is already loaded for this file
    if [[ "$ZSH_SETUP_STATE_CACHE_LOADED" == "true" && "$ZSH_SETUP_STATE_CACHE_FILE" == "$state_file" ]]; then
        return 0
    fi
    
    # Check if file exists
    if [[ ! -f "$state_file" ]]; then
        zsh_setup::state::store::init
    fi
    
    # Load JSON into cache
    if command -v jq &>/dev/null; then
        # Use jq to parse and cache
        local json_data=$(jq -c '.' "$state_file" 2>/dev/null)
        if [[ -n "$json_data" ]]; then
            ZSH_SETUP_STATE_CACHE_JSON="$json_data"
            ZSH_SETUP_STATE_CACHE_FILE="$state_file"
            ZSH_SETUP_STATE_CACHE_LOADED=true
        fi
    elif command -v python3 &>/dev/null; then
        # Use python to parse and cache
        local json_data=$(python3 -c "import json; print(json.dumps(json.load(open('$state_file'))))" 2>/dev/null)
        if [[ -n "$json_data" ]]; then
            ZSH_SETUP_STATE_CACHE_JSON="$json_data"
            ZSH_SETUP_STATE_CACHE_FILE="$state_file"
            ZSH_SETUP_STATE_CACHE_LOADED=true
        fi
    fi
}

# Save cache to file
zsh_setup::state::store::_save_cache() {
    local state_file=$(zsh_setup::state::store::_get_state_file)
    
    if [[ -z "$ZSH_SETUP_STATE_CACHE_JSON" ]]; then
        return 1
    fi
    
    if command -v jq &>/dev/null; then
        echo "$ZSH_SETUP_STATE_CACHE_JSON" | jq '.' > "$state_file" 2>/dev/null
    elif command -v python3 &>/dev/null; then
        python3 <<PYTHON_SCRIPT
import json
import sys
try:
    data = json.loads('$ZSH_SETUP_STATE_CACHE_JSON')
    with open('$state_file', 'w') as f:
        json.dump(data, f, indent=2)
except Exception as e:
    sys.stderr.write(f"Error saving state: {e}\n")
    sys.exit(1)
PYTHON_SCRIPT
    else
        # Fallback: can't save from cache
        return 1
    fi
    
    return 0
}

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

# Read state from JSON file (with caching)
zsh_setup::state::store::read() {
    local query="$1"
    local state_file=$(zsh_setup::state::store::_get_state_file)
    
    if [[ ! -f "$state_file" ]]; then
        zsh_setup::state::store::init
    fi
    
    # Load cache if not already loaded
    zsh_setup::state::store::_load_cache
    
    # Use cached data if available
    if [[ "$ZSH_SETUP_STATE_CACHE_LOADED" == "true" && -n "$ZSH_SETUP_STATE_CACHE_JSON" ]]; then
        if command -v jq &>/dev/null; then
            echo "$ZSH_SETUP_STATE_CACHE_JSON" | jq -r "$query" 2>/dev/null || echo ""
        elif command -v python3 &>/dev/null; then
            ZSH_SETUP_STATE_FILE="$state_file" \
            ZSH_SETUP_QUERY="$query" \
            ZSH_SETUP_JSON_DATA="$ZSH_SETUP_STATE_CACHE_JSON" \
            python3 <<'PYTHON_SCRIPT'
import json
import sys
import os

json_data = os.environ.get('ZSH_SETUP_JSON_DATA', '{}')
query = os.environ.get('ZSH_SETUP_QUERY', '')

try:
    data = json.loads(json_data)
    result = data
    for key in query.strip('.').split('.'):
        if not key:
            continue
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
            # Fallback to file-based parsing
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
        return
    fi
    
    # Fallback to file-based reading
    if command -v jq &>/dev/null; then
        jq -r "$query" "$state_file" 2>/dev/null || echo ""
    elif command -v python3 &>/dev/null; then
        ZSH_SETUP_STATE_FILE="$state_file" \
        ZSH_SETUP_QUERY="$query" \
        python3 <<'PYTHON_SCRIPT'
import json
import sys
import os

state_file = os.environ.get('ZSH_SETUP_STATE_FILE')
query = os.environ.get('ZSH_SETUP_QUERY', '')

try:
    with open(state_file, 'r') as f:
        data = json.load(f)
    result = data
    for key in query.strip('.').split('.'):
        if not key:
            continue
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

# Add plugin to installed list (with cache update)
zsh_setup::state::store::add_plugin() {
    local plugin_name="$1"
    local method="${2:-unknown}"
    local version="${3:-unknown}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local state_file=$(zsh_setup::state::store::_get_state_file)
    
    # Load cache
    zsh_setup::state::store::_load_cache
    
    # Check if already added
    local current_plugins
    if [[ "$ZSH_SETUP_STATE_CACHE_LOADED" == "true" && -n "$ZSH_SETUP_STATE_CACHE_JSON" ]]; then
        if command -v jq &>/dev/null; then
            current_plugins=$(echo "$ZSH_SETUP_STATE_CACHE_JSON" | jq -r '.installed_plugins[]' 2>/dev/null | tr '\n' '|')
        else
            current_plugins=$(zsh_setup::state::store::read ".installed_plugins[]" | tr '\n' '|')
        fi
    else
        if command -v jq &>/dev/null; then
            current_plugins=$(jq -r '.installed_plugins[]' "$state_file" 2>/dev/null | tr '\n' '|')
        else
            current_plugins=$(zsh_setup::state::store::read ".installed_plugins[]" | tr '\n' '|')
        fi
    fi
    
    if echo "$current_plugins" | grep -q "|$plugin_name|" || echo "$current_plugins" | grep -q "^$plugin_name|"; then
        return 0
    fi
    
    # Update cache if loaded, otherwise update file directly
    if [[ "$ZSH_SETUP_STATE_CACHE_LOADED" == "true" && -n "$ZSH_SETUP_STATE_CACHE_JSON" ]]; then
        # Update cache
        if command -v jq &>/dev/null; then
            ZSH_SETUP_STATE_CACHE_JSON=$(echo "$ZSH_SETUP_STATE_CACHE_JSON" | \
                jq --arg plugin "$plugin_name" --arg method "$method" --arg version "$version" --arg ts "$timestamp" \
                   '.installed_plugins += [$plugin] | 
                    (.plugins[$plugin] //= {}) | 
                    .plugins[$plugin].version = $version | 
                    .plugins[$plugin].method = $method | 
                    .plugins[$plugin].last_checked = $ts |
                    .installation_order += [{"plugin": $plugin, "method": $method, "timestamp": $ts, "version": $version}]' -c)
            zsh_setup::state::store::_save_cache
        else
            # Fall through to file-based update
            ZSH_SETUP_STATE_CACHE_LOADED=false
        fi
    fi
    
    # File-based update (if cache not available or update failed)
    if [[ "$ZSH_SETUP_STATE_CACHE_LOADED" != "true" ]]; then
        if command -v jq &>/dev/null; then
            jq --arg plugin "$plugin_name" --arg method "$method" --arg version "$version" --arg ts "$timestamp" \
               '.installed_plugins += [$plugin] | 
                (.plugins[$plugin] //= {}) | 
                .plugins[$plugin].version = $version | 
                .plugins[$plugin].method = $method | 
                .plugins[$plugin].last_checked = $ts |
                .installation_order += [{"plugin": $plugin, "method": $method, "timestamp": $ts, "version": $version}]' \
               "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
        elif command -v python3 &>/dev/null; then
            ZSH_SETUP_STATE_FILE="$state_file" \
            ZSH_SETUP_PLUGIN_NAME="$plugin_name" \
            ZSH_SETUP_METHOD="$method" \
            ZSH_SETUP_VERSION="$version" \
            ZSH_SETUP_TIMESTAMP="$timestamp" \
            python3 <<'PYTHON_SCRIPT'
import json
import os
import sys

state_file = os.environ.get('ZSH_SETUP_STATE_FILE')
plugin_name = os.environ.get('ZSH_SETUP_PLUGIN_NAME')
method = os.environ.get('ZSH_SETUP_METHOD', 'unknown')
version = os.environ.get('ZSH_SETUP_VERSION', 'unknown')
timestamp = os.environ.get('ZSH_SETUP_TIMESTAMP')

try:
    with open(state_file, 'r') as f:
        data = json.load(f)
    
    if plugin_name not in data.get('installed_plugins', []):
        data.setdefault('installed_plugins', []).append(plugin_name)
    
    if 'plugins' not in data:
        data['plugins'] = {}
    if plugin_name not in data['plugins']:
        data['plugins'][plugin_name] = {}
    
    data['plugins'][plugin_name]['version'] = version
    data['plugins'][plugin_name]['method'] = method
    data['plugins'][plugin_name]['last_checked'] = timestamp
    
    if 'installation_order' not in data:
        data['installation_order'] = []
    data['installation_order'].append({
        "plugin": plugin_name,
        "method": method,
        "timestamp": timestamp,
        "version": version
    })
    
    with open(state_file, 'w') as f:
        json.dump(data, f, indent=2)
except Exception as e:
    sys.stderr.write(f"Error updating state: {e}\n")
    sys.exit(1)
PYTHON_SCRIPT
        fi
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
        ZSH_SETUP_STATE_FILE="$state_file" \
        ZSH_SETUP_PLUGIN_NAME="$plugin_name" \
        python3 <<'PYTHON_SCRIPT'
import json
import os
import sys

state_file = os.environ.get('ZSH_SETUP_STATE_FILE')
plugin_name = os.environ.get('ZSH_SETUP_PLUGIN_NAME')

try:
    with open(state_file, 'r') as f:
        data = json.load(f)
    
    if 'failed_plugins' not in data:
        data['failed_plugins'] = []
    if plugin_name not in data['failed_plugins']:
        data['failed_plugins'].append(plugin_name)
    
    with open(state_file, 'w') as f:
        json.dump(data, f, indent=2)
except Exception as e:
    sys.stderr.write(f"Error updating state: {e}\n")
    sys.exit(1)
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
        ZSH_SETUP_STATE_FILE="$state_file" \
        ZSH_SETUP_PLUGIN_NAME="$plugin_name" \
        python3 <<'PYTHON_SCRIPT'
import json
import os
import sys

state_file = os.environ.get('ZSH_SETUP_STATE_FILE')
plugin_name = os.environ.get('ZSH_SETUP_PLUGIN_NAME')

try:
    with open(state_file, 'r') as f:
        data = json.load(f)
    version = data.get('plugins', {}).get(plugin_name, {}).get('version', '')
    print(version)
except Exception:
    print('')
PYTHON_SCRIPT
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
        ZSH_SETUP_STATE_FILE="$state_file" \
        ZSH_SETUP_PLUGIN_NAME="$plugin_name" \
        ZSH_SETUP_VERSION="$version" \
        ZSH_SETUP_TIMESTAMP="$timestamp" \
        python3 <<'PYTHON_SCRIPT'
import json
import os
import sys

state_file = os.environ.get('ZSH_SETUP_STATE_FILE')
plugin_name = os.environ.get('ZSH_SETUP_PLUGIN_NAME')
version = os.environ.get('ZSH_SETUP_VERSION', 'unknown')
timestamp = os.environ.get('ZSH_SETUP_TIMESTAMP')

try:
    with open(state_file, 'r') as f:
        data = json.load(f)
    
    if 'plugins' not in data:
        data['plugins'] = {}
    if plugin_name not in data['plugins']:
        data['plugins'][plugin_name] = {}
    
    data['plugins'][plugin_name]['version'] = version
    data['plugins'][plugin_name]['last_checked'] = timestamp
    
    with open(state_file, 'w') as f:
        json.dump(data, f, indent=2)
except Exception as e:
    sys.stderr.write(f"Error updating state: {e}\n")
    sys.exit(1)
PYTHON_SCRIPT
    fi
}

# Clear state file and cache
zsh_setup::state::store::clear() {
    local state_file=$(zsh_setup::state::store::_get_state_file)
    rm -f "$state_file"
    zsh_setup::state::store::_clear_cache
}

# Batch update multiple plugins (more efficient than individual updates)
zsh_setup::state::store::batch_add_plugins() {
    local plugins=("$@")
    local state_file=$(zsh_setup::state::store::_get_state_file)
    
    # Load cache
    zsh_setup::state::store::_load_cache
    
    if command -v jq &>/dev/null; then
        # Build jq update expression for all plugins
        local jq_expr="."
        local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        
        for plugin_info in "${plugins[@]}"; do
            IFS='|' read -r plugin_name method version <<< "$plugin_info"
            version="${version:-unknown}"
            method="${method:-unknown}"
            
            jq_expr="$jq_expr | .installed_plugins += [\"$plugin_name\"] | 
                     (.plugins[\"$plugin_name\"] //= {}) | 
                     .plugins[\"$plugin_name\"].version = \"$version\" | 
                     .plugins[\"$plugin_name\"].method = \"$method\" | 
                     .plugins[\"$plugin_name\"].last_checked = \"$timestamp\" |
                     .installation_order += [{\"plugin\": \"$plugin_name\", \"method\": \"$method\", \"timestamp\": \"$timestamp\", \"version\": \"$version\"}]"
        done
        
        if [[ "$ZSH_SETUP_STATE_CACHE_LOADED" == "true" && -n "$ZSH_SETUP_STATE_CACHE_JSON" ]]; then
            ZSH_SETUP_STATE_CACHE_JSON=$(echo "$ZSH_SETUP_STATE_CACHE_JSON" | jq "$jq_expr" -c)
            zsh_setup::state::store::_save_cache
        else
            jq "$jq_expr" "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
        fi
    else
        # Fallback: add plugins one by one
        for plugin_info in "${plugins[@]}"; do
            IFS='|' read -r plugin_name method version <<< "$plugin_info"
            zsh_setup::state::store::add_plugin "$plugin_name" "$method" "$version"
        done
    fi
}

