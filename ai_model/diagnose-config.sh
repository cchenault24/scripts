#!/bin/bash
# diagnose-config.sh - Diagnose configuration issues

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

print_header "Configuration Diagnostics"

# Check environment variables
echo ""
print_info "Environment Variables:"
echo "  PORT: ${PORT:-<not set>}"
echo "  OLLAMA_HOST: ${OLLAMA_HOST:-<not set>}"
echo "  OLLAMA_MODEL: ${OLLAMA_MODEL:-<not set>}"

# Check if Ollama is running
echo ""
print_info "Ollama Server Status:"
if pgrep -x "ollama" > /dev/null; then
    echo "  ✓ Ollama process is running"

    # Try to connect
    if curl -sf http://127.0.0.1:31434/api/tags > /dev/null 2>&1; then
        echo "  ✓ Ollama API responding on port 31434"

        # List models
        echo ""
        print_info "Installed Models:"
        curl -s http://127.0.0.1:31434/api/tags | python3 -c "
import json, sys
data = json.load(sys.stdin)
for model in data.get('models', []):
    print(f'  - {model[\"name\"]}')
" 2>/dev/null || echo "  (unable to parse)"
    else
        echo "  ✗ Ollama API not responding on port 31434"
    fi
else
    echo "  ✗ Ollama process not running"
fi

# Check OpenCode config
echo ""
print_info "OpenCode Configuration:"
if [[ -f "$HOME/.config/opencode/opencode.jsonc" ]]; then
    echo "  ✓ Config file exists"
    echo "  Model configured:"
    grep '"model"' "$HOME/.config/opencode/opencode.jsonc" | head -2
else
    echo "  ✗ Config file not found"
fi

if [[ -f "$HOME/.local/share/opencode/auth.json" ]]; then
    echo "  ✓ Auth file exists"
    echo "  Provider:"
    cat "$HOME/.local/share/opencode/auth.json"
else
    echo "  ✗ Auth file not found"
fi

# Check Continue.dev config
echo ""
print_info "Continue.dev Configuration:"
if [[ -f "$HOME/.continue/config.json" ]]; then
    echo "  ✓ Config file exists"
    echo "  Models configured:"
    python3 -c "
import json
try:
    with open('$HOME/.continue/config.json') as f:
        config = json.load(f)
        for model in config.get('models', []):
            print(f'  - {model.get(\"title\")}: {model.get(\"model\")}')
            print(f'    API URL: {model.get(\"apiUrl\")}')
except Exception as e:
    print(f'  Error parsing: {e}')
" 2>/dev/null || echo "  (unable to parse)"
else
    echo "  ✗ Config file not found"
fi

# Test model detection
echo ""
print_info "Testing Model Detection:"
if command -v ollama &> /dev/null; then
    echo "  ✓ ollama command available"

    # Test with OLLAMA_HOST set
    export OLLAMA_HOST="127.0.0.1:31434"
    if timeout 5 ollama list &> /dev/null; then
        echo "  ✓ ollama list works with OLLAMA_HOST=127.0.0.1:31434"
        ollama list | head -5
    else
        echo "  ✗ ollama list failed or timed out"
    fi
else
    echo "  ✗ ollama command not available"
fi

# Summary
echo ""
print_header "Summary"
echo "If you see issues above, try:"
echo "  1. Ensure Ollama is running: ./llama-control.sh start"
echo "  2. Set environment: export OLLAMA_HOST=127.0.0.1:31434"
echo "  3. Regenerate configs: ./setup.sh --unattended"
