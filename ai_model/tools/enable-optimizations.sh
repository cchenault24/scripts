#!/bin/bash
#
# enable-optimizations.sh - Enable auto-start for optimization services
#
# This script explicitly enables auto-start without starting services.
# To start services immediately, use start-optimizations.sh instead.
#
# Usage:
#   ./tools/enable-optimizations.sh [--start]
#
# Options:
#   --start    Also start services immediately after enabling

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load library functions
source "$PROJECT_DIR/lib/constants.sh" 2>/dev/null || true
source "$PROJECT_DIR/lib/logger.sh" 2>/dev/null || true
source "$PROJECT_DIR/lib/ui.sh" 2>/dev/null || true
source "$PROJECT_DIR/lib/optimization.sh" 2>/dev/null || true

# Fallback print functions if sourcing failed
if ! command -v print_header &>/dev/null; then
  print_header() { echo ""; echo "═══════════════════════════════════════════════════════════"; echo "$1"; echo "═══════════════════════════════════════════════════════════"; echo ""; }
  print_success() { echo "✓ $1"; }
  print_info() { echo "ℹ $1"; }
fi

print_header "🔓 Enabling Auto-Start for Optimizations"

# Check if already enabled
if ! is_auto_start_disabled 2>/dev/null; then
  print_info "Auto-start is already enabled"
else
  # Enable auto-start
  if command -v enable_auto_start &>/dev/null; then
    enable_auto_start
    print_success "Auto-start enabled"
  else
    # Fallback: remove flag file directly
    if [[ -f "$HOME/.local-llm-setup/optimizations.disabled" ]]; then
      rm -f "$HOME/.local-llm-setup/optimizations.disabled"
      print_success "Auto-start enabled"
    else
      print_info "Auto-start was already enabled"
    fi
  fi
fi

# Check if user wants to start services immediately
if [[ "${1:-}" == "--start" ]]; then
  echo ""
  print_info "Starting optimization services..."
  if [[ -f "$SCRIPT_DIR/start-optimizations.sh" ]]; then
    "$SCRIPT_DIR/start-optimizations.sh"
  else
    print_info "start-optimizations.sh not found"
  fi
else
  echo ""
  print_info "Auto-start is now enabled. Services will start automatically when needed."
  print_info "To start services now: ./tools/start-optimizations.sh"
fi
