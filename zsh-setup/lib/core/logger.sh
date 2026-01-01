#!/usr/bin/env bash

#==============================================================================
# logger.sh - Logging Interface
#
# Provides namespaced logging functions
#==============================================================================

# Load config if available
if [[ -n "${ZSH_SETUP_ROOT:-}" ]] && [[ -f "$ZSH_SETUP_ROOT/lib/core/config.sh" ]]; then
    source "$ZSH_SETUP_ROOT/lib/core/config.sh"
    zsh_setup::core::config::load
fi

# Get log file path
zsh_setup::core::logger::_get_log_file() {
    if zsh_setup::core::config::has log_file; then
        echo "$(zsh_setup::core::config::get log_file)"
    else
        echo "/tmp/zsh_setup.log"
    fi
}

# Get verbose setting
zsh_setup::core::logger::_is_verbose() {
    local verbose=$(zsh_setup::core::config::get verbose "true")
    [[ "$verbose" == "true" ]]
}

# Ensure log directory exists
zsh_setup::core::logger::_ensure_log_dir() {
    local log_file=$(zsh_setup::core::logger::_get_log_file)
    mkdir -p "$(dirname "$log_file")" 2>/dev/null
}

# Get timestamp
zsh_setup::core::logger::_get_timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

#------------------------------------------------------------------------------
# Logging Functions
#------------------------------------------------------------------------------

# Log a message
zsh_setup::core::logger::log() {
    local level="$1"
    local message="$2"
    local timestamp=$(zsh_setup::core::logger::_get_timestamp)
    local log_file=$(zsh_setup::core::logger::_get_log_file)
    
    zsh_setup::core::logger::_ensure_log_dir
    
    # Write to log file
    echo "[$timestamp] [$level] $message" >>"$log_file"
    
    # Print to console based on level and verbose setting
    case "$level" in
        ERROR)
            echo "❌ ERROR: $message" >&2
            ;;
        WARN)
            echo "⚠️  $message" >&2
            ;;
        SUCCESS)
            echo "✅ $message"
            ;;
        DEBUG)
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo "🔍 DEBUG: $message" >&2
            fi
            ;;
        *)
            if zsh_setup::core::logger::_is_verbose; then
                echo "$message"
            fi
            ;;
    esac
}

# Log info message
zsh_setup::core::logger::info() {
    zsh_setup::core::logger::log "INFO" "$1"
}

# Log warning message
zsh_setup::core::logger::warn() {
    zsh_setup::core::logger::log "WARN" "$1"
}

# Log error message
zsh_setup::core::logger::error() {
    zsh_setup::core::logger::log "ERROR" "$1"
}

# Log debug message
zsh_setup::core::logger::debug() {
    zsh_setup::core::logger::log "DEBUG" "$1"
}

# Log success message
zsh_setup::core::logger::success() {
    zsh_setup::core::logger::log "SUCCESS" "$1"
}

# Log section header
zsh_setup::core::logger::section() {
    local section="$1"
    local timestamp=$(zsh_setup::core::logger::_get_timestamp)
    local log_file=$(zsh_setup::core::logger::_get_log_file)
    
    zsh_setup::core::logger::_ensure_log_dir
    
    {
        echo ""
        echo "[$timestamp] ========================================"
        echo "[$timestamp] $section"
        echo "[$timestamp] ========================================"
    } >>"$log_file"
    
    if zsh_setup::core::logger::_is_verbose; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "$section"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
}

# Initialize log file
zsh_setup::core::logger::init() {
    local script_name="${1:-zsh-setup}"
    local version="${2:-unknown}"
    local log_file=$(zsh_setup::core::logger::_get_log_file)
    
    zsh_setup::core::logger::_ensure_log_dir
    
    {
        echo "=== $script_name Log - $(date) ==="
        echo "System: $(uname -a)"
        echo "User: $(whoami)"
        echo "Script version: $version"
        echo "=================================="
    } >"$log_file"
    
    zsh_setup::core::logger::info "Log file initialized at $log_file"
}

# Backward compatibility functions (for migration)
log_message() {
    zsh_setup::core::logger::info "$1"
}

log_info() {
    zsh_setup::core::logger::info "$1"
}

log_warn() {
    zsh_setup::core::logger::warn "$1"
}

log_error() {
    zsh_setup::core::logger::error "$1"
}

log_debug() {
    zsh_setup::core::logger::debug "$1"
}

log_success() {
    zsh_setup::core::logger::success "$1"
}

log_section() {
    zsh_setup::core::logger::section "$1"
}

init_log_file() {
    zsh_setup::core::logger::init "$@"
}
