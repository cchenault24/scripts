#!/bin/zsh
#
# plugins/base.sh - Base plugin interface for mac-cleanup plugins
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

#==============================================================================
# Plugin API Documentation
#==============================================================================
#
# Plugin Registration:
#   register_plugin <name> <category> <clean_function> <requires_admin> [size_function] [version] [dependencies]
#
# Parameters:
#   - name: Display name of the plugin (string)
#   - category: Category name (e.g., "browsers", "system", "package-managers")
#   - clean_function: Function name that performs the cleanup (must exist)
#   - requires_admin: "true" or "false" - whether plugin needs admin privileges
#   - size_function: (optional) Function name that calculates size to be cleaned
#   - version: (optional) Plugin version string (e.g., "1.0.0")
#   - dependencies: (optional) Space-separated list of plugin names that must run first
#
# Plugin Function Requirements:
#   - clean_function: Must exist and be callable. Should handle errors gracefully.
#   - size_function: (optional) Should return size in bytes as a number
#
# Plugin Categories:
#   Plugins can define custom categories, but standard categories are:
#   - browsers: Browser cache cleanup
#   - system: System-level cleanup (may require admin)
#   - package-managers: Package manager cache cleanup
#   - development: Development tool cleanup
#   - maintenance: General maintenance operations
#
# Example:
#   register_plugin "Chrome Cache" "browsers" "clean_chrome_cache" "false" "" "1.0.0" ""
#
#==============================================================================

# SEC-10: Helper function to register a plugin with input validation
# Usage: register_plugin "Plugin Name" "category" "clean_function" "requires_admin" ["size_function"] ["version"] ["dependencies"]
# PERF-3: Optional size_function parameter allows plugins to register their own size calculation
# QUAL-12: Optional version parameter for plugin versioning
# QUAL-9: Optional dependencies parameter for plugin execution order
register_plugin() {
  local name="$1"
  local category="$2"
  local function="$3"
  local requires_admin="${4:-false}"
  local size_function="${5:-}"  # Optional size calculation function (PERF-3)
  local version="${6:-}"  # Optional version string (QUAL-12)
  local dependencies="${7:-}"  # Optional space-separated dependencies (QUAL-9)

  # SEC-10: All validation happens in mc_register_plugin
  mc_register_plugin "$name" "$category" "$function" "$requires_admin" "$size_function" "$version" "$dependencies"
}

# Helper function to safely write to space tracking file with locking (SEC-4)
# SEC-4: Uses proper file locking (lockf or atomic mkdir) to prevent TOCTOU race conditions
_write_space_tracking_file() {
  local plugin_name="$1"
  local space_bytes=$2

  if [[ -z "${MC_SPACE_TRACKING_FILE:-}" || ! -f "$MC_SPACE_TRACKING_FILE" ]]; then
    return 0
  fi

  # SEC-4: Use proper file locking to prevent race conditions
  local lock_file="${MC_SPACE_TRACKING_FILE}.lock"
  local lock_dir="${MC_SPACE_TRACKING_FILE}.lock.d"
  local max_attempts=${MC_LOCK_TIMEOUT_ATTEMPTS:-50}
  local timeout=5

  # Clean up stale locks (older than 30 seconds)
  if [[ -f "$lock_file" ]]; then
    local lock_age=$(($(/bin/date +%s 2>/dev/null || echo 0) - $(stat -f %m "$lock_file" 2>/dev/null || echo 0)))
    if [[ $lock_age -gt 30 ]]; then
      rm -f "$lock_file" 2>/dev/null || true
    fi
  fi
  if [[ -d "$lock_dir" ]]; then
    local lock_age=$(($(/bin/date +%s 2>/dev/null || echo 0) - $(stat -f %m "$lock_dir" 2>/dev/null || echo 0)))
    if [[ $lock_age -gt 30 ]]; then
      rmdir "$lock_dir" 2>/dev/null || true
    fi
  fi

  # Try lockf first (proper file locking, race-condition-free)
  if command -v lockf &>/dev/null; then
    # SEC-4: lockf provides proper advisory locking without TOCTOU vulnerability
    touch "$lock_file" 2>/dev/null || return 1

    # Use lockf to append atomically
    if lockf -t "$timeout" -k "$lock_file" sh -c "echo '$plugin_name|$space_bytes' >> '$MC_SPACE_TRACKING_FILE' 2>/dev/null"; then
      return 0
    else
      log_message "ERROR" "Failed to acquire lock or write space tracking file"
      return 1
    fi
  fi

  # Fallback: Use atomic mkdir
  local attempts=0
  while [[ $attempts -lt $max_attempts ]]; do
    # SEC-4: mkdir is atomic - only one process can successfully create
    if mkdir "$lock_dir" 2>/dev/null; then
      # Successfully acquired lock
      echo "$plugin_name|$space_bytes" >> "$MC_SPACE_TRACKING_FILE" 2>/dev/null || true
      rmdir "$lock_dir" 2>/dev/null || true
      return 0
    fi

    # Lock exists - wait and retry
    sleep 0.1
    attempts=$((attempts + 1))
  done

  # SEC-4: If lock acquisition failed, log error and fail
  # We no longer write without lock to prevent race conditions
  log_message "ERROR" "Failed to acquire lock after ${attempts} attempts, aborting write"
  return 1
}

# Helper function to track space saved for a plugin
# Usage: track_space_saved <plugin_name> <space_bytes> [skip_total]
#   - plugin_name: Name of the plugin
#   - space_bytes: Space freed in bytes
#   - skip_total: (optional) If "true", don't update MC_TOTAL_SPACE_SAVED (use when safe_clean_dir/safe_remove already updated it)
track_space_saved() {
  local plugin_name="$1"
  local space_bytes=$2
  local skip_total="${3:-false}"
  
  MC_SPACE_SAVED_BY_OPERATION["$plugin_name"]=$space_bytes
  
  # Only update the total space saved if not skipped
  # (safe_clean_dir/safe_remove already update MC_TOTAL_SPACE_SAVED, so we skip to avoid double-counting)
  if [[ "$skip_total" != "true" ]]; then
    MC_TOTAL_SPACE_SAVED=$((MC_TOTAL_SPACE_SAVED + space_bytes))
  fi
  
  # If we're in a background process, write to space tracking file with locking
  # This allows the parent process to read the space saved data
  _write_space_tracking_file "$plugin_name" "$space_bytes"
}

# Helper function to get space saved for a plugin
get_space_saved() {
  local plugin_name="$1"
  echo "${MC_SPACE_SAVED_BY_OPERATION[$plugin_name]:-0}"
}
