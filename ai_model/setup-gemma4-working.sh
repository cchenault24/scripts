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
# - Homebrew, git, gh CLI installed
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
CONTEXT_SIZE="32768"  # Options: 32768, 65536, 131072
PORT="8089"

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

echo ""

# Step 1: Build llama.cpp from source
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Step 1: Building llama.cpp with Gemma 4 fixes${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

if [ -d "$LLAMA_BUILD_DIR" ]; then
    print_warning "Removing existing build directory: $LLAMA_BUILD_DIR"
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

# Backup and install
if [ -f "$HOME/.opencode/bin/opencode" ]; then
    print_info "Backing up original OpenCode binary..."
    cp "$HOME/.opencode/bin/opencode" "$HOME/.opencode/bin/opencode.backup"
fi

print_info "Installing custom build..."
cp dist/opencode-darwin-arm64/bin/opencode "$HOME/.opencode/bin/opencode"
chmod +x "$HOME/.opencode/bin/opencode"

print_status "OpenCode custom build installed"
"$HOME/.opencode/bin/opencode" --version

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
        "baseURL": "http://127.0.0.1:8089/v1",
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

# Final instructions
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""
print_status "llama.cpp built at: $LLAMA_BUILD_DIR/build/bin/llama-server"
print_status "OpenCode custom build installed"
print_status "Configuration created at: $CONFIG_DIR"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "1. Start llama-server in a new terminal:"
echo ""
echo -e "   ${GREEN}$LLAMA_BUILD_DIR/build/bin/llama-server \\${NC}"
echo -e "   ${GREEN}  -hf ggml-org/gemma-4-26B-A4B-it-GGUF:Q4_K_M \\${NC}"
echo -e "   ${GREEN}  --port $PORT -ngl 99 -c $CONTEXT_SIZE --jinja${NC}"
echo ""
echo "2. Wait for 'listening on http://127.0.0.1:8089', then verify:"
echo ""
echo -e "   ${GREEN}curl http://127.0.0.1:$PORT/health${NC}"
echo ""
echo "3. Run OpenCode in your project directory:"
echo ""
echo -e "   ${GREEN}cd /path/to/your/project${NC}"
echo -e "   ${GREEN}opencode${NC}"
echo ""
print_info "Context sizes: 32768 (~17GB), 65536 (~20GB), 131072 (~25GB)"
print_info "For 16GB Macs, use gemma-4-E4B-it-GGUF:Q4_K_M instead"
echo ""
echo -e "${BLUE}Documentation: https://gist.github.com/daniel-farina/87dc1c394b94e45bb700d27e9ea03193${NC}"
echo ""
