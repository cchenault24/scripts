#!/bin/zsh
#
# lib/core.sh - Core utilities and state management for mac-cleanup
#

# Global state variables (MC_ prefix for mac-cleanup)
MC_BACKUP_DIR="$HOME/.mac-cleanup-backups/$(date +%Y-%m-%d-%H-%M-%S)"
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

# Create backup directory if it doesn't exist
create_backup_dir() {
  if [[ ! -d "$MC_BACKUP_DIR" ]]; then
    mkdir -p "$MC_BACKUP_DIR" 2>/dev/null || {
      print_error "Failed to create backup directory at $MC_BACKUP_DIR"
      print_info "Creating backup directory in /tmp instead..."
      MC_BACKUP_DIR="/tmp/mac-cleanup-backups/$(date +%Y-%m-%d-%H-%M-%S)"
      mkdir -p "$MC_BACKUP_DIR"
    }
    print_success "Created backup directory at $MC_BACKUP_DIR"
  fi
}

# Initialize core
mc_core_init() {
  # Create backup directory
  create_backup_dir
  
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
mc_check_dependencies() {
  local missing_deps=()
  
  for cmd in find; do
    if ! command -v $cmd &>/dev/null; then
      missing_deps+=($cmd)
    fi
  done
  
  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    print_error "Missing required dependencies: ${missing_deps[*]}"
    print_info "Please install these tools before running the script."
    exit 1
  fi
}

# Clean up any temporary files created by the script
mc_cleanup_script() {
  # Perform any necessary cleanup before exiting
  print_info "Cleaning up script resources..."
  
  # Remove any temp files (N qualifier prevents error if no matches)
  rm -f /tmp/mac-cleanup-temp-*(/N) 2>/dev/null
  rm -f /tmp/mac-cleanup-sweep-*.tmp(N) 2>/dev/null
  
  # Clean up selection tool if it was installed by this script
  mc_cleanup_selection_tool
  
  # Compress backup logs if they exist
  if [[ -d "$MC_BACKUP_DIR" && $(find "$MC_BACKUP_DIR" -type f | wc -l) -gt 0 ]]; then
    find "$MC_BACKUP_DIR" -type f -name "*.log" -exec gzip {} \; 2>/dev/null
  fi
}

# Handle script interruptions gracefully
mc_handle_interrupt() {
  echo ""
  print_warning "Script interrupted by user."
  print_info "Cleaning up and exiting..."
  
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
  
  # Clean up sweep temp files (N qualifier prevents error if no matches)
  rm -f /tmp/mac-cleanup-sweep-*.tmp(N) 2>/dev/null
  rm -f /tmp/mac-cleanup-*.tmp 2>/dev/null || true
  
  # Clean up selection tool if it was installed by this script
  mc_cleanup_selection_tool
  
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

# Plugin registry functions
mc_register_plugin() {
  local name="$1"
  local category="$2"
  local function="$3"
  local requires_admin="${4:-false}"
  local size_function="${5:-}"  # Optional size calculation function (PERF-3)
  
  # Normalize plugin name at registration time to avoid redundant lookups
  name=$(_normalize_plugin_name "$name")
  
  MC_PLUGIN_REGISTRY["$name"]="$function|$category|$requires_admin"
  
  # Register size calculation function if provided (PERF-3)
  if [[ -n "$size_function" ]]; then
    MC_PLUGIN_SIZE_FUNCTIONS["$name"]="$size_function"
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
