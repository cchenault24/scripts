#!/bin/bash
#
# status-optimizations.sh - Check status of optimization services

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load UI functions
source "$PROJECT_DIR/lib/constants.sh" 2>/dev/null || true
source "$PROJECT_DIR/lib/logger.sh" 2>/dev/null || true
source "$PROJECT_DIR/lib/ui.sh" 2>/dev/null || true

PID_DIR="$HOME/.local-llm-setup/pids"

# Fallback print functions if sourcing failed
if ! command -v print_header &>/dev/null; then
  print_header() { echo ""; echo "═══════════════════════════════════════════════════════════"; echo "$1"; echo "═══════════════════════════════════════════════════════════"; echo ""; }
  print_success() { echo "✓ $1"; }
  print_info() { echo "ℹ $1"; }
  print_warn() { echo "⚠ $1"; }
fi

print_header "📊 Optimization Services Status"

# Check memory monitor
if [[ -f "$PID_DIR/memory_monitor.pid" ]]; then
  pid=$(cat "$PID_DIR/memory_monitor.pid" 2>/dev/null || echo "")
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    print_success "Memory Monitor: Running (PID: $pid)"
  else
    print_warn "Memory Monitor: Not running"
    rm -f "$PID_DIR/memory_monitor.pid"
  fi
else
  print_info "Memory Monitor: Not started"
fi

# Check queue processor
if [[ -f "$PID_DIR/queue_processor.pid" ]]; then
  pid=$(cat "$PID_DIR/queue_processor.pid" 2>/dev/null || echo "")
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    print_success "Queue Processor: Running (PID: $pid)"
    # Show queue status if available
    if command -v get_queue_status &>/dev/null; then
      queue_status=$(get_queue_status 2>/dev/null || echo "")
      if [[ -n "$queue_status" ]]; then
        print_info "  Queue: $queue_status"
      fi
    fi
  else
    print_warn "Queue Processor: Not running"
    rm -f "$PID_DIR/queue_processor.pid"
  fi
else
  print_info "Queue Processor: Not started"
fi

# Check Ollama proxy
if [[ -f "$PID_DIR/ollama_proxy.pid" ]]; then
  pid=$(cat "$PID_DIR/ollama_proxy.pid" 2>/dev/null || echo "")
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    print_success "Ollama Proxy: Running (PID: $pid)"
    print_info "  Proxy URL: http://localhost:11435"
    # Test proxy
    if curl -s http://localhost:11435/api/tags &>/dev/null; then
      print_success "  Proxy is responding"
    else
      print_warn "  Proxy is not responding"
    fi
  else
    print_warn "Ollama Proxy: Not running"
    rm -f "$PID_DIR/ollama_proxy.pid"
  fi
else
  print_info "Ollama Proxy: Not started"
fi

echo ""
print_info "To start services: ./tools/start-optimizations.sh"
print_info "To stop services: ./tools/stop-optimizations.sh"
