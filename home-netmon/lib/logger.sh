#!/bin/bash
# Home Network Monitor - Logging Functions
# Comprehensive logging system with rotation support
# Compatible with macOS default Bash 3.2

# Prevent direct execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "This is a library file and should be sourced, not executed."
  exit 1
fi

#------------------------------------------------------------------------------
# Logging Functions
#------------------------------------------------------------------------------

init_logging() {
  # Ensure BASE_DIR is set (from config or main script)
  : "${BASE_DIR:=${HOME}/home-netmon}"
  : "${LOG_FILE:=${BASE_DIR}/install.log}"
  
  mkdir -p "$BASE_DIR"
  
  # Rotate log if it's too large (10MB)
  if [ -f "$LOG_FILE" ]; then
    local log_size
    log_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo "0")
    if [ "$log_size" -gt 10485760 ]; then
      rotate_logs
    fi
  fi
  
  if [ ! -f "$LOG_FILE" ]; then
    {
      echo "=== Home Network Monitor Install Log ==="
      echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
      echo "System: $(uname -a)"
      echo "User: $(whoami)"
      echo "macOS Version: $(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
      echo "========================================"
    } > "$LOG_FILE"
  fi
}

log_message() {
  local level="$1"
  shift
  local message="$*"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  : "${LOG_FILE:=${BASE_DIR}/install.log}"
  
  echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

log_info() {
  log_message "INFO" "$@"
}

log_warn() {
  log_message "WARN" "$@"
}

log_error() {
  log_message "ERROR" "$@"
}

log_user_input() {
  # Sanitize and log user inputs (remove sensitive data)
  local sanitized=$(echo "$1" | sed 's/[^a-zA-Z0-9._:-]//g')
  log_info "User input: $sanitized"
}

rotate_logs() {
  : "${LOG_FILE:=${BASE_DIR}/install.log}"
  : "${BASE_DIR:=${HOME}/home-netmon}"
  
  if [ ! -f "$LOG_FILE" ]; then
    return 0
  fi
  
  local max_backups=5
  local backup_file
  local i
  
  # Rotate existing backups
  for i in $(seq $((max_backups - 1)) -1 1); do
    backup_file="${LOG_FILE}.${i}.gz"
    if [ -f "$backup_file" ]; then
      mv "$backup_file" "${LOG_FILE}.$((i + 1)).gz" 2>/dev/null || true
    fi
  done
  
  # Compress and move current log
  if [ -f "$LOG_FILE" ]; then
    gzip -c "$LOG_FILE" > "${LOG_FILE}.1.gz" 2>/dev/null || true
    > "$LOG_FILE"  # Clear current log
    log_info "Log rotated"
  fi
  
  # Remove old backups beyond max_backups
  for i in $(seq $((max_backups + 1)) 10); do
    backup_file="${LOG_FILE}.${i}.gz"
    [ -f "$backup_file" ] && rm -f "$backup_file"
  done
}
