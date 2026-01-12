# Local LLM Setup for Continue.dev

A comprehensive, interactive Python script for setting up locally hosted Large Language Models (LLMs) and configuring Continue.dev for VS Code and IntelliJ IDEA. Optimized for Mac with Apple Silicon (M1/M2/M3/M4) and supports Linux/Windows with NVIDIA GPUs.

## Installation Options

This project supports two local LLM backends:

### Option 1: Docker Model Runner (Recommended for Docker users)
- **Requires**: Docker Desktop 4.40+ (with Docker Model Runner enabled)
- **Setup**: `python3 docker/docker-llm-setup.py`
- **Pros**: Integrated with Docker, official Docker images
- **Cons**: Requires Docker Desktop

### Option 2: Ollama (Recommended for standalone installation)
- **Requires**: Ollama installed (https://ollama.com)
- **Setup**: `python3 ollama/ollama-llm-setup.py`
- **Pros**: Lightweight, dedicated LLM runtime, easier setup
- **Cons**: Separate installation required

Both options generate the same Continue.dev configuration and work identically in VS Code and IntelliJ IDEA.

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
- [IDE Support](#ide-support)
- [Hardware Requirements](#hardware-requirements)
- [Model Catalog](#model-catalog)
- [Troubleshooting](#troubleshooting)
- [Uninstallation](#uninstallation)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

## 🎯 Overview

This project provides an automated setup solution for running LLMs locally using either Docker Model Runner or Ollama. It automatically:

- Detects your hardware capabilities (CPU, RAM, GPU)
- Recommends appropriate models based on your system
- Pulls and configures models via Docker Model Runner or Ollama (your choice)
- Generates Continue.dev configuration files for VS Code and IntelliJ IDEA
- Generates global rules file for assistant behavior
- Sets up the complete development environment

The setup is optimized for Apple Silicon Macs with Metal GPU acceleration, but also supports Linux and Windows systems with NVIDIA GPUs. Both Docker Model Runner and Ollama backends are fully supported.

## ✨ Features

### Core Functionality

- **Hardware Detection**: Automatically detects CPU, RAM, GPU, and Apple Silicon details
- **Fixed Model Installation**: Installs GPT-OSS 20B and nomic-embed-text for all users (16GB+ RAM)
- **Simplified Setup**: Same two models for everyone - no complex selection needed
- **Backend Support**: Full support for both Docker Model Runner and Ollama
- **Docker Integration**: Full Docker Model Runner integration for model management (Docker option)
- **Ollama Integration**: Full Ollama integration for model management (Ollama option)
- **Continue.dev Configuration**: Generates both YAML and JSON config files
- **Global Rules**: Automatically generates `global-rule.md` with assistant behavior rules
- **VS Code Integration**: Optional automatic extension installation and setup
- **IntelliJ IDEA Support**: Full support for IntelliJ IDEA with Continue plugin

### Advanced Features (Ollama Setup v4.0)

> **Note:** "v4.0" refers to the setup script version (see [Changelog](#changelog)), not the Ollama product version. The module API version is `__version__ = "2.0.0"`.

- **Fixed Model Installation**: Installs GPT-OSS 20B and nomic-embed-text for all users
- **Reliable Model Pulling**: Verification after each pull with automatic retry on failure
- **IDE Auto-Detection**: Automatically finds VS Code, Cursor, and IntelliJ IDEA
- **Retry Mechanism**: Re-attempt failed model installations with one command

### Advanced Features (Both Backends)

- **RAM Validation**: Validates that models fit in available system memory
- **API Endpoint Detection**: Automatically detects API endpoints (Docker Model Runner or Ollama)
- **Backup & Restore**: Backs up existing Continue.dev configs before overwriting
- **Progress Tracking**: Enhanced progress bars with real-time download progress (percentage, speed, time remaining) for both Docker and Ollama backends, with optional `rich` library support (auto-installed if needed)
- **Error Handling**: Comprehensive error handling with user-friendly messages

### Platform Support

- **macOS**: Full support with Apple Silicon optimization (Metal GPU acceleration)
- **Linux**: Support with NVIDIA GPU detection
- **Windows**: Support with NVIDIA GPU detection

## 📦 Requirements

### System Requirements

- **Python**: 3.8 or higher
- **Backend** (choose one):
  - **Docker Desktop**: 4.40 or later (with Docker Model Runner enabled) - for Docker option
  - **Ollama**: Latest version (https://ollama.com) - for Ollama option
- **Operating System**:
  - macOS 12.0+ (recommended for Apple Silicon)
  - Linux (with NVIDIA drivers for GPU support)
  - Windows 10/11 (with NVIDIA drivers for GPU support)

### Hardware Recommendations

- **Minimum**: 16GB RAM - systems with less than 16GB RAM are not supported
- **Recommended**: 16GB+ RAM for GPT-OSS 20B (16GB) + nomic-embed-text (0.3GB)

### Optional Dependencies

The script works with Python standard library only, but can optionally use:

- `rich>=13.7.0`: Enhanced terminal output with progress bars (auto-installed if available)
- `pyyaml>=6.0`: YAML parsing (not required - script has built-in YAML generator)
- `requests>=2.31.0`: HTTP requests (not required - uses subprocess for backend commands)

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

### 3. Choose Your Backend

#### Option A: Docker Model Runner

1. Install Docker Desktop from [docker.com/desktop](https://docker.com/desktop)
2. Start Docker Desktop
3. Enable Docker Model Runner:
   - Open Docker Desktop
   - Go to Settings → Features in development (or Beta features)
   - Enable "Docker Model Runner" or "Enable Docker AI"
   - Click "Apply & restart"

   Or via terminal:
   ```bash
   docker desktop enable model-runner --tcp 12434
   ```

4. Verify Docker Model Runner:
   ```bash
   docker model list
   ```

#### Option B: Ollama

1. Install Ollama from [ollama.com](https://ollama.com)
2. Verify installation:
   ```bash
   ollama --version
   ollama list
   ```

## 🎬 Quick Start

### Docker Model Runner Setup

```bash
cd ai_model
python3 docker/docker-llm-setup.py
```

### Ollama Setup

```bash
cd ai_model
python3 ollama/ollama-llm-setup.py
```

The script will:
1. Detect your hardware
2. Check backend (Docker Model Runner or Ollama)
3. Guide you through model selection
4. Pull selected models
5. Generate Continue.dev configuration
6. Generate global rules file
7. Provide next steps

### Preset Selection (Docker)

The Docker script offers presets for model selection. All presets install the same two models:
- **GPT-OSS 20B** (16GB) - Primary reasoning/chat model
- **nomic-embed-text** (0.3GB) - Embedding model for code indexing

Choose "Custom" preset to manually select models if needed.

### Model Selection (Ollama Setup)

The Ollama script installs the same two models for all users:
- **Fixed models**: GPT-OSS 20B (primary) + Nomic Embed Text (embedding)
- **Simplified setup**: No model selection needed - same models for everyone
- **Consistent experience**: All users get the same high-quality models

Example recommendation for M3 Max 36GB:

```text
┌─────────────────────────────────────────────────────────┐
│  RECOMMENDED SETUP FOR YOUR SYSTEM                       │
│                                                          │
│  Primary (Chat/Edit):  gpt-oss:20b            ~16.0 GB   │
│  Embeddings:           nomic-embed-text        ~0.3 GB    │
│                                                          │
│  Total RAM usage: ~16.3 GB                               │
└─────────────────────────────────────────────────────────┘
```

Example recommendation for M4 Pro 48GB:

```text
┌─────────────────────────────────────────────────────────┐
│  RECOMMENDED SETUP FOR YOUR SYSTEM                       │
│                                                          │
│  Primary (Chat/Edit):  gpt-oss:20b            ~16.0 GB   │
│  Embeddings:           nomic-embed-text        ~0.3 GB    │
│                                                          │
│  Total RAM usage: ~16.3 GB                              │
└─────────────────────────────────────────────────────────┘
```

## 📖 Usage

### Setup Scripts

#### Docker Model Runner Setup

```bash
cd ai_model
python3 docker/docker-llm-setup.py
```

#### Ollama Setup

```bash
cd ai_model
python3 ollama/ollama-llm-setup.py
```

**Interactive Flow (Docker):**
1. Hardware detection
2. IDE selection (VS Code, IntelliJ IDEA, or Both)
3. Backend verification (Docker Model Runner)
4. API check
5. Preset selection (or Custom)
6. Model selection (fixed models: GPT-OSS 20B + nomic-embed-text)
7. RAM usage validation
8. Model pulling
9. Configuration generation
10. Global rules generation
11. Next steps display

**Interactive Flow (Ollama Setup):**
1. Hardware detection (Mac model + RAM)
2. IDE auto-detection (VS Code, Cursor, IntelliJ IDEA)
3. Ollama service verification
4. API check
5. **Model selection** - displays the two fixed models (GPT-OSS 20B + nomic-embed-text)
6. **Confirm installation** - proceed with the models
7. Pre-installation validation (RAM, network, API)
8. Model pulling with verification and automatic retry
9. Setup result display (success/failures with retry options)
10. Configuration generation
11. Global rules generation
12. Next steps display

### Uninstall Scripts

#### Docker Model Runner Uninstall

```bash
python3 docker/docker-llm-uninstall.py
```

#### Ollama Uninstall

```bash
python3 ollama/ollama-llm-uninstall.py
```

**Options (both uninstallers):**
```bash
# Skip backend checks (useful if backend is hanging)
python3 docker/docker-llm-uninstall.py --skip-docker-checks
python3 ollama/ollama-llm-uninstall.py --skip-docker-checks

# Skip model removal
python3 docker/docker-llm-uninstall.py --skip-models
python3 ollama/ollama-llm-uninstall.py --skip-models

# Skip config file removal
python3 docker/docker-llm-uninstall.py --skip-config
python3 ollama/ollama-llm-uninstall.py --skip-config

# Skip both VS Code extension and IntelliJ plugin removal
python3 docker/docker-llm-uninstall.py --skip-extension
python3 ollama/ollama-llm-uninstall.py --skip-extension

# Skip only VS Code extension removal
python3 docker/docker-llm-uninstall.py --skip-vscode
python3 ollama/ollama-llm-uninstall.py --skip-vscode

# Skip only IntelliJ plugin removal
python3 docker/docker-llm-uninstall.py --skip-intellij
python3 ollama/ollama-llm-uninstall.py --skip-intellij
```

### IDE-Specific Uninstallation

The uninstaller detects which IDE(s) have Continue installed:

- **Both IDEs installed**: You'll be prompted to choose:
  - VS Code only
  - IntelliJ only
  - Both
  - Neither (skip plugin removal)

- **Only one IDE installed**: You'll be asked to confirm uninstallation for that IDE

- **Config files**: The script warns that config files are shared between IDEs and asks for confirmation before removing

### Manual Cleanup

If the uninstaller doesn't work:

```bash
# Remove models manually
docker model rm <model-name>

# Remove config files (shared between both IDEs)
rm ~/.continue/config.yaml
rm ~/.continue/config.json
rm ~/.continue/rules/global-rule.md

# Restore backups
cp ~/.continue/config.yaml.backup ~/.continue/config.yaml
cp ~/.continue/rules/global-rule.md.backup ~/.continue/rules/global-rule.md

# Remove VS Code extension manually
# Press Cmd+Shift+X (macOS) or Ctrl+Shift+X (Linux/Windows)
# Search for 'Continue' → Click Uninstall

# Remove IntelliJ plugin manually
# Open IntelliJ IDEA → Preferences/Settings → Plugins
# Search for 'Continue' → Click Uninstall
```

### IntelliJ Plugin Uninstallation Notes

- **IntelliJ must be closed**: The uninstaller will warn if IntelliJ is running
- **Plugin directories**: Located at:
  - macOS: `~/Library/Application Support/JetBrains/*/plugins/Continue`
  - Linux: `~/.local/share/JetBrains/*/plugins/Continue`
  - Windows: `%APPDATA%\JetBrains\*\plugins\Continue`
- **Manual removal**: If automatic removal fails, you can delete the plugin directory directly or use IntelliJ's UI

### Backend Commands

After setup, you can manage models directly:

**Docker Model Runner:**

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

**Ollama:**

```bash
# List installed models
ollama list

# Pull a model
ollama pull llama3.2:3b

# Run a model interactively
ollama run llama3.2:3b

# Remove a model
ollama rm llama3.2:3b
```

## 📁 Project Structure

```text
ai_model/
├── docker/                      # Docker Model Runner implementation
│   ├── docker-llm-setup.py      # Docker setup script
│   ├── docker-llm-uninstall.py  # Docker uninstaller script
│   ├── requirements-docker-setup.txt
│   └── lib/                     # Docker-specific modules
│       ├── __init__.py
│       ├── config.py
│       ├── docker.py
│       ├── hardware.py
│       ├── ide.py
│       ├── models.py
│       ├── ui.py
│       └── utils.py
├── ollama/                      # Ollama implementation
│   ├── ollama-llm-setup.py      # Ollama setup script (v4.0 - smart recommendations)
│   ├── ollama-llm-uninstall.py  # Ollama uninstaller script
│   ├── requirements-ollama-setup.txt
│   └── lib/                     # Ollama-specific modules
│       ├── __init__.py          # Module exports (v2.0.0)
│       ├── config.py            # Continue.dev config generation
│       ├── hardware.py          # Hardware detection
│       ├── ide.py               # IDE detection and integration
│       ├── model_selector.py    # Fixed model selection (GPT-OSS 20B + nomic-embed-text)
│       ├── models.py            # Legacy model catalog (backward compat)
│       ├── ollama.py            # Ollama service management
│       ├── ui.py                # Terminal UI utilities
│       ├── utils.py             # General utilities
│       └── validator.py         # NEW: Robust model pulling & verification
├── lib/                         # Shared hardware detection module
│   └── hardware.py              # Hardware detection & classification
└── README.md                    # This file
```

## 🏗️ Architecture

### Module Overview

#### `docker-llm-setup.py` / `ollama-llm-setup.py`
Main entry points. Orchestrate the setup workflow:
- Hardware detection
- IDE selection (VS Code, IntelliJ, or Both)
- Backend verification (Docker Model Runner or Ollama)
- Model selection
- Model pulling with progress tracking
- Configuration generation
- User guidance

#### `lib/hardware.py`
Hardware detection:
- **HardwareInfo**: Dataclass for system information
- **detect_hardware()**: Detects CPU, RAM, GPU, Apple Silicon details
- **validate_apple_silicon_support()**: Validates Apple Silicon hardware

#### `lib/model_selector.py` (Ollama Setup)

Fixed model selection:
- **ModelRole**: Enum for model roles (CHAT, EDIT, EMBED)
- **RecommendedModel**: Dataclass for model information with role, RAM, and model names
- **PRIMARY_MODEL**: GPT-OSS 20B (primary coding model)
- **EMBED_MODEL**: Universal embedding model (nomic-embed-text)
- **select_models()**: Returns the two fixed models for all users (GPT-OSS 20B + nomic-embed-text)

#### `lib/validator.py` (Ollama Setup v4.0 - NEW)

Robust model pulling with verification and retry:
- **PullResult**: Dataclass tracking individual model pull outcomes
- **SetupResult**: Dataclass tracking overall setup success/failure
- **is_ollama_api_available()**: Checks Ollama API status
- **get_installed_models()**: Lists currently installed models
- **verify_model_exists()**: Confirms model installation
- **pull_model_with_verification()**: Pulls with verification
- **pull_models_with_tracking()**: Manages multi-model installation
- **display_setup_result()**: Clear summary with actionable next steps
- **retry_failed_models()**: Re-attempts failed installations
- **validate_pre_install()**: Pre-flight checks before downloading

#### `lib/models.py` (Docker & Ollama - Legacy)

Legacy model catalog (maintained for backward compatibility with config.py):
- **ModelInfo**: Dataclass for model metadata (used by config.py for normalization)
- **MODEL_CATALOG**: Static model catalog (GPT-OSS 20B and nomic-embed-text only)
- **validate_model_selection()**: Validates RAM usage
- **parse_tag_info()**: Parses Docker model tags to extract size and quantization info

**Note**: Most functions have been deprecated in favor of `model_selector` and `validator` modules. This module is kept only for backward compatibility with config.py normalization.

#### `lib/docker.py` (Docker only)

Docker and Docker Model Runner management:
- **check_docker()**: Verifies Docker installation
- **check_docker_model_runner()**: Verifies DMR availability
- **fetch_available_models_from_api()**: Fetches models from DMR API

#### `lib/ollama.py` (Ollama only)

Ollama management:
- **check_ollama()**: Verifies Ollama installation and API availability
- **install_ollama()**: Prompts user to install Ollama if not found
- **get_installation_instructions()**: Provides platform-specific installation instructions

#### `lib/config.py`

Continue.dev configuration generation:
- **generate_continue_config()**: Generates config.yaml and config.json
- **generate_global_rule()**: Generates global-rule.md with assistant behavior rules
- **save_setup_summary()**: Saves setup summary JSON
- **generate_yaml()**: YAML generation utility

#### `lib/ide.py`

IDE integration for VS Code and IntelliJ IDEA:
- **install_vscode_extension()**: Installs Continue.dev extension in VS Code
- **detect_intellij_cli()**: Detects IntelliJ IDEA CLI command
- **install_intellij_plugin()**: Installs Continue plugin in IntelliJ IDEA
- **restart_vscode()**: Restarts VS Code (macOS)
- **restart_intellij()**: Restarts IntelliJ IDEA (macOS)
- **show_next_steps()**: Displays post-setup instructions for selected IDE(s)

#### `lib/ui.py`

Terminal UI utilities:
- **Colors**: ANSI color codes
- **print_header()**, **print_subheader()**: Formatted headers
- **print_success()**, **print_error()**, **print_warning()**: Status messages
- **prompt_yes_no()**, **prompt_choice()**: Interactive prompts

#### `lib/utils.py`

General utilities:
- **run_command()**: Execute shell commands with timeout

### Data Flow (Docker)

```text
User Input
    ↓
Hardware Detection → Minimum RAM Check (16GB+)
    ↓
IDE Selection (VS Code, IntelliJ, or Both)
    ↓
Preset Selection → Fixed Models (GPT-OSS 20B + nomic-embed-text)
    ↓
Model Selection → RAM Validation
    ↓
Model Pulling → Configuration Generation → Global Rules Generation
    ↓
IDE Setup → Next Steps
```

### Data Flow (Ollama Setup)

```text
Hardware Detection → Mac Model + RAM Identification
    ↓
IDE Auto-Detection (VS Code, Cursor, IntelliJ)
    ↓
Ollama Service Check → API Verification
    ↓
Model Selection (model_selector.select_models)
    - Returns GPT-OSS 20B + Nomic Embed Text (same for all users)
    ↓
Display Hardware Info + Models to Install
    ↓
User Confirms Installation
    ↓
Pre-Install Validation (validator.validate_pre_install)
    ↓
Model Pulling with Verification (validator.pull_models_with_tracking)
    │
    ├── Success → Continue
    │
    └── Failure → Retry
                                                          ↓
Setup Result Display → Retry Option for Failures
    ↓
Configuration Generation (config.generate_continue_config)
    ↓
Global Rules Generation (config.generate_global_rule)
    ↓
Next Steps Display (ide.show_next_steps)
```

## ⚙️ Configuration

### Continue.dev Config Location

Both VS Code and IntelliJ IDEA use the same config location:
- **macOS/Linux**: `~/.continue/config.json` (and `config.yaml` for VS Code)
- **Windows**: `%USERPROFILE%\.continue\config.json` (and `config.yaml` for VS Code)

**Note**: 
- VS Code uses both `config.yaml` and `config.json` (YAML is preferred)
- IntelliJ IDEA uses only `config.json` (does not support YAML)
- When selecting "Both" IDEs, the script generates both formats
- When selecting "IntelliJ only", only `config.json` is generated

### Global Rules Location

- **macOS/Linux**: `~/.continue/rules/global-rule.md`
- **Windows**: `%USERPROFILE%\.continue\rules\global-rule.md`

### Config Structure

The generated config includes:
- **Models**: Chat, edit, autocomplete, and embedding models
  - Chat models have roles: `chat`, `edit`, `apply`
  - Autocomplete models have `autocompleteOptions` with optimized settings
  - Embedding models have role: `embed`
  - All models use `defaultCompletionOptions.contextLength` for context window
- **API Endpoint**: 
  - Docker Model Runner: `http://localhost:12434/v1`
  - Ollama: `http://localhost:11434/v1`
- **Context Providers**: Codebase, folder, file, terminal, diff, problems, open (using new `context` format)

**Note**: The config strictly follows the Continue.dev schema. Fields not in the official schema (like `supportsToolCalls`, `experimental`, and `ui`) have been removed to ensure validation compliance.

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

**Docker Model Runner Example:**
```yaml
name: Docker Model Runner Local LLM
version: 1.0.0

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
```

**Ollama Example:**
```yaml
name: Ollama Local LLM
version: 1.0.0

models:
  - name: Llama 3.2
    provider: openai
    model: llama3.2:3b
    apiBase: http://localhost:11434/v1
    roles:
      - chat
      - edit
      - apply
    defaultCompletionOptions:
      contextLength: 131072
```

### Backup Files

The script automatically backs up existing configs to:
- `~/.continue/config.yaml.backup` (if YAML exists)
- `~/.continue/config.json.backup` (if JSON exists)
- `~/.continue/rules/global-rule.md.backup`

## 🔍 Codebase Awareness: Dual Approach

Continue.dev provides two complementary approaches for understanding your codebase. This setup script configures both:

### 1. Embedding-Based Search (Legacy @Codebase)

**What it does**: Creates vector embeddings of your code for semantic similarity search

**Status**: Deprecated but fully functional in all current versions

**Configuration**: 
- Embedding model: Automatically selected (e.g., Nomic Embed Text)
- Context provider: `{"provider": "codebase"}` (auto-configured)
- Index location: `~/.continue/index/`

**Usage**:
```
Type in Continue chat:
@Codebase find all authentication code
@Folder explain the structure of /src/api
```

**Best for**:
- "Find all code related to X" queries
- Discovering similar code patterns
- Quick semantic searches across files

**Important Notes**:
- ⚠️ **Required for JetBrains**: IntelliJ/PyCharm cannot use the transformers.js fallback
- 📦 Indexing happens automatically on first use
- 🔄 Respects `.gitignore` and `.continueignore` files

---

### 2. Agent Mode Codebase Awareness (New & Recommended)

**What it does**: Agent uses built-in tools and rules to understand your project structure

**Status**: Current recommended approach by Continue.dev

**Configuration**: 
- Rules file: `~/.continue/rules/codebase-context.md` (auto-generated template)
- No indexing required
- Works immediately

**Usage**:
1. Edit `~/.continue/rules/codebase-context.md` with your project details
2. Use Agent mode for complex tasks
3. Agent automatically reads rules for context

**Best for**:
- Complex multi-step tasks
- Architectural questions
- Tasks requiring project knowledge
- Understanding conventions and patterns

**Template Sections**:
- Project Structure (directories and purposes)
- Key Technologies (frameworks, libraries)
- Coding Standards (conventions, style guides)
- Architecture Patterns (design decisions)
- Common Tasks (how to perform frequent operations)

---

### 🌟 Best Practice: Use Both Together

The hybrid approach gives you maximum flexibility:

| Scenario | Use This Approach |
|----------|------------------|
| "Find all API endpoints" | @Codebase search |
| "Explain the auth flow" | Agent mode with rules |
| "Show similar components" | @Codebase search |
| "Refactor user service" | Agent mode with rules |
| "Where is JWT validation?" | @Codebase search |
| "Add new feature X" | Agent mode with rules |

**Quick Start**:
1. ✅ Embedding model is already configured
2. ✅ Rules template is already created at `~/.continue/rules/codebase-context.md`
3. 📝 Edit the rules file with your project info
4. 🚀 Use both @Codebase and Agent mode as needed

---

### Configuration Details

**Embedding Model** (for @Codebase):
```json
{
  "name": "Nomic Embed Text (Embedding)",
  "provider": "openai",
  "model": "nomic-embed-text:latest",
  "apiBase": "http://localhost:11434/v1",
  "roles": ["embed"]
}
```

**Context Provider**:
```json
{
  "context": [
    {"provider": "codebase"},
    {"provider": "folder"}
  ]
}
```

**Rules Locations**:
- Global behavior: `~/.continue/rules/global-rule.md`
- Codebase context: `~/.continue/rules/codebase-context.md`
- Project-specific: `.continue/rules/*.md` (in your project root)

---

### Migration Notes

If you're using older Continue versions:
- Legacy @Codebase will continue working
- New Agent mode features are opt-in
- Both approaches can coexist
- No breaking changes to your workflow

**Learn More**:
- [Agent Mode Guide](https://docs.continue.dev/guides/codebase-documentation-awareness)
- [Embedding Models](https://docs.continue.dev/customize/model-roles/embeddings)
- [Legacy @Codebase Reference](https://docs.continue.dev/reference/deprecated-codebase)

## 💻 IDE Support

The setup script supports both VS Code and IntelliJ IDEA with the Continue plugin/extension.

### VS Code (Continue.dev Extension)

**Installation:**
- The script can automatically install the Continue.dev extension via VS Code CLI
- Or install manually: Press `Cmd+Shift+X` (macOS) or `Ctrl+Shift+X` (Linux/Windows) → Search "Continue" → Install

**Keyboard Shortcuts:**
- **macOS**: 
  - `Cmd+L` - Open Continue.dev chat
  - `Cmd+K` - Inline code edits
  - `Cmd+I` - Quick actions
- **Linux/Windows**: 
  - `Ctrl+L` - Open Continue.dev chat
  - `Ctrl+K` - Inline code edits
  - `Ctrl+I` - Quick actions

**Config Files:**
- Uses both `config.yaml` and `config.json`
- YAML is the preferred format for VS Code

### IntelliJ IDEA (Continue Plugin)

**Installation:**
- Install manually via IntelliJ IDEA:
  - **macOS**: Preferences → Plugins (or `Cmd+,` then Plugins)
  - **Linux/Windows**: Settings → Plugins (or `Ctrl+Alt+S` then Plugins)
  - Search for "Continue" and click Install

**Keyboard Shortcuts:**
- **macOS**: 
  - `Cmd+J` - Open Continue chat
  - `Cmd+Shift+J` - Inline edit
- **Linux/Windows**: 
  - `Ctrl+J` - Open Continue chat
  - `Ctrl+Shift+J` - Inline edit

**Config Files:**
- Uses only `config.json` (IntelliJ doesn't support YAML configs)
- Same location as VS Code: `~/.continue/config.json`

**Verification:**
After installing the plugin and generating config:
1. Open IntelliJ IDEA
2. Press `Cmd+J` (or `Ctrl+J`) to open Continue
3. Check that your models appear in the model selector
4. If models don't appear:
   - Verify config file exists: `~/.continue/config.json`
   - Check model server is running: `docker model list`
   - Restart IntelliJ IDEA if needed

### Shared Features

Both IDEs support:
- **@Codebase** - Semantic code search
- **@file** - Reference specific files
- **@folder** - Reference entire folders
- **Global Rules** - Same `global-rule.md` file works for both IDEs

### IDE Selection During Setup

When running the setup script, you'll be prompted to select:
- **VS Code only** - Generates YAML and JSON configs
- **IntelliJ only** - Generates JSON config only
- **Both** - Generates both YAML and JSON (recommended if you use both IDEs)

## 🖥️ Hardware Requirements

### RAM Requirements

The setup installs the same two models for all users:
- **GPT-OSS 20B**: 16GB RAM (primary reasoning/chat model)
- **nomic-embed-text**: 0.3GB RAM (embedding model)
- **Total**: ~16.3GB RAM

**Minimum Requirements:**
- **16GB RAM**: Minimum supported (installs GPT-OSS 20B + nomic-embed-text)
- Systems with less than 16GB RAM are not supported

**Recommended:**
- **16GB+ RAM**: All systems with 16GB+ RAM get the same models
- No tier-based selection - same high-quality models for everyone

**Note**: GPT-OSS 20B is the primary model for all configurations (16GB+ RAM). It matches o3-mini performance, runs at 1200 tokens/sec, uses only 16GB RAM, and is Apache 2.0 licensed (US-based, OpenAI, released August 2025).

### Example: M4 Pro (48GB)

```text
Total RAM:          48GB
Reserved (30%):     -14.4GB
Usable:             33.6GB

Recommended Models:
- gpt-oss:20b (Ollama) / ai/gpt-oss:20B-UD-Q6_K_XL (Docker)  16.0GB (primary)
- nomic-embed-text (Ollama) / ai/nomic-embed-text-v1.5 (Docker)  0.3GB (embeddings)
────────────────────────────────
Total Models:             16.3GB
Remaining Buffer:          17.3GB ✓
```

**Note**: GPT-OSS 20B is the primary model for all configurations. It matches o3-mini performance, runs at 1200 tokens/sec, uses only 16GB RAM, and is superior to Llama 3.1/3.3.

### Fixed Model Installation

The setup uses a simplified approach:
- **Primary model**: GPT-OSS 20B (16GB) - installed for all users (16GB+ RAM)
  - Matches o3-mini performance, 1200 tokens/sec, Apache 2.0 license
  - Superior to Llama 3.1/3.3 - no longer competitive
- **Embedding model**: nomic-embed-text (~0.3GB) - installed for all users
- **No selection needed**: Same two models for everyone - consistent experience

### Apple Silicon Optimization

For Apple Silicon Macs:
- **Metal GPU Acceleration**: Automatic via Docker Model Runner
- **Unified Memory**: Shared CPU/GPU/Neural Engine memory
- **Neural Engine**: 16-32 cores available for acceleration
- **Optimized Models**: Quantized variants for efficient inference

### Model Selection Matrix (Source of Truth)

The following table shows the exact model selection based on Mac model and RAM configuration. This is the authoritative reference for model recommendations:

| Mac Model | RAM | CPU Cores | GPU Cores | Model | Size | Ollama Command | Docker Model Runner Command |
|-----------|-----|-----------|----------|-------|------|----------------|----------------------------|
| M1 | 16GB | 8 (4P+4E) | 7-8 | GPT-OSS 20B | 16.0GB | `ollama pull gpt-oss:20b` | `docker model pull ai/gpt-oss:20B-UD-Q6_K_XL` |
| M1 Pro | 16GB | 8-10 (6-8P+2E) | 14-16 | GPT-OSS 20B | 16.0GB | `ollama pull gpt-oss:20b` | `docker model pull ai/gpt-oss:20B-UD-Q6_K_XL` |
| M1 Max | 32GB | 10 (8P+2E) | 24-32 | GPT-OSS 20B | 16.0GB | `ollama pull gpt-oss:20b` | `docker model pull ai/gpt-oss:20B-UD-Q6_K_XL` |
| M1 Ultra | 64GB+ | 20 (16P+4E) | 48-64 | GPT-OSS 20B | 16.0GB | `ollama pull gpt-oss:20b` | `docker model pull ai/gpt-oss:20B-UD-Q6_K_XL` |
| M2 | 16GB | 8 (4P+4E) | 8-10 | GPT-OSS 20B | 16.0GB | `ollama pull gpt-oss:20b` | `docker model pull ai/gpt-oss:20B-UD-Q6_K_XL` |
| M2 | 24GB | 8 (4P+4E) | 8-10 | GPT-OSS 20B | 16.0GB | `ollama pull gpt-oss:20b` | `docker model pull ai/gpt-oss:20B-UD-Q6_K_XL` |
| M2 Pro | 16GB | 10-12 (6-8P+4E) | 16-19 | GPT-OSS 20B | 16.0GB | `ollama pull gpt-oss:20b` | `docker model pull ai/gpt-oss:20B-UD-Q6_K_XL` |
| M2 Max | 32GB | 12 (8P+4E) | 30-38 | GPT-OSS 20B | 16.0GB | `ollama pull gpt-oss:20b` | `docker model pull ai/gpt-oss:20B-UD-Q6_K_XL` |
| M2 Ultra | 64GB+ | 24 (16P+8E) | 60-76 | GPT-OSS 20B | 16.0GB | `ollama pull gpt-oss:20b` | `docker model pull ai/gpt-oss:20B-UD-Q6_K_XL` |
| M3 | 16GB | 8 (4P+4E) | 8-10 | GPT-OSS 20B | 16.0GB | `ollama pull gpt-oss:20b` | `docker model pull ai/gpt-oss:20B-UD-Q6_K_XL` |
| M3 | 24GB | 8 (4P+4E) | 8-10 | GPT-OSS 20B | 16.0GB | `ollama pull gpt-oss:20b` | `docker model pull ai/gpt-oss:20B-UD-Q6_K_XL` |
| M3 Pro | 18GB | 11-12 (5-6P+5-6E) | 14-18 | GPT-OSS 20B | 16.0GB | `ollama pull gpt-oss:20b` | `docker model pull ai/gpt-oss:20B-UD-Q6_K_XL` |
| M3 Pro | 36GB | 12 (6P+6E) | 18 | GPT-OSS 20B | 16.0GB | `ollama pull gpt-oss:20b` | `docker model pull ai/gpt-oss:20B-UD-Q6_K_XL` |
| M3 Max | 36GB | 14-16 (10-12P+4E) | 30-40 | GPT-OSS 20B | 16.0GB | `ollama pull gpt-oss:20b` | `docker model pull ai/gpt-oss:20B-UD-Q6_K_XL` |
| M3 Max | 48GB+ | 16 (12P+4E) | 40 | GPT-OSS 20B | 16.0GB | `ollama pull gpt-oss:20b` | `docker model pull ai/gpt-oss:20B-UD-Q6_K_XL` |
| M4 | 16GB | 10 (4P+6E) | 10 | GPT-OSS 20B | 16.0GB | `ollama pull gpt-oss:20b` | `docker model pull ai/gpt-oss:20B-UD-Q6_K_XL` |
| M4 | 24GB | 10 (4P+6E) | 10 | GPT-OSS 20B | 16.0GB | `ollama pull gpt-oss:20b` | `docker model pull ai/gpt-oss:20B-UD-Q6_K_XL` |
| M4 Pro | 24GB | 14 (10P+4E) | 20 | GPT-OSS 20B | 16.0GB | `ollama pull gpt-oss:20b` | `docker model pull ai/gpt-oss:20B-UD-Q6_K_XL` |
| M4 Pro | 48GB | 14 (10P+4E) | 20 | GPT-OSS 20B | 16.0GB | `ollama pull gpt-oss:20b` | `docker model pull ai/gpt-oss:20B-UD-Q6_K_XL` |
| M4 Max | 36GB+ | 16 (12P+4E) | 40 | GPT-OSS 20B | 16.0GB | `ollama pull gpt-oss:20b` | `docker model pull ai/gpt-oss:20B-UD-Q6_K_XL` |

**Selection Rules:**
- **All configurations (16GB+ RAM)**: Use `gpt-oss:20b` (16GB) - matches o3-mini performance, 1200 tokens/sec
- **Superior to Llama 3.1/3.3**: Llama models are no longer competitive with GPT-OSS 20B
- **Apache 2.0 license**: US-based (OpenAI), released August 2025

**Embedding Model (All Configurations):**
- **Ollama**: `nomic-embed-text` (~0.3GB)
- **Docker**: `ai/nomic-embed-text-v1.5` (~0.3GB)

## 🤖 Model Catalog

### Available Models

This setup offers **GPT-OSS 20B** as the primary reasoning/chat model:

#### Primary Models
- **GPT-OSS 20B** (16GB): Used for all Mac configurations (16GB+ RAM)
  - Ollama: `gpt-oss:20b`
  - Docker: `ai/gpt-oss:20B-UD-Q6_K_XL`
  - Matches o3-mini performance, 1200 tokens/sec, Apache 2.0 license
  - US-based (OpenAI), released August 2025
  - Superior to Llama 3.1/3.3 - no longer competitive
  - Recommended for: All configurations (M1, M2, M3, M4, Ultra, Max)

#### Embedding Models
- **Nomic Embed Text** (~0.3GB): Used for all configurations
  - Ollama: `nomic-embed-text`
  - Docker: `ai/nomic-embed-text-v1.5`
  - Best open embedding model for code indexing (8192 tokens)

See the [Model Selection Matrix](#model-selection-matrix-source-of-truth) for exact model selection based on your Mac model and RAM configuration.

### Model Installation

The setup installs fixed model variants:
- **GPT-OSS 20B**: Pre-selected variant optimized for Apple Silicon
- **nomic-embed-text**: Standard embedding model
- **No variant selection needed**: Optimal variants are pre-selected

### Model Roles

Valid roles per Continue.dev schema:
- **chat**: General conversation and code assistance
- **edit**: Code editing and refactoring
- **apply**: Apply code changes
- **autocomplete**: Tab autocomplete in VS Code
- **embed**: Semantic code search embeddings
- **rerank**: Reranking search results
- **summarize**: Summarization tasks

### Model Roles

The selected models support the following roles:
- **chat**: General conversation and code assistance
- **edit**: Code editing and refactoring
- **apply**: Apply code changes
- **embed**: Semantic code search embeddings (nomic-embed-text)

## 🔧 Troubleshooting

### Docker Model Runner Not Available

**Problem**: `docker model list` returns "unknown command"

**Solutions**:
1. Update Docker Desktop to 4.40+
2. Enable Docker Model Runner in Settings → Features in development
3. Restart Docker Desktop
4. Run: `docker desktop enable model-runner --tcp 12434`

### Models Not Pulling

**Problem**: Model pull fails or hangs

**Docker Model Runner Solutions**:
1. Check Docker Desktop is running
2. Verify internet connection
3. Check Docker Hub access
4. Try pulling manually: `docker model pull ai/llama3.2`
5. Check Docker logs: Docker Desktop → Troubleshoot → View logs

**Ollama Solutions**:
1. Check Ollama is running: `ollama list`
2. Verify internet connection
3. Check Ollama service: `ollama serve` (if not running as service)
4. Try pulling manually: `ollama pull llama3.2:3b`
5. Check Ollama logs: `ollama logs` or system logs
6. Verify model name format (Ollama uses `model:tag` format, e.g., `llama3.2:3b`)

### SSH Key Errors on macOS

**Problem**: Model pulls fail with "ssh: no key found" error

**Root Cause**: 
- macOS SSH agent sets `SSH_AUTH_SOCK` environment variable for git/GitHub
- This causes Ollama (written in Go) to malfunction when making HTTPS requests
- It's a bug in Go's HTTP library, not Ollama trying to use SSH

**Solution**:
The setup script automatically handles this by using a clean environment when calling Ollama.

If you still see this error:
1. The script may not have been updated - pull latest version
2. Manually unset the variable:
   ```bash
   unset SSH_AUTH_SOCK
   pkill ollama
   ollama serve &
   ollama pull <model-name>
   ```

**Prevention**:
This is handled automatically in the latest version of the script.

### API Endpoint Not Reachable

**Problem**: Continue.dev can't connect to model API

**Docker Model Runner Solutions**:
1. Verify model is running: `docker model list`
2. Start model: `docker model run <model-name>`
3. Check API endpoint: `curl http://localhost:12434/v1/models`
4. Verify port 12434 is not blocked by firewall
5. Check Docker Desktop is running

**Ollama Solutions**:
1. Verify Ollama service is running: `ollama list`
2. Start Ollama service if needed: `ollama serve` (or start as system service)
3. Check API endpoint: `curl http://localhost:11434/v1/models`
4. Verify port 11434 is not blocked by firewall
5. Check Ollama is installed: `ollama --version`

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

### IntelliJ IDEA Plugin Not Working

**Problem**: Continue plugin doesn't load config or models don't appear

**Solutions**:
1. Restart IntelliJ IDEA completely (quit and reopen)
2. Check config file exists: `~/.continue/config.json` (not YAML - IntelliJ doesn't use YAML)
3. Verify JSON syntax is valid: `cat ~/.continue/config.json | python3 -m json.tool`
4. Check IntelliJ IDEA Event Log: Help → Show Log in Finder/Explorer
5. Verify plugin is installed: Preferences → Plugins → Installed → Search "Continue"
6. Reinstall Continue plugin if needed
7. Check that model server is running:
   - Docker: `docker model list`
   - Ollama: `ollama list`
8. Verify API endpoint is accessible:
   - Docker: `curl http://localhost:12434/v1/models`
   - Ollama: `curl http://localhost:11434/v1/models`
9. If models still don't appear:
   - Check IntelliJ IDEA version compatibility (plugin may require specific version)
   - Try invalidating caches: File → Invalidate Caches / Restart

**Problem**: IntelliJ IDEA CLI not found

**Solutions**:
1. IntelliJ IDEA CLI is optional - plugin installation can be done manually
2. To enable CLI on macOS:
   - Open IntelliJ IDEA
   - Tools → Create Command-line Launcher
   - Or check: `/Applications/IntelliJ IDEA.app/Contents/MacOS/idea`
3. On Linux/Windows, CLI may be in different locations - manual installation is recommended

### Apple Silicon Issues

**Problem**: Models run slowly or use CPU instead of GPU

**Solutions**:
1. Verify Docker Desktop is using Apple Silicon version
2. Check Metal acceleration is enabled in Docker Desktop
3. Ensure models are Apple Silicon optimized
4. Check Activity Monitor for GPU usage

## 🗑️ Uninstallation

### Full Uninstallation

**For Ollama Setup (Recommended - Smart Uninstaller v2.0):**

```bash
python3 ollama/ollama-llm-uninstall.py
```

The smart uninstaller will:
1. **Load installation manifest** - Knows exactly what was installed
2. **Detect running processes** - Warns about active Ollama/IDE processes
3. **Scan for orphaned files** - Finds files created by installer but not in manifest
4. **Remove Ollama models** - Only models we installed (keeps pre-existing)
5. **Handle config customization** - Detects if you modified configs, offers backup
6. **Auto-clean cache/temp** - Removes cache files without asking
7. **Remove IDE extensions** - Asks before removing (can be used with other LLMs)

**For Docker Setup:**

```bash
python3 docker/docker-llm-uninstall.py
```

This will:
1. Remove Docker models (optional)
2. Remove Continue.dev config files (optional)
3. Restore backup config if available (optional)
4. Remove VS Code extension (optional)
5. Remove IntelliJ IDEA plugin (optional)

The script will automatically detect which IDE(s) have Continue installed and ask which to uninstall.

### Selective Uninstallation

Use flags to skip specific steps:

```bash
# Only remove models
python3 docker/docker-llm-uninstall.py --skip-config --skip-extension

# Only remove config files
python3 docker/docker-llm-uninstall.py --skip-models --skip-extension

# Uninstall from VS Code only
python3 docker/docker-llm-uninstall.py --skip-intellij

# Uninstall from IntelliJ only
python3 docker/docker-llm-uninstall.py --skip-vscode

# Skip both IDE plugins but remove models/config
python3 docker/docker-llm-uninstall.py --skip-extension
```

### Command-Line Options

```bash
# Skip Docker checks (useful if Docker is hanging)
python3 docker/docker-llm-uninstall.py --skip-docker-checks

# Skip model removal
python3 docker/docker-llm-uninstall.py --skip-models

# Skip config file removal
python3 docker/docker-llm-uninstall.py --skip-config

# Skip both VS Code extension and IntelliJ plugin removal
python3 docker/docker-llm-uninstall.py --skip-extension

# Skip only VS Code extension removal
python3 docker/docker-llm-uninstall.py --skip-vscode

# Skip only IntelliJ plugin removal
python3 docker/docker-llm-uninstall.py --skip-intellij
```

### IDE-Specific Uninstallation

The uninstaller detects which IDE(s) have Continue installed:

- **Both IDEs installed**: You'll be prompted to choose:
  - VS Code only
  - IntelliJ only
  - Both
  - Neither (skip plugin removal)

- **Only one IDE installed**: You'll be asked to confirm uninstallation for that IDE

- **Config files**: The script warns that config files are shared between IDEs and asks for confirmation before removing

### Manual Cleanup

If the uninstaller doesn't work:

```bash
# Remove models manually
docker model rm <model-name>

# Remove config files (shared between both IDEs)
rm ~/.continue/config.yaml
rm ~/.continue/config.json
rm ~/.continue/rules/global-rule.md

# Restore backups
cp ~/.continue/config.yaml.backup ~/.continue/config.yaml
cp ~/.continue/rules/global-rule.md.backup ~/.continue/rules/global-rule.md

# Remove VS Code extension manually
# Press Cmd+Shift+X (macOS) or Ctrl+Shift+X (Linux/Windows)
# Search for 'Continue' → Click Uninstall

# Remove IntelliJ plugin manually
# Open IntelliJ IDEA → Preferences/Settings → Plugins
# Search for 'Continue' → Click Uninstall
```

### IntelliJ Plugin Uninstallation Notes

- **IntelliJ must be closed**: The uninstaller will warn if IntelliJ is running
- **Plugin directories**: Located at:
  - macOS: `~/Library/Application Support/JetBrains/*/plugins/Continue`
  - Linux: `~/.local/share/JetBrains/*/plugins/Continue`
  - Windows: `%APPDATA%\JetBrains\*\plugins\Continue`
- **Manual removal**: If automatic removal fails, you can delete the plugin directory directly or use IntelliJ's UI

## 💻 Development

### Project Setup

```bash
# Clone repository
git clone <repository-url>
cd ai_model

# Verify Python version
python3 --version

# (Optional) Install development dependencies
pip install -r docker/requirements-docker-setup.txt
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
    recommended_for=["Use case description"]
)
```

### Testing

```bash
# Test hardware detection
python3 -c "from lib import hardware; print(hardware.detect_hardware())"

# Test Docker check (Docker backend)
python3 -c "from lib import docker; print(docker.check_docker())"

# Test model catalog (legacy)
python3 -c "from lib import models; print(len(models.MODEL_CATALOG))"
```

**Testing Ollama Setup v4.0 Modules:**

```bash
cd ai_model/ollama

# Test model selector
python3 -c "
from lib import hardware, model_selector
hw = hardware.detect_hardware()
models = model_selector.select_models(hw)
print(f'Selected models: {len(models)}')
for m in models:
    print(f'  - {m.name}: {m.ollama_name} ({m.ram_gb:.1f}GB)')
"

# Test validator module
python3 -c "
from lib import validator
print(f'Ollama API available: {validator.is_ollama_api_available()}')
print(f'Installed models: {validator.get_installed_models()}')
"

# Test IDE detection
python3 -c "
from lib import ide
ides = ide.detect_installed_ides()
print(f'Detected IDEs: {ides}')
"
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
- **Ollama**: [ollama.com](https://ollama.com)
- **Continue.dev**: [docs.continue.dev](https://docs.continue.dev)
- **Docker Desktop**: [docker.com/desktop](https://docker.com/desktop)

## 📝 Changelog

### Version 4.0.0 (Fixed Model Selection)
- **Simplified Model Selection**: Fixed model installation for all users
  - Installs GPT-OSS 20B for all configurations (16GB+ RAM)
  - GPT-OSS 20B matches o3-mini performance, 1200 tokens/sec, Apache 2.0 license
  - Superior to Llama 3.1/3.3 - no longer competitive
  - Includes nomic-embed-text embedding model for all configurations
- **Consistent Experience**: Same models for all users
  - No hardware-based selection - same two models for everyone
  - Simplified setup process
  - Selects optimal model variant that fits hardware capabilities
- **Reliable Model Pulling**: Robust installation with retry
  - Immediate verification after each model pull
  - Automatic retry on failure
  - Clear feedback and actionable next steps for partial setups
  - Retry mechanism for failed models
- **Smart Uninstaller v2.0**: Manifest-based cleanup system
  - Installation manifest tracking for precise uninstallation
  - File fingerprinting to detect user customizations
  - Pre-existing model preservation (keeps models you had before setup)
  - Orphaned file detection and cleanup
  - Running process detection and graceful handling
  - Smart config removal with backup/restore options
  - Auto-cleanup of cache and temporary files
  - New `lib/uninstaller.py` module
- **New Modules**: Modular architecture for maintainability
  - `lib/model_selector.py`: Fixed model selection (GPT-OSS 20B + nomic-embed-text)
  - `lib/validator.py`: Robust model pulling with verification and retry
  - `lib/uninstaller.py`: Smart uninstallation with manifest tracking
- **IDE Auto-Detection**: Automatically finds installed IDEs
  - Detects VS Code, Cursor, and IntelliJ IDEA installations
  - No manual IDE selection required

### Version 3.0.0
- **Full Ollama support**: Complete parallel implementation of Ollama backend alongside Docker Model Runner
  - New `ollama/` directory with parallel structure to `docker/`
  - Independent setup and uninstall scripts for Ollama
  - Full feature parity with Docker implementation
- **Enhanced Ollama progress bars**: Fixed rich progress bar display for Ollama model downloads
  - Now properly parses Ollama's text format output (with ANSI escape codes)
  - Handles mixed units (KB/MB/GB) during download progress
  - Shows real-time download progress with percentage, speed, and time remaining
  - Progress bars work correctly throughout the entire download process
- **Improved Ollama integration**: Simplified model installation
  - Fixed model selection (GPT-OSS 20B + nomic-embed-text)
  - Improved retry logic for model pulling
  - Automatic Ollama installation detection and prompts
- **Dual-backend architecture**: Users can now choose between Docker Model Runner or Ollama
  - Both backends generate identical Continue.dev configurations
  - Same hardware detection and model recommendations
  - Independent operation - no conflicts between backends
- **Documentation updates**: Comprehensive README updates to reflect both backends equally
  - Updated all sections to cover both Docker and Ollama
  - Enhanced troubleshooting guides for both backends
  - Clear installation instructions for both options

### Version 2.1.0
- **Conservative model selection**: Simplified to GPT-OSS 20B
  - Removed support for multiple model families (Mistral, CodeLlama, etc.)
  - Focus on GPT-OSS 20B for superior performance and Apache 2.0 license
  - Model selection based on Mac model + RAM configuration (all 16GB+ get GPT-OSS 20B)
- **Simplified RAM allocation**: Single model + embedding approach
  - Primary model: GPT-OSS 20B (16GB) - matches o3-mini performance, 1200 tokens/sec
  - Embedding model: nomic-embed-text (~0.3GB)
  - Remaining RAM reserved for OS, apps, and context

### Version 2.0.0
- **Schema compliance**: Removed all fields not in the official Continue.dev schema to ensure validation passes
  - Removed `supportsToolCalls` (not in schema)
  - Removed `experimental` section (not in schema)
  - Removed `ui` section (not in schema)
  - Removed `agent` role (not in schema's role enum)
- **Updated to official schema**: 
  - Added required `name` and `version` fields
  - Changed `contextProviders` to `context` (new format)
  - Moved `contextLength` to `defaultCompletionOptions.contextLength`
  - Moved autocomplete settings to model-level `autocompleteOptions`
  - Removed deprecated fields: `tabAutocompleteModel`, `embeddingsProvider`, `slashCommands`, `allowAnonymousTelemetry`
- **Improved model configuration**: All models now properly configured with roles and completion options per schema requirements
- **Fixed validation errors**: Config now passes Continue.dev extension validation (v1.2.11+)

### Version 1.0.0
- Initial release
- Hardware detection
- Model catalog
- Continue.dev configuration generation
- Global rules file generation
- VS Code integration
- Uninstaller script
- Apple Silicon optimization

## 🙏 Acknowledgments

- Docker for Docker Model Runner
- Continue.dev team for the VS Code extension
- Meta for Llama models
- Nomic AI for nomic-embed-text
- Open source community

---

**Note**: This project is not affiliated with Docker, Continue.dev, or any model providers. It is an independent tool for setting up local LLM development environments.
