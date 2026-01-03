#!/bin/zsh
#
# plugins/base.sh - Base plugin interface for mac-cleanup plugins
#

# Plugin interface functions that each plugin should implement:
# - plugin_name() - Returns display name
# - plugin_description() - Returns description  
# - plugin_calculate_size() - Calculates size to be cleaned
# - plugin_clean() - Performs the cleanup
# - plugin_requires_admin() - Returns true if admin needed
# - plugin_warnings() - Returns array of warnings (optional)

# Helper function to register a plugin
# Usage: register_plugin "Plugin Name" "category" "clean_function" "requires_admin" ["size_function"]
# PERF-3: Optional size_function parameter allows plugins to register their own size calculation
register_plugin() {
  local name="$1"
  local category="$2"
  local function="$3"
  local requires_admin="${4:-false}"
  local size_function="${5:-}"  # Optional size calculation function (PERF-3)
  
  mc_register_plugin "$name" "$category" "$function" "$requires_admin" "$size_function"
}

# Helper function to safely write to space tracking file with locking
_write_space_tracking_file() {
  local plugin_name="$1"
  local space_bytes=$2
  
  if [[ -z "${MC_SPACE_TRACKING_FILE:-}" || ! -f "$MC_SPACE_TRACKING_FILE" ]]; then
    return 0
  fi
  
  # Use file locking to prevent race conditions when multiple plugins write simultaneously
  local lock_file="${MC_SPACE_TRACKING_FILE}.lock"
  # Try to acquire lock (wait up to 5 seconds)
  local lock_acquired=false
  local attempts=0
  while [[ $attempts -lt 50 && "$lock_acquired" == "false" ]]; do
    if (set -C; echo $$ > "$lock_file" 2>/dev/null); then
      lock_acquired=true
      # Append to file: plugin_name|space_bytes
      echo "$plugin_name|$space_bytes" >> "$MC_SPACE_TRACKING_FILE" 2>/dev/null || true
      rm -f "$lock_file" 2>/dev/null || true
      return 0
    else
      sleep 0.1
      attempts=$((attempts + 1))
    fi
  done
  
  # If lock acquisition failed, try one more time without lock (better than losing data)
  echo "$plugin_name|$space_bytes" >> "$MC_SPACE_TRACKING_FILE" 2>/dev/null || true
  log_message "WARNING" "Space tracking file lock timeout, wrote without lock"
}

# Helper function to track space saved for a plugin
track_space_saved() {
  local plugin_name="$1"
  local space_bytes=$2
  
  MC_SPACE_SAVED_BY_OPERATION["$plugin_name"]=$space_bytes
  # Also update the total space saved if it's not already being tracked
  # (some plugins use safe_clean_dir/safe_remove which already update the total)
  MC_TOTAL_SPACE_SAVED=$((MC_TOTAL_SPACE_SAVED + space_bytes))
  
  # If we're in a background process, write to space tracking file with locking
  # This allows the parent process to read the space saved data
  _write_space_tracking_file "$plugin_name" "$space_bytes"
}

# Helper function to get space saved for a plugin
get_space_saved() {
  local plugin_name="$1"
  echo "${MC_SPACE_SAVED_BY_OPERATION[$plugin_name]:-0}"
}
