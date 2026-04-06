# Gemma 4 Working Setup (via llama.cpp)

This is a **proven working configuration** for running Gemma 4 with OpenCode on macOS, avoiding the current Ollama and OpenCode compatibility issues.

## Why This Approach?

As of April 2026:

- **Ollama v0.20.0 has Gemma 4 bugs**:
  - Tool call parser crashes ([#15241](https://github.com/ollama/ollama/issues/15241))
  - Streaming drops tool calls
  - `<unused25>` token spam

- **OpenCode has local provider issues**:
  - Can't handle non-standard tool call formats ([#20669](https://github.com/anomalyco/opencode/issues/20669), [#20719](https://github.com/anomalyco/opencode/issues/20719))

This setup uses:
- **llama.cpp** built from source with Gemma 4 fixes
- **OpenCode** built from source with tool-call compatibility layer

## Quick Start

```bash
cd ai_model

# Run the automated setup script
./setup-gemma4-working.sh

# To uninstall later
./uninstall-gemma4-working.sh
```

The script will:
0. ✅ Setup HuggingFace CLI via pipx with SSL certificate support
1. ✅ Build llama.cpp with Gemma 4 fixes (PRs #21326, #21343)
2. ✅ Install OpenCode (official installer)
3. ✅ Build OpenCode from source with PR #16531 (tool-call compat)
4. ✅ Create configuration files (opencode.jsonc, AGENTS.md, prompts)
5. ✅ Download Gemma 4 26B model (~16GB)
6. ✅ Start llama-server automatically

**Time:** ~15-30 minutes (compilation + model download)

**Idempotent:** Safe to run multiple times - skips already completed steps

## Configuration Options

The script supports environment variables for customization:

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

## Idempotency

The script is **fully idempotent** and safe to run multiple times:

- ✅ Skips llama.cpp build if already compiled
- ✅ Skips OpenCode custom build if already installed (checks marker file)
- ✅ Skips model download if already cached
- ✅ Skips launchd service if already loaded
- ✅ Only backs up OpenCode binary once (preserves original)

To force a rebuild:
```bash
# Force llama.cpp rebuild
rm -rf /tmp/llama-cpp-build

# Force OpenCode rebuild
rm ~/.opencode/bin/.custom-build-pr16531

# Force model re-download
rm -rf ~/.cache/huggingface/hub/models--ggml-org--gemma-4-26B-A4B-it-GGUF
```

## After Setup

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

### With AUTO_START=false (manual setup)

#### 1. Start llama-server

In a new terminal:

```bash
/tmp/llama-cpp-build/build/bin/llama-server \
  -m ~/.cache/huggingface/hub/models--ggml-org--gemma-4-26B-A4B-it-GGUF/snapshots/*/gemma-4-26B-A4B-it-Q4_K_M.gguf \
  --port 3456 -ngl 99 -c 131072 --jinja
```

Wait for: `listening on http://127.0.0.1:3456`

#### 2. Verify the server

```bash
curl http://127.0.0.1:3456/health
# Should return: {"status":"ok"}
```

#### 3. Run OpenCode

```bash
cd /path/to/your/project
opencode
```

## Memory Requirements

| Model | Context | RAM Needed | Best For |
|-------|---------|------------|----------|
| 26B Q4_K_M | 32K | ~17GB | Most users (32GB+ Macs) |
| 26B Q4_K_M | 64K | ~20GB | Longer sessions |
| 26B Q4_K_M | 128K | ~25GB | Maximum context |
| E4B Q4_K_M | 32K | ~10GB | 16GB Macs (weaker quality) |

**Important:** Close Chrome and heavy apps before running the 26B model.

## Configuration Files

The setup creates these in `~/.config/opencode/`:

- **opencode.jsonc** - Points OpenCode to llama-server on port 8089
  - Enables `toolParser` compatibility layer
  - Configures model limits and permissions

- **AGENTS.md** - Tool parameter reference for Gemma 4
  - Exact parameter names (camelCase: `filePath`, `oldString`, etc.)
  - Prevents common tool call errors

- **prompts/build.txt** - Build agent system prompt
  - Emphasizes immediate tool usage
  - Lists all available tools with examples

## Troubleshooting

### SSL Certificate Errors (CERTIFICATE_VERIFY_FAILED)

The script automatically installs pip-system-certs for corporate networks. If you still see SSL errors:

```bash
# Verify pip-system-certs is injected
pipx runpip huggingface-hub list | grep pip-system-certs

# Re-inject if needed
pipx inject huggingface-hub pip-system-certs

# Or manually set HF_TOKEN to avoid rate limits
export HF_TOKEN=your_huggingface_token
```

### Memory pressure / screen flickering
Close Chrome and other heavy apps. If still too much, use the E4B model:

```bash
/tmp/llama-cpp-build/build/bin/llama-server \
  -hf ggml-org/gemma-4-E4B-it-GGUF:Q4_K_M \
  --port 8089 -ngl 99 -c 32768 --jinja
```

### "Context size has been exceeded"
Increase the context size when starting llama-server:
- `-c 32768` (minimum, ~17GB RAM)
- `-c 65536` (recommended, ~20GB RAM)
- `-c 131072` (maximum, ~25GB RAM)

### Model doesn't call tools correctly
The `toolParser` and AGENTS.md help reduce errors, but Gemma 4 may take a few retries. This is expected.

### Download fails with `-hf` flag
Download manually:

```bash
# Install HF CLI if needed
pip install huggingface-cli

# Download model
huggingface-cli download ggml-org/gemma-4-26B-A4B-it-GGUF gemma-4-26B-A4B-it-Q4_K_M.gguf

# Start with local file
/tmp/llama-cpp-build/build/bin/llama-server \
  -m ~/.cache/huggingface/hub/models--ggml-org--gemma-4-26B-A4B-it-GGUF/snapshots/*/gemma-4-26B-A4B-it-Q4_K_M.gguf \
  --port 8089 -ngl 99 -c 32768 --jinja
```

### Rollback OpenCode
If the custom build has issues:

```bash
cp ~/.opencode/bin/opencode.backup ~/.opencode/bin/opencode
```

## Uninstallation

A comprehensive uninstaller is provided to cleanly remove all components:

```bash
cd ai_model
./uninstall-gemma4-working.sh
```

### What Gets Removed

The uninstaller is **interactive** and lets you choose what to remove:

1. **llama.cpp build** (~500MB)
   - Source code and compiled binaries
   - Build artifacts in `/tmp/llama-cpp-build`

2. **OpenCode custom build**
   - Custom PR #16531 binary
   - Option to restore original from backup
   - Build directory in `/tmp/opencode-build`

3. **Configuration files**
   - `~/.config/opencode/opencode.jsonc`
   - `~/.config/opencode/AGENTS.md`
   - `~/.config/opencode/prompts/build.txt`

4. **Gemma 4 26B model** (~16GB)
   - Downloaded GGUF file in HuggingFace cache
   - **Default: Keep** (models are reusable)

5. **Running processes**
   - Stops llama-server if running
   - Removes PID file

6. **launchd service**
   - Auto-start on login configuration
   - `/Library/LaunchAgents/com.llamacpp.server.plist`

7. **Log files**
   - `~/.local/var/log/llama-server.log`
   - `~/.local/var/llama-server.pid`

8. **HuggingFace CLI (optional)**
   - pipx installation with pip-system-certs
   - **Default: Keep** (may be used by other tools)

### Uninstall Examples

```bash
# Interactive mode (recommended)
./uninstall-gemma4-working.sh

# The script will:
# - Scan for installed components
# - Show sizes and locations
# - Ask what to remove
# - Display summary before proceeding
```

### Quick Clean (Keep Model Cache)

Most users want to remove the build artifacts but keep the downloaded model:

```bash
# The uninstaller defaults to:
# ✅ Remove llama.cpp build
# ✅ Remove OpenCode custom build + restore backup
# ✅ Remove configuration files
# ✅ Remove log files
# ✅ Remove launchd service
# ❌ Keep Gemma 4 model (16GB)
# ❌ Keep HuggingFace CLI
```

This reclaims ~500MB while preserving the 16GB model for reinstallation.

### Full Clean (Remove Everything)

To completely remove all traces including the model:

```bash
./uninstall-gemma4-working.sh
# Answer "yes" to all prompts including:
# - Remove downloaded Gemma 4 26B model? [y/N]: y
# - Uninstall HuggingFace CLI (pipx)? [y/N]: y
```

### Safety Features

- ✅ **Interactive prompts** - explicit confirmation for each component
- ✅ **Size display** - shows disk space to be reclaimed
- ✅ **Backup preservation** - restores original OpenCode if available
- ✅ **Smart defaults** - keeps reusable components (models, CLI tools)
- ✅ **Graceful stopping** - cleanly stops running processes
- ✅ **Empty directory cleanup** - removes directories only if empty

### After Uninstallation

To reinstall:
```bash
./setup-gemma4-working.sh
```

If you kept the model cache (~16GB), reinstallation will be much faster.

## Manual Setup

If you prefer manual steps, see the original guide:
https://gist.github.com/daniel-farina/87dc1c394b94e45bb700d27e9ea03193

## Comparison: setup-llamacpp.py vs setup-gemma4-working.sh

| Feature | setup-llamacpp.py | setup-gemma4-working.sh |
|---------|-------------------|-------------------------|
| **Backend** | Homebrew llama.cpp (stable) | Source build with Gemma 4 fixes |
| **OpenCode** | Official release | Custom build with tool-call compat |
| **Gemma 4 Support** | ⚠️ Limited (Homebrew lags) | ✅ Full (latest fixes) |
| **Tool Calling** | ⚠️ May have issues | ✅ Compatibility layer |
| **Maintenance** | Low (official packages) | Higher (source builds) |
| **Setup Time** | ~5 minutes | ~10-15 minutes (compilation) |
| **Recommended For** | Production use (when stable) | Current Gemma 4 users |

**Current Recommendation:** Use `setup-gemma4-working.sh` until:
1. Ollama releases v0.20.1+ with Gemma 4 fixes
2. OpenCode merges PR #16531
3. Homebrew llama.cpp updates to latest

Then switch back to `setup-llamacpp.py` for easier maintenance.

## Related Issues

- [ollama/ollama#15241](https://github.com/ollama/ollama/issues/15241) - Gemma4 tool call parsing fails
- [ggml-org/llama.cpp#21326](https://github.com/ggml-org/llama.cpp/pull/21326) - Gemma 4 template fix (merged)
- [ggml-org/llama.cpp#21343](https://github.com/ggml-org/llama.cpp/pull/21343) - Gemma 4 tokenizer fix
- [anomalyco/opencode#20669](https://github.com/anomalyco/opencode/issues/20669) - Local provider quirks
- [anomalyco/opencode#16531](https://github.com/anomalyco/opencode/pull/16531) - Tool-call compat PR

## Credits

Based on the excellent guide by [@daniel-farina](https://gist.github.com/daniel-farina/87dc1c394b94e45bb700d27e9ea03193).
