#!/bin/bash
# lib/launchagent.sh - macOS LaunchAgent configuration for Ollama
#
# Provides:
# - LaunchAgent plist creation with hardware-optimized settings
# - LaunchAgent loading/unloading
# - Ollama server readiness checks

set -euo pipefail

# Create and load Ollama LaunchAgent with hardware-optimized settings
#
# Globals read:
#   - LAUNCHAGENT_LABEL: LaunchAgent identifier
#   - LAUNCHAGENT_PLIST: Path to plist file
#   - METAL_MEMORY: Calculated Metal memory allocation
#   - NUM_PARALLEL: Calculated parallel request count
#   - CONTEXT_LENGTH: Selected context length
#   - NUM_CTX: Same as CONTEXT_LENGTH (Ollama parameter name)
#   - OLLAMA_HOST: Ollama server URL
create_launchagent() {
    print_header "Step 3: Configuring Ollama LaunchAgent"

    # Create LaunchAgents directory if it doesn't exist
    mkdir -p "$HOME/Library/LaunchAgents"

    # Check if LaunchAgent already exists and is loaded
    local needs_reload=false
    if [[ -f "$LAUNCHAGENT_PLIST" ]]; then
        print_info "LaunchAgent already exists at $LAUNCHAGENT_PLIST"

        # Check if it's already loaded
        if launchctl list | grep -q "$LAUNCHAGENT_LABEL"; then
            print_info "Unloading existing LaunchAgent..."
            launchctl unload "$LAUNCHAGENT_PLIST" 2>/dev/null || true
            sleep 2
        fi
        needs_reload=true
    fi

    # Detect Homebrew prefix (handles both Intel and Apple Silicon)
    local brew_prefix
    brew_prefix=$(brew --prefix)

    print_info "Creating dynamically optimized LaunchAgent configuration..."
    print_info "Optimizations based on your hardware:"
    echo "  • Metal Memory:     $(format_bytes "$METAL_MEMORY")"
    echo "  • Parallel Requests: $NUM_PARALLEL"
    echo "  • Context Length:    $(printf "%'d" "$CONTEXT_LENGTH") tokens"
    echo "  • GPU Layers:        All (999)"
    echo ""

    # Create log directory
    mkdir -p "$HOME/.local/var/log"

    cat > "$LAUNCHAGENT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LAUNCHAGENT_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${brew_prefix}/bin/ollama</string>
        <string>serve</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>OLLAMA_HOST</key>
        <string>127.0.0.1:11434</string>
        <key>OLLAMA_METAL_MEMORY</key>
        <string>${METAL_MEMORY}</string>
        <key>OLLAMA_KEEP_ALIVE</key>
        <string>-1</string>
        <key>OLLAMA_NUM_PARALLEL</key>
        <string>${NUM_PARALLEL}</string>
        <key>OLLAMA_FLASH_ATTENTION</key>
        <string>1</string>
        <key>OLLAMA_GPU_LAYERS</key>
        <string>999</string>
        <key>OLLAMA_CONTEXT_LENGTH</key>
        <string>${CONTEXT_LENGTH}</string>
        <key>OLLAMA_NUM_CTX</key>
        <string>${NUM_CTX}</string>
    </dict>
    <key>StandardOutPath</key>
    <string>$HOME/.local/var/log/ollama.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.local/var/log/ollama.stderr.log</string>
</dict>
</plist>
EOF

    print_status "LaunchAgent configuration created with hardware-optimized settings"

    # Validate plist syntax
    if ! plutil -lint "$LAUNCHAGENT_PLIST" > /dev/null 2>&1; then
        print_error "LaunchAgent plist validation failed"
        print_info "This is a bug - please report to the maintainer"
        exit 1
    fi
    print_status "LaunchAgent plist validated successfully"

    # Load the LaunchAgent
    print_info "Loading LaunchAgent (starts Ollama)..."
    launchctl load "$LAUNCHAGENT_PLIST"

    if [[ "$needs_reload" == true ]]; then
        print_status "LaunchAgent reloaded with new configuration"
    else
        print_status "LaunchAgent loaded - Ollama will start automatically on boot"
    fi

    # Wait for Ollama to be ready
    wait_for_ollama_ready
}

# Wait for Ollama server to be ready
#
# Globals read:
#   - OLLAMA_HOST: Ollama server URL
wait_for_ollama_ready() {
    print_info "Waiting for Ollama server to be ready..."
    local max_attempts=60
    local attempt=0
    while ! curl -s "$OLLAMA_HOST/api/tags" > /dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            print_error "Ollama server failed to start after ${max_attempts} seconds"
            print_info "Check logs: tail -f $HOME/.local/var/log/ollama.stdout.log $HOME/.local/var/log/ollama.stderr.log"
            exit 1
        fi
        sleep 1
    done
    print_status "Ollama server is ready"
}
