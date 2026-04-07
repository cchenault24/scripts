# Gemma 4 + Ollama + OpenCode Setup

Automated setup for running Gemma 4 models locally with Ollama and OpenCode on Apple Silicon.

## Quick Start

```bash
# Interactive setup (recommended)
./setup-gemma4-working.sh

# Or use new modular version
./setup.sh
```

## Scripts Overview

### Main Scripts

- **`setup-gemma4-working.sh`** - Complete all-in-one setup (952 lines)
  - Full-featured with all configuration options
  - Includes OpenCode installation and configuration
  - Recommended for first-time setup

- **`setup.sh`** - Modular setup orchestrator (new)
  - Cleaner, focused implementation
  - Sources functionality from `lib/` modules
  - Easier to maintain and extend

- **`llama-control.sh`** - Server management
  ```bash
  ./llama-control.sh start    # Start Ollama server
  ./llama-control.sh stop     # Stop server
  ./llama-control.sh restart  # Restart server
  ./llama-control.sh status   # Check status and list models
  ./llama-control.sh logs     # View logs
  ./llama-control.sh models   # List installed models
  ```

- **`uninstall-gemma4-working.sh`** - Clean uninstaller
  - Interactive removal of all components
  - Selective uninstallation options

### Library Modules (`lib/`)

- **`common.sh`** - Shared utilities
  - Color definitions
  - Print functions (print_status, print_error, etc.)
  - System detection (RAM, architecture)
  - Prerequisites checking

- **`model-selection.sh`** - Interactive model selection
  - RAM-based recommendations
  - Shows already installed models
  - 8 Gemma 4 model variants to choose from

- **`ollama-setup.sh`** - Ollama build and management
  - Build from latest main branch commit
  - Apple Silicon optimizations (Metal, Accelerate, native ARM64)
  - Server startup with keep-alive
  - Model pulling and optimization (128K/256K context)

## Usage Examples

### Environment Variables

```bash
# Skip model selection
OLLAMA_MODEL=gemma4:26b-a4b-it-q4_K_M ./setup.sh

# Build OpenCode from dev branch
BUILD_OPENCODE_FROM_SOURCE=true ./setup.sh

# Skip embedding model
INSTALL_EMBEDDING_MODEL=false ./setup.sh

# Skip auto-start
AUTO_START=false ./setup.sh
```

### Model Options

| Model | Size | Context | RAM Needed | Best For |
|-------|------|---------|------------|----------|
| gemma4:e2b-it-q4_K_M | 7.2GB | 128K | 16GB+ | Small/fast |
| gemma4:e4b-it-q8_0 | 12GB | 128K | 24GB+ | Balanced |
| gemma4:26b-a4b-it-q4_K_M | 18GB | 256K | 32GB+ | Large codebases |
| gemma4:31b-it-q8_0 | 34GB | 256K | 48GB+ | Maximum quality |

## Architecture

```
setup.sh (orchestrator)
├── lib/common.sh          # Shared utilities
├── lib/model-selection.sh # Model selection
└── lib/ollama-setup.sh    # Ollama build & management

setup-gemma4-working.sh    # All-in-one (legacy)
llama-control.sh           # Server control
uninstall-gemma4-working.sh # Cleanup
```

## Features

### Performance Optimizations
- **OLLAMA_KEEP_ALIVE=-1**: Models stay in memory (no cold starts)
- **Metal GPU**: All layers offloaded to Apple Silicon GPU
- **Accelerate framework**: Optimized BLAS operations
- **Native ARM64**: `-O3 -march=native -mtune=native` compilation flags
- **Proper context sizes**: 128K for e2b/e4b, 256K for 26b/31b models

### Embedding Support
- Automatic installation of `nomic-embed-text` (274MB)
- Optimized for semantic code search
- Essential for large codebases (1000+ files)

### OpenCode Integration
- **Multiple specialized agents**:
  - `build` - Full-featured coding agent with edit permissions
  - `review` - Code review expert (read-only, no edits)
  - `refactor` - Refactoring specialist with safety checks
- **Gemma 4 optimizations**:
  - `repeat_penalty: 1.1` - Reduces repetitive responses
  - `num_predict: 16384` - Ensures complete responses
- **Large codebase workflows**:
  - Context management for 10,000+ files
  - Task tool integration for efficient exploration
  - Few-shot examples showing correct patterns
- **Comprehensive tool documentation**:
  - Best practices for each tool
  - Common mistakes to avoid
  - Workflow guidance for different scenarios
- Proper model name format (colons, not dashes)

## Requirements

- macOS Apple Silicon (M1/M2/M3/M4)
- 24GB+ RAM (32GB+ recommended)
- Homebrew
- Internet connection

Dependencies auto-installed: `git`, `go`, `bun`

## Configuration Files

```
~/.config/opencode/
├── opencode.jsonc          # Main configuration
├── AGENTS.md               # Agent instructions
└── prompts/
    └── build.txt           # Build agent prompt

~/.local/var/
├── ollama-server.pid       # Server PID
└── log/
    └── ollama-server.log   # Server logs
```

## Troubleshooting

### Server not responding
```bash
./llama-control.sh logs     # Check logs
./llama-control.sh restart  # Restart server
```

### Model not found
Ensure model name uses colons, not dashes:
- ✅ `gemma4:e4b-it-q8_0`
- ❌ `gemma4-e4b-it-q8_0`

### Context truncation
Models are auto-configured with proper context sizes. If you see truncation warnings, check:
```bash
./llama-control.sh models   # Verify -128k or -256k suffix
```

### Rebuild from scratch
```bash
rm -rf /tmp/ollama-build
./setup.sh
```

## Updates

### Update Ollama
```bash
rm -rf /tmp/ollama-build
./setup.sh  # Rebuilds from latest commit
```

### Update OpenCode
```bash
# Official release
opencode update

# Dev branch build
BUILD_OPENCODE_FROM_SOURCE=true ./setup.sh
```

## License

MIT

## Credits

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
