#!/usr/bin/env python3
"""
Ollama + OpenCode Setup Script (v5.1)

Interactive setup for Gemma4 models with OpenCode CLI.

NEW in v5.1:
- OpenCode CLI installation and configuration
- Simplified terminal-based workflow
- No IDE dependencies required

Previous (v5.0):
- Single model selection with user choice
- Gemma4 model family (2B, 4B, 26B, 31B)
- Mac Silicon optimized parameters
- Optional embedding model (nomic-embed-text)

Requirements:
- Python 3.8+
- macOS with Apple Silicon (M1/M2/M3/M4)
- Ollama installed (https://ollama.com)

Author: AI-Generated for Local LLM Development
License: MIT
"""

from __future__ import annotations

import logging
import sys
from pathlib import Path

# Add project root to path
script_path = Path(__file__).resolve()
project_root = script_path.parent
if str(project_root) not in sys.path:
    sys.path.insert(0, str(project_root))

# Import from lib modules
from lib import config
from lib import hardware
from lib import model_selector
from lib import opencode
from lib import ollama
from lib import ui
from lib import validator

# Module logger
_logger = logging.getLogger(__name__)

# Embedding model (optional, recommended for code search)
EMBEDDING_MODEL = "nomic-embed-text"


def is_model_installed(model_name: str, installed_models: list) -> bool:
    """
    Check if a model is installed (handles :latest tag variants).

    Args:
        model_name: Model name to check (e.g., "nomic-embed-text" or "nomic-embed-text:latest")
        installed_models: List of installed model names

    Returns:
        True if model is installed (with any tag variant)
    """
    # Exact match
    if model_name in installed_models:
        return True

    # Check if model name without tag matches installed name with tag
    # e.g., "nomic-embed-text" should match "nomic-embed-text:latest"
    base_name = model_name.split(':')[0]
    return any(
        installed.split(':')[0] == base_name
        for installed in installed_models
    )


def main() -> int:
    """Main entry point."""
    ui.clear_screen()

    ui.print_header("🚀 Ollama + OpenCode Setup v5.1")
    ui.print_info("Gemma4 models with OpenCode CLI")
    ui.print_info("Optimized for Mac Silicon")
    print()

    if not ui.prompt_yes_no("Ready to begin setup?", default=True):
        ui.print_info("Setup cancelled. Run again when ready!")
        return 0

    # Step 1: Hardware detection
    print()
    hw_info = hardware.detect_hardware()

    # Step 1.5: Check currently installed models (for display in selection menu)
    try:
        installed_models = validator.get_installed_models()
    except Exception as e:
        _logger.warning(f"Could not check installed models: {e}")
        installed_models = []

    # Step 2: Check/Install OpenCode CLI
    print()
    ui.print_subheader("OpenCode CLI")

    if opencode.is_opencode_installed():
        version = opencode.get_opencode_version()
        ui.print_success(f"OpenCode CLI already installed ({version})")
    else:
        ui.print_info("OpenCode CLI not found")
        print()
        if ui.prompt_yes_no("Install OpenCode CLI now?", default=True):
            print()
            success, message = opencode.install_opencode_cli()
            print()
            if success:
                ui.print_success(f"{message}")
            else:
                ui.print_error(f"{message}")
                return 1
        else:
            ui.print_warning("⚠ Skipping OpenCode CLI installation")
            ui.print_info("You can install it later: curl -fsSL https://opencode.ai/install | bash")
            print()
            if not ui.prompt_yes_no("Continue without OpenCode CLI?", default=False):
                return 0

    # Step 3: Model selection (interactive with installation status)
    print()
    selected_model = model_selector.select_model_interactive(hw_info, installed_models)

    # Step 4: Ask about embedding model
    print()
    ui.print_subheader("Embedding Model (Optional)")
    print()

    # Check if embedding model is already installed (handle :latest tag)
    embedding_installed = is_model_installed(EMBEDDING_MODEL, installed_models)

    if embedding_installed:
        installed_marker = ui.colorize(" - ALREADY INSTALLED", ui.Colors.BLUE)
    else:
        installed_marker = ""

    print("An embedding model enables semantic code search:")
    print("  • Ask 'how does authentication work?' → finds relevant files")
    print("  • Understands code meaning, not just keywords")
    print(f"  • Model: {ui.colorize(EMBEDDING_MODEL, ui.Colors.CYAN)} (274 MB){installed_marker}")
    print()

    if embedding_installed:
        ui.print_success(f"{EMBEDDING_MODEL} is already installed")
        print()
        if ui.prompt_yes_no("Use this embedding model?", default=True):
            embedding_model_name = EMBEDDING_MODEL
        else:
            embedding_model_name = None
    else:
        install_embedding = ui.prompt_yes_no(
            "Install embedding model for code search?",
            default=True
        )
        embedding_model_name = EMBEDDING_MODEL if install_embedding else None

    # Step 5: Pre-flight checks
    print()
    ui.print_subheader("Pre-flight Checks")

    # Check Ollama
    success, msg, ollama_version = validator.run_preflight_check(show_progress=False)
    if not success:
        ui.print_error(msg)
        print()

        # Try to auto-start Ollama
        ui.print_info("Attempting to start Ollama...")
        start_success, start_msg = ollama.start_ollama()

        if start_success:
            ui.print_success(start_msg)
            print()

            # Retry preflight check
            ui.print_info("Retrying connection...")
            success, msg, ollama_version = validator.run_preflight_check(show_progress=False)

            if success:
                ui.print_success(f"Ollama {ollama_version} ready")
            else:
                ui.print_error(msg)
                return 1
        else:
            ui.print_error(start_msg)
            print()
            ui.print_info("Please start Ollama manually:")
            print("  • macOS: Open Ollama app or run 'ollama serve'")
            print("  • Linux: Run 'systemctl start ollama' or 'ollama serve'")
            return 1
    else:
        ui.print_success(f"Ollama {ollama_version} ready")

    # Check if Ollama needs upgrading
    print()
    ui.print_info("Checking Ollama version...")
    needs_upgrade, current_version, latest_version = ollama.check_and_prompt_upgrade()

    if needs_upgrade and latest_version:
        ui.print_warning(f"Ollama {current_version} is outdated")
        ui.print_info(f"Latest version: {latest_version}")
        print()
        print("Newer Gemma4 models require the latest Ollama version.")
        print("Without upgrading, some models may fail to download with HTTP 412 errors.")
        print()

        if ui.prompt_yes_no(f"Upgrade Ollama to {latest_version} now?", default=True):
            print()
            ui.print_info("Upgrading Ollama...")
            success, upgrade_msg = ollama.upgrade_ollama()

            if success:
                ui.print_success(f"{upgrade_msg}")
                print()
                ui.print_info("Please restart Ollama for the upgrade to take effect:")
                print(f"  1. Quit Ollama from menu bar (if running)")
                print(f"  2. Start Ollama again")
                print(f"  3. Re-run this setup: {ui.colorize('python3 setup.py', ui.Colors.CYAN)}")
                print()
                return 0
            else:
                ui.print_error(f"Upgrade failed: {upgrade_msg}")
                print()
                if not ui.prompt_yes_no("Continue with outdated Ollama?", default=False):
                    return 1
        else:
            ui.print_warning("Continuing with outdated Ollama - some models may fail to download")
    elif current_version:
        ui.print_success(f"Ollama {current_version} is up to date")

    # Step 6: Check and pull models (idempotent)
    print()
    ui.print_header("📥 Model Installation")
    print()

    models_to_pull = [selected_model.ollama_name]
    if embedding_model_name:
        models_to_pull.append(embedding_model_name)

    # Check which models are already installed
    already_installed = []
    needs_installation = []

    try:
        installed_models = validator.get_installed_models()
        for model_name in models_to_pull:
            if is_model_installed(model_name, installed_models):
                already_installed.append(model_name)
            else:
                needs_installation.append(model_name)
    except Exception as e:
        _logger.warning(f"Could not check installed models: {e}")
        needs_installation = models_to_pull

    # Show what's already installed
    if already_installed:
        ui.print_success(f"Already installed ({len(already_installed)} model(s)):")
        for model in already_installed:
            print(f"  • {ui.colorize(model, ui.Colors.GREEN)}")
        print()

    # Pull missing models
    pulled_models = []
    failed_models = []

    if needs_installation:
        ui.print_info(f"Installing {len(needs_installation)} model(s)...")
        print()

        for i, model_name in enumerate(needs_installation, start=1):
            print(f"[{i}/{len(needs_installation)}] Pulling {ui.colorize(model_name, ui.Colors.CYAN)}...")
            print()

            success, error_msg = validator.pull_model_with_verification(
                model_name=model_name,
                show_progress=True
            )

            if success:
                pulled_models.append(model_name)
                print()
            else:
                failed_models.append((model_name, error_msg))
                ui.print_error(f"Failed to pull {model_name}: {error_msg}")
                print()
    else:
        ui.print_success("All required models already installed!")
        print()

    # Step 7: Summary
    print()
    ui.print_header("📊 Setup Summary")
    print()

    # Show what was newly installed
    if pulled_models:
        ui.print_success(f"Newly installed {len(pulled_models)} model(s):")
        for model in pulled_models:
            print(f"  • {ui.colorize(model, ui.Colors.GREEN)}")
        print()

    # Show what was already there
    if already_installed:
        ui.print_info(f"Already had {len(already_installed)} model(s) (not re-downloaded):")
        for model in already_installed:
            print(f"  • {ui.colorize(model, ui.Colors.CYAN)}")
        print()

    # Show failures
    if failed_models:
        ui.print_error(f"Failed to pull {len(failed_models)} model(s):")
        for model, error in failed_models:
            print(f"  • {ui.colorize(model, ui.Colors.RED)}: {error}")
        print()

        # Ask user if they want to continue with partial setup
        print("Model download failed. This is usually caused by:")
        print("  • Network connectivity issues")
        print("  • Ollama server problems")
        print("  • Large model size causing timeouts")
        print()
        print("You can:")
        print(f"  1. Try pulling manually: {ui.colorize(f'ollama pull {failed_models[0][0]}', ui.Colors.CYAN)}")
        print(f"  2. Run setup again (it will skip already-installed models)")
        print()

        if not ui.prompt_yes_no("Continue with partial setup?", default=True):
            ui.print_warning("Setup cancelled due to failed model installation")
            return 1

    # Step 8: Configure OpenCode CLI (idempotent)
    print()
    ui.print_header("⚙️ Configuration")
    print()

    # Generate OpenCode config
    if opencode.is_opencode_installed():
        # Check if config already exists
        config_exists = opencode.config_exists()
        auth_exists = opencode.auth_exists()

        if config_exists:
            ui.print_info("OpenCode config already exists")
            print()
            if ui.prompt_yes_no("Update config with Mac Silicon optimizations?", default=True):
                success, message = opencode.generate_opencode_config(
                    selected_model.ollama_name,
                    overwrite=False,
                    hw_info=hw_info
                )
                if success:
                    ui.print_success(f"{message}")
                else:
                    ui.print_warning(f"{message}")
            else:
                ui.print_info("Preserving existing config")
        else:
            # No existing config, create new one with optimizations
            ui.print_info("Creating optimized OpenCode config for Mac Silicon...")
            success, message = opencode.generate_opencode_config(
                selected_model.ollama_name,
                overwrite=False,
                hw_info=hw_info
            )
            if success:
                ui.print_success(f"Config: ~/.config/opencode/opencode.jsonc")
                print()
                ui.print_info(f"Optimizations applied:")
                print(f"  • Context length: {32768 if hw_info.ram_gb >= 48 else 16384 if hw_info.ram_gb >= 32 else 8192} tokens")
                print(f"  • GPU acceleration: Metal (all layers)")
                print(f"  • CPU threads: {hw_info.cpu_cores_performance if hasattr(hw_info, 'cpu_cores_performance') else hw_info.cpu_cores}")
                print(f"  • Extended timeouts for large models")
            else:
                ui.print_warning(f"{message}")

        print()

        # Create optimized Modelfile for advanced users
        ui.print_info("Creating optimized Modelfile template...")
        success, message = opencode.create_optimized_modelfile(
            selected_model.ollama_name,
            hw_info=hw_info
        )
        if success:
            ui.print_success("Optimized Modelfile template created")
            print(f"  Location: ~/.config/opencode/Modelfile.{selected_model.ollama_name}.optimized")
            print(f"  To use: ollama create {selected_model.ollama_name}-optimized -f <path-to-modelfile>")

        print()

        # Generate auth file (safe - won't overwrite)
        success, message = opencode.generate_opencode_auth(overwrite=False)
        if "already exists" in message:
            ui.print_success(f"Auth: {message}")
        elif success:
            ui.print_success(f"Auth: ~/.local/share/opencode/auth.json")
        else:
            ui.print_warning(f"{message}")

        print()

        # Test connection
        ui.print_info("Testing connection to Ollama...")
        success, message = opencode.test_opencode_connection(selected_model.ollama_name)
        if success:
            ui.print_success(message)
        else:
            ui.print_warning(f"{message}")
    else:
        ui.print_warning("⚠ OpenCode CLI not installed, skipping configuration")

    print()

    # Create installation manifest
    manifest_path = config.create_installation_manifest(
        model_name=selected_model.ollama_name,
        embedding_model=embedding_model_name,
        hw_info=hw_info
    )
    if manifest_path.exists():
        ui.print_success(f"Created manifest: {manifest_path}")

    # Step 9: Display usage instructions
    if opencode.is_opencode_installed():
        opencode.display_opencode_usage_instructions(selected_model.ollama_name)

    # Step 10: Completion
    print()
    ui.print_header("✅ Setup Complete!")
    print()

    if opencode.is_opencode_installed():
        print("🎯 Ready to code with AI assistance!")
        print()
        print("Quick start:")
        print(f"  {ui.colorize('cd /path/to/your/project', ui.Colors.CYAN)}")
        print(f"  {ui.colorize('opencode', ui.Colors.GREEN)}  # Opens interactive TUI")
    else:
        print("Models installed successfully!")
        print()
        print("To use OpenCode CLI, install it first:")
        print(f"  {ui.colorize('curl -fsSL https://opencode.ai/install | bash', ui.Colors.CYAN)}")
        print()
        print("Or use Ollama directly:")
        print(f"  {ui.colorize(f'ollama run {selected_model.ollama_name}', ui.Colors.GREEN)}")

    print()

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print()
        ui.print_warning("Setup interrupted by user")
        sys.exit(130)
    except Exception as e:
        _logger.exception("Unexpected error during setup")
        ui.print_error(f"Setup failed: {type(e).__name__}: {e}")
        sys.exit(1)
