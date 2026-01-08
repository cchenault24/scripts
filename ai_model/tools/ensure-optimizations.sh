#!/bin/bash
#
# ensure-optimizations.sh - Ensure optimization services are running
#
# This wrapper script ensures all optimization services are running.
# It can be called manually, by LaunchAgents, or by other scripts.
# If services aren't running, it starts them automatically (unless disabled).
#
# Usage:
#   ./tools/ensure-optimizations.sh
#
# Exit codes:
#   0 - Services are running or auto-start is disabled
#   1 - Failed to start services

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PID_DIR="$HOME/.local-llm-setup/pids"
mkdir -p "$PID_DIR"

# Load library functions
source "$PROJECT_DIR/lib/constants.sh" 2>/dev/null || true
source "$PROJECT_DIR/lib/logger.sh" 2>/dev/null || true
source "$PROJECT_DIR/lib/ui.sh" 2>/dev/null || true
source "$PROJECT_DIR/lib/optimization.sh" 2>/dev/null || true

# Fallback print functions if sourcing failed
if ! command -v print_info &>/dev/null; then
  print_info() { echo "ℹ $1"; }
  print_success() { echo "✓ $1"; }
  print_warn() { echo "⚠ $1"; }
  print_error() { echo "✗ $1"; }
fi

PROXY_PORT="${PROXY_PORT:-11435}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"

# Check if auto-start is disabled
if is_auto_start_disabled 2>/dev/null; then
  log_info "Auto-start is disabled, skipping service startup"
  exit 0
fi

# Check if proxy is running
is_proxy_running() {
  if [[ -f "$PID_DIR/ollama_proxy.pid" ]]; then
    local pid
    pid=$(cat "$PID_DIR/ollama_proxy.pid" 2>/dev/null || echo "")
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      # Check if port is actually listening
      if lsof -i ":$PROXY_PORT" &>/dev/null 2>&1 || \
         netstat -an 2>/dev/null | grep -q ":$PROXY_PORT.*LISTEN"; then
        return 0
      fi
    fi
    # Stale PID file - remove it
    rm -f "$PID_DIR/ollama_proxy.pid"
  fi
  return 1
}

# Start proxy server
start_proxy() {
  # Check if Ollama is running (proxy depends on it)
  if ! curl -s --max-time 2 "http://localhost:${OLLAMA_PORT}/api/tags" &>/dev/null; then
    log_warn "Ollama is not running on port ${OLLAMA_PORT}"
    print_warn "Ollama is not running. Proxy will start but may not function until Ollama is running."
  fi
  
  # Check if Python 3 is available
  if ! command -v python3 &>/dev/null; then
    log_error "Python 3 is required for the proxy server"
    print_error "Python 3 not found. Install with: brew install python3"
    return 1
  fi
  
  # Check if proxy script exists
  if [[ ! -f "$SCRIPT_DIR/ollama_proxy_server.py" ]]; then
    log_error "Proxy server script not found: $SCRIPT_DIR/ollama_proxy_server.py"
    print_error "Proxy server script not found"
    return 1
  fi
  
  # Check if port is already in use by another process
  local port_in_use=false
  if lsof -i ":$PROXY_PORT" &>/dev/null 2>&1 || \
     netstat -an 2>/dev/null | grep -q ":$PROXY_PORT.*LISTEN"; then
    # Check if it's our proxy (by checking PID file)
    if [[ -f "$PID_DIR/ollama_proxy.pid" ]]; then
      local existing_pid
      existing_pid=$(cat "$PID_DIR/ollama_proxy.pid" 2>/dev/null || echo "")
      if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
        # It's our proxy, it's already running
        return 0
      fi
    fi
    # Port is in use by something else
    log_error "Port $PROXY_PORT is already in use by another process"
    print_error "Port $PROXY_PORT is already in use. Stop the service using this port or set PROXY_PORT to a different value."
    return 1
  fi
  
  # Set optimization flags (can be overridden via environment)
  export PROJECT_DIR="$PROJECT_DIR"
  export PROXY_PORT="$PROXY_PORT"
  export OLLAMA_PORT="$OLLAMA_PORT"
  export ENABLE_PROMPT_OPTIMIZATION="${ENABLE_PROMPT_OPTIMIZATION:-1}"
  export ENABLE_CONTEXT_COMPRESSION="${ENABLE_CONTEXT_COMPRESSION:-1}"
  export ENABLE_ENSEMBLE="${ENABLE_ENSEMBLE:-0}"
  
  # Start proxy in background
  log_info "Starting Ollama optimization proxy..."
  python3 "$SCRIPT_DIR/ollama_proxy_server.py" > "$HOME/.local-llm-setup/proxy.log" 2>&1 &
  local proxy_pid=$!
  echo $proxy_pid > "$PID_DIR/ollama_proxy.pid"
  
  # Give proxy time to start
  sleep 2
  
  # Verify proxy started successfully
  if kill -0 "$proxy_pid" 2>/dev/null; then
    # Check if port is listening
    if lsof -i ":$PROXY_PORT" &>/dev/null 2>&1 || \
       netstat -an 2>/dev/null | grep -q ":$PROXY_PORT.*LISTEN"; then
      log_info "Ollama proxy started successfully (PID: $proxy_pid, Port: $PROXY_PORT)"
      return 0
    else
      log_warn "Proxy process started but port $PROXY_PORT is not listening yet"
      # Process is running, port might still be initializing - consider it success
      return 0
    fi
  else
    log_error "Ollama proxy failed to start"
    print_error "Proxy failed to start. Check logs: $HOME/.local-llm-setup/proxy.log"
    rm -f "$PID_DIR/ollama_proxy.pid"
    return 1
  fi
}

# Main execution
main() {
  # Check if proxy is already running
  if is_proxy_running; then
    log_info "Proxy is already running"
    exit 0
  fi
  
  # Start proxy
  if start_proxy; then
    log_info "Optimization services ensured (proxy started)"
    exit 0
  else
    log_error "Failed to ensure optimization services"
    exit 1
  fi
}

# Run main function
main "$@"
