# Gemma 4 + llama.cpp + OpenCode Setup

Automated setup for **Gemma 4 26B** with **llama.cpp** and **OpenCode** on macOS. This is a proven working configuration that avoids current Ollama and OpenCode compatibility issues.

## 🎯 Overview

This project provides a **minimal, bash-only** setup for running Gemma 4 26B locally with OpenCode, bypassing known issues:
- ✅ **llama.cpp** with Gemma 4 tokenizer fixes (PR #21343)
- ✅ **OpenCode** with tool-call compatibility layer (PR #16531)
- ✅ **Automatic SSL certificate support** for corporate networks
- ✅ **Automatic model download and server startup**
- ✅ **Comprehensive uninstaller** for clean removal
- ✅ **No Python dependencies** - self-contained bash scripts

**Based on**: [daniel-farina's proven guide](https://gist.github.com/daniel-farina/87dc1c394b94e45bb700d27e9ea03193)

## ✨ Why This Setup?

**As of April 2026:**

- **Ollama v0.20.0** has Gemma 4 bugs:
  - Tool call parser crashes ([#15241](https://github.com/ollama/ollama/issues/15241))
  - Streaming drops tool calls
  - `<unused25>` token spam

- **OpenCode** has local provider issues:
  - Can't handle non-standard tool call formats ([#20669](https://github.com/anomalyco/opencode/issues/20669), [#20719](https://github.com/anomalyco/opencode/issues/20719))

**This setup uses:**
- **llama.cpp** built from source with Gemma 4 fixes
- **OpenCode** built from source with tool-call compatibility
- **HuggingFace CLI** with SSL certificate support

## 📦 Requirements

### System Requirements
- **macOS**: Apple Silicon (M1/M2/M3/M4)
- **RAM**: 24GB+ recommended (32GB ideal)
- **Homebrew**: For dependencies
- **XCode Command Line Tools**: For compilation

### Automatic Dependencies
The setup script automatically installs:
- `pipx` - Python application isolation
- `git` - Version control (if missing)
- `gh` - GitHub CLI (if missing)
- `cmake` - Build system (if missing)
- `bun` - JavaScript runtime (if missing)
- `huggingface-hub` - Model downloads with SSL support

## 🚀 Quick Start

```bash
cd ai_model

# Run the automated setup script
./setup-gemma4-working.sh

# The script will:
# 0. Setup HuggingFace CLI with SSL certificate support
# 1. Build llama.cpp with Gemma 4 fixes (~5 min)
# 2. Install OpenCode via official installer
# 3. Build OpenCode custom version with tool-call compat (~5 min)
# 4. Create configuration files
# 5. Download Gemma 4 26B model (~16GB, 10-30 min)
# 6. Start llama-server automatically

# Total time: ~15-30 minutes
```

## ⚙️ Configuration Options

The script supports environment variables:

```bash
# Skip auto-download and auto-start (manual setup)
AUTO_START=false ./setup-gemma4-working.sh

# Enable auto-start on login (launchd service)
AUTO_START_ON_LOGIN=true ./setup-gemma4-working.sh

# Custom context size (default: 131072)
CONTEXT_SIZE=65536 ./setup-gemma4-working.sh

# Custom port (default: 3456)
PORT=8089 ./setup-gemma4-working.sh
```

## 🔄 Idempotency

The script is **fully idempotent** and safe to run multiple times:

- ✅ Skips llama.cpp build if already compiled
- ✅ Skips OpenCode custom build if already installed
- ✅ Skips model download if already cached
- ✅ Skips launchd service if already loaded
- ✅ Only backs up OpenCode binary once

## 📖 After Setup

### With AUTO_START=true (default)

The server is already running! 🎉

```bash
# Verify it's working
curl http://127.0.0.1:3456/health

# View logs
tail -f ~/.local/var/log/llama-server.log

# Stop the server
kill $(cat ~/.local/var/llama-server.pid)

# Start using OpenCode
cd /path/to/your/project
opencode
```

### Memory Requirements

| Context Size | RAM Needed | Best For |
|--------------|------------|----------|
| 32K (32768) | ~17GB | Most users |
| 64K (65536) | ~20GB | Longer sessions |
| 128K (131072) | ~25GB | Maximum context |

## 🗑️ Uninstallation

A comprehensive uninstaller is provided:

```bash
cd ai_model
./uninstall-gemma4-working.sh
```

### What It Does

The uninstaller is **interactive** and lets you choose:

1. **llama.cpp build** (~500MB) - Build artifacts
2. **OpenCode custom build** - Restore original backup
3. **Configuration files** - OpenCode configs
4. **Gemma 4 26B model** (~16GB) - **Default: Keep** (reusable)
5. **Running processes** - Stop llama-server
6. **launchd service** - Auto-start configuration
7. **Log files** - Server logs and PID files
8. **HuggingFace CLI** - **Default: Keep** (shared tool)

**Typical removal** (keeps model for reinstall):
- Frees ~500MB
- Keeps 16GB model cache for quick reinstall

**Full removal** (everything):
- Frees ~17GB
- Returns system to pre-install state

## 📝 Documentation

- **[GEMMA4_WORKING_SETUP.md](./GEMMA4_WORKING_SETUP.md)** - Complete setup guide
- **[REFACTORING_SUMMARY.md](./REFACTORING_SUMMARY.md)** - Project history

## 🔧 Troubleshooting

### SSL Certificate Errors

The script automatically installs pip-system-certs. If you see SSL errors:

```bash
# Verify injection
pipx runpip huggingface-hub list | grep pip-system-certs

# Re-inject if needed
pipx inject huggingface-hub pip-system-certs
```

### Memory Pressure / Screen Flickering

Close Chrome and heavy apps. If still too much, reduce context size:

```bash
CONTEXT_SIZE=65536 ./setup-gemma4-working.sh
```

### Model Download Fails

Set HuggingFace token for better rate limits:

```bash
export HF_TOKEN=your_token_here
./setup-gemma4-working.sh
```

### Server Won't Start

Check logs for errors:

```bash
tail -50 ~/.local/var/log/llama-server.log
```

## 📁 Project Structure

```
ai_model/
├── setup-gemma4-working.sh        # Main installer (bash)
├── uninstall-gemma4-working.sh    # Comprehensive uninstaller (bash)
├── GEMMA4_WORKING_SETUP.md        # Detailed setup guide
├── README.md                      # This file
└── REFACTORING_SUMMARY.md         # Project history
```

**Note**: This is a minimal, production-ready package with no dependencies. The scripts are self-contained bash scripts that don't require Python or any external libraries.

## 🤝 Contributing

This is a working solution for current Gemma 4 compatibility issues. Once the upstream projects fix their bugs:
- Ollama v0.20.1+ with Gemma 4 fixes
- OpenCode merges PR #16531
- Homebrew llama.cpp updates

You can switch back to simpler official packages.

## 📄 License

MIT

## 🙏 Credits

- Setup approach: [@daniel-farina](https://gist.github.com/daniel-farina/87dc1c394b94e45bb700d27e9ea03193)
- llama.cpp: [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)
- OpenCode: [anomalyco/opencode](https://github.com/anomalyco/opencode)
- Gemma 4: Google
