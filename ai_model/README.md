# Comprehensive Local LLM Setup

Enterprise-ready setup for running Meta Llama, Mistral, Microsoft Phi, and Google Gemma models locally on Apple Silicon Macs.

## Features

- **Multi-Model Support** - 13 models across 4 families
- **Intelligent Recommendations** - RAM-based model suggestions
- **Multiple Clients** - Continue.dev (IDE), Open WebUI (browser), OpenCode CLI
- **Apple Silicon Optimized** - LTO, Metal, Flash Attention
- **Security First** - Only US/EU models, blocks risky sources
- **Enterprise Ready** - Unattended install, presets, health checks

---

## Quick Start

```bash
# Clone or download
cd ai_model

# Interactive setup
./lib/ollama-setup.sh

# Start the server
source lib/common.sh && start_ollama_server

# Pull your first model
ollama pull llama3.2:3b-instruct-q8_0
```

**Hardware detected?** We'll recommend the best model for your RAM.

---

## Model Families

| Family | Models | Best For | RAM Range |
|--------|--------|----------|-----------|
| **Llama** (Meta) | 4 models | General purpose, balanced | 16-48GB |
| **Mistral/Codestral** (Mistral AI) | 3 models | Code generation, development | 24-32GB |
| **Phi** (Microsoft) | 2 models | Reasoning, math, logic | 8-24GB |
| **Gemma** (Google) | 4 models | Large context (256K), documents | 16-48GB |

### Popular Models

- `llama3.3:70b-instruct-q4_K_M` - Best overall quality (42GB, needs 48GB RAM)
- `codestral:22b-v0.1-q8_0` - Purpose-built for code (25GB, needs 32GB RAM)
- `llama3.2:11b-instruct-q8_0` - Balanced performance (12GB, needs 24GB RAM)
- `llama3.2:3b-instruct-q8_0` - Fast responses (3GB, needs 16GB RAM)
- `phi4:14b-q8_0` - Reasoning and math (14GB, needs 24GB RAM)
- `gemma4:31b-it-q8_0` - Large context window (34GB, needs 48GB RAM)

---

## Hardware Requirements

### Minimum
- Apple Silicon Mac (M1 or later)
- 16GB RAM
- 50GB free disk space
- macOS 13.0 or later

### Recommended
- M3 or later
- 32GB+ RAM
- 100GB+ free disk space
- Fast internet for model downloads

### RAM Recommendations

| Your RAM | Recommended Models |
|----------|-------------------|
| 16GB | llama3.2:3b, phi3.5:3.8b, gemma4:e2b |
| 24GB | llama3.2:11b, mistral-nemo:12b, phi4:14b |
| 32GB | codestral:22b, gemma4:26b |
| 48GB+ | llama3.3:70b, gemma4:31b |

---

## Client Interfaces

### 1. Continue.dev (IDE Integration)
**Best for:** Daily coding, autocomplete, inline edits

**Supported IDEs:**
- JetBrains (IntelliJ, PyCharm, WebStorm, etc.)
- VS Code

**Features:**
- AI-powered autocomplete
- Inline code editing
- Chat interface in sidebar
- Context-aware suggestions

**Setup:** Install plugin from IDE marketplace, configure `~/.continue/config.json`

### 2. Open WebUI (Browser Interface)
**Best for:** Testing models, demos, non-developers

**Features:**
- Browser-based at `localhost:8080`
- Chat interface similar to ChatGPT
- Model switching
- Conversation history

**Setup:** Docker-based, configured via `lib/webui-setup.sh`

### 3. OpenCode CLI (Terminal Interface)
**Best for:** Automation, scripts, CI/CD pipelines

**Features:**
- Command-line access
- Scriptable interactions
- Pipeline integration
- Batch processing

**Setup:** npm/bun installation via `lib/opencode-setup.sh`

---

## Usage Examples

### Server Management

```bash
# Source common utilities first
source lib/common.sh

# Start server
start_ollama_server

# Check status
ollama_status

# Stop server
stop_ollama_server

# Health check
curl http://localhost:11434/api/tags
```

### Model Operations

```bash
# List available models
ollama list

# Pull a specific model
ollama pull llama3.2:11b-instruct-q8_0

# Run model interactively
ollama run llama3.2:11b-instruct-q8_0

# Remove model
ollama rm llama3.2:11b-instruct-q8_0
```

### Installation with Presets

```bash
# Developer preset (Codestral for code)
export MODEL_FAMILY=mistral
export MODEL=codestral:22b-v0.1-q8_0
./lib/ollama-setup.sh

# Researcher preset (Llama 70B for quality)
export MODEL_FAMILY=llama
export MODEL=llama3.3:70b-instruct-q4_K_M
./lib/ollama-setup.sh

# Production preset (Balanced 11B)
export MODEL_FAMILY=llama
export MODEL=llama3.2:11b-instruct-q8_0
./lib/ollama-setup.sh
```

---

## Utilities

### Library Scripts (`lib/`)

| Script | Purpose |
|--------|---------|
| `common.sh` | Core utilities, hardware detection, print functions |
| `model-families.sh` | Model definitions, security filters, recommendations |
| `ollama-setup.sh` | Build Ollama, server management, optimizations |
| `continue-setup.sh` | Configure Continue.dev plugin for IDEs |
| `webui-setup.sh` | Setup Open WebUI Docker container |
| `opencode-setup.sh` | Install OpenCode CLI tool |

### Testing

```bash
# Test Ollama installation
./test-ollama-setup.sh
```

---

## Documentation

Comprehensive guides available in `docs/`:

- **[Model Selection Guide](docs/MODEL_GUIDE.md)** - Choose the right model for your needs
- **[Client Setup](docs/CLIENT_SETUP.md)** - Configure Continue.dev, WebUI, OpenCode
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[Team Deployment](docs/TEAM_DEPLOYMENT.md)** - Enterprise rollout guide

---

## Architecture

```
ai_model/
├── lib/                      # Core libraries (modular design)
│   ├── common.sh            # Utilities, hardware detection
│   ├── model-families.sh    # Model definitions, security
│   ├── ollama-setup.sh      # Ollama build & management
│   ├── continue-setup.sh    # IDE plugin configuration
│   ├── webui-setup.sh       # Browser UI setup
│   └── opencode-setup.sh    # CLI tool setup
├── docs/                     # Comprehensive documentation
│   ├── MODEL_GUIDE.md       # Model selection help
│   ├── CLIENT_SETUP.md      # Client configuration
│   ├── TROUBLESHOOTING.md   # Problem solving
│   └── TEAM_DEPLOYMENT.md   # Enterprise guide
├── presets/                  # Pre-configured setups
│   ├── developer.env        # Code-focused
│   ├── researcher.env       # Quality-focused
│   └── production.env       # Balanced
└── test-ollama-setup.sh     # Integration tests
```

**Design Philosophy:**
- Modular library structure (`lib/`) for maintainability
- Comprehensive documentation (`docs/`) for self-service
- Preset configurations for quick deployment
- Source-first approach for latest features

---

## Performance

### Apple Silicon Optimizations

**Build-time optimizations:**
- Link-Time Optimization (LTO) enabled
- Native ARM64 compilation
- Metal GPU acceleration
- Accelerate framework integration

**Runtime optimizations:**
- `OLLAMA_KEEP_ALIVE=-1` (keep models loaded)
- `OLLAMA_NUM_GPU=999` (all layers on GPU)
- `OLLAMA_FLASH_ATTENTION=1` (faster attention)

### Inference Speed Benchmarks

Approximate tokens/second on M3 Max 64GB:

| Model | Speed | Use Case |
|-------|-------|----------|
| llama3.2:3b-instruct-q8_0 | ~90 t/s | Fast iteration |
| llama3.2:11b-instruct-q8_0 | ~45 t/s | General use |
| phi4:14b-q8_0 | ~40 t/s | Reasoning |
| codestral:22b-v0.1-q8_0 | ~30 t/s | Code generation |
| gemma4:31b-it-q8_0 | ~22 t/s | Large context |
| llama3.3:70b-instruct-q4_K_M | ~12 t/s | Best quality |

**Note:** Actual speeds vary based on hardware, context length, and system load.

### Quantization

| Format | Size | Quality | When to Use |
|--------|------|---------|-------------|
| Q8_0 | 50% | 99% | Maximum quality, sufficient RAM |
| Q4_K_M | 25% | 95-98% | Fit larger models, limited RAM |

**Example:** Llama 3.3 70B
- FP16: ~140GB (impractical)
- Q8_0: ~70GB (requires 80GB+ RAM)
- Q4_K_M: ~42GB (runs on 48GB RAM)

---

## Security

### Model Source Verification

**Allowlist (US/EU sources only):**
- Meta Llama (USA)
- Mistral/Codestral (France)
- Microsoft Phi (USA)
- Google Gemma (USA)

**Blocklist (enforced by `model-families.sh`):**
- DeepSeek, Qwen, Yi, Baichuan, ChatGLM (Chinese sources)

**Function:** `is_model_allowed()` in `lib/model-families.sh`

### Local-Only Operation

- All processing happens on-device
- No data sent to external servers
- No telemetry or tracking
- Ollama binds to localhost only (127.0.0.1)

### Best Practices

1. Only use approved model families
2. Verify model checksums when downloading manually
3. Keep configs in version control
4. Regular security updates via rebuild
5. Audit model usage in team environments

---

## Troubleshooting

### Common Issues

**1. Slow Inference Performance**
- **Cause:** Not all layers on GPU
- **Solution:** Set `OLLAMA_NUM_GPU=999`, restart Ollama
- **Verify:** Check GPU usage in Activity Monitor

**2. Out of Memory Errors**
- **Cause:** Model too large for available RAM
- **Solution:** Switch to smaller model or Q4_K_M quantization
- **Check:** Use recommended models for your RAM tier

**3. Port Already in Use**
- **Cause:** Another Ollama instance running
- **Solution:** `pkill ollama` or use custom port
- **Verify:** `lsof -i :11434`

**4. Model Download Fails**
- **Cause:** Network issues or disk space
- **Solution:** Check internet, ensure 50GB+ free space
- **Retry:** Use `ollama pull <model> --insecure` for proxies

For more issues, see [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

---

## Contributing

### Development

```bash
# Run tests
./test-ollama-setup.sh

# Check library functions
source lib/common.sh
detect_m_chip
detect_ram_gb

# Validate model definitions
source lib/model-families.sh
display_model_families_summary
```

### Adding New Models

1. Edit `lib/model-families.sh`
2. Add model to appropriate family array
3. Format: `"name|size_gb|min_ram_gb|context|quantization|use_case"`
4. Update documentation in `docs/MODEL_GUIDE.md`

### Code Style

- Use shellcheck for linting
- Follow existing naming conventions
- Add comments for complex logic
- Test with `set -euo pipefail`

---

## License

MIT License - See [LICENSE](../LICENSE) file for details.

### Third-Party Software

- **Ollama** - MIT License
- **Continue.dev** - Apache 2.0 License
- **Open WebUI** - MIT License
- **OpenCode** - ISC License

---

## Changelog

### 2026-04-07
- Complete modularization into `lib/` structure
- Added comprehensive documentation suite
- Implemented preset configurations
- Enhanced security with allowlist/blocklist
- Added integration tests
- Performance optimizations for Apple Silicon

---

## Support

### Resources

- **Documentation:** `docs/` directory
- **Issues:** Check `TROUBLESHOOTING.md` first
- **Model Help:** See `MODEL_GUIDE.md`
- **Team Setup:** Review `TEAM_DEPLOYMENT.md`

### Community

- Ollama: https://ollama.com
- Continue.dev: https://continue.dev
- Open WebUI: https://github.com/open-webui/open-webui

---

## Acknowledgments

Built with:
- **Ollama** - Local LLM inference engine
- **Meta Llama** - State-of-the-art language models
- **Mistral AI** - Specialized code models
- **Microsoft Phi** - Reasoning-focused models
- **Google Gemma** - Large context models

Optimized for Apple Silicon by the community.

---

*Last Updated: 2026-04-07*
*Version: 1.0.0*
