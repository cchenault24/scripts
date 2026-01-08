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
source "$PROJECT_DIR/lib/utils.sh"
source "$PROJECT_DIR/lib/hardware.sh"
source "$PROJECT_DIR/lib/ollama.sh"
source "$PROJECT_DIR/lib/models.sh"
source "$PROJECT_DIR/lib/optimization.sh"

# Enable auto-start by removing disable flag
if command -v enable_auto_start &>/dev/null; then
  enable_auto_start
  log_info "Auto-start enabled"
fi

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
    local monitor_pid=$!
    echo $monitor_pid > "$PID_DIR/memory_monitor.pid"
    
    # Health check: verify process is still running after a moment
    sleep 1
    if kill -0 "$monitor_pid" 2>/dev/null; then
      print_success "Memory monitor started (PID: $monitor_pid)"
    else
      print_error "Memory monitor failed to start"
      rm -f "$PID_DIR/memory_monitor.pid"
      return 1
    fi
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
    local queue_pid=$!
    echo $queue_pid > "$PID_DIR/queue_processor.pid"
    
    # Health check: verify process is still running after a moment
    sleep 1
    if kill -0 "$queue_pid" 2>/dev/null; then
      print_success "Queue processor started (PID: $queue_pid)"
    else
      print_error "Queue processor failed to start"
      rm -f "$PID_DIR/queue_processor.pid"
      return 1
    fi
  fi
fi

# Start Ollama proxy (use wrapper script)
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
    
    # Use wrapper script to start proxy (it will handle all checks and startup)
    if [[ -f "$SCRIPT_DIR/ensure-optimizations.sh" ]]; then
      if "$SCRIPT_DIR/ensure-optimizations.sh" 2>/dev/null; then
        # Verify proxy started
        sleep 1
        if [[ -f "$PID_DIR/ollama_proxy.pid" ]]; then
          local proxy_pid
          proxy_pid=$(cat "$PID_DIR/ollama_proxy.pid" 2>/dev/null || echo "")
          if [[ -n "$proxy_pid" ]] && kill -0 "$proxy_pid" 2>/dev/null; then
            print_success "Ollama proxy started (PID: $proxy_pid, Port: ${PROXY_PORT:-11435})"
            print_info "Advanced optimizations: Prompt=${ENABLE_PROMPT_OPTIMIZATION:-1}, Compression=${ENABLE_CONTEXT_COMPRESSION:-1}, Ensemble=${ENABLE_ENSEMBLE:-0}"
            print_info "Update Continue.dev config to use: apiBase: http://localhost:${PROXY_PORT:-11435}"
          else
            print_warn "Proxy may have failed to start. Check logs: $HOME/.local-llm-setup/proxy.log"
          fi
        fi
      else
        print_warn "Wrapper script failed to start proxy. Check logs: $HOME/.local-llm-setup/ensure-optimizations.log"
      fi
    else
      print_error "Wrapper script not found: $SCRIPT_DIR/ensure-optimizations.sh"
      print_info "Falling back to direct proxy startup..."
      # Fallback to direct startup if wrapper doesn't exist
      export PROJECT_DIR="$PROJECT_DIR"
      export PROXY_PORT="${PROXY_PORT:-11435}"
      export OLLAMA_PORT="${OLLAMA_PORT:-11434}"
      export ENABLE_PROMPT_OPTIMIZATION="${ENABLE_PROMPT_OPTIMIZATION:-1}"
      export ENABLE_CONTEXT_COMPRESSION="${ENABLE_CONTEXT_COMPRESSION:-1}"
      export ENABLE_ENSEMBLE="${ENABLE_ENSEMBLE:-0}"
      
      if ! command -v python3 &>/dev/null; then
        print_error "Python 3 is required for the proxy server"
        return 1
      fi
      
      python3 "$SCRIPT_DIR/ollama_proxy_server.py" > "$HOME/.local-llm-setup/proxy.log" 2>&1 &
      echo $! > "$PID_DIR/ollama_proxy.pid"
      sleep 2
      if [[ -f "$PID_DIR/ollama_proxy.pid" ]]; then
        local proxy_pid
        proxy_pid=$(cat "$PID_DIR/ollama_proxy.pid" 2>/dev/null || echo "")
        if [[ -n "$proxy_pid" ]] && kill -0 "$proxy_pid" 2>/dev/null; then
          print_success "Ollama proxy started (PID: $proxy_pid)"
        fi
      fi
    fi
  fi
fi

echo ""
print_success "Optimization services started"
print_info "Check status with: ./tools/status-optimizations.sh"
print_info "Stop services with: ./tools/stop-optimizations.sh"
