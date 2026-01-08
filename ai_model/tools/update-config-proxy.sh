#!/bin/bash
#
# update-config-proxy.sh - Update Continue.dev config to use optimization proxy
#
# Updates existing ~/.continue/config.yaml to use proxy (port 11435) if running

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_DIR/lib/constants.sh"
source "$PROJECT_DIR/lib/logger.sh"
source "$PROJECT_DIR/lib/ui.sh"

CONFIG_FILE="$HOME/.continue/config.yaml"
BACKUP_FILE="${CONFIG_FILE}.backup-$(date +%Y%m%d-%H%M%S)"

print_header "🔄 Updating Continue.dev Config for Proxy"

# Check if proxy is running
local proxy_running=false
if [[ -f "$HOME/.local-llm-setup/pids/ollama_proxy.pid" ]]; then
  local proxy_pid
  proxy_pid=$(cat "$HOME/.local-llm-setup/pids/ollama_proxy.pid" 2>/dev/null || echo "")
  if [[ -n "$proxy_pid" ]] && kill -0 "$proxy_pid" 2>/dev/null; then
    proxy_running=true
    print_success "Proxy is running (PID: $proxy_pid)"
  else
    print_warn "Proxy PID file exists but process not running"
    rm -f "$HOME/.local-llm-setup/pids/ollama_proxy.pid"
  fi
fi

if [[ "$proxy_running" != "true" ]]; then
  # Test if proxy is responding (might be running but PID file missing)
  if curl -s http://localhost:11435/api/tags &>/dev/null; then
    proxy_running=true
    print_success "Proxy is responding on port 11435"
  else
    print_warn "Proxy is not running"
    print_info "Start it with: ./tools/start-optimizations.sh --proxy"
    exit 1
  fi
fi

# Check if config exists
if [[ ! -f "$CONFIG_FILE" ]]; then
  print_error "Continue.dev config not found: $CONFIG_FILE"
  print_info "Run setup script first: ./setup-local-llm.sh"
  exit 1
fi

# Backup config
cp "$CONFIG_FILE" "$BACKUP_FILE"
print_info "Backed up config to: $BACKUP_FILE"

# Update config to use proxy
if command -v python3 &>/dev/null; then
  # Use Python for YAML editing (more reliable)
  python3 <<PYTHON_SCRIPT
import re
import sys

config_file = "$CONFIG_FILE"
backup_file = "$BACKUP_FILE"

try:
    with open(config_file, 'r') as f:
        content = f.read()
    
    # Replace apiBase: http://localhost:11434 with 11435
    updated = re.sub(
        r'apiBase:\s*http://localhost:11434',
        'apiBase: http://localhost:11435',
        content
    )
    
    if updated != content:
        with open(config_file, 'w') as f:
            f.write(updated)
        print("✓ Config updated to use proxy (port 11435)")
        sys.exit(0)
    else:
        print("ℹ Config already uses proxy or no apiBase found")
        sys.exit(0)
except Exception as e:
    print(f"✗ Error updating config: {e}")
    sys.exit(1)
PYTHON_SCRIPT
  exit_code=$?
  
  if [[ $exit_code -eq 0 ]]; then
    print_success "Continue.dev config updated"
    print_info "Restart VS Code (Cmd+Q) to apply changes"
  else
    print_error "Failed to update config"
    exit 1
  fi
else
  # Fallback: use sed
  if sed -i.bak 's|apiBase: http://localhost:11434|apiBase: http://localhost:11435|g' "$CONFIG_FILE" 2>/dev/null; then
    rm -f "${CONFIG_FILE}.bak"
    print_success "Continue.dev config updated"
    print_info "Restart VS Code (Cmd+Q) to apply changes"
  else
    print_error "Failed to update config (sed failed)"
    print_info "Manually edit $CONFIG_FILE and change:"
    print_info "  apiBase: http://localhost:11434"
    print_info "  to:"
    print_info "  apiBase: http://localhost:11435"
    exit 1
  fi
fi

# Verify update
if grep -q "apiBase: http://localhost:11435" "$CONFIG_FILE"; then
  print_success "Verification: Config now uses proxy"
else
  print_warn "Verification: Config may not have been updated correctly"
  print_info "Please check $CONFIG_FILE manually"
fi
