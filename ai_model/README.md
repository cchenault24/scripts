# Docker Model Runner + Continue.dev Setup

A comprehensive, interactive Python script for setting up locally hosted Large Language Models (LLMs) via Docker Model Runner (DMR) and configuring Continue.dev for VS Code. Optimized for Mac with Apple Silicon (M1/M2/M3/M4) and supports Linux/Windows with NVIDIA GPUs.

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Project Structure](#project-structure)
- [Architecture](#architecture)
- [Configuration](#configuration)
- [Hardware Tiers](#hardware-tiers)
- [Model Catalog](#model-catalog)
- [Troubleshooting](#troubleshooting)
- [Uninstallation](#uninstallation)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

## 🎯 Overview

This project provides an automated setup solution for running LLMs locally using Docker Model Runner, a feature introduced in Docker Desktop 4.40+. It automatically:

- Detects your hardware capabilities (CPU, RAM, GPU)
- Recommends appropriate models based on your system
- Pulls and configures models via Docker Model Runner
- Generates Continue.dev configuration files for VS Code
- Generates global rules file for assistant behavior
- Sets up the complete development environment

The setup is optimized for Apple Silicon Macs with Metal GPU acceleration, but also supports Linux and Windows systems with NVIDIA GPUs.

## ✨ Features

### Core Functionality

- **Hardware Detection**: Automatically detects CPU, RAM, GPU, and Apple Silicon details
- **Tier Classification**: Classifies hardware into tiers (S, A, B, C, D) for model recommendations
- **Model Selection**: Interactive model selection with hardware-aware recommendations
- **Portfolio Recommendations**: Suggests model portfolios based on hardware tier
- **Docker Integration**: Full Docker Model Runner integration for model management
- **Continue.dev Configuration**: Generates both YAML and JSON config files
- **Global Rules**: Automatically generates `global-rule.md` with assistant behavior rules
- **VS Code Integration**: Optional automatic extension installation and setup

### Advanced Features

- **Variant Discovery**: Automatically discovers and selects optimal model variants (quantization levels)
- **RAM Validation**: Validates model selections against available system memory
- **API Endpoint Detection**: Automatically detects Docker Model Runner API endpoints
- **Backup & Restore**: Backs up existing Continue.dev configs before overwriting
- **Progress Tracking**: Enhanced progress bars with optional `rich` library support
- **Error Handling**: Comprehensive error handling with user-friendly messages

### Platform Support

- **macOS**: Full support with Apple Silicon optimization (Metal GPU acceleration)
- **Linux**: Support with NVIDIA GPU detection
- **Windows**: Support with NVIDIA GPU detection

## 📦 Requirements

### System Requirements

- **Python**: 3.8 or higher
- **Docker Desktop**: 4.40 or later (with Docker Model Runner enabled)
- **Operating System**:
  - macOS 12.0+ (recommended for Apple Silicon)
  - Linux (with NVIDIA drivers for GPU support)
  - Windows 10/11 (with NVIDIA drivers for GPU support)

### Hardware Recommendations

- **Minimum**: 8GB RAM (Tier D)
- **Recommended**: 16GB+ RAM (Tier B or higher)
- **Optimal**: 32GB+ RAM (Tier A or S) for larger models

### Optional Dependencies

The script works with Python standard library only, but can optionally use:

- `rich>=13.7.0`: Enhanced terminal output with progress bars (auto-installed if available)
- `pyyaml>=6.0`: YAML parsing (not required - script has built-in YAML generator)
- `requests>=2.31.0`: HTTP requests (not required - uses subprocess for docker commands)

## 🚀 Installation

### 1. Clone or Download

```bash
cd /path/to/your/scripts
# If using git:
git clone <repository-url> ai_model
# Or download and extract the ai_model folder
```

### 2. Verify Python

```bash
python3 --version  # Should be 3.8+
```

### 3. Install Docker Desktop

1. Download from [docker.com/desktop](https://docker.com/desktop)
2. Install and start Docker Desktop
3. Enable Docker Model Runner:
   - Open Docker Desktop
   - Go to Settings → Features in development (or Beta features)
   - Enable "Docker Model Runner" or "Enable Docker AI"
   - Click "Apply & restart"

   Or via terminal:
   ```bash
   docker desktop enable model-runner --tcp 12434
   ```

### 4. Verify Docker Model Runner

```bash
docker model list
```

If this command works, Docker Model Runner is enabled.

## 🎬 Quick Start

### Basic Setup

```bash
cd ai_model
python3 docker-llm-setup.py
```

The script will:
1. Detect your hardware
2. Check Docker and Docker Model Runner
3. Guide you through model selection
4. Pull selected models
5. Generate Continue.dev configuration
6. Generate global rules file
7. Provide next steps

### Preset Selection

The script offers presets based on your hardware tier:
- **Tier S** (>64GB RAM): Large models for complex tasks
- **Tier A** (32-64GB RAM): High-quality models
- **Tier B** (17-32GB RAM): Balanced models
- **Tier C** (8-17GB RAM): Efficient models
- **Tier D** (<8GB RAM): Minimal models

### Custom Selection

Choose "Custom" preset to manually select models based on your needs.

## 📖 Usage

### Setup Script

```bash
python3 docker-llm-setup.py
```

**Interactive Flow:**
1. Hardware detection
2. Docker verification
3. Docker Model Runner check
4. Preset selection (or Custom)
5. Model selection (with recommendations)
6. RAM usage validation
7. Model pulling
8. Configuration generation
9. Global rules generation
10. Next steps display

### Uninstall Script

```bash
python3 docker-llm-uninstall.py
```

**Options:**
```bash
# Skip Docker checks (useful if Docker is hanging)
python3 docker-llm-uninstall.py --skip-docker-checks

# Skip model removal
python3 docker-llm-uninstall.py --skip-models

# Skip config file removal
python3 docker-llm-uninstall.py --skip-config

# Skip VS Code extension removal
python3 docker-llm-uninstall.py --skip-extension
```

### Docker Model Runner Commands

After setup, you can manage models directly:

```bash
# List installed models
docker model list

# Pull a model
docker model pull ai/llama3.2

# Run a model interactively
docker model run ai/llama3.2

# Remove a model
docker model rm ai/llama3.2
```

## 📁 Project Structure

```
ai_model/
├── docker-llm-setup.py          # Main setup script
├── docker-llm-uninstall.py     # Uninstaller script
├── requirements-docker-setup.txt  # Optional dependencies
├── README.md                    # This file
└── lib/                         # Library modules
    ├── __init__.py              # Package initialization
    ├── config.py                # Continue.dev config generation
    ├── docker.py                # Docker & DMR management
    ├── hardware.py              # Hardware detection & classification
    ├── models.py                # Model catalog & selection
    ├── ui.py                    # Terminal UI utilities
    ├── utils.py                 # General utilities
    └── vscode.py                # VS Code integration
```

## 🏗️ Architecture

### Module Overview

#### `docker-llm-setup.py`
Main entry point. Orchestrates the setup workflow:
- Hardware detection
- Docker verification
- Model selection
- Configuration generation
- User guidance

#### `lib/hardware.py`
Hardware detection and classification:
- **HardwareInfo**: Dataclass for system information
- **HardwareTier**: Enum for tier classification (S, A, B, C, D)
- **detect_hardware()**: Detects CPU, RAM, GPU, Apple Silicon details
- **calculate_os_overhead()**: Calculates OS memory overhead
- **get_estimated_model_memory()**: Estimates available RAM for models

#### `lib/models.py`
Model catalog and selection:
- **ModelInfo**: Dataclass for model metadata
- **MODEL_CATALOG**: Comprehensive model catalog
- **select_preset()**: Preset selection based on hardware tier
- **select_models()**: Interactive model selection
- **generate_portfolio_recommendation()**: Hardware-aware recommendations
- **pull_models_docker()**: Pulls models via Docker Model Runner
- **validate_model_selection()**: Validates RAM usage

#### `lib/docker.py`
Docker and Docker Model Runner management:
- **check_docker()**: Verifies Docker installation
- **check_docker_model_runner()**: Verifies DMR availability
- **fetch_available_models_from_api()**: Fetches models from DMR API

#### `lib/config.py`
Continue.dev configuration generation:
- **generate_continue_config()**: Generates config.yaml and config.json
- **generate_global_rule()**: Generates global-rule.md with assistant behavior rules
- **save_setup_summary()**: Saves setup summary JSON
- **generate_yaml()**: YAML generation utility

#### `lib/vscode.py`
VS Code integration:
- **install_vscode_extension()**: Installs Continue.dev extension
- **show_next_steps()**: Displays post-setup instructions
- **restart_vscode()**: Restarts VS Code (macOS)

#### `lib/ui.py`
Terminal UI utilities:
- **Colors**: ANSI color codes
- **print_header()**, **print_subheader()**: Formatted headers
- **print_success()**, **print_error()**, **print_warning()**: Status messages
- **prompt_yes_no()**, **prompt_choice()**: Interactive prompts

#### `lib/utils.py`
General utilities:
- **run_command()**: Execute shell commands with timeout

### Data Flow

```
User Input
    ↓
Hardware Detection → Tier Classification
    ↓
Preset Selection → Model Recommendations
    ↓
Model Selection → RAM Validation
    ↓
Model Pulling → Configuration Generation → Global Rules Generation
    ↓
VS Code Setup → Next Steps
```

## ⚙️ Configuration

### Continue.dev Config Location

- **macOS/Linux**: `~/.continue/config.yaml`
- **Windows**: `%USERPROFILE%\.continue\config.yaml`

### Global Rules Location

- **macOS/Linux**: `~/.continue/rules/global-rule.md`
- **Windows**: `%USERPROFILE%\.continue\rules\global-rule.md`

### Config Structure

The generated config includes:
- **Models**: Chat, edit, autocomplete, and embedding models
  - All models include `supportsToolCalls: false` to fix @codebase compatibility with local models
  - Chat models have roles: `chat`, `edit`, `apply`
  - Autocomplete models have `autocompleteOptions` with optimized settings
  - Embedding models have role: `embed`
  - All models use `defaultCompletionOptions.contextLength` for context window
- **API Endpoint**: Docker Model Runner API (typically `http://localhost:12434/v1`)
- **Context Providers**: Codebase, folder, file, terminal, diff, problems, open (using new `context` format)
- **Experimental Settings** (extension-specific): 
  - `streamAfterToolRejection: true` - Prevents model from stopping mid-response if it tries to use a tool inappropriately (fixes palindrome/response interruption issues)
  - Note: `codebaseUseToolCallingOnly` removed - using `supportsToolCalls: false` on models instead
- **UI Settings** (extension-specific): 
  - `showChatScrollbar: true` - Shows scrollbar in chat interface
  - `wrapCodeblocks: true` - Wraps long code blocks for better readability
  - `formatMarkdown: true` - Enables markdown formatting
  - `textToSpeechOutput: false` - Disables TTS (not needed for coding)

**Note**: The script no longer includes `systemMessage` in the config.yaml. All assistant behavior is controlled by the `global-rule.md` file.

### Global Rules Structure

The generated `global-rule.md` includes:
- **CRITICAL RESPONSE RULE**: Guidelines for when to provide code vs. English explanations
- **Output Format**: Rules for response formatting (no metadata, direct answers)
- **React Components**: Guidelines for functional vs. class components
- **TypeScript**: Type safety and best practices
- **Redux**: State management patterns
- **Material-UI**: Component usage guidelines
- **Code Quality**: Production-ready code standards

### Manual Configuration

You can manually edit the generated config:

```yaml
models:
  - name: Llama 3.2
    provider: openai
    model: ai/llama3.2
    apiBase: http://localhost:12434/v1
    roles:
      - chat
      - edit
      - apply
    defaultCompletionOptions:
      contextLength: 131072
    supportsToolCalls: false

  - name: Llama 3.2 3B (Autocomplete)
    provider: openai
    model: ai/llama3.2:3b
    apiBase: http://localhost:12434/v1
    roles:
      - autocomplete
    autocompleteOptions:
      debounceDelay: 300
      modelTimeout: 3000
    defaultCompletionOptions:
      contextLength: 131072
    supportsToolCalls: false

context:
  - provider: codebase
  - provider: file
  - provider: code
  - provider: terminal
  - provider: diff

experimental:
  streamAfterToolRejection: true

ui:
  showChatScrollbar: true
  wrapCodeblocks: true
  formatMarkdown: true
  textToSpeechOutput: false
```

### Backup Files

The script automatically backs up existing configs to:
- `~/.continue/config.yaml.backup`
- `~/.continue/rules/global-rule.md.backup`

## 🖥️ Hardware Tiers

The script classifies hardware into tiers based on total RAM:

| Tier | RAM Range | Description | Typical Models |
|------|-----------|-------------|----------------|
| **S** | >64GB | High-end workstations | Llama 3.3, Llama 3.1, Granite 4.0 H-Small |
| **A** | 32-64GB | Professional systems | Granite 4.0 H-Small, Codestral 22B, Devstral Small |
| **B** | 17-32GB | Mid-range systems | Phi-4, Granite 4.0 H-Micro, CodeLlama 13B |
| **C** | 8-17GB | Entry-level systems | Granite 4.0 H-Nano, CodeGemma 7B, Llama 3.2 |
| **D** | <8GB | Minimal systems | StarCoder2 3B, minimal models |

### Apple Silicon Optimization

For Apple Silicon Macs:
- **Metal GPU Acceleration**: Automatic via Docker Model Runner
- **Unified Memory**: Shared CPU/GPU/Neural Engine memory
- **Neural Engine**: 16-32 cores available for acceleration
- **Optimized Models**: Quantized variants for efficient inference

## 🤖 Model Catalog

### Model Categories

#### Chat/Edit Models
- **Large** (Tier S): Llama 3.3, Llama 3.1
- **Medium-Large** (Tier A): Granite 4.0 H-Small, Codestral 22B
- **Medium** (Tier B): Phi-4, Granite 4.0 H-Micro, CodeLlama 13B
- **Small** (Tier C): Granite 4.0 H-Nano, CodeGemma 7B, Llama 3.2

#### Autocomplete Models
- **Ultra-fast**: StarCoder2 3B, Llama 3.2 (small variants)

#### Embedding Models
- **Code Embeddings**: Specialized models for semantic code search

### Model Variants

Some models support automatic variant discovery:
- **Quantization Levels**: Q4_K_M, Q5_K_M, Q8_0, etc.
- **Hardware-Aware Selection**: Automatically selects optimal variant
- **RAM Optimization**: Balances quality vs. memory usage

### Model Roles

- **chat**: General conversation and code assistance
- **edit**: Code editing and refactoring
- **autocomplete**: Tab autocomplete in VS Code
- **embed**: Semantic code search embeddings
- **agent**: Agentic workflows

## 🔧 Troubleshooting

### Docker Model Runner Not Available

**Problem**: `docker model list` returns "unknown command"

**Solutions**:
1. Update Docker Desktop to 4.40+
2. Enable Docker Model Runner in Settings → Features in development
3. Restart Docker Desktop
4. Run: `docker desktop enable model-runner --tcp 12434`

### Models Not Pulling

**Problem**: `docker model pull` fails or hangs

**Solutions**:
1. Check Docker Desktop is running
2. Verify internet connection
3. Check Docker Hub access
4. Try pulling manually: `docker model pull ai/llama3.2`
5. Check Docker logs: Docker Desktop → Troubleshoot → View logs

### API Endpoint Not Reachable

**Problem**: Continue.dev can't connect to model API

**Solutions**:
1. Verify model is running: `docker model list`
2. Start model: `docker model run <model-name>`
3. Check API endpoint: `curl http://localhost:12434/v1/models`
4. Verify port 12434 is not blocked by firewall

### Insufficient RAM

**Problem**: Validation fails due to insufficient RAM

**Solutions**:
1. Select smaller models (lower RAM requirements)
2. Close other applications to free RAM
3. Use quantized variants (Q4_K_M, Q5_K_M)
4. Consider upgrading hardware

### VS Code Extension Not Working

**Problem**: Continue.dev extension doesn't load config

**Solutions**:
1. Restart VS Code completely
2. Check config file exists: `~/.continue/config.yaml`
3. Verify YAML syntax is valid
4. Check VS Code output panel for errors
5. Reinstall Continue.dev extension

### Apple Silicon Issues

**Problem**: Models run slowly or use CPU instead of GPU

**Solutions**:
1. Verify Docker Desktop is using Apple Silicon version
2. Check Metal acceleration is enabled in Docker Desktop
3. Ensure models are Apple Silicon optimized
4. Check Activity Monitor for GPU usage

## 🗑️ Uninstallation

### Full Uninstallation

```bash
python3 docker-llm-uninstall.py
```

This will:
1. Remove Docker models (optional)
2. Remove Continue.dev config files (optional)
3. Restore backup config if available (optional)
4. Remove VS Code extension (optional)

### Selective Uninstallation

Use flags to skip specific steps:

```bash
# Only remove models
python3 docker-llm-uninstall.py --skip-config --skip-extension

# Only remove config files
python3 docker-llm-uninstall.py --skip-models --skip-extension
```

### Manual Cleanup

If the uninstaller doesn't work:

```bash
# Remove models manually
docker model rm <model-name>

# Remove config files
rm ~/.continue/config.yaml
rm ~/.continue/config.json
rm ~/.continue/rules/global-rule.md

# Restore backups
cp ~/.continue/config.yaml.backup ~/.continue/config.yaml
cp ~/.continue/rules/global-rule.md.backup ~/.continue/rules/global-rule.md
```

## 💻 Development

### Project Setup

```bash
# Clone repository
git clone <repository-url>
cd ai_model

# Verify Python version
python3 --version

# (Optional) Install development dependencies
pip install -r requirements-docker-setup.txt
```

### Code Structure

- **Modular Design**: Each module has a specific responsibility
- **Type Hints**: Full type annotations for better IDE support
- **Error Handling**: Comprehensive try/except blocks
- **User Feedback**: Clear, colored terminal output
- **Documentation**: Docstrings for all functions

### Adding New Models

Edit `lib/models.py` and add to `MODEL_CATALOG`:

```python
ModelInfo(
    name="New Model",
    docker_name="ai/new-model",
    description="Description of the model",
    ram_gb=8.0,
    context_length=32768,
    roles=["chat", "edit"],
    tiers=[hardware.HardwareTier.B, hardware.HardwareTier.C],
    recommended_for=["Use case description"]
)
```

### Testing

```bash
# Test hardware detection
python3 -c "from lib import hardware; print(hardware.detect_hardware())"

# Test Docker check
python3 -c "from lib import docker; print(docker.check_docker())"

# Test model catalog
python3 -c "from lib import models; print(len(models.MODEL_CATALOG))"
```

### Debugging

Enable verbose output by modifying `lib/utils.py`:

```python
def run_command(cmd, capture=True, timeout=300):
    # Add print statements for debugging
    print(f"Running: {' '.join(cmd)}")
    # ... rest of function
```

## 🤝 Contributing

Contributions are welcome! Areas for improvement:

- Additional model support
- Better hardware detection
- Enhanced error messages
- Cross-platform improvements
- Documentation updates

### Contribution Guidelines

1. Follow existing code style
2. Add type hints to new functions
3. Update docstrings
4. Test on multiple platforms
5. Update README if adding features

## 📄 License

MIT License - See LICENSE file for details.

## 🔗 References

- **Docker Model Runner**: [docs.docker.com/ai/model-runner/](https://docs.docker.com/ai/model-runner/)
- **Continue.dev**: [docs.continue.dev](https://docs.continue.dev)
- **Docker Desktop**: [docker.com/desktop](https://docker.com/desktop)

## 📝 Changelog

### Version 2.0.0
- **Fixed @codebase compatibility**: Added `supportsToolCalls: false` to all models to fix "Error parsing chat history" error
- **Removed deprecated setting**: Removed `codebaseUseToolCallingOnly` from experimental (replaced with model-level `supportsToolCalls: false`)
- **Updated to official schema**: 
  - Changed `contextProviders` to `context` (new format)
  - Moved `contextLength` to `defaultCompletionOptions.contextLength`
  - Moved autocomplete settings to model-level `autocompleteOptions`
  - Removed deprecated fields: `tabAutocompleteModel`, `embeddingsProvider`, `slashCommands`, `allowAnonymousTelemetry`
- **Improved model configuration**: All models now properly configured with roles, completion options, and tool calling settings

### Version 1.1.0
- Added experimental settings to config.yaml:
  - `streamAfterToolRejection: true` - Prevents response interruption on tool rejection
- Added UI settings to config.yaml:
  - Enhanced readability settings (scrollbar, codeblock wrapping, markdown formatting)
  - Disabled text-to-speech output
- Added autocomplete settings to model-level `autocompleteOptions`:
  - Optimized `debounceDelay: 300` and `modelTimeout: 3000` for local llama3.3 model performance on M4 Pro

### Version 1.0.0
- Initial release
- Hardware detection and tier classification
- Model catalog with variant discovery
- Continue.dev configuration generation
- Global rules file generation
- VS Code integration
- Uninstaller script
- Apple Silicon optimization

## 🙏 Acknowledgments

- Docker for Docker Model Runner
- Continue.dev team for the VS Code extension
- Model providers (Meta, Mistral, IBM, Google, etc.)
- Open source community

---

**Note**: This project is not affiliated with Docker, Continue.dev, or any model providers. It is an independent tool for setting up local LLM development environments.
