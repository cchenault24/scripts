#!/bin/bash
#
# logger.sh - Logging functions for setup-local-llm.sh
#
# Depends on: constants.sh (for LOG_FILE)

# Logging functions
log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
}

log_info() {
  log "INFO" "$@"
}

log_warn() {
  log "WARN" "$@"
  echo -e "${YELLOW}⚠ $*${NC}" >&2
}

log_error() {
  log "ERROR" "$@"
  echo -e "${RED}✗ $*${NC}" >&2
}

log_success() {
  log "SUCCESS" "$@"
  echo -e "${GREEN}✓ $*${NC}"
}
