#!/usr/bin/env bash

#==============================================================================
# logger.sh - Standardized Logging Library
#
# Provides consistent logging interface across all zsh-setup scripts
#==============================================================================

# Load config if available
if [ -f "${SCRIPT_DIR:-$(dirname "${BASH_SOURCE[0]}")}/config.sh" ]; then
    source "${SCRIPT_DIR:-$(dirname "${BASH_SOURCE[0]}")}/config.sh"
fi

# Default log file if not set
LOG_FILE="${LOG_FILE:-/tmp/zsh_setup.log}"

# Verbose mode (default: true)
VERBOSE="${VERBOSE:-true}"

#------------------------------------------------------------------------------
# Logging Functions
#------------------------------------------------------------------------------

# Ensure log directory exists
ensure_log_dir() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
}

# Get timestamp
get_timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

# Log a message (info level)
log_message() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp=$(get_timestamp)
    
    ensure_log_dir
    
    # Always write to log file
    echo "[$timestamp] [$level] $message" >>"$LOG_FILE"
    
    # Print to console if verbose mode is enabled
    if $VERBOSE; then
        echo "$message"
    fi
}

# Log an info message
log_info() {
    log_message "$1" "INFO"
}

# Log a warning message
log_warn() {
    local message="$1"
    local timestamp=$(get_timestamp)
    
    ensure_log_dir
    
    # Write to log file
    echo "[$timestamp] [WARN] $message" >>"$LOG_FILE"
    
    # Always print warnings to console
    echo "⚠️  $message" >&2
}

# Log an error message
log_error() {
    local message="$1"
    local timestamp=$(get_timestamp)
    
    ensure_log_dir
    
    # Write to log file
    echo "[$timestamp] [ERROR] $message" >>"$LOG_FILE"
    
    # Always print errors to stderr
    echo "❌ ERROR: $message" >&2
}

# Log a debug message (only if DEBUG is set)
log_debug() {
    local message="$1"
    
    if [[ "${DEBUG:-false}" == "true" ]]; then
        local timestamp=$(get_timestamp)
        ensure_log_dir
        echo "[$timestamp] [DEBUG] $message" >>"$LOG_FILE"
        
        if $VERBOSE; then
            echo "🔍 DEBUG: $message" >&2
        fi
    fi
}

# Log a success message
log_success() {
    local message="$1"
    local timestamp=$(get_timestamp)
    
    ensure_log_dir
    
    # Write to log file
    echo "[$timestamp] [SUCCESS] $message" >>"$LOG_FILE"
    
    # Print to console
    echo "✅ $message"
}

# Initialize log file
init_log_file() {
    local script_name="${1:-zsh-setup}"
    local version="${2:-unknown}"
    
    ensure_log_dir
    
    {
        echo "=== $script_name Log - $(date) ==="
        echo "System: $(uname -a)"
        echo "User: $(whoami)"
        echo "Script version: $version"
        echo "=================================="
    } >"$LOG_FILE"
    
    log_info "Log file initialized at $LOG_FILE"
}

# Log a section header
log_section() {
    local section="$1"
    local timestamp=$(get_timestamp)
    
    ensure_log_dir
    
    {
        echo ""
        echo "[$timestamp] ========================================"
        echo "[$timestamp] $section"
        echo "[$timestamp] ========================================"
    } >>"$LOG_FILE"
    
    if $VERBOSE; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "$section"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
}

# Log command execution
log_command() {
    local command="$1"
    local description="${2:-Executing command}"
    
    log_debug "$description: $command"
}

# Export functions for use in other scripts
export -f log_message
export -f log_info
export -f log_warn
export -f log_error
export -f log_debug
export -f log_success
export -f init_log_file
export -f log_section
export -f log_command
export -f get_timestamp
export -f ensure_log_dir
