#!/bin/bash
#
# Kill all ollama processes and remove Homebrew installation
#

set -euo pipefail

echo "🛑 Stopping and removing Homebrew Ollama..."
echo ""

# 1. Stop and uninstall Homebrew Ollama
if brew list ollama &>/dev/null; then
    echo "Uninstalling Homebrew Ollama..."
    brew services stop ollama 2>/dev/null || true
    brew uninstall ollama 2>/dev/null || true
    echo "✓ Homebrew Ollama uninstalled"
else
    echo "✓ No Homebrew Ollama installation found"
fi

# Also stop service if it's still registered
if launchctl list | grep -q homebrew.mxcl.ollama 2>/dev/null; then
    launchctl unload ~/Library/LaunchAgents/homebrew.mxcl.ollama.plist 2>/dev/null || true
    echo "✓ Homebrew Ollama service unloaded"
fi

# 2. Kill all ollama processes
OLLAMA_PIDS=$(pgrep ollama 2>/dev/null || true)
if [ -n "$OLLAMA_PIDS" ]; then
    echo ""
    echo "Killing ollama processes: $OLLAMA_PIDS"
    echo "$OLLAMA_PIDS" | xargs kill -9 2>/dev/null || true
    sleep 2
    echo "✓ All ollama processes killed"
else
    echo "✓ No ollama processes found"
fi

# 3. Clean up PID file
rm -f ~/.local/var/ollama-server.pid

# 4. Verify nothing is running
echo ""
echo "Verification:"
if pgrep ollama >/dev/null 2>&1; then
    echo "⚠️  Warning: Some ollama processes still running:"
    ps aux | grep ollama | grep -v grep
else
    echo "✓ No ollama processes running"
fi

# 5. Check ports
echo ""
echo "Port check:"
if lsof -i :3456 >/dev/null 2>&1; then
    echo "⚠️  Port 3456 still in use"
else
    echo "✓ Port 3456 available"
fi

if lsof -i :11434 >/dev/null 2>&1; then
    echo "⚠️  Port 11434 still in use"
else
    echo "✓ Port 11434 available"
fi

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "To start Ollama properly, use:"
echo "  ./llama-control.sh start"
