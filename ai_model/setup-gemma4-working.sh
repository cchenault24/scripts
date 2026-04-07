#!/bin/bash
#
# Setup Gemma 4 with Ollama + OpenCode
#
# This script builds Ollama and OpenCode from the latest commits and configures them together
# The script will detect your system RAM and help you choose the best model
#
# Usage:
#   # Interactive mode (recommended) - script will help you choose a model
#   ./setup-gemma4-working.sh
#
#   # Skip interactive selection by setting model via environment variable
#   OLLAMA_MODEL=gemma4:26b-a4b-it-q4_K_M ./setup-gemma4-working.sh
#   OLLAMA_MODEL=gemma4:e4b-it-q8_0 ./setup-gemma4-working.sh
#
#   # Build OpenCode from latest dev branch commit (bleeding edge)
#   BUILD_OPENCODE_FROM_SOURCE=true ./setup-gemma4-working.sh
#
#   # Skip embedding model installation (for small codebases)
#   INSTALL_EMBEDDING_MODEL=false ./setup-gemma4-working.sh
#
# Available models: https://ollama.com/library/gemma4/tags
#   Small (128K context):  e2b variants (7-8GB, q4_K_M or q8_0)
#   Medium (128K context): e4b variants (9-12GB, q4_K_M or q8_0)
#   Large (256K context):  26b variants (18-28GB, q4_K_M or q8_0)
#   XL (256K context):     31b variants (20-34GB, q4_K_M or q8_0)
#
#   Recommendations by RAM:
#   16GB RAM:  gemma4:e2b-it-q4_K_M or e4b-it-q4_K_M
#   24GB RAM:  gemma4:26b-a4b-it-q4_K_M or e4b-it-q8_0
#   32GB RAM:  gemma4:26b-a4b-it-q8_0 or 31b-it-q4_K_M
#   48GB+ RAM: gemma4:31b-it-q8_0
#
# What gets built from source:
#   • Ollama: Always built from latest commit on main branch with full Apple Silicon optimizations:
#     - Metal GPU acceleration (via CGO)
#     - Accelerate framework for BLAS
#     - Native ARM64 CPU optimizations (-O3 -march=native)
#   • OpenCode: Official release by default, or latest dev branch with BUILD_OPENCODE_FROM_SOURCE=true
#
# Requirements:
# - macOS Apple Silicon with 24GB+ RAM (32GB recommended)
# - Homebrew (for automatic dependency installation)
# - Internet connection (dependencies installed automatically)
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Configuration
OLLAMA_BUILD_DIR="/tmp/ollama-build"
OPENCODE_BUILD_DIR="/tmp/opencode-build"
PORT="3456"

# Model will be selected interactively based on hardware
OLLAMA_MODEL=""

AUTO_START="${AUTO_START:-true}"  # Set to false to skip auto-start
AUTO_START_ON_LOGIN="${AUTO_START_ON_LOGIN:-false}"  # Set to true for launchd
BUILD_OPENCODE_FROM_SOURCE="${BUILD_OPENCODE_FROM_SOURCE:-false}"  # Set to true to build from source
INSTALL_EMBEDDING_MODEL="${INSTALL_EMBEDDING_MODEL:-true}"  # Set to false to skip embedding model

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

# Detect system RAM (in GB) - global variable
TOTAL_RAM_MB=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024)}')
TOTAL_RAM_GB=$((TOTAL_RAM_MB / 1024))

# Function to detect RAM and recommend models
select_model() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Model Selection${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""

    print_info "Detected system RAM: ${TOTAL_RAM_GB}GB"
    echo ""

    # Check for already installed models
    INSTALLED_MODELS=""

    # Try 1: Check if server is already running
    if curl -s -m 2 http://127.0.0.1:$PORT/api/tags >/dev/null 2>&1; then
        print_info "Checking already installed models (server running)..."
        INSTALLED_MODELS=$(curl -s http://127.0.0.1:$PORT/api/tags | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | grep "^gemma4:" || true)
    # Try 2: Check Ollama model directory directly
    elif [ -d "$HOME/.ollama/models/manifests/registry.ollama.ai/library" ]; then
        print_info "Checking already installed models (local storage)..."
        INSTALLED_MODELS=$(find "$HOME/.ollama/models/manifests/registry.ollama.ai/library" -type d -name "gemma4" 2>/dev/null | while read -r dir; do
            if [ -d "$dir" ]; then
                find "$dir" -type f 2>/dev/null | while read -r file; do
                    basename "$(dirname "$file")" | sed 's/^/gemma4:/'
                done
            fi
        done | sort -u || true)
    # Try 3: Use ollama binary if it exists
    elif [ -f "$OLLAMA_BUILD_DIR/ollama" ]; then
        print_info "Checking already installed models (ollama list)..."
        INSTALLED_MODELS=$("$OLLAMA_BUILD_DIR/ollama" list 2>/dev/null | grep "^gemma4:" | awk '{print $1}' || true)
    fi

    if [ -n "$INSTALLED_MODELS" ]; then
        echo ""
        echo -e "${GREEN}Already Installed:${NC}"
        echo "$INSTALLED_MODELS" | while IFS= read -r model; do
            # Check if optimized variant exists
            if echo "$model" | grep -q "\-128k\|\-256k"; then
                echo "  ✓ $model ${DIM}(optimized)${NC}"
            else
                echo "  ✓ $model ${DIM}(base)${NC}"
            fi
        done
        echo ""
    fi

    # Define available models with sizes and recommendations
    echo -e "${YELLOW}Available Gemma 4 Models (https://ollama.com/library/gemma4/tags):${NC}"
    echo ""

    # Function to check if model is installed (checks both base and optimized variants)
    is_installed() {
        local model="$1"
        local has_base=false
        local has_optimized=false

        # Check for base model
        if echo "$INSTALLED_MODELS" | grep -q "^${model}$"; then
            has_base=true
        fi

        # Check for optimized variant (128k or 256k)
        if echo "$INSTALLED_MODELS" | grep -q "^${model}-128k$\|^${model}-256k$"; then
            has_optimized=true
        fi

        # Display status
        if [ "$has_optimized" = true ]; then
            echo " ${GREEN}[INSTALLED - OPTIMIZED]${NC}"
        elif [ "$has_base" = true ]; then
            echo " ${GREEN}[INSTALLED - BASE]${NC}"
        else
            echo ""
        fi
    }

    echo -e "${BLUE}Small Models (128K context):${NC}"
    echo -e "  1)  gemma4:e2b-it-q4_K_M    (7.2GB)  - Smallest quantized$(is_installed 'gemma4:e2b-it-q4_K_M')"
    echo -e "  2)  gemma4:e2b-it-q8_0      (8.1GB)  - Better quality$(is_installed 'gemma4:e2b-it-q8_0')"
    echo ""
    echo -e "${BLUE}Medium Models (128K context):${NC}"
    echo -e "  3)  gemma4:e4b-it-q4_K_M    (9.6GB)  - Balanced size/quality$(is_installed 'gemma4:e4b-it-q4_K_M')"
    echo -e "  4)  gemma4:e4b-it-q8_0      (12GB)   - Higher quality$(is_installed 'gemma4:e4b-it-q8_0')"
    echo ""
    echo -e "${BLUE}Large Models (256K context):${NC}"
    echo -e "  5)  gemma4:26b-a4b-it-q4_K_M (18GB)  - Large quantized$(is_installed 'gemma4:26b-a4b-it-q4_K_M')"
    echo -e "  6)  gemma4:26b-a4b-it-q8_0   (28GB)  - Large high quality$(is_installed 'gemma4:26b-a4b-it-q8_0')"
    echo ""
    echo -e "${BLUE}Extra Large Models (256K context):${NC}"
    echo -e "  7)  gemma4:31b-it-q4_K_M    (20GB)  - XL quantized$(is_installed 'gemma4:31b-it-q4_K_M')"
    echo -e "  8)  gemma4:31b-it-q8_0      (34GB)  - XL high quality$(is_installed 'gemma4:31b-it-q8_0')"
    echo ""

    # Provide recommendations based on RAM
    echo -e "${GREEN}Recommendations for ${TOTAL_RAM_GB}GB RAM:${NC}"
    if [ "$TOTAL_RAM_GB" -ge 48 ]; then
        echo "  • Best: gemma4:31b-it-q8_0 (34GB, excellent quality, 256K context)"
        echo "  • Alt:  gemma4:31b-it-q4_K_M (20GB, good quality)"
    elif [ "$TOTAL_RAM_GB" -ge 32 ]; then
        echo "  • Best: gemma4:26b-a4b-it-q8_0 (28GB, high quality, 256K context)"
        echo "  • Alt:  gemma4:31b-it-q4_K_M (20GB, larger model, quantized)"
    elif [ "$TOTAL_RAM_GB" -ge 24 ]; then
        echo "  • Best: gemma4:26b-a4b-it-q4_K_M (18GB, good balance, 256K context)"
        echo "  • Alt:  gemma4:e4b-it-q8_0 (12GB, smaller model, higher quality)"
    elif [ "$TOTAL_RAM_GB" -ge 16 ]; then
        echo "  • Best: gemma4:e4b-it-q8_0 (12GB, good quality)"
        echo "  • Alt:  gemma4:e4b-it-q4_K_M (9.6GB, balanced)"
    else
        echo "  • Best: gemma4:e2b-it-q4_K_M (7.2GB, smallest)"
        print_warning "Your system has ${TOTAL_RAM_GB}GB RAM. 16GB+ recommended for better models."
    fi
    echo ""
    echo "  Context sizes: Small/Medium (128K), Large/XL (256K)"
    echo "  Quantization: q4_K_M (smaller, faster) < q8_0 (larger, better quality)"
    echo ""

    # Prompt for selection
    while true; do
        read -p "Select model (1-8) or enter custom model name: " choice
        case $choice in
            1)  OLLAMA_MODEL="gemma4:e2b-it-q4_K_M"; break ;;
            2)  OLLAMA_MODEL="gemma4:e2b-it-q8_0"; break ;;
            3)  OLLAMA_MODEL="gemma4:e4b-it-q4_K_M"; break ;;
            4)  OLLAMA_MODEL="gemma4:e4b-it-q8_0"; break ;;
            5)  OLLAMA_MODEL="gemma4:26b-a4b-it-q4_K_M"; break ;;
            6)  OLLAMA_MODEL="gemma4:26b-a4b-it-q8_0"; break ;;
            7)  OLLAMA_MODEL="gemma4:31b-it-q4_K_M"; break ;;
            8)  OLLAMA_MODEL="gemma4:31b-it-q8_0"; break ;;
            gemma4:*)
                OLLAMA_MODEL="$choice"
                print_info "Using custom model: $OLLAMA_MODEL"
                break
                ;;
            *)
                print_error "Invalid selection. Please choose 1-8 or enter a model name starting with 'gemma4:'"
                ;;
        esac
    done

    echo ""
    print_status "Selected model: $OLLAMA_MODEL"
    echo ""
}

# Start of setup script
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Gemma 4 + Ollama + OpenCode Setup${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"
echo ""

# Verify Apple Silicon
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    print_warning "Not running on Apple Silicon (detected: $ARCH)"
    print_warning "Metal optimizations require Apple Silicon (M1/M2/M3/M4)"
    print_info "Script will continue but performance may be suboptimal"
    echo ""
else
    print_status "Apple Silicon detected ($ARCH)"
fi

MISSING_DEPS=()
for cmd in git go bun; do
    if command_exists "$cmd"; then
        print_status "$cmd installed"
    else
        print_warning "$cmd not found"
        MISSING_DEPS+=("$cmd")
    fi
done

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo ""
    print_info "Missing dependencies: ${MISSING_DEPS[*]}"

    # Check if brew is available to install them
    if ! command_exists brew; then
        print_error "Homebrew not found. Please install Homebrew first:"
        echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi

    print_info "Installing missing dependencies with Homebrew..."
    echo ""

    for dep in "${MISSING_DEPS[@]}"; do
        print_info "Installing $dep..."
        brew install "$dep"
    done

    echo ""
    print_status "All dependencies installed successfully"
fi

echo ""

# Step 1: Build Ollama from source
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Step 1: Building Ollama from latest commit${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if already built
if [ -f "$OLLAMA_BUILD_DIR/ollama" ]; then
    print_status "Ollama already built"
    "$OLLAMA_BUILD_DIR/ollama" --version
    print_info "To rebuild, remove: $OLLAMA_BUILD_DIR"
else
    if [ -d "$OLLAMA_BUILD_DIR" ]; then
        print_warning "Removing incomplete build directory: $OLLAMA_BUILD_DIR"
        rm -rf "$OLLAMA_BUILD_DIR"
    fi

    print_info "Cloning latest Ollama from main branch..."
    git clone --depth 1 https://github.com/ollama/ollama.git "$OLLAMA_BUILD_DIR"
    cd "$OLLAMA_BUILD_DIR"

    print_info "Installing build dependencies..."
    go install github.com/tkrajina/typescriptify-golang-structs/tscriptify@latest

    # Ensure Go bin is in PATH
    export PATH="$PATH:$(go env GOPATH)/bin"

    # Detect CPU count for parallel compilation
    NUM_CPUS=$(sysctl -n hw.ncpu)

    print_info "Building Ollama with Apple Silicon optimizations..."
    print_info "Enabling: Metal GPU, Accelerate Framework, Native CPU optimizations"
    print_info "Additional: LTO, Frame Pointer Optimization, Parallel Build (${NUM_CPUS} cores)"
    print_info "This may take 5-10 minutes..."
    echo ""

    # Set build environment for maximum Apple Silicon performance
    export CGO_ENABLED=1
    export GOARCH=arm64
    export GOMAXPROCS=$NUM_CPUS

    # Aggressive CGO optimizations
    # -O3: Maximum optimization level
    # -march=native: Use all available CPU features
    # -mtune=native: Tune for this specific CPU
    # -flto: Link Time Optimization for cross-module optimization
    # -fomit-frame-pointer: Free up register for better performance
    # -DNDEBUG: Disable debug assertions
    export CGO_CFLAGS="-O3 -march=native -mtune=native -flto -fomit-frame-pointer -DNDEBUG"
    export CGO_LDFLAGS="-flto -framework Metal -framework Foundation -framework Accelerate"

    # Generate C++ components with Metal support
    go generate ./... || {
        print_warning "go generate had some warnings, continuing..."
    }

    # Build with optimizations
    # -p: Parallel compilation using all CPU cores
    # -trimpath: Remove absolute paths for reproducible builds
    # -ldflags="-s -w": Strip debug info and symbol table
    # -ldflags="-linkmode=external": Use external linker for better LTO
    go build -p $NUM_CPUS -trimpath -ldflags="-s -w -linkmode=external" .

    print_status "Ollama built successfully"
    "$OLLAMA_BUILD_DIR/ollama" --version
fi

echo ""

# Step 1.5: Model Selection (after Ollama is built so we can detect installed models)
if [ -z "$OLLAMA_MODEL" ]; then
    select_model
else
    print_info "Using model from environment: $OLLAMA_MODEL"
fi

echo ""

# Step 2: Install OpenCode
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Step 2: Installing OpenCode${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Remove Homebrew version if exists
if brew list opencode &>/dev/null; then
    print_warning "Removing Homebrew version of OpenCode..."
    brew uninstall opencode
fi

if [ "$BUILD_OPENCODE_FROM_SOURCE" = "true" ]; then
    print_info "Building OpenCode from source (BUILD_OPENCODE_FROM_SOURCE=true)"

    # Check if custom build marker exists
    CUSTOM_BUILD_MARKER="$HOME/.opencode/bin/.custom-build-dev"

    if [ -f "$CUSTOM_BUILD_MARKER" ]; then
        print_status "OpenCode custom build already installed"
        "$HOME/.opencode/bin/opencode" --version
        print_info "To rebuild, remove: $CUSTOM_BUILD_MARKER"
    else
        # Install base OpenCode first if not present
        if [ ! -d "$HOME/.opencode" ]; then
            print_info "Installing base OpenCode first..."
            curl -fsSL https://opencode.ai/install -o /tmp/opencode-install.sh
            bash /tmp/opencode-install.sh
        fi

        if [ -d "$OPENCODE_BUILD_DIR" ]; then
            print_warning "Removing existing build directory: $OPENCODE_BUILD_DIR"
            rm -rf "$OPENCODE_BUILD_DIR"
        fi

        print_info "Cloning latest OpenCode from dev branch..."
        print_info "This includes the newest features and fixes"
        git clone --depth 1 --branch dev https://github.com/anomalyco/opencode.git "$OPENCODE_BUILD_DIR" || {
            print_error "Failed to clone OpenCode repository (dev branch)"
            exit 1
        }
        cd "$OPENCODE_BUILD_DIR"

        # Show the latest commit info
        LATEST_COMMIT=$(git log -1 --pretty=format:"%h - %s (%ar)" 2>/dev/null || echo "unknown")
        print_info "Latest commit: $LATEST_COMMIT"

        print_info "Installing dependencies and building..."
        bun install || {
            print_error "Failed to install dependencies"
            exit 1
        }
        cd packages/opencode || {
            print_error "packages/opencode directory not found"
            exit 1
        }
        print_info "Building OpenCode binary (this may take 3-5 minutes)..."
        bun run build -- --single --skip-install || {
            print_error "Failed to build OpenCode"
            exit 1
        }

        # Backup original if it exists and isn't already backed up
        if [ -f "$HOME/.opencode/bin/opencode" ] && [ ! -f "$HOME/.opencode/bin/opencode.backup" ]; then
            print_info "Backing up original OpenCode binary..."
            cp "$HOME/.opencode/bin/opencode" "$HOME/.opencode/bin/opencode.backup"
        fi

        print_info "Installing custom build..."

        # Check if build output exists
        if [ ! -f "dist/opencode-darwin-arm64/bin/opencode" ]; then
            print_error "Build output not found: dist/opencode-darwin-arm64/bin/opencode"
            print_info "Available files:"
            find dist -name "opencode" 2>/dev/null || echo "No opencode binary found"
            exit 1
        fi

        mkdir -p "$HOME/.opencode/bin"
        cp dist/opencode-darwin-arm64/bin/opencode "$HOME/.opencode/bin/opencode" || {
            print_error "Failed to copy OpenCode binary"
            exit 1
        }
        chmod +x "$HOME/.opencode/bin/opencode"

        # Create marker file to indicate custom build
        touch "$CUSTOM_BUILD_MARKER"

        print_status "OpenCode custom build installed from source"
        "$HOME/.opencode/bin/opencode" --version
    fi
else
    print_info "Using official OpenCode release (recommended)"
    print_info "This version gets automatic updates via 'opencode update'"

    # Check if OpenCode binary exists (not just the directory)
    if [ ! -f "$HOME/.opencode/bin/opencode" ]; then
        # Check if we have a backup to restore
        if [ -f "$HOME/.opencode/bin/opencode.backup" ]; then
            print_info "Restoring OpenCode from backup..."
            cp "$HOME/.opencode/bin/opencode.backup" "$HOME/.opencode/bin/opencode"
            chmod +x "$HOME/.opencode/bin/opencode"
            print_status "Restored from backup"
        else
            print_info "Installing OpenCode..."
            curl -fsSL https://opencode.ai/install -o /tmp/opencode-install.sh
            bash /tmp/opencode-install.sh
        fi
    else
        print_status "OpenCode already installed"

        # Check if update is available
        if "$HOME/.opencode/bin/opencode" --version 2>&1 | grep -q "update available"; then
            print_info "Update available - run 'opencode update' to update"
        fi
    fi

    # Verify installation succeeded
    if [ -f "$HOME/.opencode/bin/opencode" ]; then
        print_status "OpenCode installed at: $(which opencode || echo "$HOME/.opencode/bin/opencode")"
        "$HOME/.opencode/bin/opencode" --version
    else
        print_error "OpenCode installation failed"
        exit 1
    fi
fi

echo ""

# Step 3: Configure OpenCode for Ollama
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Step 3: Creating OpenCode configuration for Ollama${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

CONFIG_DIR="$HOME/.config/opencode"
mkdir -p "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR/prompts"

print_info "Creating opencode.jsonc..."

# Set context size based on model (26b/31b support 256K, e2b/e4b support 128K)
if [[ "$OLLAMA_MODEL" == *"26b"* ]] || [[ "$OLLAMA_MODEL" == *"31b"* ]]; then
    CONTEXT_SIZE=256000
else
    CONTEXT_SIZE=128000
fi

cat > "$CONFIG_DIR/opencode.jsonc" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama (local)",
      "options": {
        "baseURL": "http://127.0.0.1:3456/v1",
        "toolParser": [
          { "type": "raw-function-call" },
          { "type": "json" }
        ]
      },
      "models": {
        "$OLLAMA_MODEL": {
          "name": "Gemma 4 ($OLLAMA_MODEL)",
          "tool_call": true,
          "limit": {
            "context": $CONTEXT_SIZE,
            "output": 16384
          },
          "options": {
            "temperature": 0.7,
            "top_p": 0.95,
            "top_k": 64,
            "repeat_penalty": 1.1,
            "num_predict": 16384
          }
        }
      }
    }
  },
  "model": "ollama/$OLLAMA_MODEL",
  "agent": {
    "build": {
      "prompt": "{file:./prompts/build.txt}",
      "permission": {
        "edit": "allow",
        "bash": "allow",
        "webfetch": "allow",
        "task": "allow"
      }
    },
    "review": {
      "prompt": "{file:./prompts/review.txt}",
      "permission": {
        "edit": "deny",
        "bash": "allow",
        "webfetch": "allow",
        "task": "allow"
      }
    },
    "refactor": {
      "prompt": "{file:./prompts/refactor.txt}",
      "permission": {
        "edit": "allow",
        "bash": "allow",
        "webfetch": "deny",
        "task": "allow"
      }
    }
  }
}
EOF

print_status "Created: $CONFIG_DIR/opencode.jsonc"

print_info "Creating AGENTS.md..."
cat > "$CONFIG_DIR/AGENTS.md" <<'EOF'
# OpenCode Agent Instructions

You are a coding assistant with direct access to the user's file system.

## CRITICAL: When user mentions a file
If the user asks about a file or provides a file path:
1. IMMEDIATELY use the 'read' tool to read it
2. Do NOT ask them to paste the content
3. Do NOT say you don't have access
4. Just read the file and answer

## Available Tools

### read
Read a file from the file system.
Parameters:
- `filePath` (string, REQUIRED): Absolute path to the file
- `offset` (number, optional): Line number to start from
- `limit` (number, optional): Max lines to read

Example: `{"filePath": "/Users/web/project/hello.txt"}`

Best practices:
- ALWAYS read files before editing them
- Use for specific files you know about
- For large files, use offset/limit to read sections

### edit
Modify an existing file by replacing text.
Parameters:
- `filePath` (string, REQUIRED): Absolute path to the file
- `oldString` (string, REQUIRED): The exact text to find and replace
- `newString` (string, REQUIRED): The replacement text
- `replaceAll` (boolean, optional): Replace all occurrences

Example: `{"filePath": "/path/to/file.ts", "oldString": "foo", "newString": "bar"}`

Best practices:
- MUST read the file first
- Make oldString unique enough to match once
- Preserve indentation and formatting

### write
Create or overwrite a file.
Parameters (ALL required):
- `filePath` (string, REQUIRED): Absolute path to the file
- `content` (string, REQUIRED): The content to write

Example: `{"filePath": "/Users/web/project/hello.txt", "content": "Hello world"}`

Best practices:
- Use only for NEW files
- Prefer 'edit' for existing files
- Include complete file content

### bash
Execute shell commands.
Parameters (ALL required unless noted):
- `command` (string, REQUIRED): The shell command to run
- `description` (string, REQUIRED): Short description of what the command does (5-10 words)
- `timeout` (number, optional): Timeout in milliseconds
- `workdir` (string, optional): Working directory

Example: `{"command": "ls -la", "description": "List files in current directory"}`

Best practices:
- Use for git, tests, builds, package management
- ALWAYS provide description
- Check exit codes for errors

### glob
Find files by pattern.
Parameters:
- `pattern` (string, REQUIRED): Glob pattern like `**/*.ts`
- `path` (string, optional): Directory to search in

Example: `{"pattern": "**/*.test.ts"}`

Best practices:
- Use for finding files by name pattern
- Good for: "Find all test files", "Find component files"
- NOT for content search (use grep or task)

### grep
Search file contents.
Parameters:
- `pattern` (string, REQUIRED): Regex pattern to search for
- `path` (string, optional): Directory to search in
- `include` (string, optional): File pattern filter like `*.js`

Example: `{"pattern": "function.*auth", "include": "*.ts"}`

Best practices:
- Use for specific content searches
- Good for: Known function/class names, specific strings
- For open-ended searches, use 'task' tool with Explore agent

### task
Launch specialized agents for complex tasks.
Parameters:
- `subagent_type` (string, REQUIRED): Agent type (e.g., "Explore")
- `prompt` (string, REQUIRED): Task description for the agent

Example: `{"subagent_type": "Explore", "prompt": "Find all error handling code in the authentication system"}`

Best practices for LARGE CODEBASES (10,000+ files):
- Use 'task' with subagent_type=Explore for open-ended searches
- Good for: "Where is X handled?", "How does Y work?", "Find all Z"
- Much faster and more thorough than manual grep/glob
- The Explore agent can search multiple files efficiently

### question
Ask the user for clarification.
Parameters:
- `question` (string, REQUIRED): The question to ask

Best practices:
- Use when requirements are unclear
- Ask before making large changes
- Get approval for refactoring plans

### webfetch
Fetch content from external URLs.
Parameters:
- `url` (string, REQUIRED): URL to fetch
- `prompt` (string, REQUIRED): What to extract from the content

Best practices:
- Use for documentation, API references
- NOT for authenticated content

### todowrite
Track tasks and progress. The `todos` parameter MUST be a JSON array of objects, NOT a string.
Parameters:
- `todos` (array of objects, REQUIRED): Each object has:
  - `content` (string, REQUIRED): Brief description of the task
  - `status` (string, REQUIRED): One of: `pending`, `in_progress`, `completed`, `cancelled`
  - `priority` (string, REQUIRED): One of: `high`, `medium`, `low`

Example: `{"todos": [{"content": "Add game over screen", "status": "in_progress", "priority": "high"}, {"content": "Add sound effects", "status": "pending", "priority": "low"}]}`

IMPORTANT: `todos` MUST be an array `[...]`, NOT a string `"[...]"`. Never stringify the array.

## WORKFLOW FOR LARGE CODEBASES

When working with large codebases (10,000+ files):

1. **Exploration Phase**
   - Use 'task' tool with Explore agent for broad searches
   - Use 'glob' for finding specific file names
   - Use 'grep' for known patterns

2. **Reading Phase**
   - Use 'read' only for files directly relevant to the task
   - Don't read files "just in case" - be targeted

3. **Modification Phase**
   - ALWAYS read files before editing
   - Make changes incrementally
   - Test after each logical change

4. **Verification Phase**
   - Use 'bash' to run tests
   - Check that changes work as expected

## IMPORTANT REMINDERS

**Parameter Format:**
- Use camelCase: `filePath` not `file_path`
- Provide all required parameters
- Use correct types (string, number, boolean, array)

**Common Mistakes to Avoid:**
- ❌ Calling non-existent tools (google:search, web_search)
- ❌ Using snake_case parameters
- ❌ Making changes without reading files first
- ❌ Using grep/glob for open-ended searches (use task tool)
- ❌ Stringifying array parameters

## DO NOT
- Call tools that don't exist (like google:search, web_search, etc.)
- Ask user to paste file contents when you can read them
- Use snake_case parameters (use camelCase: filePath not file_path)
- Edit files without reading them first
- Make large changes (3+ files) without asking user first
EOF

print_status "Created: $CONFIG_DIR/AGENTS.md"

print_info "Creating build.txt prompt..."
cat > "$CONFIG_DIR/prompts/build.txt" <<'EOF'
You are an expert coding assistant with direct file system access.

## File Access
When the user mentions a file path or asks about code:
1. IMMEDIATELY use 'read' tool to read it
2. Do NOT ask them to paste content
3. Do NOT say you lack access
4. Read it and answer

## Code Exploration (Large Codebases)
For open-ended searches like "where is X handled" or "how does Y work":
- Use 'task' tool with subagent_type=Explore for multi-file searches
- This is faster and more thorough than manual grep/glob
- Example: "Find all error handling code" → use task tool

For specific searches:
- Known file: use 'read' directly
- Specific pattern: use 'grep' or 'glob'
- Class/function name: use 'glob' for "**/*ClassName*"

## Context Management (Large Codebases)
When working with large codebases (10,000+ files):
- Read ONLY files directly relevant to the current task
- Use 'task' tool for exploration, not manual file reads
- Prioritize targeted searches over broad scans
- When context grows large, summarize findings before continuing
- For changes spanning 3+ files, present plan to user first
- Break large tasks into smaller, focused subtasks

## Code Modifications
Small changes (1-2 files):
- Read the file first (ALWAYS)
- Use 'edit' for precise changes
- Use 'write' for new files only
- Test after changes
- Verify the change worked

Large refactors (3+ files):
- Present a plan to the user first
- Get approval before making changes
- Make changes incrementally
- Test after each logical step
- Document what changed and why

## Commands
- Use 'bash' for git, tests, builds
- Always provide 'description' parameter
- Run tests after significant changes
- Check exit codes and handle errors

## Good Examples
User: "Fix the bug in auth.ts"
✅ CORRECT: Read auth.ts first, understand the bug, make targeted fix, test

User: "Where is error handling?"
✅ CORRECT: Use task tool with Explore agent for multi-file search

User: "Update the API endpoint to support pagination"
✅ CORRECT: Read endpoint file, read tests, update both, run tests

## Bad Examples
❌ WRONG: Making changes without reading the file first
❌ WRONG: Using grep/glob for open-ended searches (use task tool)
❌ WRONG: Creating new files when editing existing ones would work
❌ WRONG: Making 5+ file changes without asking user first
❌ WRONG: Calling non-existent tools like google:search

## Available Tools
- read: {filePath} - Read any file
- write: {filePath, content} - Create new files
- edit: {filePath, oldString, newString} - Modify files
- bash: {command, description} - Run commands (BOTH required)
- glob: {pattern} - Find files by pattern
- grep: {pattern} - Search file contents
- task: Use for complex multi-file exploration
- webfetch: Fetch external content
- todowrite: Track tasks
- question: Ask user for clarification
- skill: Invoke specialized skills

## DO NOT
- Invent tools (no google:search, web_search, etc.)
- Ask for file content you can read
- Use snake_case params (use camelCase)
- Make large changes without asking first
- Skip reading files before editing them
- Use manual grep/glob for open-ended searches
EOF

print_status "Created: $CONFIG_DIR/prompts/build.txt"

print_info "Creating review.txt prompt..."
cat > "$CONFIG_DIR/prompts/review.txt" <<'EOF'
You are a code review expert focusing on quality, security, and best practices.

## Review Approach
Your role is to review code changes, NOT to make edits directly.
Focus on: correctness, security, performance, maintainability, testing.

## Review Process
1. Read all changed files thoroughly
2. Understand the context and purpose
3. Check for common issues:
   - Security vulnerabilities (injection, XSS, auth bypass)
   - Logic errors and edge cases
   - Performance issues
   - Code smell and maintainability
   - Missing tests or documentation
   - Breaking changes
4. Provide constructive feedback with specific examples
5. Suggest improvements with code snippets

## Review Categories
**CRITICAL** - Must fix (security, bugs, breaking changes)
**IMPORTANT** - Should fix (performance, best practices)
**SUGGESTION** - Consider (refactoring, style improvements)

## Security Checklist
- [ ] Input validation and sanitization
- [ ] Authentication and authorization
- [ ] SQL injection prevention
- [ ] XSS prevention
- [ ] CSRF protection
- [ ] Sensitive data handling
- [ ] Dependency vulnerabilities

## Output Format
For each issue found:
```
[CATEGORY] Issue in file.ts:123
Description of the issue
Why it matters
Suggested fix with code example
```

## DO NOT
- Make direct edits (edit permission is denied)
- Approve code without thorough review
- Ignore security issues
- Be overly critical about style preferences
EOF

print_status "Created: $CONFIG_DIR/prompts/review.txt"

print_info "Creating refactor.txt prompt..."
cat > "$CONFIG_DIR/prompts/refactor.txt" <<'EOF'
You are a refactoring expert focused on improving code quality without changing behavior.

## Refactoring Principles
1. Preserve existing functionality (behavior stays the same)
2. Improve code structure, readability, and maintainability
3. Make changes incrementally and test frequently
4. Follow existing code patterns and conventions

## Before Refactoring
1. Read all relevant files to understand current structure
2. Identify code smells and improvement opportunities
3. Present refactoring plan to user for approval
4. Get explicit approval before making changes

## Common Refactoring Patterns
- Extract repeated code into functions/classes
- Rename variables/functions for clarity
- Simplify complex conditionals
- Remove dead code
- Consolidate duplicate logic
- Improve error handling
- Add type safety

## Refactoring Process
1. **Analyze**: Read code, identify issues, understand dependencies
2. **Plan**: Present structured refactoring plan to user
3. **Approve**: Wait for user approval before changes
4. **Execute**: Make changes incrementally
5. **Test**: Run tests after each logical change
6. **Verify**: Confirm behavior unchanged

## Safety First
- ALWAYS run existing tests after changes
- Make one logical change at a time
- Commit working changes frequently
- If tests fail, revert and reassess
- Keep refactoring separate from new features

## Context Management
For large refactorings:
- Break into smaller phases (3-5 files per phase)
- Get approval for each phase
- Test and commit between phases
- Document what changed and why

## Available Tools
- read: Read files to understand structure
- edit: Make precise refactoring changes
- bash: Run tests, git commands
- task: Explore codebase for patterns
- question: Ask user for clarification or approval

## DO NOT
- Change behavior or add features (that's not refactoring)
- Make large changes without user approval
- Skip running tests
- Refactor and add features in same change
- Use external APIs (webfetch is denied)
EOF

print_status "Created: $CONFIG_DIR/prompts/refactor.txt"

echo ""

# Step 4: Start Ollama server (if AUTO_START is true)
if [ "$AUTO_START" = "true" ]; then
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Step 4: Starting Ollama server${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Create log directory
    LOG_DIR="$HOME/.local/var/log"
    mkdir -p "$LOG_DIR"

    # Check if port is already in use
    if lsof -ti:$PORT >/dev/null 2>&1; then
        print_warning "Port $PORT is already in use"
        print_info "Killing existing process..."
        lsof -ti:$PORT | xargs kill -9
        sleep 2
    fi

    print_info "Starting Ollama server on port $PORT..."
    print_info "Log file: $LOG_DIR/ollama-server.log"
    print_info "Performance: Keep-alive enabled, all GPU layers, flash attention"
    echo ""

    # Start Ollama in background with performance optimizations
    # OLLAMA_HOST: Bind to specific port
    # OLLAMA_KEEP_ALIVE=-1: Keep models in memory indefinitely
    # OLLAMA_NUM_GPU=999: Offload all layers to GPU
    # OLLAMA_MAX_LOADED_MODELS=1: Focus memory on single model for best performance
    # OLLAMA_FLASH_ATTENTION=1: Enable flash attention for faster inference
    OLLAMA_HOST=127.0.0.1:$PORT \
    OLLAMA_KEEP_ALIVE=-1 \
    OLLAMA_NUM_GPU=999 \
    OLLAMA_MAX_LOADED_MODELS=1 \
    OLLAMA_FLASH_ATTENTION=1 \
    nohup "$OLLAMA_BUILD_DIR/ollama" serve \
        > "$LOG_DIR/ollama-server.log" 2>&1 &

    SERVER_PID=$!
    echo "$SERVER_PID" > "$HOME/.local/var/ollama-server.pid"

    print_status "Ollama server started (PID: $SERVER_PID)"
    print_info "Waiting for server to be ready..."

    # Wait for health check (up to 60 seconds)
    TIMEOUT=60
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        if curl -s -f "http://127.0.0.1:$PORT/api/tags" >/dev/null 2>&1; then
            print_status "Ollama server is ready!"
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
        print_info "Check logs: tail -f $LOG_DIR/ollama-server.log"
    else
        # Server is ready, now pull the model
        echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}  Pulling Model: $OLLAMA_MODEL${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
        echo ""

        print_info "Checking if model is already available..."

        # Set OLLAMA_HOST for the CLI commands
        export OLLAMA_HOST="127.0.0.1:$PORT"

        if OLLAMA_HOST="127.0.0.1:$PORT" "$OLLAMA_BUILD_DIR/ollama" list 2>/dev/null | grep -q "$OLLAMA_MODEL"; then
            print_status "Model $OLLAMA_MODEL already pulled"
        else
            # Estimate size based on model name
            MODEL_SIZE="unknown size"
            case "$OLLAMA_MODEL" in
                *e2b*q4*)  MODEL_SIZE="~7GB" ;;
                *e2b*q8*)  MODEL_SIZE="~8GB" ;;
                *e4b*q4*)  MODEL_SIZE="~10GB" ;;
                *e4b*q8*)  MODEL_SIZE="~12GB" ;;
                *26b*q4*)  MODEL_SIZE="~18GB" ;;
                *26b*q8*)  MODEL_SIZE="~28GB" ;;
                *31b*q4*)  MODEL_SIZE="~20GB" ;;
                *31b*q8*)  MODEL_SIZE="~34GB" ;;
            esac

            print_info "Pulling model $OLLAMA_MODEL ($MODEL_SIZE)..."
            print_info "This may take 10-30 minutes depending on your connection"
            echo ""

            if OLLAMA_HOST="127.0.0.1:$PORT" "$OLLAMA_BUILD_DIR/ollama" pull "$OLLAMA_MODEL"; then
                echo ""
                print_status "Model $OLLAMA_MODEL pulled successfully"

                # Create optimized model with proper context size
                print_info "Creating optimized model with $CONTEXT_SIZE token context..."
                MODEL_SUFFIX=$(echo "$OLLAMA_MODEL" | grep -q "26b\|31b" && echo "256k" || echo "128k")
                OPTIMIZED_MODEL="${OLLAMA_MODEL}-${MODEL_SUFFIX}"

                cat > /tmp/modelfile-$$<< EOF
FROM $OLLAMA_MODEL
PARAMETER num_ctx $CONTEXT_SIZE
PARAMETER temperature 0.7
PARAMETER top_k 64
PARAMETER top_p 0.95
EOF

                if OLLAMA_HOST="127.0.0.1:$PORT" "$OLLAMA_BUILD_DIR/ollama" create "$OPTIMIZED_MODEL" -f /tmp/modelfile-$$ >/dev/null 2>&1; then
                    rm -f /tmp/modelfile-$$
                    print_status "Created optimized model: $OPTIMIZED_MODEL"
                    OLLAMA_MODEL="$OPTIMIZED_MODEL"

                    # Update OpenCode config to use optimized model
                    CONFIG_FILE="$HOME/.config/opencode/opencode.jsonc"
                    if [ -f "$CONFIG_FILE" ]; then
                        print_info "Updating OpenCode config to use optimized model..."
                        # Update the model references in the config
                        sed -i.bak "s|\"${OLLAMA_MODEL%-*}\":|\"$OPTIMIZED_MODEL\":|g" "$CONFIG_FILE"
                        sed -i.bak "s|ollama/${OLLAMA_MODEL%-*}|ollama/$OPTIMIZED_MODEL|g" "$CONFIG_FILE"
                        rm -f "$CONFIG_FILE.bak"
                        print_status "Config updated to use: $OPTIMIZED_MODEL"
                    fi
                else
                    rm -f /tmp/modelfile-$$
                    print_warning "Could not create optimized model, using original"
                fi
            else
                echo ""
                print_error "Failed to pull model"
                print_info "You can pull it manually later with:"
                print_info "  OLLAMA_HOST=127.0.0.1:$PORT $OLLAMA_BUILD_DIR/ollama pull $OLLAMA_MODEL"
            fi
        fi

        echo ""
    fi

    # Install embedding model for semantic code search (large codebases)
    if [ "$INSTALL_EMBEDDING_MODEL" = "true" ]; then
        echo ""
        echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}  Installing Embedding Model${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
        echo ""

        EMBEDDING_MODEL="nomic-embed-text"

        print_info "Checking if embedding model is already available..."

        if OLLAMA_HOST="127.0.0.1:$PORT" "$OLLAMA_BUILD_DIR/ollama" list 2>/dev/null | grep -q "$EMBEDDING_MODEL"; then
            print_status "Embedding model $EMBEDDING_MODEL already installed"
        else
            print_info "Pulling $EMBEDDING_MODEL (274MB, optimized for code/text)..."
            print_info "Use case: Semantic search for large codebases (1000+ files)"
            echo ""

            if OLLAMA_HOST="127.0.0.1:$PORT" "$OLLAMA_BUILD_DIR/ollama" pull "$EMBEDDING_MODEL"; then
                echo ""
                print_status "Embedding model installed successfully"
                print_info "Use for: Semantic code search, finding similar functions, etc."
            else
                echo ""
                print_warning "Failed to pull embedding model (optional, can skip)"
                print_info "You can install it later with:"
                print_info "  OLLAMA_HOST=127.0.0.1:$PORT $OLLAMA_BUILD_DIR/ollama pull $EMBEDDING_MODEL"
            fi
        fi

        echo ""
    fi

    echo ""

    # Optionally create launchd plist for auto-start on login
    if [ "$AUTO_START_ON_LOGIN" = "true" ]; then
        PLIST_DIR="$HOME/Library/LaunchAgents"
        PLIST_FILE="$PLIST_DIR/com.ollama.server.plist"
        mkdir -p "$PLIST_DIR"

        # Check if already loaded
        if launchctl list | grep -q "com.ollama.server"; then
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
    <string>com.ollama.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>$OLLAMA_BUILD_DIR/ollama</string>
        <string>serve</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>OLLAMA_HOST</key>
        <string>127.0.0.1:$PORT</string>
        <key>OLLAMA_KEEP_ALIVE</key>
        <string>-1</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/ollama-server.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/ollama-server.log</string>
</dict>
</plist>
EOF

            launchctl load "$PLIST_FILE"
            print_status "Created launchd service: $PLIST_FILE"
            print_info "Ollama server will start automatically on login"
        fi
    fi

    echo ""
fi

# Final instructions
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

print_status "Ollama built at: $OLLAMA_BUILD_DIR/ollama"

if [ "$BUILD_OPENCODE_FROM_SOURCE" = "true" ]; then
    print_status "OpenCode built from latest dev branch commit"
else
    print_status "OpenCode official release installed"
fi

print_status "Configuration created at: $CONFIG_DIR"

if [ "$AUTO_START" = "true" ]; then
    print_status "Model: $OLLAMA_MODEL"
    if [ -n "${SERVER_PID:-}" ]; then
        print_status "Ollama server running on port $PORT (PID: $SERVER_PID)"
    else
        print_status "Ollama server on port $PORT"
    fi
fi

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""

if [ "$AUTO_START" = "true" ]; then
    echo "✅ Ollama server is already running and ready!"
    echo ""
    echo "To verify the server:"
    echo -e "   ${GREEN}curl http://127.0.0.1:$PORT/api/tags${NC}"
    echo ""
    echo "To view logs:"
    echo -e "   ${GREEN}tail -f $LOG_DIR/ollama-server.log${NC}"
    echo ""
    echo "To stop the server:"
    echo -e "   ${GREEN}kill \$(cat $HOME/.local/var/ollama-server.pid)${NC}"
    echo ""
    echo "To restart the server manually:"
    echo ""
    echo "   OLLAMA_HOST=127.0.0.1:$PORT OLLAMA_KEEP_ALIVE=-1 OLLAMA_NUM_GPU=999 \\"
    echo "   OLLAMA_MAX_LOADED_MODELS=1 OLLAMA_FLASH_ATTENTION=1 \\"
    echo "   $OLLAMA_BUILD_DIR/ollama serve"
    echo ""
    echo "Ready to use OpenCode! In your project directory:"
    echo -e "   ${GREEN}cd /path/to/your/project${NC}"
    echo -e "   ${GREEN}opencode${NC}"
else
    echo "1. Start Ollama server in a new terminal:"
    echo ""
    echo "   OLLAMA_HOST=127.0.0.1:$PORT OLLAMA_KEEP_ALIVE=-1 OLLAMA_NUM_GPU=999 \\"
    echo "   OLLAMA_MAX_LOADED_MODELS=1 OLLAMA_FLASH_ATTENTION=1 \\"
    echo "   $OLLAMA_BUILD_DIR/ollama serve"
    echo ""
    echo "2. Wait for server to start, then verify:"
    echo ""
    echo -e "   ${GREEN}curl http://127.0.0.1:$PORT/api/tags${NC}"
    echo ""
    echo "3. Run OpenCode in your project directory:"
    echo ""
    echo -e "   ${GREEN}cd /path/to/your/project${NC}"
    echo -e "   ${GREEN}opencode${NC}"
fi

echo ""
echo -e "${BLUE}Configuration:${NC}"
echo "  • Backend: Ollama (built from latest commit)"
echo "  • Model: $OLLAMA_MODEL"
echo "  • API Port: $PORT (OpenAI-compatible)"
echo "  • System RAM: ${TOTAL_RAM_GB}GB"
if [ "$INSTALL_EMBEDDING_MODEL" = "true" ]; then
    echo "  • Embeddings: nomic-embed-text (for semantic code search)"
fi
echo ""
echo -e "${BLUE}Apple Silicon Optimizations Enabled:${NC}"
echo "  • Metal GPU acceleration (all layers offloaded)"
echo "  • Apple Accelerate framework for BLAS operations"
echo "  • Native ARM64 CPU optimizations (-O3 -march=native)"
echo "  • CGO enabled for maximum performance"
echo ""
echo -e "${YELLOW}To change models later:${NC}"
echo "  1. Stop the server: kill \$(cat ~/.local/var/ollama-server.pid)"
echo "  2. Pull new model: $OLLAMA_BUILD_DIR/ollama pull <model-name>"
echo "  3. Update OpenCode config: ~/.config/opencode/opencode.jsonc"
echo "  4. Restart server"
echo ""
echo "  Available models: https://ollama.com/library/gemma4/tags"
echo ""

if [ "$BUILD_OPENCODE_FROM_SOURCE" = "true" ]; then
    echo -e "${YELLOW}To update OpenCode to latest dev commit:${NC}"
    echo "  rm -f ~/.opencode/bin/.custom-build-dev"
    echo "  BUILD_OPENCODE_FROM_SOURCE=true ./setup-gemma4-working.sh"
    echo ""
fi
