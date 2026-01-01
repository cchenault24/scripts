#!/bin/bash
# Home Network Monitor - Utility Functions
# Core utility functions used across all modules
# Compatible with macOS default Bash 3.2

# Prevent direct execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "This is a library file and should be sourced, not executed."
  exit 1
fi

#------------------------------------------------------------------------------
# Global Variables (if not already set)
#------------------------------------------------------------------------------

: "${LOG_PREFIX:=[netmon]}"
: "${INSTALL_IN_PROGRESS:=false}"
: "${CLEANUP_NEEDED:=false}"

#------------------------------------------------------------------------------
# Output Functions
#------------------------------------------------------------------------------

say() {
  echo "${LOG_PREFIX} $*"
  # Note: log_info will be available after logger.sh is sourced
  if command -v log_info >/dev/null 2>&1; then
    log_info "$@"
  fi
}

warn() {
  echo "${LOG_PREFIX} WARNING: $*" >&2
  if command -v log_warn >/dev/null 2>&1; then
    log_warn "$@"
  fi
}

err() {
  echo "${LOG_PREFIX} ERROR: $*" >&2
  if command -v log_error >/dev/null 2>&1; then
    log_error "$@"
  fi
}

info() {
  echo "${LOG_PREFIX} INFO: $*"
  if command -v log_info >/dev/null 2>&1; then
    log_info "$@"
  fi
}

#------------------------------------------------------------------------------
# Utility Functions
#------------------------------------------------------------------------------

lower() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

confirm() {
  local prompt="$1"
  local def="${2:-Y}"
  local ans=""
  local other_opt
  
  if [ "$def" = "Y" ]; then
    other_opt="n"
  else
    other_opt="y"
  fi
  
  read -r -p "$prompt [${def}/${other_opt}]: " ans || true
  ans=$(lower "${ans:-$def}")
  case "$ans" in
    y|yes) return 0 ;;
    n|no)  return 1 ;;
    *)     [ "$def" = "Y" ] && return 0 || return 1 ;;
  esac
}

sanitize_input() {
  # Remove potentially dangerous characters
  echo "$1" | tr -d ';|&<>`$"\\'
}

#------------------------------------------------------------------------------
# Error Handling & Cleanup
#------------------------------------------------------------------------------

cleanup_on_exit() {
  local exit_code=$?
  
  if [ $exit_code -ne 0 ] && [ "$INSTALL_IN_PROGRESS" = "true" ]; then
    if command -v log_error >/dev/null 2>&1; then
      log_error "Installation failed with exit code $exit_code"
    fi
    warn "Installation was interrupted. You may need to run uninstall to clean up."
  fi
  
  if [ "$CLEANUP_NEEDED" = "true" ]; then
    if command -v log_info >/dev/null 2>&1; then
      log_info "Performing cleanup..."
    fi
  fi
  
  exit $exit_code
}

cleanup_on_interrupt() {
  if command -v log_error >/dev/null 2>&1; then
    log_error "Script interrupted by user"
  fi
  echo ""
  warn "Installation interrupted. Run uninstall if you need to clean up."
  exit 130
}

# Setup traps (can be overridden by main script)
trap cleanup_on_exit EXIT
trap cleanup_on_interrupt INT TERM
