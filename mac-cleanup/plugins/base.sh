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
register_plugin() {
  local name="$1"
  local category="$2"
  local function="$3"
  local requires_admin="${4:-false}"
  
  mc_register_plugin "$name" "$category" "$function" "$requires_admin"
}

# Helper function to track space saved for a plugin
track_space_saved() {
  local plugin_name="$1"
  local space_bytes=$2
  
  MC_SPACE_SAVED_BY_OPERATION["$plugin_name"]=$space_bytes
  # Also update the total space saved if it's not already being tracked
  # (some plugins use safe_clean_dir/safe_remove which already update the total)
  MC_TOTAL_SPACE_SAVED=$((MC_TOTAL_SPACE_SAVED + space_bytes))
  
  # If we're in a background process, write to space tracking file
  # This allows the parent process to read the space saved data
  if [[ -n "${MC_SPACE_TRACKING_FILE:-}" && -f "$MC_SPACE_TRACKING_FILE" ]]; then
    # Append to file: plugin_name|space_bytes
    echo "$plugin_name|$space_bytes" >> "$MC_SPACE_TRACKING_FILE" 2>/dev/null || true
  fi
}

# Helper function to get space saved for a plugin
get_space_saved() {
  local plugin_name="$1"
  echo "${MC_SPACE_SAVED_BY_OPERATION[$plugin_name]:-0}"
}
