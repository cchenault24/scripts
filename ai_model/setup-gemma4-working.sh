#!/bin/bash
#
# Setup Gemma 4 26B with llama.cpp + OpenCode (Working Configuration)
#
# Based on: https://gist.github.com/daniel-farina/87dc1c394b94e45bb700d27e9ea03193
#
# This script implements a proven working setup that avoids:
# - Ollama tool calling bugs (#15241)
# - OpenCode local provider issues (#20669, #20719)
#
# Requirements:
# - macOS Apple Silicon with 24GB+ RAM (32GB recommended)
# - Homebrew, git, gh CLI, cmake, bun installed
# - pipx will be installed automatically if missing
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
LLAMA_BUILD_DIR="/tmp/llama-cpp-build"
OPENCODE_BUILD_DIR="/tmp/opencode-build"
CONTEXT_SIZE="131072"  # Options: 32768, 65536, 131072
PORT="3456"
MODEL_REPO="ggml-org/gemma-4-26B-A4B-it-GGUF"
MODEL_FILE="gemma-4-26B-A4B-it-Q4_K_M.gguf"
AUTO_START="${AUTO_START:-true}"  # Set to false to skip auto-start
AUTO_START_ON_LOGIN="${AUTO_START_ON_LOGIN:-false}"  # Set to true for launchd

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Gemma 4 26B + llama.cpp + OpenCode Setup${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print status
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"
echo ""

MISSING_DEPS=()
for cmd in git gh cmake bun brew; do
    if command_exists "$cmd"; then
        print_status "$cmd installed"
    else
        print_error "$cmd not found"
        MISSING_DEPS+=("$cmd")
    fi
done

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo ""
    print_error "Missing dependencies: ${MISSING_DEPS[*]}"
    echo ""
    echo "Install them with:"
    echo "  brew install git gh cmake bun"
    exit 1
fi

# pipx will be installed in Step 0 if needed

echo ""

# Step 0: Setup HuggingFace CLI with SSL support
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Step 0: Setting up HuggingFace CLI${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if pipx is installed
if ! command_exists pipx; then
    print_info "Installing pipx..."
    brew install pipx
    pipx ensurepath
fi

# Check if huggingface-hub is installed via pipx
if ! pipx list 2>/dev/null | grep -q "huggingface-hub"; then
    print_info "Installing huggingface-hub via pipx..."
    pipx install huggingface-hub
else
    print_status "huggingface-hub already installed via pipx"
fi

# Check if pip-system-certs is injected
if pipx runpip huggingface-hub list 2>/dev/null | grep -q "pip_system_certs"; then
    print_status "SSL certificate support already enabled"
else
    print_info "Injecting pip-system-certs for SSL support..."
    pipx inject huggingface-hub pip-system-certs
    print_status "SSL certificate support enabled"
fi

# Verify hf command is available
if command_exists hf; then
    print_status "HuggingFace CLI ready"
    hf --version
else
    print_warning "hf command not in PATH - you may need to restart your shell"
    print_info "Or run: pipx ensurepath && source ~/.zshrc"
fi

echo ""

# Step 1: Build llama.cpp from source
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Step 1: Building llama.cpp with Gemma 4 fixes${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if already built
if [ -f "$LLAMA_BUILD_DIR/build/bin/llama-server" ]; then
    print_status "llama.cpp already built"
    "$LLAMA_BUILD_DIR/build/bin/llama-server" --version
    print_info "To rebuild, remove: $LLAMA_BUILD_DIR"
else
    if [ -d "$LLAMA_BUILD_DIR" ]; then
        print_warning "Removing incomplete build directory: $LLAMA_BUILD_DIR"
        rm -rf "$LLAMA_BUILD_DIR"
    fi

    print_info "Cloning llama.cpp..."
    git clone --depth 50 https://github.com/ggml-org/llama.cpp.git "$LLAMA_BUILD_DIR"
    cd "$LLAMA_BUILD_DIR"

    print_info "Cherry-picking PR #21343 (tokenizer fix)..."
    git fetch origin pull/21343/head:pr-21343
    git cherry-pick pr-21343 --no-commit || {
        print_warning "Cherry-pick had conflicts, resolving automatically..."
        git cherry-pick --continue || git cherry-pick --skip
    }

    print_info "Building llama.cpp with Metal support..."
    cmake -B build -DGGML_METAL=ON -DLLAMA_CURL=ON
    cmake --build build --config Release -j$(sysctl -n hw.ncpu) -- llama-server

    print_status "llama.cpp built successfully"
    "$LLAMA_BUILD_DIR/build/bin/llama-server" --version
fi

echo ""

# Step 2: Install OpenCode
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Step 2: Installing OpenCode${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

if [ ! -d "$HOME/.opencode" ]; then
    print_info "Installing OpenCode..."
    curl -fsSL https://opencode.ai/install -o /tmp/opencode-install.sh
    bash /tmp/opencode-install.sh
else
    print_status "OpenCode already installed"
fi

# Remove Homebrew version if exists
if brew list opencode &>/dev/null; then
    print_warning "Removing Homebrew version of OpenCode..."
    brew uninstall opencode
fi

print_status "OpenCode installed at: $(which opencode)"

echo ""

# Step 3: Build OpenCode from source with PR #16531
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Step 3: Building OpenCode with tool-call compat (PR #16531)${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if custom build marker exists
CUSTOM_BUILD_MARKER="$HOME/.opencode/bin/.custom-build-pr16531"

if [ -f "$CUSTOM_BUILD_MARKER" ]; then
    print_status "OpenCode custom build already installed"
    "$HOME/.opencode/bin/opencode" --version
    print_info "To rebuild, remove: $CUSTOM_BUILD_MARKER"
else
    if [ -d "$OPENCODE_BUILD_DIR" ]; then
        print_warning "Removing existing build directory: $OPENCODE_BUILD_DIR"
        rm -rf "$OPENCODE_BUILD_DIR"
    fi

    print_info "Cloning OpenCode repository..."
    git clone https://github.com/anomalyco/opencode.git "$OPENCODE_BUILD_DIR"
    cd "$OPENCODE_BUILD_DIR"

    print_info "Checking out PR #16531 (tool-call compatibility)..."
    gh pr checkout 16531

    print_info "Installing dependencies and building..."
    bun install
    cd packages/opencode
    bun run build -- --single --skip-install

    # Backup original if it exists and isn't already backed up
    if [ -f "$HOME/.opencode/bin/opencode" ] && [ ! -f "$HOME/.opencode/bin/opencode.backup" ]; then
        print_info "Backing up original OpenCode binary..."
        cp "$HOME/.opencode/bin/opencode" "$HOME/.opencode/bin/opencode.backup"
    fi

    print_info "Installing custom build..."
    cp dist/opencode-darwin-arm64/bin/opencode "$HOME/.opencode/bin/opencode"
    chmod +x "$HOME/.opencode/bin/opencode"

    # Create marker file to indicate custom build
    touch "$CUSTOM_BUILD_MARKER"

    print_status "OpenCode custom build installed"
    "$HOME/.opencode/bin/opencode" --version
fi

echo ""

# Step 4: Configure OpenCode
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Step 4: Creating OpenCode configuration${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

CONFIG_DIR="$HOME/.config/opencode"
mkdir -p "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR/prompts"

print_info "Creating opencode.json..."
cat > "$CONFIG_DIR/opencode.jsonc" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "llama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "llama.cpp (local)",
      "options": {
        "baseURL": "http://127.0.0.1:3456/v1",
        "toolParser": [
          { "type": "raw-function-call" },
          { "type": "json" }
        ]
      },
      "models": {
        "gemma4-26b": {
          "name": "Gemma 4 26B",
          "tool_call": true,
          "limit": {
            "context": 32768,
            "output": 8192
          }
        }
      }
    }
  },
  "model": "llama/gemma4-26b",
  "agent": {
    "build": {
      "prompt": "{file:./.opencode/prompts/build.txt}",
      "permission": {
        "edit": "allow",
        "bash": "allow",
        "webfetch": "allow"
      }
    }
  }
}
EOF

print_status "Created: $CONFIG_DIR/opencode.jsonc"

print_info "Creating AGENTS.md..."
cat > "$CONFIG_DIR/AGENTS.md" <<'EOF'
# OpenCode Agent Instructions

You are a coding assistant with FULL access to the user's file system and terminal through tools.

CRITICAL: You MUST use tools to complete tasks. NEVER say "I don't have access". NEVER suggest the user run commands. NEVER output code snippets instead of using tools. Always take action immediately.

## Tool Schemas (EXACT parameter names - you MUST use these exactly)

### bash
Execute shell commands.
Parameters (ALL required unless noted):
- `command` (string, REQUIRED): The shell command to run
- `description` (string, REQUIRED): Short description of what the command does (5-10 words)
- `timeout` (number, optional): Timeout in milliseconds
- `workdir` (string, optional): Working directory

Example: `{"command": "ls -la", "description": "List files in current directory"}`

### write
Create or overwrite a file.
Parameters (ALL required):
- `filePath` (string, REQUIRED): Absolute path to the file
- `content` (string, REQUIRED): The content to write

Example: `{"filePath": "/Users/web/project/hello.txt", "content": "Hello world"}`

### read
Read a file.
Parameters:
- `filePath` (string, REQUIRED): Absolute path to the file
- `offset` (number, optional): Line number to start from
- `limit` (number, optional): Max lines to read

Example: `{"filePath": "/Users/web/project/hello.txt"}`

### edit
Modify an existing file by replacing text.
Parameters:
- `filePath` (string, REQUIRED): Absolute path to the file
- `oldString` (string, REQUIRED): The exact text to find and replace
- `newString` (string, REQUIRED): The replacement text
- `replaceAll` (boolean, optional): Replace all occurrences

Example: `{"filePath": "/path/to/file.ts", "oldString": "foo", "newString": "bar"}`

### glob
Find files by pattern.
Parameters:
- `pattern` (string, REQUIRED): Glob pattern like `**/*.ts`
- `path` (string, optional): Directory to search in

### grep
Search file contents.
Parameters:
- `pattern` (string, REQUIRED): Regex pattern to search for
- `path` (string, optional): Directory to search in
- `include` (string, optional): File pattern filter like `*.js`

### todowrite
Track tasks and progress. The `todos` parameter MUST be a JSON array of objects, NOT a string.
Parameters:
- `todos` (array of objects, REQUIRED): Each object has:
  - `content` (string, REQUIRED): Brief description of the task
  - `status` (string, REQUIRED): One of: `pending`, `in_progress`, `completed`, `cancelled`
  - `priority` (string, REQUIRED): One of: `high`, `medium`, `low`

Example: `{"todos": [{"content": "Add game over screen", "status": "in_progress", "priority": "high"}, {"content": "Add sound effects", "status": "pending", "priority": "low"}]}`

IMPORTANT: `todos` MUST be an array `[...]`, NOT a string `"[...]"`. Never stringify the array.

## IMPORTANT REMINDERS

- The `bash` tool REQUIRES both `command` AND `description` fields. Always include both.
- The `write` tool parameter is `filePath` (camelCase), NOT `file_path`.
- The `edit` tool uses `oldString`/`newString` (camelCase), NOT `old_string`/`new_string`.
- Do NOT call tools that don't exist. Available tools: bash, read, write, edit, glob, grep, task, webfetch, todowrite, question, skill.
- There is NO `list` tool. To list files use `bash` with `ls`.
EOF

print_status "Created: $CONFIG_DIR/AGENTS.md"

print_info "Creating build.txt prompt..."
cat > "$CONFIG_DIR/prompts/build.txt" <<'EOF'
You are a coding assistant with FULL access to the user's file system and terminal through tools.

CRITICAL RULES:
1. You MUST use tools to complete tasks. NEVER say "I don't have access".
2. NEVER suggest the user run commands - YOU run them using your tools.
3. NEVER output code snippets as your answer - USE the tools to create/edit files.
4. Call the appropriate tool IMMEDIATELY when action is needed.

TOOL PARAMETER REFERENCE (use these exact names):

bash: {"command": "ls -la", "description": "List files in directory"}
  - command (REQUIRED string): the shell command
  - description (REQUIRED string): 5-10 word description of what the command does

write: {"filePath": "/absolute/path/file.txt", "content": "file content here"}
  - filePath (REQUIRED string, camelCase): absolute path to the file
  - content (REQUIRED string): the content to write

read: {"filePath": "/absolute/path/file.txt"}
  - filePath (REQUIRED string, camelCase): absolute path

edit: {"filePath": "/path/file.txt", "oldString": "old text", "newString": "new text"}
  - filePath (REQUIRED string, camelCase)
  - oldString (REQUIRED string, camelCase): exact text to find
  - newString (REQUIRED string, camelCase): replacement text

glob: {"pattern": "**/*.ts"}
  - pattern (REQUIRED string): glob pattern

grep: {"pattern": "searchRegex"}
  - pattern (REQUIRED string): regex pattern

todowrite: {"todos": [{"content": "task description", "status": "pending", "priority": "high"}]}
  - todos (REQUIRED array of objects, NOT a string): each object has content, status, priority
  - status: one of "pending", "in_progress", "completed", "cancelled"
  - priority: one of "high", "medium", "low"
  - CRITICAL: todos MUST be an array [...], NEVER a string "[...]"

IMPORTANT:
- bash REQUIRES both "command" AND "description" parameters. Always include both.
- Use camelCase for all parameter names: filePath, oldString, newString, replaceAll
- Do NOT call tools that don't exist. There is NO "list" tool. Use bash with ls instead.
- Always take action. Never just describe what could be done.
EOF

print_status "Created: $CONFIG_DIR/prompts/build.txt"

echo ""

# Step 5: Download Gemma 4 Model
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Step 5: Downloading Gemma 4 26B Model${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Initialize variable
MODEL_FULL_PATH=""

# Check if model is already cached
HF_CACHE_DIR="$HOME/.cache/huggingface/hub"
MODEL_CACHE_PATH="$HF_CACHE_DIR/models--ggml-org--gemma-4-26B-A4B-it-GGUF"

if [ -d "$MODEL_CACHE_PATH" ]; then
    print_status "Model already cached at: $MODEL_CACHE_PATH"
    # Verify the specific file exists
    MODEL_FILE_PATH=$(find "$MODEL_CACHE_PATH" -name "$MODEL_FILE" 2>/dev/null | head -n 1)
    if [ -n "$MODEL_FILE_PATH" ]; then
        print_status "Found model file: $MODEL_FILE"
        MODEL_FULL_PATH="$MODEL_FILE_PATH"
    else
        print_warning "Model directory exists but file not found, re-downloading..."
        rm -rf "$MODEL_CACHE_PATH"
    fi
fi

if [ -z "$MODEL_FULL_PATH" ]; then
    print_info "Downloading $MODEL_FILE (~16GB)..."
    print_info "This may take 10-30 minutes depending on your connection"
    echo ""

    # Check for HF_TOKEN
    if [ -z "${HF_TOKEN:-}" ]; then
        print_warning "HF_TOKEN not set - download may be slower"
        print_info "To speed up future downloads: export HF_TOKEN=your_token"
    fi

    # Download model using pipx-installed hf CLI (with SSL support)
    print_info "Using HuggingFace CLI to download model..."

    # Try pipx hf first (has SSL support), then fallback
    if command_exists hf; then
        hf download "$MODEL_REPO" "$MODEL_FILE" || {
            print_error "Download failed with hf command"
            exit 1
        }
    else
        print_error "hf command not found - this should not happen after Step 0"
        print_info "Try running: pipx ensurepath && source ~/.zshrc"
        exit 1
    fi

    # Find the downloaded file
    MODEL_FILE_PATH=$(find "$MODEL_CACHE_PATH" -name "$MODEL_FILE" 2>/dev/null | head -n 1)
    if [ -n "$MODEL_FILE_PATH" ]; then
        print_status "Model downloaded successfully"
        MODEL_FULL_PATH="$MODEL_FILE_PATH"
    else
        print_error "Model download failed or file not found"
        exit 1
    fi
fi

echo ""

# Step 6: Start llama-server (if AUTO_START is true)
if [ "$AUTO_START" = "true" ]; then
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Step 6: Starting llama-server${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Create log directory
    LOG_DIR="$HOME/.local/var/log"
    mkdir -p "$LOG_DIR"

    # Check if llama-server is already running
    if lsof -ti:$PORT >/dev/null 2>&1; then
        print_warning "Port $PORT is already in use"
        print_info "Killing existing process..."
        lsof -ti:$PORT | xargs kill -9
        sleep 2
    fi

    print_info "Starting llama-server on port $PORT..."
    print_info "Context size: $CONTEXT_SIZE tokens"
    print_info "Log file: $LOG_DIR/llama-server.log"
    echo ""

    # Start llama-server in background
    nohup "$LLAMA_BUILD_DIR/build/bin/llama-server" \
        -m "$MODEL_FULL_PATH" \
        --port "$PORT" \
        -ngl 99 \
        -c "$CONTEXT_SIZE" \
        --jinja \
        > "$LOG_DIR/llama-server.log" 2>&1 &

    LLAMA_PID=$!
    echo "$LLAMA_PID" > "$HOME/.local/var/llama-server.pid"

    print_status "llama-server started (PID: $LLAMA_PID)"
    print_info "Waiting for server to be ready..."

    # Wait for health check (up to 60 seconds)
    TIMEOUT=60
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        if curl -s -f "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
            print_status "llama-server is ready!"
            echo ""
            curl -s "http://127.0.0.1:$PORT/health"
            echo ""
            break
        fi
        sleep 2
        ELAPSED=$((ELAPSED + 2))
        if [ $((ELAPSED % 10)) -eq 0 ]; then
            print_info "Still waiting... ($ELAPSED/${TIMEOUT}s)"
        fi
    done

    if [ $ELAPSED -ge $TIMEOUT ]; then
        print_warning "Server did not respond within ${TIMEOUT}s"
        print_info "Check logs: tail -f $LOG_DIR/llama-server.log"
    fi

    echo ""

    # Optionally create launchd plist for auto-start on login
    if [ "$AUTO_START_ON_LOGIN" = "true" ]; then
        PLIST_DIR="$HOME/Library/LaunchAgents"
        PLIST_FILE="$PLIST_DIR/com.llamacpp.server.plist"
        mkdir -p "$PLIST_DIR"

        # Check if already loaded
        if launchctl list | grep -q "com.llamacpp.server"; then
            print_status "launchd service already loaded"
            print_info "To reload, run: launchctl unload $PLIST_FILE && launchctl load $PLIST_FILE"
        else
            print_info "Creating launchd plist for auto-start on login..."

            cat > "$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.llamacpp.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>$LLAMA_BUILD_DIR/build/bin/llama-server</string>
        <string>-m</string>
        <string>$MODEL_FULL_PATH</string>
        <string>--port</string>
        <string>$PORT</string>
        <string>-ngl</string>
        <string>99</string>
        <string>-c</string>
        <string>$CONTEXT_SIZE</string>
        <string>--jinja</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/llama-server.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/llama-server.log</string>
</dict>
</plist>
EOF

            launchctl load "$PLIST_FILE"
            print_status "Created launchd service: $PLIST_FILE"
            print_info "llama-server will start automatically on login"
        fi
    fi

    echo ""
fi

# Final instructions
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""
print_status "llama.cpp built at: $LLAMA_BUILD_DIR/build/bin/llama-server"
print_status "OpenCode custom build installed"
print_status "Configuration created at: $CONFIG_DIR"

if [ "$AUTO_START" = "true" ]; then
    print_status "Gemma 4 26B model downloaded"
    if [ -n "${LLAMA_PID:-}" ]; then
        print_status "llama-server running on port $PORT (PID: $LLAMA_PID)"
    else
        print_status "llama-server on port $PORT"
    fi
fi

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""

if [ "$AUTO_START" = "true" ]; then
    echo "✅ llama-server is already running and ready!"
    echo ""
    echo "To verify the server:"
    echo -e "   ${GREEN}curl http://127.0.0.1:$PORT/health${NC}"
    echo ""
    echo "To view logs:"
    echo -e "   ${GREEN}tail -f $LOG_DIR/llama-server.log${NC}"
    echo ""
    echo "To stop the server:"
    echo -e "   ${GREEN}kill \$(cat $HOME/.local/var/llama-server.pid)${NC}"
    echo ""
    echo "To restart the server manually:"
    echo -e "   ${GREEN}$LLAMA_BUILD_DIR/build/bin/llama-server \\${NC}"
    echo -e "   ${GREEN}  -m $MODEL_FULL_PATH \\${NC}"
    echo -e "   ${GREEN}  --port $PORT -ngl 99 -c $CONTEXT_SIZE --jinja${NC}"
    echo ""
    echo "Ready to use OpenCode! In your project directory:"
    echo -e "   ${GREEN}cd /path/to/your/project${NC}"
    echo -e "   ${GREEN}opencode${NC}"
else
    echo "1. Start llama-server in a new terminal:"
    echo ""
    echo -e "   ${GREEN}$LLAMA_BUILD_DIR/build/bin/llama-server \\${NC}"
    echo -e "   ${GREEN}  -m $MODEL_FULL_PATH \\${NC}"
    echo -e "   ${GREEN}  --port $PORT -ngl 99 -c $CONTEXT_SIZE --jinja${NC}"
    echo ""
    echo "2. Wait for 'listening on http://127.0.0.1:$PORT', then verify:"
    echo ""
    echo -e "   ${GREEN}curl http://127.0.0.1:$PORT/health${NC}"
    echo ""
    echo "3. Run OpenCode in your project directory:"
    echo ""
    echo -e "   ${GREEN}cd /path/to/your/project${NC}"
    echo -e "   ${GREEN}opencode${NC}"
fi

echo ""
print_info "Context sizes: 32768 (~17GB), 65536 (~20GB), 131072 (~25GB)"
print_info "For 16GB Macs, use gemma-4-E4B-it-GGUF:Q4_K_M instead"
echo ""
echo -e "${BLUE}Documentation: https://gist.github.com/daniel-farina/87dc1c394b94e45bb700d27e9ea03193${NC}"
echo ""
