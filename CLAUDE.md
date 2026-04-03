# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a collection of macOS productivity tools and scripts, organized into independent subprojects:

- **ai_model**: Python-based LLM setup automation for Continue.dev (Docker Model Runner & Ollama)
- **mac-cleanup**: Interactive macOS cleanup utility (shell script)
- **zsh-setup**: Zsh/Oh My Zsh setup automation with plugin management (shell script)
- **home-netmon**: Network monitoring installer using Gatus/ntfy (shell script)

Each subproject is self-contained with its own README and architecture.

## Project Structure

```
scripts/
├── ai_model/           # LLM setup for Continue.dev (Python)
│   ├── docker/         # Docker Model Runner backend
│   ├── ollama/         # Ollama backend
│   ├── llamacpp/       # llama.cpp backend
│   └── tests/          # Shared test suite
├── mac-cleanup/        # macOS cleanup utility (Bash)
├── zsh-setup/          # Zsh setup automation (Bash)
│   ├── lib/            # Modular architecture with namespaced functions
│   ├── commands/       # Command implementations
│   └── tests/          # Test suite
└── home-netmon/        # Network monitoring setup (Bash)
```

## ai_model: LLM Setup Project

### Architecture

**Dual Backend Support**: The project implements two parallel backends (Docker Model Runner and Ollama) with identical functionality. Both generate the same Continue.dev configuration but use different model hosting solutions.

**Module Structure**:
- `lib/hardware.py`: Shared hardware detection across backends
- `docker/lib/`: Docker-specific implementation
- `ollama/lib/`: Ollama-specific implementation
- Both backends share identical module organization: `config.py`, `hardware.py`, `ide.py`, `model_selector.py`, `models.py`, `ui.py`, `utils.py`, `validator.py`

**Key Design Principle**: Model selection is now **fixed** - GPT-OSS 20B (16GB) + nomic-embed-text (0.3GB) for all users with 16GB+ RAM. No tiered selection or user choice.

### Running Tests

```bash
# Navigate to ai_model directory first
cd ai_model

# Run all tests (both backends)
python3 run_tests.py

# Run specific backend tests
python3 run_tests.py --ollama
python3 run_tests.py --docker

# Run specific test types
python3 run_tests.py --unit           # Unit tests only
python3 run_tests.py --integration    # Integration tests only
python3 run_tests.py --e2e            # End-to-end tests only

# Run with coverage
python3 run_tests.py --cov
python3 run_tests.py --cov --html     # Generate HTML coverage report

# Verbose output
python3 run_tests.py -v

# Filter tests by keyword
python3 run_tests.py -k "config"

# Quick mode (skip slow tests)
python3 run_tests.py --quick

# Fail fast (stop on first failure)
python3 run_tests.py -x
```

**Test Infrastructure**:
- Automatic virtual environment setup (`.venv/`)
- Automatic dependency installation from `tests/requirements.txt`
- Backend-specific PYTHONPATH management to avoid module conflicts
- Shared tests in `tests/` directory test common functionality
- Backend-specific tests in `docker/tests/` and `ollama/tests/`

### Running Setup Scripts

```bash
cd ai_model

# Docker Model Runner setup
python3 docker/docker-llm-setup.py

# Ollama setup
python3 ollama/ollama-llm-setup.py

# llama.cpp setup (experimental)
python3 llamacpp/setup_llamacpp_server.py

# Uninstallers
python3 docker/docker-llm-uninstall.py
python3 ollama/ollama-llm-uninstall.py
```

### Important Implementation Notes

**Backend Isolation**: When working on backend-specific code:
- Changes to `docker/lib/*.py` only affect Docker backend
- Changes to `ollama/lib/*.py` only affect Ollama backend
- Shared `lib/hardware.py` affects both backends
- Test files must import from the correct backend module

**Model Selection**: The `model_selector.py` and `validator.py` modules now implement **fixed model selection**:
- All users get GPT-OSS 20B (16GB) + nomic-embed-text (0.3GB)
- No hardware-based tiering or user choice
- Simplified setup flow

**VPN/SSH Handling**: The Ollama backend has special SSH_AUTH_SOCK handling due to a Go HTTP library bug. When calling Ollama commands, the environment is cleaned to remove SSH_AUTH_SOCK.

**Progress Bars**: Both backends support rich terminal progress bars with automatic fallback to basic output if `rich` library is unavailable.

## zsh-setup: Modern Shell Script Architecture

### Architecture

**Namespaced Functions**: All functions use `zsh_setup::` namespace with module hierarchy:
- `zsh_setup::core::logger::info()` - Core logging
- `zsh_setup::plugins::manager::install_list()` - Plugin management
- `zsh_setup::system::package_manager::install()` - Package operations

**Module Organization**:
- `lib/core/`: Bootstrap, config, logger, errors
- `lib/state/`: JSON-based state store
- `lib/system/`: Package manager, validation, shell
- `lib/plugins/`: Registry, resolver, installer, manager
- `lib/config/`: Validator, backup, generator
- `lib/utils/`: Network, filesystem utilities

**State Management**: Uses JSON-based state store (`lib/state/store.sh`) for cross-script communication instead of exported arrays.

### Running zsh-setup

```bash
cd zsh-setup

# Install
./zsh-setup install [options]

# Update plugins
./zsh-setup update

# Remove plugin
./zsh-setup remove <plugin-name>

# Check status
./zsh-setup status

# Monitor performance
./zsh-setup monitor [type]

# Self-heal
./zsh-setup heal

# Uninstall
./zsh-setup uninstall
```

## General Development Guidelines

### Shell Scripts (mac-cleanup, zsh-setup, home-netmon)

**Safety First**: These scripts make system-level changes. Always:
- Validate input before operations
- Provide clear confirmation prompts
- Create backups before destructive operations
- Use color-coded output for warnings/errors
- Implement dry-run modes where applicable

**Error Handling**: Use proper exit codes and trap statements for cleanup.

**Testing**: Shell scripts are harder to test. Verify changes manually on test systems.

### Python Projects (ai_model)

**Type Hints**: All functions should have complete type annotations.

**Testing**: Write unit tests for new functionality. Use the test runner:
```bash
cd ai_model
python3 run_tests.py --unit
```

**Backend Symmetry**: When adding features to one backend, consider adding to the other for consistency.

**Documentation**: Update module docstrings and README when changing functionality.

### Git Workflow

This repository uses standard feature branch workflow:
- Main branch: `master`
- Current branch: `cursor/llama-cpp-server-setup-5a6c`
- Recent commits show work on hardware detection and HuggingFace CLI integration

## Key Files to Understand

### ai_model Architecture
- `ai_model/README.md`: Comprehensive documentation (1500+ lines)
- `ai_model/run_tests.py`: Test runner with backend selection
- `ai_model/docker/docker-llm-setup.py`: Docker backend entry point
- `ai_model/ollama/ollama-llm-setup.py`: Ollama backend entry point
- `ai_model/ollama/lib/validator.py`: Model pulling with verification (v4.0 feature)
- `ai_model/ollama/lib/uninstaller.py`: Smart uninstaller with manifest tracking

### zsh-setup Architecture
- `zsh-setup/ARCHITECTURE.md`: Modern architecture documentation
- `zsh-setup/zsh-setup`: Main CLI entry point
- `zsh-setup/lib/core/bootstrap.sh`: Module loader
- `zsh-setup/lib/state/store.sh`: JSON-based state management

## Common Patterns

### ai_model: Adding a New Backend Module

When adding functionality to a backend, follow this pattern:

1. Create/modify module in `{backend}/lib/module_name.py`
2. Import in main script: `from lib import module_name`
3. Add unit tests in `{backend}/tests/test_unit_module_name.py`
4. Add integration tests if needed
5. Update backend's lib/__init__.py if adding new module

### zsh-setup: Adding a New Command

1. Create command file in `commands/command_name.sh`
2. Implement function: `zsh_setup::commands::command_name::execute()`
3. Use bootstrap to load required modules
4. Update main CLI script to dispatch to new command
5. Add tests in `tests/`

### Shell Script Error Handling

Standard pattern used across shell scripts:
```bash
trap cleanup EXIT
set -euo pipefail  # Exit on error, undefined vars, pipe failures

cleanup() {
    # Cleanup code here
}
```

## Working with Continue.dev Configuration

The ai_model project generates Continue.dev configs:
- **Location**: `~/.continue/config.yaml` and `~/.continue/config.json`
- **Global Rules**: `~/.continue/rules/global-rule.md`
- **Schema Compliance**: Configs follow official Continue.dev JSON schema
- **IDE Support**: VS Code (YAML + JSON) and IntelliJ IDEA (JSON only)

When modifying config generation (`config.py`):
- Maintain schema compliance with Continue.dev specification
- Update both YAML and JSON generators
- Test with actual IDE to verify config loads correctly
