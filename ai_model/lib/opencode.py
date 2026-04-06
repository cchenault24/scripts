"""
OpenCode CLI installation and configuration.

Provides functions to:
- Check if OpenCode CLI is installed
- Install OpenCode CLI
- Generate OpenCode configuration files
- Test OpenCode connection
"""

import json
import logging
import subprocess
from pathlib import Path
from typing import Optional, Tuple

from . import ui

# Module logger
_logger = logging.getLogger(__name__)

# OpenCode paths
OPENCODE_BIN = Path.home() / ".opencode" / "bin" / "opencode"
OPENCODE_CONFIG_DIR = Path.home() / ".config" / "opencode"
OPENCODE_DATA_DIR = Path.home() / ".local" / "share" / "opencode"


def is_opencode_installed() -> bool:
    """Check if OpenCode CLI is installed."""
    return OPENCODE_BIN.exists() and OPENCODE_BIN.is_file()


def get_opencode_version() -> Optional[str]:
    """Get installed OpenCode version."""
    if not is_opencode_installed():
        return None

    try:
        result = subprocess.run(
            [str(OPENCODE_BIN), "--version"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            # Extract version from output
            return result.stdout.strip()
        return None
    except Exception as e:
        _logger.warning(f"Failed to get OpenCode version: {e}")
        return None


def install_opencode_cli() -> Tuple[bool, str]:
    """
    Install OpenCode CLI from official installer.

    Returns:
        Tuple of (success, message)
    """
    ui.print_info("Installing OpenCode CLI...")
    print()

    try:
        # Run official installer
        result = subprocess.run(
            ["bash", "-c", "curl -fsSL https://opencode.ai/install | bash"],
            capture_output=False,  # Show installer output
            timeout=120
        )

        if result.returncode == 0:
            if is_opencode_installed():
                version = get_opencode_version()
                return True, f"OpenCode CLI installed successfully ({version})"
            else:
                return False, "Installer completed but opencode binary not found"
        else:
            return False, f"Installer failed with exit code {result.returncode}"

    except subprocess.TimeoutExpired:
        return False, "Installation timed out after 120 seconds"
    except Exception as e:
        return False, f"Installation failed: {e}"


def config_exists() -> bool:
    """Check if OpenCode config file exists."""
    config_file = OPENCODE_CONFIG_DIR / "opencode.jsonc"
    return config_file.exists()


def auth_exists() -> bool:
    """Check if OpenCode auth file exists."""
    auth_file = OPENCODE_DATA_DIR / "auth.json"
    return auth_file.exists()


def get_existing_config() -> Optional[dict]:
    """
    Read existing OpenCode config file.

    Returns:
        Config dict if exists, None otherwise
    """
    config_file = OPENCODE_CONFIG_DIR / "opencode.jsonc"
    if not config_file.exists():
        return None

    try:
        with open(config_file, 'r') as f:
            return json.load(f)
    except Exception as e:
        _logger.warning(f"Failed to read existing config: {e}")
        return None


def generate_opencode_config(
    model_name: str,
    overwrite: bool = False,
    hw_info: Optional[Any] = None
) -> Tuple[bool, str]:
    """
    Generate or update OpenCode configuration file with Mac Silicon optimizations.

    Args:
        model_name: Ollama model name to configure
        overwrite: If True, replace existing config. If False, merge model into existing config.
        hw_info: Hardware information for optimizations (optional)

    Returns:
        Tuple of (success, message)
    """
    OPENCODE_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    config_file = OPENCODE_CONFIG_DIR / "opencode.jsonc"

    # Check if config already exists
    existing_config = get_existing_config()

    if existing_config and not overwrite:
        # Merge model into existing config
        try:
            if "provider" in existing_config and "ollama" in existing_config["provider"]:
                # Add model to existing ollama provider
                if "models" not in existing_config["provider"]["ollama"]:
                    existing_config["provider"]["ollama"]["models"] = {}

                models = existing_config["provider"]["ollama"]["models"]

                # Check if model already exists
                if model_name in models:
                    # If it's already first, no changes needed
                    if list(models.keys())[0] == model_name:
                        return True, f"Model {model_name} already configured as default"

                    # Move model to first position (make it default)
                    models = {model_name: models.pop(model_name), **models}
                    existing_config["provider"]["ollama"]["models"] = models

                    with open(config_file, 'w') as f:
                        json.dump(existing_config, f, indent=2)
                    return True, f"Set {model_name} as default model"
                else:
                    # Add new model at the beginning (make it default)
                    models = {model_name: {}, **models}
                    existing_config["provider"]["ollama"]["models"] = models

                    with open(config_file, 'w') as f:
                        json.dump(existing_config, f, indent=2)
                    return True, f"Added {model_name} and set as default"
            else:
                # Existing config doesn't have ollama, add it
                if "provider" not in existing_config:
                    existing_config["provider"] = {}

                existing_config["provider"]["ollama"] = {
                    "npm": "@ai-sdk/openai-compatible",
                    "options": {
                        "baseURL": "http://localhost:11434/v1"
                    },
                    "models": {
                        model_name: {}
                    }
                }

                with open(config_file, 'w') as f:
                    json.dump(existing_config, f, indent=2)
                return True, "Added Ollama provider with default model"
        except Exception as e:
            _logger.error(f"Failed to merge config: {e}")
            return False, f"Failed to merge config: {e}"

    # Get optimized settings for Mac Silicon
    optimized_options = _get_optimized_ollama_options(hw_info)

    # Create new config with selected model as default (first in list)
    config = {
        "$schema": "https://opencode.ai/config.json",
        "model": f"ollama/{model_name}",
        "provider": {
            "ollama": {
                "npm": "@ai-sdk/openai-compatible",
                "options": optimized_options,
                "models": {
                    model_name: {}
                }
            }
        }
    }

    try:
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=2)
        return True, "Created optimized config for Mac Silicon"
    except Exception as e:
        _logger.error(f"Failed to write OpenCode config: {e}")
        return False, f"Failed to write config: {e}"


def _get_optimized_ollama_options(hw_info: Optional[Any] = None) -> Dict[str, Any]:
    """
    Generate optimized Ollama provider options for Mac Silicon.

    Args:
        hw_info: Hardware information (optional)

    Returns:
        Dictionary of optimized options
    """
    options = {
        "baseURL": "http://localhost:11434/v1",
        # Longer timeout for large models on Mac Silicon
        "timeout": 600000,  # 10 minutes
        # Longer chunk timeout for GPU inference
        "chunkTimeout": 60000,  # 60 seconds between chunks
    }

    # Add Mac Silicon specific optimizations if hardware info is available
    if hw_info:
        # Add comment for documentation (will be stripped by JSON parser but useful for manual editing)
        pass

    return options


def create_optimized_modelfile(
    model_name: str,
    hw_info: Optional[Any] = None
) -> Tuple[bool, str]:
    """
    Create an optimized Modelfile for Mac Silicon with the selected model.

    This creates a custom Modelfile with optimized parameters for:
    - Context length based on available RAM
    - GPU layer configuration for Metal acceleration
    - Thread count based on CPU cores
    - Batch size optimization

    Args:
        model_name: The base Ollama model to optimize
        hw_info: Hardware information for optimization

    Returns:
        Tuple of (success, message)
    """
    try:
        # Calculate optimal parameters based on hardware
        if hw_info:
            ram_gb = getattr(hw_info, 'ram_gb', 16)
            cpu_cores = getattr(hw_info, 'cpu_cores', 8)
            performance_cores = getattr(hw_info, 'cpu_cores_performance', cpu_cores)
        else:
            ram_gb = 16
            performance_cores = 8

        # Determine optimal context length based on available RAM
        # Rule of thumb: ~1GB RAM per 4K context for large models
        if ram_gb >= 48:
            num_ctx = 32768  # 32K context for 48GB+ RAM
        elif ram_gb >= 32:
            num_ctx = 16384  # 16K context for 32GB+ RAM
        elif ram_gb >= 24:
            num_ctx = 8192   # 8K context for 24GB+ RAM
        else:
            num_ctx = 4096   # 4K context for lower RAM

        # Generate optimized Modelfile
        optimized_name = f"{model_name}-optimized"
        modelfile_content = f"""# Optimized Modelfile for Mac Silicon
# Based on {model_name}
# Generated for: {ram_gb}GB RAM, {performance_cores} performance cores

FROM {model_name}

# Context window - optimized for available RAM
PARAMETER num_ctx {num_ctx}

# GPU acceleration - use all layers on Metal GPU
PARAMETER num_gpu 99

# CPU threads - use performance cores
PARAMETER num_thread {performance_cores}

# Batch size - higher for faster processing
PARAMETER num_batch 512

# Generation parameters (keep model defaults)
PARAMETER top_p 0.95
PARAMETER temperature 1
PARAMETER top_k 64

# Keep model loaded in memory (with {ram_gb}GB RAM)
PARAMETER num_keep 24
"""

        # Save Modelfile to a known location
        modelfile_path = OPENCODE_CONFIG_DIR / f"Modelfile.{model_name}.optimized"
        OPENCODE_CONFIG_DIR.mkdir(parents=True, exist_ok=True)

        with open(modelfile_path, 'w') as f:
            f.write(modelfile_content)

        return True, f"Created optimized Modelfile at {modelfile_path}"

    except Exception as e:
        _logger.error(f"Failed to create optimized Modelfile: {e}")
        return False, f"Failed to create Modelfile: {e}"


def generate_opencode_auth(overwrite: bool = False) -> Tuple[bool, str]:
    """
    Generate OpenCode auth file.

    OpenCode expects an auth.json file even for local Ollama.

    Args:
        overwrite: If True, replace existing auth. If False, skip if exists.

    Returns:
        Tuple of (success, message)
    """
    OPENCODE_DATA_DIR.mkdir(parents=True, exist_ok=True)
    auth_file = OPENCODE_DATA_DIR / "auth.json"

    # Check if auth already exists
    if auth_file.exists() and not overwrite:
        return True, "Auth file already exists (preserved)"

    auth = {
        "ollama": {
            "type": "api",
            "key": "ollama"
        }
    }

    try:
        with open(auth_file, 'w') as f:
            json.dump(auth, f, indent=2)
        return True, "Created auth file"
    except Exception as e:
        _logger.error(f"Failed to write OpenCode auth: {e}")
        return False, f"Failed to write auth: {e}"


def test_opencode_connection(model_name: str) -> Tuple[bool, str]:
    """
    Test OpenCode connection to Ollama.

    Args:
        model_name: Ollama model to test

    Returns:
        Tuple of (success, message)
    """
    if not is_opencode_installed():
        return False, "OpenCode CLI not installed"

    try:
        # List available models
        result = subprocess.run(
            [str(OPENCODE_BIN), "models", "ollama"],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode == 0:
            if f"ollama/{model_name}" in result.stdout:
                return True, f"OpenCode can see model: {model_name}"
            else:
                return False, f"Model {model_name} not visible to OpenCode"
        else:
            return False, f"Failed to list models: {result.stderr}"

    except Exception as e:
        return False, f"Connection test failed: {e}"


def display_opencode_usage_instructions(model_name: str) -> None:
    """
    Display instructions for using OpenCode CLI.

    Args:
        model_name: The configured Ollama model name
    """
    print()
    ui.print_header("🚀 Using OpenCode CLI")
    print()

    print(ui.colorize("Interactive Mode (Recommended):", ui.Colors.CYAN + ui.Colors.BOLD))
    print("  • Navigate to your project directory")
    print("  • Run:", ui.colorize("opencode", ui.Colors.GREEN))
    print("  • Opens a TUI (Terminal User Interface) for AI-assisted coding")
    print()

    print(ui.colorize("Quick Questions:", ui.Colors.CYAN + ui.Colors.BOLD))
    print(f"  opencode run -m ollama/{model_name} \"Your question\"")
    print()

    print(ui.colorize("Useful Commands:", ui.Colors.CYAN + ui.Colors.BOLD))
    print(f"  {ui.colorize('opencode models', ui.Colors.GREEN)}          # List available models")
    print(f"  {ui.colorize('opencode --help', ui.Colors.GREEN)}          # Show all commands")
    print(f"  {ui.colorize('/models', ui.Colors.GREEN)}                  # Switch models (in TUI)")
    print()
