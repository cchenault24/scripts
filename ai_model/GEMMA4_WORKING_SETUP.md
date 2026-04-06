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
```

The script will:
1. ✅ Build llama.cpp with Gemma 4 fixes (PRs #21326, #21343)
2. ✅ Install OpenCode (official installer)
3. ✅ Build OpenCode from source with PR #16531 (tool-call compat)
4. ✅ Create configuration files (opencode.jsonc, AGENTS.md, prompts)

**Time:** ~10-15 minutes (mostly compilation)

## After Setup

### 1. Start llama-server

In a new terminal:

```bash
# For 32GB RAM (recommended)
/tmp/llama-cpp-build/build/bin/llama-server \
  -hf ggml-org/gemma-4-26B-A4B-it-GGUF:Q4_K_M \
  --port 8089 -ngl 99 -c 32768 --jinja
```

Wait for: `listening on http://127.0.0.1:8089`

### 2. Verify the server

```bash
curl http://127.0.0.1:8089/health
# Should return: {"status":"ok"}
```

### 3. Run OpenCode

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
