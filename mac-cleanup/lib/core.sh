#!/bin/zsh
#
# lib/core.sh - Core utilities and state management for mac-cleanup
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Global state variables (MC_ prefix for mac-cleanup)
# Only initialize MC_BACKUP_DIR if it's not already set (prevents re-initialization with new timestamp)
if [[ -z "${MC_BACKUP_DIR:-}" ]]; then
  MC_BACKUP_DIR="$HOME/.mac-cleanup-backups/$(date +%Y-%m-%d-%H-%M-%S)"
fi
MC_SELECTION_TOOL_INSTALLED_BY_SCRIPT=false
MC_SELECTION_TOOL=""
MC_DRY_RUN=false
MC_QUIET_MODE=false
MC_LOG_FILE=""
MC_TOTAL_SPACE_SAVED=0
MC_ADMIN_USERNAME=""
MC_CLEANUP_PID=""
MC_PROGRESS_PID=""
declare -A MC_SPACE_SAVED_BY_OPERATION
declare -A MC_PLUGIN_REGISTRY

# Get script directory for relative paths
MC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")/.." && pwd)"

# Load constants if not already loaded
if [[ -z "${MC_BYTES_PER_MB:-}" ]]; then
  source "$MC_SCRIPT_DIR/lib/constants.sh" 2>/dev/null || true
fi

# Create backup directory if it doesn't exist
_create_backup_dir() {
  if [[ ! -d "$MC_BACKUP_DIR" ]]; then
    if ! mkdir -p "$MC_BACKUP_DIR" 2>/dev/null; then
      print_error "Failed to create backup directory at $MC_BACKUP_DIR"
      print_info "This may be due to insufficient permissions or disk space."
      print_info "Creating backup directory in /tmp instead..."
      MC_BACKUP_DIR="${MC_BACKUP_FALLBACK_DIR:-/tmp/mac-cleanup-backups}/$(date +%Y-%m-%d-%H-%M-%S)"
      if ! mkdir -p "$MC_BACKUP_DIR" 2>/dev/null; then
        print_error "Failed to create fallback backup directory. Cannot proceed safely."
        print_info "Next steps:"
        print_info "  • Check disk space: df -h"
        print_info "  • Check permissions on /tmp"
        print_info "  • Set MC_BACKUP_DIR to a writable location"
        exit 1
      fi
      print_warning "Using fallback backup location: $MC_BACKUP_DIR"
      log_message "WARNING" "Using fallback backup directory: $MC_BACKUP_DIR"
    fi
    print_success "Created backup directory at $MC_BACKUP_DIR"
  fi
}

# Initialize core
mc_core_init() {
  # Create backup directory
  _create_backup_dir
  
  # Initialize backup system (will create JSON manifest)
  # Load backup module to initialize
  if [[ -f "$MC_SCRIPT_DIR/lib/backup.sh" ]]; then
    source "$MC_SCRIPT_DIR/lib/backup.sh" 2>/dev/null || true
    mc_backup_init 2>/dev/null || true
  else
    # Fallback: create old-style manifest
    touch "$MC_BACKUP_DIR/backup_manifest.txt" 2>/dev/null || true
  fi
  
  # Clear size calculation cache to ensure fresh calculations
  clear_size_cache
  
  # Initialize log file
  MC_LOG_FILE="$MC_BACKUP_DIR/cleanup.log"
  log_message "INFO" "Starting macOS cleanup utility"
  if [[ "$MC_DRY_RUN" == "true" ]]; then
    log_message "INFO" "DRY RUN MODE enabled"
  fi
}

# Check for tools the script depends on
# Phase 4.3: Enhanced with actionable error messages
mc_check_dependencies() {
  local missing_deps=()
  
  for cmd in find; do
    if ! command -v $cmd &>/dev/null; then
      missing_deps+=($cmd)
    fi
  done
  
  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    print_error "Missing required dependencies: ${missing_deps[*]}"
    print_info "These tools are required for the script to function."
    print_info "Next steps:"
    print_info "  • On macOS, these tools should be pre-installed"
    print_info "  • If missing, try: xcode-select --install"
    print_info "  • Or reinstall macOS command line tools"
    log_message "ERROR" "Missing required dependencies: ${missing_deps[*]}"
    exit 1
  fi
}

# Clean up any temporary files created by the script
# Phase 4.2: Enhanced with progress file cleanup
mc_cleanup_script() {
  # Perform any necessary cleanup before exiting
  if [[ -t 1 ]]; then
    print_info "Cleaning up script resources..."
  fi
  
  # Phase 4.2: Clean up progress files and locks
  rm -f "${MC_TEMP_DIR}/${MC_TEMP_PREFIX}-progress-"*.tmp 2>/dev/null || true
  rm -f "${MC_TEMP_DIR}/${MC_TEMP_PREFIX}-progress-"*.tmp.lock 2>/dev/null || true
  
  # Remove any temp files (N qualifier prevents error if no matches)
  rm -f "${MC_TEMP_DIR}/${MC_TEMP_PREFIX}-temp-"*(/N) 2>/dev/null
  rm -f "${MC_TEMP_DIR}/${MC_TEMP_PREFIX}-sweep-"*.tmp(N) 2>/dev/null
  rm -f "${MC_TEMP_DIR}/${MC_TEMP_PREFIX}-output-"*.tmp 2>/dev/null || true
  rm -f "${MC_TEMP_DIR}/${MC_TEMP_PREFIX}-space-"*.tmp 2>/dev/null || true
  
  # Clean up selection tool if it was installed by this script
  mc_cleanup_selection_tool
  
  # Compress backup logs if they exist
  if [[ -d "$MC_BACKUP_DIR" && $(find "$MC_BACKUP_DIR" -type f 2>/dev/null | wc -l) -gt 0 ]]; then
    find "$MC_BACKUP_DIR" -type f -name "*.log" ! -name "*.gz" -exec gzip {} \; 2>/dev/null || true
  fi
}

# Handle script interruptions gracefully
# Phase 4.2: Enhanced with progress file cleanup
mc_handle_interrupt() {
  echo ""
  print_warning "Script interrupted by user."
  print_info "Cleaning up and exiting..."
  
  # Phase 4.2: Clean up progress files
  if [[ -n "${MC_PROGRESS_FILE:-}" && -f "$MC_PROGRESS_FILE" ]]; then
    rm -f "$MC_PROGRESS_FILE" "${MC_PROGRESS_FILE}.lock" 2>/dev/null || true
    log_message "INFO" "Cleaned up progress file on interrupt"
  fi
  
  # Kill background cleanup process if running
  if [[ -n "${MC_CLEANUP_PID:-}" && "$MC_CLEANUP_PID" =~ ^[0-9]+$ ]]; then
    if kill -0 "$MC_CLEANUP_PID" 2>/dev/null; then
      print_info "Stopping cleanup process..."
      kill "$MC_CLEANUP_PID" 2>/dev/null || true
      wait "$MC_CLEANUP_PID" 2>/dev/null || true
    fi
  fi
  
  # Kill progress display process if running
  if [[ -n "${MC_PROGRESS_PID:-}" && "$MC_PROGRESS_PID" =~ ^[0-9]+$ ]]; then
    if kill -0 "$MC_PROGRESS_PID" 2>/dev/null; then
      kill "$MC_PROGRESS_PID" 2>/dev/null || true
      wait "$MC_PROGRESS_PID" 2>/dev/null || true
    fi
  fi
  
  # Phase 4.2: Clean up all temp files including progress files
  rm -f "${MC_TEMP_DIR}/${MC_TEMP_PREFIX}-sweep-"*.tmp(N) 2>/dev/null
  rm -f "${MC_TEMP_DIR}/${MC_TEMP_PREFIX}-progress-"*.tmp 2>/dev/null || true
  rm -f "${MC_TEMP_DIR}/${MC_TEMP_PREFIX}-progress-"*.tmp.lock 2>/dev/null || true
  rm -f "${MC_TEMP_DIR}/${MC_TEMP_PREFIX}-"*.tmp 2>/dev/null || true
  
  # Clean up selection tool if it was installed by this script
  mc_cleanup_selection_tool
  
  # Phase 4.3: Provide helpful message about backups
  if [[ -n "${MC_BACKUP_DIR:-}" && -d "$MC_BACKUP_DIR" ]]; then
    print_info "Backups are safe in: $MC_BACKUP_DIR"
    print_info "You can restore using: $SCRIPT_NAME --undo"
  fi
  
  # Exit with non-zero status
  exit 1
}

# Set up trap for CTRL+C and other signals
mc_setup_traps() {
  trap mc_handle_interrupt INT TERM HUP
  trap mc_cleanup_script EXIT
}

# Helper function to normalize plugin names (removes quotes and brackets)
_normalize_plugin_name() {
  local name="$1"
  # Use parameter expansion instead of multiple sed calls for better performance
  name="${name#\"}"  # Remove leading quote
  name="${name%\"}"  # Remove trailing quote
  name="${name#\[}"  # Remove leading bracket
  name="${name%\]}"  # Remove trailing bracket
  echo "$name"
}

# Plugin registry for size calculation functions (PERF-3)
typeset -A MC_PLUGIN_SIZE_FUNCTIONS
# Plugin registry for versions (QUAL-12)
typeset -A MC_PLUGIN_VERSIONS
# Plugin registry for dependencies (QUAL-9)
typeset -A MC_PLUGIN_DEPENDENCIES
# Plugin registry for category metadata (QUAL-10)
typeset -A MC_PLUGIN_CATEGORY_METADATA

# Plugin registry functions
mc_register_plugin() {
  local name="$1"
  local category="$2"
  local function="$3"
  local requires_admin="${4:-false}"
  local size_function="${5:-}"  # Optional size calculation function (PERF-3)
  local version="${6:-}"  # Optional version string (QUAL-12)
  local dependencies="${7:-}"  # Optional space-separated dependencies (QUAL-9)
  
  # Normalize plugin name at registration time to avoid redundant lookups
  name=$(_normalize_plugin_name "$name")
  
  # Validate function exists
  if [[ -z "$function" ]]; then
    print_error "Plugin registration failed: function name is empty for plugin: $name"
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Plugin registration failed: empty function for: $name"
    return 1
  fi
  
  # Store full registry entry: function|category|requires_admin|version
  MC_PLUGIN_REGISTRY["$name"]="$function|$category|$requires_admin|${version:-unknown}"
  
  # Register size calculation function if provided (PERF-3)
  if [[ -n "$size_function" ]]; then
    MC_PLUGIN_SIZE_FUNCTIONS["$name"]="$size_function"
  fi
  
  # Register version if provided (QUAL-12)
  if [[ -n "$version" ]]; then
    MC_PLUGIN_VERSIONS["$name"]="$version"
  fi
  
  # Register dependencies if provided (QUAL-9)
  if [[ -n "$dependencies" ]]; then
    MC_PLUGIN_DEPENDENCIES["$name"]="$dependencies"
  fi
  
  # Store category metadata (QUAL-10) - allows plugins to define custom categories
  if [[ -n "$category" ]]; then
    MC_PLUGIN_CATEGORY_METADATA["$category"]="${MC_PLUGIN_CATEGORY_METADATA[$category]:-}"
  fi
}

mc_get_plugin_function() {
  local name="$1"
  # Normalize the input name once
  local normalized_name=$(_normalize_plugin_name "$name")
  
  # Try direct lookup with normalized name (most common case)
  local result="${MC_PLUGIN_REGISTRY[$normalized_name]}"
  if [[ -n "$result" ]]; then
    echo "$result" | cut -d'|' -f1
    return
  fi
  
  # If not found, search through all keys (fallback for edge cases)
  # Since names are normalized at registration, this should rarely be needed
  for key in "${(@k)MC_PLUGIN_REGISTRY}"; do
    local normalized_key=$(_normalize_plugin_name "$key")
    if [[ "$normalized_key" == "$normalized_name" ]]; then
      echo "${MC_PLUGIN_REGISTRY[$key]}" | cut -d'|' -f1
      return
    fi
  done
  
  # Return empty if not found
  echo ""
}

mc_get_plugin_category() {
  local name="$1"
  # Normalize the input name once (PERF-8)
  local normalized_name=$(_normalize_plugin_name "$name")
  
  # Try direct lookup with normalized name (most common case)
  local result="${MC_PLUGIN_REGISTRY[$normalized_name]}"
  if [[ -n "$result" ]]; then
    local category=$(echo "$result" | cut -d'|' -f2)
    # Use parameter expansion instead of sed (PERF-5)
    category="${category#\"}"
    category="${category%\"}"
    echo "$category"
    return
  fi
  
  # If not found, search through all keys (fallback for edge cases)
  for key in "${(@k)MC_PLUGIN_REGISTRY}"; do
    local normalized_key=$(_normalize_plugin_name "$key")
    if [[ "$normalized_key" == "$normalized_name" ]]; then
      local category=$(echo "${MC_PLUGIN_REGISTRY[$key]}" | cut -d'|' -f2)
      # Use parameter expansion instead of sed (PERF-5)
      category="${category#\"}"
      category="${category%\"}"
      echo "$category"
      return
    fi
  done
  
  # Return empty if not found
  echo ""
}

mc_get_plugin_requires_admin() {
  local name="$1"
  echo "${MC_PLUGIN_REGISTRY[$name]}" | cut -d'|' -f3
}

mc_list_plugins() {
  for plugin_name in "${(@k)MC_PLUGIN_REGISTRY}"; do
    echo "$plugin_name"
  done | sort
}
