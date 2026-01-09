# Docker Model Runner + Continue.dev Setup

An interactive Python script that helps you set up a locally hosted LLM via **Docker Model Runner (DMR)** and generates a **continue.dev config.yaml** for VS Code.

**Optimized for Mac with Apple Silicon (M1/M2/M3/M4)** - Uses Metal GPU acceleration for fast local inference.

## Features

- 🍎 **Apple Silicon Optimized**: Detects M1/M2/M3/M4 chips and unified memory
- 🔍 **Hardware Auto-Detection**: Automatically detects RAM, CPU, GPU and classifies into hardware tiers
- 🐳 **Docker Model Runner Integration**: Uses Docker's native `docker model` commands
- 🤖 **Smart Model Recommendations**: Suggests optimal models based on your hardware tier
- ⚡ **Interactive Setup**: Guided experience with sensible defaults
- 📝 **Auto-Generated Config**: Creates continue.dev YAML config for VS Code
- 🔒 **Fully Local**: No cloud APIs, no telemetry, works offline after setup
- 🚀 **Metal Acceleration**: Automatic GPU acceleration on Apple Silicon

## Prerequisites

### Required

1. **Python 3.8+** - Comes pre-installed on macOS
2. **Docker Desktop 4.40+** - Download from [docker.com/desktop](https://docker.com/desktop)
3. **macOS with Apple Silicon** (recommended) or Linux/Windows with NVIDIA GPU

### Enable Docker Model Runner

Docker Model Runner must be enabled in Docker Desktop:

#### Option A: Via Docker Desktop UI

1. Open Docker Desktop
2. Click the ⚙️ **Settings** icon (top right)
3. Go to **Features in development** (or **Beta features**)
4. Enable **Docker Model Runner** or **Enable Docker AI**
5. Click **Apply & restart**

#### Option B: Via Terminal (macOS)

```bash
docker desktop enable model-runner --tcp 12434
```

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

All models use `ai.docker.com/` namespace and are optimized for Apple Silicon with Metal GPU acceleration.

### Chat/Edit Models (Primary)

| Model | Size | Unified Memory | Tiers | Docker Name |
|-------|------|----------------|-------|-------------|
| Llama 3.3 70B | 70B | ~35GB | S | `ai.docker.com/meta/llama3.3:70b-instruct-q4_K_M` |
| Llama 3.1 70B | 70B | ~35GB | S | `ai.docker.com/meta/llama3.1:70b-instruct-q4_K_M` |
| Qwen 2.5 Coder 32B | 32B | ~18GB | A, S | `ai.docker.com/qwen/qwen2.5-coder:32b-instruct-q4_K_M` |
| Codestral 22B | 22B | ~12GB | A, S | `ai.docker.com/mistral/codestral:22b-v0.1-q4_K_M` |
| Phi-4 14B | 14B | ~8GB | B, A, S | `ai.docker.com/microsoft/phi4:14b-q4_K_M` |
| Qwen 2.5 Coder 14B | 14B | ~8GB | B, A, S | `ai.docker.com/qwen/qwen2.5-coder:14b-instruct-q4_K_M` |
| Llama 3.2 8B | 8B | ~5GB | All | `ai.docker.com/meta/llama3.2:8b-instruct-q5_K_M` |
| Qwen 2.5 Coder 7B | 7B | ~4GB | All | `ai.docker.com/qwen/qwen2.5-coder:7b-instruct-q4_K_M` |

### Autocomplete Models (Fast)

| Model | Size | Unified Memory | Docker Name |
|-------|------|----------------|-------------|
| StarCoder2 3B | 3B | ~1.8GB | `ai.docker.com/bigcode/starcoder2:3b-q4_K_M` |
| Llama 3.2 3B | 3B | ~1.8GB | `ai.docker.com/meta/llama3.2:3b-instruct-q4_K_M` |
| Qwen 2.5 Coder 1.5B | 1.5B | ~1GB | `ai.docker.com/qwen/qwen2.5-coder:1.5b-instruct-q8_0` |

### Embedding Models (Code Indexing)

| Model | Unified Memory | Context | Docker Name |
|-------|----------------|---------|-------------|
| Nomic Embed Text v1.5 | ~0.3GB | 8192 | `ai.docker.com/nomic/nomic-embed-text:v1.5` |
| BGE-M3 | ~0.5GB | 8192 | `ai.docker.com/baai/bge-m3:latest` |
| All-MiniLM-L6-v2 | ~0.1GB | 512 | `ai.docker.com/sentence-transformers/all-minilm:l6-v2` |

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
# List installed models
docker model list

# Pull a model (example: Qwen 2.5 Coder 7B)
docker model pull ai.docker.com/qwen/qwen2.5-coder:7b-instruct-q4_K_M

# Run a model interactively (starts API server)
docker model run ai.docker.com/qwen/qwen2.5-coder:7b-instruct-q4_K_M

# Run with custom prompt
docker model run ai.docker.com/meta/llama3.2:8b-instruct-q5_K_M "Explain Python decorators"

# Remove a model
docker model rm ai.docker.com/qwen/qwen2.5-coder:7b-instruct-q4_K_M

# Enable Docker Model Runner (if not enabled)
docker desktop enable model-runner --tcp 12434
```

### API Endpoint

Docker Model Runner exposes an **OpenAI-compatible API** at:

```
http://localhost:12434/v1
```

You can test it with curl:

```bash
curl http://localhost:12434/v1/models
```

## Troubleshooting

### Docker Model Runner not available

1. Ensure Docker Desktop is version **4.40 or later**
2. Enable via terminal: `docker desktop enable model-runner --tcp 12434`
3. Or via UI: Settings → Features in development → Enable Docker Model Runner
4. Restart Docker Desktop

### Models not responding

```bash
# Check if models are installed
docker model list

# Run a model to start the API server
docker model run ai.docker.com/meta/llama3.2:8b-instruct-q5_K_M

# Test the API
curl http://localhost:12434/v1/models
```

### Continue.dev not connecting

1. Verify the API endpoint in `~/.continue/config.yaml`:
   ```yaml
   apiBase: http://localhost:12434/v1
   ```
2. Make sure a model is running (the API starts when you run a model)
3. Test the endpoint: `curl http://localhost:12434/v1/models`
4. Restart VS Code completely (Cmd+Q, then reopen)

### High Memory Usage on Apple Silicon

Apple Silicon uses **unified memory** shared between CPU, GPU, and Neural Engine:

1. Check your tier and use appropriate models:
   - **M1/M2 (8GB)**: Use Tier C models (7B or smaller)
   - **M1/M2 Pro (16GB)**: Use Tier C/B models (8B or smaller)
   - **M1/M2/M3 Pro (18-32GB)**: Use Tier B models (14B or smaller)
   - **M1/M2/M3 Max (32-48GB)**: Use Tier A models (22B or smaller)
   - **M1/M2/M3 Ultra (64GB+)**: Use Tier S models (70B)

2. Close memory-intensive apps before running large models
3. Use smaller autocomplete models (1.5B-3B) for faster response

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

## Comparison: Docker Model Runner vs Ollama

| Feature | Docker Model Runner | Ollama |
|---------|-------------------|--------|
| **Container-native** | ✅ Built into Docker | ❌ Separate service |
| **Docker Desktop integration** | ✅ Native `docker model` commands | ❌ External installation |
| **Apple Silicon (Metal)** | ✅ Automatic GPU acceleration | ✅ Automatic GPU acceleration |
| **NVIDIA GPU** | ✅ CUDA support | ✅ CUDA support |
| **Model format** | GGUF, Safetensors, ONNX | GGUF |
| **OpenAI-compatible API** | ✅ Port 12434 | ✅ Port 11434 |
| **Kubernetes ready** | ✅ Native container support | ⚠️ Requires wrapper |
| **Model registry** | Docker Hub AI models | Ollama library |
| **Setup complexity** | Low (toggle in Docker Desktop) | Low (brew install) |

### When to Use Docker Model Runner

- You're already using Docker Desktop
- You want container-native AI model management
- You need Kubernetes deployment
- You prefer unified Docker tooling

### When to Use Ollama

- You want a standalone solution
- You need Ollama-specific models
- You're using the existing `setup-local-llm.sh` script

## Contributing

1. Test thoroughly on your hardware tier
2. Ensure cross-platform compatibility (macOS, Linux, Windows)
3. Maintain backward compatibility
4. Update documentation

## License

MIT License - See LICENSE file for details.

---

**Setup complete?** Start coding with AI! Press `Cmd+L` in VS Code to open Continue.dev chat.
