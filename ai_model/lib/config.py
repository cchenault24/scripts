"""
OpenCode configuration generation for IntelliJ IDEA.

Provides functions to:
- Generate OpenCode configuration
- Optimize model parameters for Mac Silicon
- Create setup instructions
"""

import json
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

from . import hardware
from . import ui

# Module logger
_logger = logging.getLogger(__name__)

# Version for tracking
INSTALLER_VERSION = "5.0.0"

# Ollama API endpoint
OLLAMA_API_BASE = "http://127.0.0.1:11434"


def _get_utc_timestamp() -> str:
    """Get current UTC timestamp in ISO format."""
    return datetime.now(timezone.utc).isoformat()


def get_model_parameters_for_hardware(hw_info: hardware.HardwareInfo) -> Dict[str, Any]:
    """
    Get optimized model parameters based on Mac Silicon hardware.

    Args:
        hw_info: Hardware information

    Returns:
        Dictionary of model parameters optimized for the hardware
    """
    chip_gen = hw_info.apple_chip_model or ""
    ram_gb = hw_info.ram_gb

    # Base parameters (conservative)
    params = {
        "temperature": 0.7,
        "top_p": 0.9,
        "top_k": 40,
        "num_predict": -1,  # No limit
        "num_ctx": 8192,  # Context window
        "repeat_penalty": 1.1,
        "mirostat": 0,  # Disabled by default
        "mirostat_tau": 5.0,
        "mirostat_eta": 0.1,
    }

    # Optimize for chip generation and RAM
    if "M4" in chip_gen or "M3" in chip_gen:
        # M3/M4 have better Neural Engine
        if ram_gb >= 24:
            # High RAM: aggressive settings
            params.update({
                "temperature": 0.8,
                "num_ctx": 16384,  # Larger context
                "top_k": 50,
            })
        elif ram_gb >= 16:
            # Medium RAM: balanced
            params.update({
                "temperature": 0.75,
                "num_ctx": 12288,
                "top_k": 45,
            })
    elif "M2" in chip_gen or "M1" in chip_gen:
        # M1/M2: conservative settings
        if ram_gb >= 24:
            params.update({
                "temperature": 0.75,
                "num_ctx": 12288,
            })
        else:
            # Keep defaults for 16GB
            params.update({
                "num_ctx": 8192,
            })

    return params


def generate_opencode_config(
    model_name: str,
    embedding_model: Optional[str],
    hw_info: hardware.HardwareInfo,
    output_dir: Optional[Path] = None
) -> Optional[Path]:
    """
    Generate OpenCode configuration file.

    Note: OpenCode may configure directly in IntelliJ settings UI,
    but this generates a reference config for manual setup.

    Args:
        model_name: Main Gemma4 model name
        embedding_model: Embedding model name (optional)
        hw_info: Hardware information
        output_dir: Output directory (default: ~/.opencode or temp)

    Returns:
        Path to generated config file, or None if OpenCode uses UI-only config
    """
    if output_dir is None:
        # Use temp directory for reference config
        output_dir = Path.home() / ".opencode"
        output_dir.mkdir(exist_ok=True, parents=True)

    # Get optimized parameters
    params = get_model_parameters_for_hardware(hw_info)

    # Generate config structure
    config = {
        "version": "1.0",
        "created_by": f"ai_model_setup v{INSTALLER_VERSION}",
        "created_at": _get_utc_timestamp(),
        "ollama": {
            "api_base": OLLAMA_API_BASE,
            "models": {
                "chat": {
                    "name": model_name,
                    "parameters": params
                }
            }
        },
        "hardware": {
            "chip": hw_info.apple_chip_model or hw_info.cpu_brand,
            "ram_gb": hw_info.ram_gb,
            "optimized": True
        }
    }

    # Add embedding model if specified
    if embedding_model:
        config["ollama"]["models"]["embedding"] = {
            "name": embedding_model,
            "parameters": {
                "temperature": 0.0,  # Deterministic for embeddings
                "top_k": 1,
            }
        }

    # Write config file (for reference/documentation)
    config_path = output_dir / "opencode-config.json"
    try:
        with open(config_path, 'w') as f:
            json.dump(config, indent=2, fp=f)
        ui.print_success(f"Generated reference config: {config_path}")
        return config_path
    except Exception as e:
        _logger.error(f"Failed to write config: {e}")
        ui.print_warning(f"Could not write config file: {e}")
        return None


def display_opencode_setup_instructions(
    model_name: str,
    embedding_model: Optional[str],
    hw_info: hardware.HardwareInfo,
    config_path: Optional[Path]
) -> None:
    """
    Display manual setup instructions for OpenCode in IntelliJ.

    Args:
        model_name: Main Gemma4 model name
        embedding_model: Embedding model name (optional)
        hw_info: Hardware information
        config_path: Path to generated config file (for reference)
    """
    params = get_model_parameters_for_hardware(hw_info)

    print()
    ui.print_header("🔧 OpenCode Configuration")
    print()

    print("OpenCode is configured through IntelliJ IDEA settings.")
    print("Follow these steps to complete setup:")
    print()

    # Step 1: Install plugin
    print(ui.colorize("1. Install OpenCode Plugin:", ui.Colors.CYAN + ui.Colors.BOLD))
    print("   • Open IntelliJ IDEA")
    if hw_info.os_name == "Darwin":
        print("   • Go to: Preferences → Plugins (Cmd+,)")
    else:
        print("   • Go to: Settings → Plugins (Ctrl+Alt+S)")
    print("   • Click 'Marketplace' tab")
    print("   • Search for 'OpenCode'")
    print("   • Click 'Install' and restart IntelliJ")
    print("   • Plugin URL: https://plugins.jetbrains.com/plugin/30681-opencode")
    print()

    # Step 2: Configure Ollama connection
    print(ui.colorize("2. Configure Ollama Connection:", ui.Colors.CYAN + ui.Colors.BOLD))
    print("   • In IntelliJ, open OpenCode settings")
    print("   • Set Ollama API endpoint:")
    print(f"     {ui.colorize(OLLAMA_API_BASE, ui.Colors.GREEN)}")
    print()

    # Step 3: Select model
    print(ui.colorize("3. Select Gemma4 Model:", ui.Colors.CYAN + ui.Colors.BOLD))
    print("   • In OpenCode settings, choose model:")
    print(f"     {ui.colorize(model_name, ui.Colors.GREEN)}")
    print()

    # Step 4: Optimize parameters
    print(ui.colorize("4. Optimize Model Parameters:", ui.Colors.CYAN + ui.Colors.BOLD))
    print(f"   • Temperature: {ui.colorize(str(params['temperature']), ui.Colors.GREEN)}")
    print(f"   • Context Length: {ui.colorize(str(params['num_ctx']), ui.Colors.GREEN)} tokens")
    print(f"   • Top-K: {ui.colorize(str(params['top_k']), ui.Colors.GREEN)}")
    print(f"   • Top-P: {ui.colorize(str(params['top_p']), ui.Colors.GREEN)}")
    print()
    chip_model = hw_info.apple_chip_model or hw_info.cpu_brand
    print(f"   (Optimized for {chip_model} with {hw_info.ram_gb:.0f}GB RAM)")
    print()

    # Step 5: Add embedding model (if applicable)
    if embedding_model:
        print(ui.colorize("5. Configure Embedding Model (Optional):", ui.Colors.CYAN + ui.Colors.BOLD))
        print("   • For semantic code search, configure:")
        print(f"     {ui.colorize(embedding_model, ui.Colors.GREEN)}")
        print("   • Temperature: 0.0 (deterministic)")
        print()

    # Step 6: Verify
    print(ui.colorize("6. Verify Setup:", ui.Colors.CYAN + ui.Colors.BOLD))
    print("   • Open any code file in IntelliJ")
    print("   • Activate OpenCode (check plugin toolbar/menu)")
    print("   • Ask a coding question to test the connection")
    print()

    # Reference config
    if config_path:
        print(ui.colorize("📄 Reference Configuration:", ui.Colors.BLUE))
        print(f"   A reference config file was saved at:")
        print(f"   {ui.colorize(str(config_path), ui.Colors.GREEN)}")
        print()
        print("   This file documents the recommended settings but is NOT")
        print("   automatically loaded by OpenCode. Use it as a reference")
        print("   when configuring through the IntelliJ settings UI.")
        print()

    print(ui.colorize("━" * 60, ui.Colors.DIM))


def create_installation_manifest(
    model_name: str,
    embedding_model: Optional[str],
    hw_info: hardware.HardwareInfo
) -> Path:
    """
    Create installation manifest for tracking installed models.

    Args:
        model_name: Main model name
        embedding_model: Embedding model name (optional)
        hw_info: Hardware information

    Returns:
        Path to manifest file
    """
    manifest_dir = Path.home() / ".opencode"
    manifest_dir.mkdir(exist_ok=True, parents=True)
    manifest_path = manifest_dir / "setup-manifest.json"

    models = [{"name": model_name}]
    if embedding_model:
        models.append({"name": embedding_model})

    manifest = {
        "version": "1.0",
        "installer_version": INSTALLER_VERSION,
        "installer_type": "opencode",
        "timestamp": _get_utc_timestamp(),
        "hardware": {
            "chip": hw_info.apple_chip_model or hw_info.cpu_brand,
            "ram_gb": hw_info.ram_gb,
            "os": hw_info.os_name
        },
        "installed": {
            "models": models
        }
    }

    try:
        with open(manifest_path, 'w') as f:
            json.dump(manifest, indent=2, fp=f)
        return manifest_path
    except Exception as e:
        _logger.error(f"Failed to create manifest: {e}")
        return manifest_path


def check_config_customization(config_path: Path, manifest: dict) -> str:
    """
    Check if a config file has been customized since installation.

    Args:
        config_path: Path to config file
        manifest: Installation manifest

    Returns:
        Status: "original", "modified", or "unknown"
    """
    # Simple stub for uninstaller compatibility
    # Always returns "unknown" since we don't track config customizations
    return "unknown"


def is_our_file(filepath: Path, manifest: dict) -> bool:
    """
    Check if a file was created by our setup script.

    Args:
        filepath: Path to file
        manifest: Installation manifest

    Returns:
        True if file was created by us, False otherwise
    """
    # Simple stub for uninstaller compatibility
    # Always returns False (conservative approach)
    return False
