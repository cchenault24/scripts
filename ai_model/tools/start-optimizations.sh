#!/bin/bash
#
# start-optimizations.sh - Start optimization services
#
# Starts background services for:
# - Memory pressure monitoring
# - Request queue processing
# - Performance tracking
#
# Usage:
#   ./tools/start-optimizations.sh [options]
#
# Options:
#   --proxy          Start Ollama proxy server
#   --monitor        Start memory pressure monitoring
#   --queue          Start request queue processor
#   --all            Start all services (default)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PID_DIR="$HOME/.local-llm-setup/pids"
mkdir -p "$PID_DIR"

# Load optimization functions
source "$PROJECT_DIR/lib/constants.sh"
source "$PROJECT_DIR/lib/logger.sh"
source "$PROJECT_DIR/lib/ui.sh"
source "$PROJECT_DIR/lib/hardware.sh"
source "$PROJECT_DIR/lib/ollama.sh"
source "$PROJECT_DIR/lib/models.sh"
source "$PROJECT_DIR/lib/optimization.sh"

# Parse arguments
START_PROXY=false
START_MONITOR=false
START_QUEUE=false
START_ALL=true

while [[ $# -gt 0 ]]; do
  case $1 in
    --proxy)
      START_PROXY=true
      START_ALL=false
      shift
      ;;
    --monitor)
      START_MONITOR=true
      START_ALL=false
      shift
      ;;
    --queue)
      START_QUEUE=true
      START_ALL=false
      shift
      ;;
    --all)
      START_ALL=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ "$START_ALL" == "true" ]]; then
  START_PROXY=true
  START_MONITOR=true
  START_QUEUE=true
fi

print_header "🚀 Starting Optimization Services"

# Start memory pressure monitoring
if [[ "$START_MONITOR" == "true" ]]; then
  if [[ -f "$PID_DIR/memory_monitor.pid" ]]; then
    local old_pid
    old_pid=$(cat "$PID_DIR/memory_monitor.pid" 2>/dev/null || echo "")
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      print_info "Memory monitor already running (PID: $old_pid)"
    else
      rm -f "$PID_DIR/memory_monitor.pid"
    fi
  fi
  
  if [[ ! -f "$PID_DIR/memory_monitor.pid" ]]; then
    print_info "Starting memory pressure monitoring..."
    (
      source "$PROJECT_DIR/lib/optimization.sh"
      monitor_memory_pressure 60 85
    ) > "$HOME/.local-llm-setup/memory_monitor.log" 2>&1 &
    echo $! > "$PID_DIR/memory_monitor.pid"
    print_success "Memory monitor started (PID: $(cat "$PID_DIR/memory_monitor.pid"))"
  fi
fi

# Start request queue processor
if [[ "$START_QUEUE" == "true" ]]; then
  if [[ -f "$PID_DIR/queue_processor.pid" ]]; then
    local old_pid
    old_pid=$(cat "$PID_DIR/queue_processor.pid" 2>/dev/null || echo "")
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      print_info "Queue processor already running (PID: $old_pid)"
    else
      rm -f "$PID_DIR/queue_processor.pid"
    fi
  fi
  
  if [[ ! -f "$PID_DIR/queue_processor.pid" ]]; then
    print_info "Starting request queue processor..."
    (
      source "$PROJECT_DIR/lib/optimization.sh"
      while true; do
        process_request_queue 5 10
        sleep 5
      done
    ) > "$HOME/.local-llm-setup/queue_processor.log" 2>&1 &
    echo $! > "$PID_DIR/queue_processor.pid"
    print_success "Queue processor started (PID: $(cat "$PID_DIR/queue_processor.pid"))"
  fi
fi

# Start Ollama proxy
if [[ "$START_PROXY" == "true" ]]; then
  if [[ -f "$PID_DIR/ollama_proxy.pid" ]]; then
    local old_pid
    old_pid=$(cat "$PID_DIR/ollama_proxy.pid" 2>/dev/null || echo "")
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      print_info "Ollama proxy already running (PID: $old_pid)"
    else
      rm -f "$PID_DIR/ollama_proxy.pid"
    fi
  fi
  
  if [[ ! -f "$PID_DIR/ollama_proxy.pid" ]]; then
    print_info "Starting Ollama optimization proxy..."
    "$SCRIPT_DIR/ollama-proxy.sh" 11435 11434 > "$HOME/.local-llm-setup/proxy.log" 2>&1 &
    echo $! > "$PID_DIR/ollama_proxy.pid"
    print_success "Ollama proxy started (PID: $(cat "$PID_DIR/ollama_proxy.pid"))"
    print_info "Update Continue.dev config to use: apiBase: http://localhost:11435"
  fi
fi

echo ""
print_success "Optimization services started"
print_info "Check status with: ./tools/status-optimizations.sh"
print_info "Stop services with: ./tools/stop-optimizations.sh"
