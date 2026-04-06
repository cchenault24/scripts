#!/bin/zsh
#
# lib/validation.sh - Input validation functions for mac-cleanup
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Validate that a path exists
mc_validate_path_exists() {
  local path="$1"
  local description="${2:-Path}"
  
  if [[ -z "$path" ]]; then
    type print_error &>/dev/null && print_error "${description} is empty"
    type log_message &>/dev/null && log_message "$MC_LOG_LEVEL_ERROR" "Validation failed: ${description} is empty"
    return 1
  fi
  
  if [[ ! -e "$path" ]]; then
    type print_error &>/dev/null && print_error "${description} does not exist: $path"
    type log_message &>/dev/null && log_message "$MC_LOG_LEVEL_ERROR" "Validation failed: ${description} does not exist: $path"
    return 1
  fi
  
  return 0
}

# Validate that a path is a directory
mc_validate_directory() {
  local path="$1"
  local description="${2:-Directory}"
  
  if ! mc_validate_path_exists "$path" "$description"; then
    return 1
  fi
  
  if [[ ! -d "$path" ]]; then
    type print_error &>/dev/null && print_error "${description} is not a directory: $path"
    type log_message &>/dev/null && log_message "$MC_LOG_LEVEL_ERROR" "Validation failed: ${description} is not a directory: $path"
    return 1
  fi
  
  return 0
}

# Validate that a path is a file
mc_validate_file() {
  local path="$1"
  local description="${2:-File}"
  
  if ! mc_validate_path_exists "$path" "$description"; then
    return 1
  fi
  
  if [[ ! -f "$path" ]]; then
    type print_error &>/dev/null && print_error "${description} is not a file: $path"
    type log_message &>/dev/null && log_message "$MC_LOG_LEVEL_ERROR" "Validation failed: ${description} is not a file: $path"
    return 1
  fi
  
  return 0
}

# Validate that a path is writable
mc_validate_writable() {
  local path="$1"
  local description="${2:-Path}"
  
  if [[ ! -w "$path" ]]; then
    type print_error &>/dev/null && print_error "${description} is not writable: $path"
    type log_message &>/dev/null && log_message "$MC_LOG_LEVEL_ERROR" "Validation failed: ${description} is not writable: $path"
    return 1
  fi
  
  return 0
}

# Validate that a numeric value is positive
mc_validate_positive_number() {
  local value="$1"
  local description="${2:-Value}"
  
  if [[ -z "$value" ]]; then
    type print_error &>/dev/null && print_error "${description} is empty"
    type log_message &>/dev/null && log_message "$MC_LOG_LEVEL_ERROR" "Validation failed: ${description} is empty"
    return 1
  fi
  
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    type print_error &>/dev/null && print_error "${description} is not a valid positive number: $value"
    type log_message &>/dev/null && log_message "$MC_LOG_LEVEL_ERROR" "Validation failed: ${description} is not a valid number: $value"
    return 1
  fi
  
  return 0
}

# Validate plugin function exists
mc_validate_plugin_function() {
  local function_name="$1"
  local plugin_name="${2:-Unknown}"
  
  if [[ -z "$function_name" ]]; then
    type print_error &>/dev/null && print_error "Plugin function name is empty for plugin: $plugin_name"
    type log_message &>/dev/null && log_message "$MC_LOG_LEVEL_ERROR" "Validation failed: Plugin function name is empty for: $plugin_name"
    return 1
  fi
  
  if ! type "$function_name" &>/dev/null; then
    type print_error &>/dev/null && print_error "Plugin function not found: $function_name (plugin: $plugin_name)"
    type log_message &>/dev/null && log_message "$MC_LOG_LEVEL_ERROR" "Validation failed: Plugin function not found: $function_name (plugin: $plugin_name)"
    return 1
  fi
  
  return 0
}

# Validate that a directory is not empty (has content)
mc_validate_directory_has_content() {
  local path="$1"
  local description="${2:-Directory}"

  if ! mc_validate_directory "$path" "$description"; then
    return 1
  fi

  local item_count=$(find "$path" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l 2>/dev/null | tr -d ' ' || echo "0")
  if [[ $item_count -eq 0 ]]; then
    type print_warning &>/dev/null && print_warning "${description} is empty: $path"
    return 1
  fi

  return 0
}

# SEC-7: Validate and canonicalize path to prevent directory traversal attacks
# Usage: validate_and_canonicalize_path "path" ["operation"]
# Returns: Canonicalized absolute path if valid, empty string and error code if invalid
# operation: "cleanup" (default) or "backup" - determines allowed directories
# Enhanced with whitelist/blacklist approach for maximum security
validate_and_canonicalize_path() {
  local path="$1"
  local operation="${2:-cleanup}"

  # Validate input
  if [[ -z "$path" ]]; then
    type type print_error &>/dev/null && print_error &>/dev/null && type print_error &>/dev/null && print_error "Path is empty" || echo "ERROR: Path is empty" >&2
    type type log_message &>/dev/null && log_message &>/dev/null && type log_message &>/dev/null && log_message "ERROR" "Path validation failed: empty path"
    return 1
  fi

  # Convert relative path to absolute path first
  local abs_path="$path"
  if [[ "$path" != /* ]]; then
    abs_path="$(pwd)/$path"
  fi

  # Canonicalize the path to resolve symlinks and .. components
  local canonical_path=""

  # Use Python's realpath for reliable canonicalization (handles non-existent paths)
  # Escape single quotes in path for Python
  local escaped_path="${abs_path//\'/\\\'}"
  if command -v python3 &>/dev/null; then
    canonical_path=$(python3 -c "import os.path; print(os.path.normpath(os.path.abspath('$escaped_path')))" 2>/dev/null)
  elif command -v python &>/dev/null; then
    canonical_path=$(python -c "import os.path; print os.path.normpath(os.path.abspath('$escaped_path'))" 2>/dev/null)
  else
    # Fallback: manual resolution (less reliable but works)
    # Use full paths for dirname and basename to ensure they're found
    local dirname_cmd="/usr/bin/dirname"
    local basename_cmd="/usr/bin/basename"

    # Resolve to absolute canonical path (removes .., symlinks)
    if [[ -e "$abs_path" ]]; then
      # Path exists - resolve it fully
      canonical_path="$(cd "$($dirname_cmd "$abs_path")" 2>/dev/null && pwd -P 2>/dev/null)/$($basename_cmd "$abs_path")"
    else
      # Path doesn't exist yet - resolve parent recursively
      local parent="$abs_path"
      local components=()
      local iter_count=0
      local max_iterations=100

      # Walk up the directory tree until we find an existing directory
      while [[ ! -d "$parent" && "$parent" != "/" && "$parent" != "." && $iter_count -lt $max_iterations ]]; do
        components=("$($basename_cmd "$parent")" "${components[@]}")
        parent="$($dirname_cmd "$parent")"
        iter_count=$((iter_count + 1))
      done

      # If we didn't find an existing parent after max iterations, fail
      if [[ ! -d "$parent" || $iter_count -ge $max_iterations ]]; then
        type type print_error &>/dev/null && print_error &>/dev/null && type print_error &>/dev/null && print_error "No existing parent directory found for: $path" || echo "ERROR: No existing parent directory found for: $path" >&2
        type type log_message &>/dev/null && log_message &>/dev/null && type log_message &>/dev/null && log_message "ERROR" "Path validation failed: no existing parent directory for: $path"
        return 1
      fi

      # Canonicalize the existing parent
      local canonical_parent="$(cd "$parent" 2>/dev/null && pwd -P 2>/dev/null)"
      if [[ -z "$canonical_parent" ]]; then
        type type print_error &>/dev/null && print_error &>/dev/null && type print_error &>/dev/null && print_error "Failed to canonicalize parent: $parent" || echo "ERROR: Failed to canonicalize parent: $parent" >&2
        type type log_message &>/dev/null && log_message &>/dev/null && type log_message &>/dev/null && log_message "ERROR" "Path canonicalization failed for parent: $parent"
        return 1
      fi

      # Rebuild the full path
      canonical_path="$canonical_parent"
      for component in "${components[@]}"; do
        canonical_path="$canonical_path/$component"
      done
    fi
  fi

  # Verify canonicalization succeeded
  if [[ -z "$canonical_path" ]]; then
    type print_error &>/dev/null && print_error "Failed to canonicalize path: $path"
    type log_message &>/dev/null && log_message "ERROR" "Path canonicalization failed: $path"
    return 1
  fi

  # WHITELIST CHECK - ONLY allow safe directories
  local whitelist_passed=false
  case "$canonical_path" in
    "$HOME"/Library/Caches/*)
      whitelist_passed=true
      ;;
    "$HOME"/Library/Logs/*)
      whitelist_passed=true
      ;;
    "$HOME"/.cache/*)
      whitelist_passed=true
      ;;
    /Library/Caches/*)
      # System cache (requires admin)
      whitelist_passed=true
      ;;
    /tmp/*|/private/tmp/*)
      # Temp files (/tmp is often a symlink to /private/tmp on macOS)
      whitelist_passed=true
      ;;
    "$HOME"/Downloads/*)
      # Downloads
      whitelist_passed=true
      ;;
    "$HOME"/.Trash/*)
      # User trash
      whitelist_passed=true
      ;;
    "$HOME"/.mac-cleanup-backups/*)
      # Backup directory
      whitelist_passed=true
      ;;
    /tmp/mac-cleanup-backups/*)
      # Fallback backup directory
      whitelist_passed=true
      ;;
    "$HOME"/Library/Application\ Support/*/Cache/*)
      # Application caches within Application Support
      whitelist_passed=true
      ;;
    *)
      # Not in whitelist
      whitelist_passed=false
      ;;
  esac

  if [[ "$whitelist_passed" == "false" ]]; then
    type print_error &>/dev/null && print_error "Path not in whitelist: $canonical_path"
    type print_error &>/dev/null && print_error "Operation: $operation"
    type log_message &>/dev/null && log_message "ERROR" "Path traversal attempt blocked - not in whitelist: $canonical_path (operation: $operation)"
    return 1
  fi

  # BLACKLIST CHECK - NEVER allow these critical system directories
  case "$canonical_path" in
    /System/*|/usr/*|/bin/*|/sbin/*|/etc/*|/var/db/*|/private/var/db/*|/private/etc/*|/Library/LaunchDaemons/*|/Library/LaunchAgents/*)
      type print_error &>/dev/null && print_error "Path in system blacklist: $canonical_path"
      type log_message &>/dev/null && log_message "ERROR" "Blacklist violation - attempted access to critical system directory: $canonical_path"
      return 1
      ;;
  esac

  # Success - return the canonical path
  echo "$canonical_path"
  return 0
}
