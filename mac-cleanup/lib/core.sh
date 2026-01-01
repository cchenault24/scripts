#!/bin/zsh
#
# lib/core.sh - Core utilities and state management for mac-cleanup
#

# Global state variables (MC_ prefix for mac-cleanup)
MC_BACKUP_DIR="$HOME/.mac-cleanup-backups/$(date +%Y-%m-%d-%H-%M-%S)"
MC_GUM_INSTALLED_BY_SCRIPT=false
MC_DRY_RUN=false
MC_QUIET_MODE=false
MC_LOG_FILE=""
MC_TOTAL_SPACE_SAVED=0
MC_ADMIN_USERNAME=""
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
  
  # Remove any temp files
  rm -f /tmp/mac-cleanup-temp-*(/N) 2>/dev/null
  
  # Clean up gum if it was installed by this script
  mc_cleanup_gum
  
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
  
  # Clean up gum if it was installed by this script
  mc_cleanup_gum
  
  # Exit with non-zero status
  exit 1
}

# Set up trap for CTRL+C and other signals
mc_setup_traps() {
  trap mc_handle_interrupt INT TERM HUP
  trap mc_cleanup_script EXIT
}

# Plugin registry functions
mc_register_plugin() {
  local name="$1"
  local category="$2"
  local function="$3"
  local requires_admin="${4:-false}"
  
  MC_PLUGIN_REGISTRY["$name"]="$function|$category|$requires_admin"
}

mc_get_plugin_function() {
  local name="$1"
  echo "${MC_PLUGIN_REGISTRY[$name]}" | cut -d'|' -f1
}

mc_get_plugin_category() {
  local name="$1"
  echo "${MC_PLUGIN_REGISTRY[$name]}" | cut -d'|' -f2
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
