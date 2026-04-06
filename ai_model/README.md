# Local LLM Setup for Continue.dev

Automated setup for locally hosted Large Language Models (LLMs) using **Ollama** with Continue.dev integration for VS Code and IntelliJ IDEA. Optimized for Apple Silicon Macs (M1/M2/M3/M4).

## 🎯 Overview

This project provides a complete automated setup for running LLMs locally using Ollama. It:

- Detects your Apple Silicon Mac hardware (CPU, RAM, Metal GPU)
- Installs fixed models optimized for coding (GPT-OSS 20B + nomic-embed-text)
- Configures Ollama service with automatic startup
- Generates Continue.dev configuration for your IDE
- Provides smart uninstallation with manifest tracking

**Simplified Architecture**: Previously supported dual backends (Docker + Ollama). Now focused exclusively on Ollama for better maintainability and user experience.

## ✨ Features

### Core Functionality
- **Hardware Detection**: Automatic detection of Apple Silicon, RAM, and Metal GPU
- **Fixed Model Installation**: GPT-OSS 20B (16GB) + nomic-embed-text (0.3GB)
- **Ollama Integration**: Full service management with automatic startup
- **Continue.dev Configuration**: Generates both YAML and JSON configs
- **IDE Auto-Detection**: Finds VS Code, Cursor, and IntelliJ IDEA
- **Smart Uninstallation**: Manifest-based removal with backup restoration

### Advanced Features
- **Reliable Model Pulling**: Verification after each pull with automatic retry
- **Progress Tracking**: Real-time download progress (percentage, speed, ETA)
- **VPN Resilience**: Works with VPN/corporate proxies
- **Backup & Restore**: Preserves existing Continue.dev configurations
- **Error Handling**: User-friendly error messages with troubleshooting steps

## 📦 Requirements

### System Requirements
- **macOS**: Apple Silicon (M1/M2/M3/M4) required
- **RAM**: 16GB minimum (20GB+ recommended)
- **Python**: 3.8 or higher
- **Ollama**: Installed automatically if not present

### Platform Support
- ✅ **macOS (Apple Silicon)**: Full support with Metal GPU acceleration
- ❌ **Linux/Windows**: Not currently supported (code requires Apple Silicon detection)

> **Note**: Despite hardware detection for other platforms, the model selector exits on non-Apple Silicon systems. See `MIGRATION_FROM_DOCKER.md` if you need multi-platform support.

## 🚀 Quick Start

```bash
# Clone or download this repository
cd ai_model

# Run setup (installs Ollama if needed, configures everything)
python3 setup.py

# Models will be pulled automatically:
# - gpt-oss:20b (16GB - primary coding model)
# - nomic-embed-text (0.3GB - embeddings for context)

# Verify installation
ollama list
```

## 📖 Usage

### Setup Script
```bash
python3 setup.py
```

**What it does:**
1. Detects Apple Silicon hardware and validates RAM (16GB+)
2. Installs/updates Ollama if needed
3. Pulls GPT-OSS 20B and nomic-embed-text models
4. Configures Ollama service for automatic startup
5. Generates Continue.dev configuration files
6. Creates global rules for assistant behavior
7. Saves installation manifest for smart uninstallation

### Uninstall Script
```bash
python3 uninstall.py
```

**What it does:**
1. Loads installation manifest
2. Removes installed models (preserves pre-existing models)
3. Stops Ollama service if installed by setup
4. Restores backed-up Continue.dev configs
5. Cleans up generated files and cache directories
6. Optionally uninstalls Ollama completely

### Check Status
```bash
# Ollama service status
ollama list

# Test model inference
ollama run gpt-oss:20b "Write hello world in Python"

# Check API endpoint
curl http://127.0.0.1:11434/api/tags
```

## 🏗️ Project Structure

```
ai_model/
├── lib/                    # Core library modules
│   ├── __init__.py        # Lazy-loading module exports
│   ├── config.py          # Continue.dev config generation
│   ├── hardware.py        # Hardware detection
│   ├── ide.py             # IDE detection and integration
│   ├── model_selector.py  # Model selection (fixed: GPT-OSS 20B)
│   ├── models.py          # Model catalog
│   ├── ollama.py          # Ollama service management
│   ├── ui.py              # Terminal UI utilities
│   ├── uninstaller.py     # Smart uninstallation
│   ├── utils.py           # General utilities
│   └── validator.py       # Model pulling and verification
├── tests/                  # Test suite
│   ├── conftest.py        # Shared pytest fixtures
│   ├── SPECIFICATIONS.md  # TDD behavioral specs
│   ├── test_*.py          # Unit, integration, e2e tests
│   └── ...
├── setup.py               # Main entry point
├── uninstall.py           # Uninstaller entry point
├── run_tests.py           # Test runner with auto venv
└── README.md              # This file
```

## 🎨 Architecture

### Module Responsibilities

| Module | Purpose | Key Functions |
|--------|---------|---------------|
| `hardware.py` | Hardware detection | `detect_hardware()` → `HardwareInfo` |
| `model_selector.py` | Model selection | `select_models()` → `List[RecommendedModel]` |
| `validator.py` | Model pulling & verification | `pull_models_with_tracking()` → `SetupResult` |
| `ollama.py` | Ollama service management | `setup_ollama()`, `configure_launchagent()` |
| `config.py` | Continue.dev config generation | `generate_continue_config()` → `Path` |
| `ide.py` | IDE detection & setup | `detect_installed_ides()` → `List[str]` |
| `uninstaller.py` | Smart uninstallation | `uninstall_with_manifest()` |

### Data Flow

```
setup.py
  ↓
hardware.detect_hardware() → HardwareInfo
  ↓
model_selector.select_models(hw_info) → [GPT-OSS 20B, nomic-embed-text]
  ↓
validator.pull_models_with_tracking(models) → SetupResult
  ↓
ollama.setup_ollama() → Configure service
  ↓
config.generate_continue_config(models, hw_info) → ~/.continue/config.yaml
  ↓
ide.detect_installed_ides() → Auto-detect VS Code/Cursor/IntelliJ
```

## ⚙️ Configuration

### Continue.dev Files

**Generated files:**
- `~/.continue/config.yaml` - Main configuration (VS Code, Cursor)
- `~/.continue/config.json` - JSON format (IntelliJ IDEA)
- `~/.continue/rules/global-rule.md` - Assistant behavior rules
- `~/.continue/.continueignore` - Files to exclude from context

**API Endpoint:**
```yaml
models:
  - name: GPT-OSS 20B
    provider: openai
    model: gpt-oss:20b
    apiBase: http://127.0.0.1:11434/v1  # Ollama API endpoint
    roles:
      - chat
      - edit
      - autocomplete
```

### Ollama Service

**LaunchAgent (macOS):**
- `~/Library/LaunchAgents/com.ollama.server.plist`
- Starts automatically on login
- Runs on port 11434

**Model Storage:**
- `~/.ollama/models/` - Downloaded models
- `~/.ollama/logs/` - Service logs

### Installation Manifest

**Manifest file:** `~/.continue/setup-manifest.json`

**Purpose:**
- Tracks installed models, files, and configurations
- Enables smart uninstallation (preserves pre-existing setup)
- Records hardware snapshot and installer version

**Example:**
```json
{
  "version": "2.0",
  "timestamp": "2026-04-06T...",
  "installer_version": "2.0.0",
  "hardware_snapshot": {
    "ram_gb": 16.0,
    "apple_chip_model": "Apple M3 Pro"
  },
  "pre_existing": {
    "models": [],  # Models that existed before setup
    "backups": {}   # Backed-up config files
  },
  "installed": {
    "models": [
      {"name": "gpt-oss:20b", "ram_gb": 16.0},
      {"name": "nomic-embed-text", "ram_gb": 0.3}
    ],
    "files": [
      "~/.continue/config.yaml",
      "~/.continue/config.json"
    ],
    "ollama_available": true
  }
}
```

## 💻 IDE Support

### Supported IDEs

| IDE | Support | Config Format | Detection |
|-----|---------|---------------|-----------|
| **VS Code** | ✅ Full | YAML + JSON | `~/.vscode/extensions/` |
| **Cursor** | ✅ Full | YAML + JSON | Auto-detected |
| **IntelliJ IDEA** | ✅ Full | JSON only | `/Applications/IntelliJ*` |

### Installing Continue Extension

**VS Code/Cursor:**
```bash
# Manual installation
code --install-extension continue.continue

# Or install via VS Code marketplace
```

**IntelliJ IDEA:**
1. File → Settings → Plugins
2. Search for "Continue"
3. Install and restart

### Verifying Setup

After running `setup.py`:
1. Open your IDE
2. Reload window (if Continue was already installed)
3. Open Continue chat panel
4. Type a message - should respond using GPT-OSS 20B
5. Check status bar - should show "● Ollama" (connected)

## 🖥️ Hardware Requirements

### Apple Silicon Tiers

| Tier | RAM | Chip | Model Size | Context | Status |
|------|-----|------|------------|---------|--------|
| **S** | 16GB | M1/M2/M3 | 20GB max | 32K | ✅ Supported |
| **A** | 18GB | M1/M2/M3 Pro | 20GB max | 32K | ✅ Supported |
| **B** | 24-32GB | M3 Pro/Max | 20GB max | 65K | ✅ Supported |
| **C** | 36-48GB | M1/M2/M3 Max/Ultra | 20GB max | 128K | ✅ Supported |

### RAM Allocation

- **System Reserved**: 30-40% (macOS, apps, browser)
- **Available for Models**: 60-70%
- **Model RAM Usage**: 16.3GB (GPT-OSS 20B + nomic-embed-text)
- **Minimum**: 16GB total RAM

### Metal GPU

All Apple Silicon Macs have unified memory with Metal GPU acceleration:
- M1/M2/M3: 8-10 GPU cores
- M1/M2/M3 Pro: 14-19 GPU cores
- M1/M2/M3 Max: 30-40 GPU cores
- M1/M2 Ultra: 48-76 GPU cores

## 📊 Model Catalog

### Installed Models

| Model | Size | RAM | Purpose | Context Length |
|-------|------|-----|---------|----------------|
| **gpt-oss:20b** | 16GB | 16GB | Primary coding model | 131K tokens |
| **nomic-embed-text** | 274MB | 0.3GB | Embeddings for context | 8K tokens |

### Model Details

**GPT-OSS 20B:**
- **Architecture**: GPT-style transformer
- **Parameters**: 20 billion
- **Training**: Open-source code datasets
- **Strengths**: Code generation, debugging, explanations
- **Roles**: chat, edit, autocomplete

**Nomic Embed Text:**
- **Architecture**: Sentence transformer
- **Purpose**: Convert text to vector embeddings
- **Use Case**: Semantic search in codebase context
- **Roles**: embed

### Model Selection Logic

**Fixed Selection (v4.0):**
```python
# No user choice - same models for all 16GB+ systems
models = [
    RecommendedModel(name="GPT-OSS 20B", ram_gb=16.0, roles=["chat", "edit", "autocomplete"]),
    RecommendedModel(name="Nomic Embed Text", ram_gb=0.3, roles=["embed"])
]
```

**Validation:**
- ✅ Apple Silicon detected
- ✅ 16GB+ RAM available
- ✅ Models fit in available memory (with safety margin)
- ❌ Exit if requirements not met

## 🔧 Troubleshooting

### Common Issues

**1. "Apple Silicon required" error**
```
Error: This setup only supports Apple Silicon Macs
```
**Solution**: Code currently requires Apple Silicon. For Intel/Linux/Windows support, see `MIGRATION_FROM_DOCKER.md`.

**2. "Insufficient RAM" error**
```
Error: 16GB RAM required (found: 8GB)
```
**Solution**: Upgrade to 16GB+ RAM or use smaller models (requires code modification).

**3. Ollama models not pulling**
```
Error: Failed to pull gpt-oss:20b
```
**Solutions:**
- Check internet connection
- Verify disk space (20GB+ free)
- Try manual pull: `ollama pull gpt-oss:20b`
- Check Ollama logs: `tail -f ~/.ollama/logs/server.log`

**4. Continue not connecting to Ollama**
```
Status: Disconnected from Ollama
```
**Solutions:**
- Verify Ollama running: `ollama list`
- Check API endpoint: `curl http://127.0.0.1:11434/api/tags`
- Restart Ollama: `pkill ollama && ollama serve`
- Check Continue config: `~/.continue/config.yaml`

**5. VPN/Corporate Proxy Issues**
```
Error: Connection refused / SSL error
```
**Solutions:**
- Script handles SSH_AUTH_SOCK automatically
- Uses `127.0.0.1` instead of `localhost` for VPN resilience
- SSL verification disabled for corporate proxies (security tradeoff)

### Debug Mode

Enable detailed logging:
```bash
# Set environment variable before running setup
export DEBUG=1
python3 setup.py
```

**Debug logs:**
- Console output shows all subprocess commands
- API call details and responses
- Model pull progress with detailed parsing

### Getting Help

1. **Check logs:**
   - Ollama: `~/.ollama/logs/server.log`
   - Setup: Console output during `setup.py`

2. **Verify setup:**
   ```bash
   ollama list                    # Should show gpt-oss:20b, nomic-embed-text
   cat ~/.continue/config.yaml    # Check configuration
   curl http://127.0.0.1:11434/api/tags  # Test API
   ```

3. **Clean reinstall:**
   ```bash
   python3 uninstall.py  # Clean uninstall
   python3 setup.py      # Fresh install
   ```

4. **Open an issue:** [GitHub Issues](https://github.com/[your-repo]/issues)

## 🗑️ Uninstallation

### Smart Uninstallation

```bash
python3 uninstall.py
```

**What gets removed:**
- Models installed by setup (gpt-oss:20b, nomic-embed-text)
- Generated config files (~/.continue/config.yaml, config.json)
- Global rules file (~/.continue/rules/global-rule.md)
- Cache directories

**What gets preserved:**
- Pre-existing models (tracked in manifest)
- Backed-up config files (restored automatically)
- Ollama installation (unless you choose to remove it)

### Manual Cleanup

If manifest is lost:
```bash
# Remove models
ollama rm gpt-oss:20b
ollama rm nomic-embed-text

# Remove configs
rm -rf ~/.continue/config.yaml
rm -rf ~/.continue/config.json
rm -rf ~/.continue/rules/global-rule.md

# Stop Ollama service
launchctl unload ~/Library/LaunchAgents/com.ollama.server.plist

# Optionally remove Ollama
brew uninstall ollama
rm -rf ~/.ollama
```

## 🧪 Development

### Running Tests

```bash
# Run all tests (auto-creates venv, installs dependencies)
python3 run_tests.py

# Run with coverage
python3 run_tests.py --cov

# Run specific tests
python3 run_tests.py -k "test_hardware"

# Verbose output
python3 run_tests.py -v

# Quick mode (skip slow tests)
python3 run_tests.py --quick
```

**Test Infrastructure:**
- Automatic virtual environment (`.venv/`)
- Auto-installs `pytest`, `pytest-cov` from `tests/requirements.txt`
- Parametrized fixtures for comprehensive coverage
- TDD approach with `SPECIFICATIONS.md` defining expected behavior

### Test Organization

```
tests/
├── conftest.py              # Shared fixtures and test configuration
├── SPECIFICATIONS.md        # Behavioral specifications for TDD
├── test_unit_*.py          # Unit tests (11 files)
├── test_integration.py     # Integration tests
├── test_e2e_flows.py       # End-to-end workflow tests
└── mocks.py                 # Test mocks and utilities
```

### Code Quality

**Type Hints:**
- 95%+ coverage with complete type annotations
- Uses `dataclasses`, `Optional`, `List`, `Dict`, `Tuple`

**Documentation:**
- Module docstrings
- Function docstrings with Args/Returns sections
- Inline comments for complex logic

**Architecture:**
- Clean module boundaries
- Single Responsibility Principle
- No circular dependencies

## 📝 Changelog

### v4.1.0 (2026-04-06) - Ollama-Only Refactoring
- **Breaking**: Removed Docker Model Runner backend
- **Simplified**: Single backend architecture (Ollama only)
- **Improved**: -40% code reduction (6,759 lines deleted)
- **Enhanced**: Flattened directory structure for clarity
- **Migration**: See `MIGRATION_FROM_DOCKER.md` for Docker users

### v4.0.0 (2025-01-13) - Fixed Model Selection
- **Changed**: Fixed model installation (GPT-OSS 20B + nomic-embed-text)
- **Removed**: Hardware-based model tier selection
- **Simplified**: No user choice needed
- **Added**: Manifest-based smart uninstallation

### v3.0.0 - Dual Backend Support
- **Added**: Docker Model Runner backend support
- **Added**: AI fine-tuning profiles (performance/balanced/quality)
- **Enhanced**: Parametrized test fixtures for both backends

### v2.0.0 - TDD Rewrite
- **Rewrote**: Test-driven development approach
- **Added**: SPECIFICATIONS.md with behavioral specs
- **Enhanced**: Hardware detection with Apple Silicon details

### v1.0.0 - Initial Release
- **Released**: Ollama setup automation
- **Features**: Hardware detection, model selection, Continue.dev config

## 📄 License

MIT License - See LICENSE file for details

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for new functionality
4. Ensure all tests pass (`python3 run_tests.py`)
5. Update documentation (README.md, docstrings)
6. Submit a pull request

### Development Guidelines
- Follow PEP 8 style guide
- Add type hints to all functions
- Write docstrings with Args/Returns sections
- Add unit tests for new functions
- Update `SPECIFICATIONS.md` for behavioral changes

## 🙏 Acknowledgments

- **Ollama** - Local LLM runtime (https://ollama.com)
- **Continue.dev** - AI coding assistant (https://continue.dev)
- **GPT-OSS** - Open-source coding model
- **Nomic AI** - Embedding models

---

**Questions?** Open an issue: [GitHub Issues](https://github.com/[your-repo]/issues)

**Migration Guide:** See `MIGRATION_FROM_DOCKER.md` for Docker Model Runner users
