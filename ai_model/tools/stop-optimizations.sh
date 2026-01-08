#!/bin/bash
#
# stop-optimizations.sh - Stop optimization services
#
# Stops all background optimization services and disables auto-start

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load UI functions
source "$PROJECT_DIR/lib/constants.sh" 2>/dev/null || true
source "$PROJECT_DIR/lib/logger.sh" 2>/dev/null || true
source "$PROJECT_DIR/lib/ui.sh" 2>/dev/null || true
source "$PROJECT_DIR/lib/optimization.sh" 2>/dev/null || true

PID_DIR="$HOME/.local-llm-setup/pids"

# Fallback print functions if sourcing failed
if ! command -v print_header &>/dev/null; then
  print_header() { echo ""; echo "═══════════════════════════════════════════════════════════"; echo "$1"; echo "═══════════════════════════════════════════════════════════"; echo ""; }
  print_success() { echo "✓ $1"; }
  print_info() { echo "ℹ $1"; }
  print_warn() { echo "⚠ $1"; }
fi

print_header "🛑 Stopping Optimization Services"

# Stop memory monitor
if [[ -f "$PID_DIR/memory_monitor.pid" ]]; then
  pid=$(cat "$PID_DIR/memory_monitor.pid" 2>/dev/null || echo "")
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    print_success "Stopped memory monitor (PID: $pid)"
  fi
  rm -f "$PID_DIR/memory_monitor.pid"
fi

# Stop queue processor
if [[ -f "$PID_DIR/queue_processor.pid" ]]; then
  pid=$(cat "$PID_DIR/queue_processor.pid" 2>/dev/null || echo "")
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    print_success "Stopped queue processor (PID: $pid)"
  fi
  rm -f "$PID_DIR/queue_processor.pid"
fi

# Stop Ollama proxy
if [[ -f "$PID_DIR/ollama_proxy.pid" ]]; then
  pid=$(cat "$PID_DIR/ollama_proxy.pid" 2>/dev/null || echo "")
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    print_success "Stopped Ollama proxy (PID: $pid)"
  fi
  rm -f "$PID_DIR/ollama_proxy.pid"
fi

# Disable auto-start to prevent services from restarting automatically
if command -v disable_auto_start &>/dev/null; then
  disable_auto_start
  print_info "Auto-start disabled. Services will not restart automatically."
  print_info "To re-enable: ./tools/start-optimizations.sh or ./tools/enable-optimizations.sh"
else
  # Fallback: create flag file directly
  mkdir -p "$HOME/.local-llm-setup"
  touch "$HOME/.local-llm-setup/optimizations.disabled"
  print_info "Auto-start disabled. Services will not restart automatically."
  print_info "To re-enable: ./tools/start-optimizations.sh or ./tools/enable-optimizations.sh"
fi

print_success "All optimization services stopped"
