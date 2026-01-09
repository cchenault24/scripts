# Docker Model Runner + Continue.dev Setup

An interactive Python script that helps you set up a locally hosted LLM via **Docker Model Runner** and generates a **continue.dev config.yaml** for VS Code.

## Features

- 🔍 **Hardware Auto-Detection**: Automatically detects RAM, CPU, GPU and classifies your system into hardware tiers
- 🐳 **Docker Model Runner Integration**: Uses Docker's native AI model running capabilities
- 🤖 **Smart Model Recommendations**: Suggests optimal models based on your hardware tier
- ⚡ **Interactive Setup**: Guided experience with sensible defaults
- 📝 **Auto-Generated Config**: Creates continue.dev YAML config for VS Code
- 🔒 **Fully Local**: No cloud APIs, no telemetry, works offline after setup

## Prerequisites

### Required

1. **Python 3.8+** - Comes pre-installed on macOS and most Linux distributions
2. **Docker Desktop 4.40+** - Download from [docker.com/desktop](https://docker.com/desktop)

### Docker Model Runner Setup

Docker Model Runner is a feature in Docker Desktop that allows you to run AI models locally:

1. Open Docker Desktop
2. Go to **Settings** → **Features in development**
3. Enable **Docker Model Runner** (or **Docker AI**)
4. Click **Apply & Restart**

## Quick Start

```bash
# Navigate to the ai_model directory
cd ai_model

# Run the setup script
python3 docker-llm-setup.py
```

Or make it executable and run directly:

```bash
chmod +x docker-llm-setup.py
./docker-llm-setup.py
```

## Hardware Tiers

The script automatically classifies your system based on RAM:

| Tier | RAM | Recommended Models |
|------|-----|-------------------|
| **S** | ≥49GB | Llama 3.3 70B, Qwen 2.5 Coder 32B |
| **A** | 33-48GB | Codestral 22B, Qwen 2.5 Coder 14B |
| **B** | 17-32GB | Phi-4 14B, Llama 3.1 8B |
| **C** | <17GB | Qwen 2.5 Coder 7B, StarCoder2 3B |

## Available Models

### Chat/Edit Models (Primary)

| Model | Size | RAM | Description |
|-------|------|-----|-------------|
| Llama 3.3 70B | 70B | ~35GB | Highest quality for complex tasks |
| Llama 3.1 70B | 70B | ~35GB | Excellent for architecture work |
| Qwen 2.5 Coder 32B | 32B | ~16GB | State-of-the-art coding |
| Codestral 22B | 22B | ~11GB | Excellent code generation |
| Phi-4 14B | 14B | ~7GB | Great reasoning |
| Llama 3.1 8B | 8B | ~4GB | Fast general-purpose |
| Qwen 2.5 Coder 7B | 7B | ~3.5GB | Efficient coding |

### Autocomplete Models (Fast)

| Model | Size | RAM | Description |
|-------|------|-----|-------------|
| StarCoder2 3B | 3B | ~1.5GB | Ultra-fast autocomplete |
| Llama 3.2 3B | 3B | ~1.5GB | Small and efficient |

### Embedding Models (Code Indexing)

| Model | Size | RAM | Description |
|-------|------|-----|-------------|
| Nomic Embed Text | - | ~0.3GB | Best for code indexing |
| BGE Large | - | ~0.4GB | High-quality embeddings |

## Generated Configuration

The script generates a `config.yaml` at `~/.continue/config.yaml` that includes:

- **Models**: Selected chat, autocomplete, and embedding models
- **Tab Autocomplete**: Configured for fast code completion
- **Embeddings**: For semantic code search with `@Codebase`
- **Context Providers**: Codebase, folder, file, terminal, diff, problems

### Example Config

```yaml
models:
  - name: Qwen 2.5 Coder 14B
    provider: openai
    model: qwen2.5-coder:14B-Q4_K_M
    apiBase: http://localhost:12434/v1
    contextLength: 32768
    roles:
      - chat
      - edit
      - apply

tabAutocompleteModel:
  provider: openai
  model: starcoder2:3B-Q4_K_M
  apiBase: http://localhost:12434/v1

embeddingsProvider:
  provider: openai
  model: nomic-embed-text:latest
  apiBase: http://localhost:12434/v1

contextProviders:
  - name: codebase
  - name: folder
  - name: file
  - name: terminal

allowAnonymousTelemetry: false
```

## Using Continue.dev in VS Code

### Installation

1. Open VS Code
2. Press `Cmd+Shift+X` (or `Ctrl+Shift+X` on Windows/Linux)
3. Search for "Continue" and install the Continue.dev extension
4. Restart VS Code

### Usage

| Shortcut | Action |
|----------|--------|
| `Cmd+L` / `Ctrl+L` | Open Continue.dev chat |
| `Cmd+K` / `Ctrl+K` | Inline edit selected code |
| `Tab` | Accept autocomplete suggestion |
| `@Codebase` | Search codebase semantically |
| `@file` | Reference a specific file |
| `@folder` | Reference a folder |

## Docker Model Runner Commands

```bash
# List available models
docker model list

# Pull a model
docker model pull ai/llama3.1:8B-Q5_K_M

# Start model runner
docker model start

# Check running models
docker model ps

# Stop model runner
docker model stop
```

## Troubleshooting

### Docker Model Runner not available

1. Ensure Docker Desktop is version 4.40 or later
2. Go to Settings → Features in development → Enable Docker Model Runner
3. Apply & Restart Docker Desktop

### Models not responding

1. Check if Docker Model Runner is running: `docker model ps`
2. Start it if needed: `docker model start`
3. Verify the model is pulled: `docker model list`

### Continue.dev not connecting

1. Check the API endpoint in `~/.continue/config.yaml`
2. Default Docker Model Runner port is `12434`
3. Verify with: `curl http://localhost:12434/v1/models`

### High RAM usage

1. Use smaller models appropriate for your tier
2. Only run one chat model at a time
3. Close other memory-intensive applications

## File Structure

```
ai_model/
├── docker-llm-setup.py         # Main setup script
├── DOCKER_SETUP_README.md      # This file
├── requirements-docker-setup.txt # Python requirements
└── ~/.continue/
    ├── config.yaml             # Generated Continue.dev config
    └── config.json             # JSON version of config
```

## Comparison with Ollama Setup

| Feature | Docker Model Runner | Ollama |
|---------|-------------------|--------|
| Container-native | ✅ Yes | ❌ No (separate service) |
| Docker Desktop integration | ✅ Built-in | ❌ External |
| GPU support | ✅ NVIDIA, Apple Silicon | ✅ NVIDIA, Apple Silicon |
| Model format | GGUF, Safetensors | GGUF |
| OpenAI-compatible API | ✅ Yes | ✅ Yes |
| Kubernetes ready | ✅ Yes | ⚠️ Requires extra setup |

## Contributing

1. Test thoroughly on your hardware tier
2. Ensure cross-platform compatibility (macOS, Linux, Windows)
3. Maintain backward compatibility
4. Update documentation

## License

MIT License - See LICENSE file for details.

---

**Setup complete?** Start coding with AI! Press `Cmd+L` in VS Code to open Continue.dev chat.
