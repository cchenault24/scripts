#!/usr/bin/env python3
"""
Ollama + OpenCode Setup Script (v5.0)

Interactive setup for Gemma4 models with OpenCode in IntelliJ IDEA.

NEW in v5.0:
- Single model selection with user choice
- Gemma4 model family (2B, 4B, 26B, 31B)
- OpenCode plugin for IntelliJ IDEA
- Mac Silicon optimized parameters
- Optional embedding model (nomic-embed-text)

Requirements:
- Python 3.8+
- macOS with Apple Silicon (M1/M2/M3/M4)
- Ollama installed (https://ollama.com)
- IntelliJ IDEA + OpenCode plugin

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
from lib import ide
from lib import model_selector
from lib import ollama
from lib import ui
from lib import validator

# Module logger
_logger = logging.getLogger(__name__)

# Embedding model (optional, recommended for code search)
EMBEDDING_MODEL = "nomic-embed-text"


def main() -> int:
    """Main entry point."""
    ui.clear_screen()

    ui.print_header("🚀 Ollama + OpenCode Setup v5.0")
    ui.print_info("Gemma4 models for IntelliJ IDEA")
    ui.print_info("Optimized for Mac Silicon")
    print()

    if not ui.prompt_yes_no("Ready to begin setup?", default=True):
        ui.print_info("Setup cancelled. Run again when ready!")
        return 0

    # Step 1: Hardware detection
    print()
    hw_info = hardware.detect_hardware()

    # Step 2: Check for IntelliJ IDEA
    print()
    ui.print_subheader("Detecting IntelliJ IDEA")
    if ide.is_intellij_installed():
        ui.print_success("✓ IntelliJ IDEA detected")

        # Check for OpenCode plugin
        if ide.verify_opencode_plugin():
            ui.print_success("✓ OpenCode plugin detected")
        else:
            ui.print_warning("⚠ OpenCode plugin not detected")
            print()
            print("You'll need to install the OpenCode plugin after model setup.")
            print(f"Plugin URL: {ide.get_opencode_plugin_url()}")
    else:
        ui.print_warning("⚠ IntelliJ IDEA not found")
        print()
        print("Please install IntelliJ IDEA before continuing:")
        print("  https://www.jetbrains.com/idea/download/")
        print()
        if not ui.prompt_yes_no("Continue setup anyway?", default=False):
            return 0

    # Step 3: Model selection (interactive)
    print()
    selected_model = model_selector.select_model_interactive(hw_info)

    # Step 4: Ask about embedding model
    print()
    ui.print_subheader("Embedding Model (Optional)")
    print()
    print("An embedding model enables semantic code search:")
    print("  • Ask 'how does authentication work?' → finds relevant files")
    print("  • Understands code meaning, not just keywords")
    print(f"  • Model: {ui.colorize(EMBEDDING_MODEL, ui.Colors.CYAN)} (274 MB)")
    print()

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
        ui.print_error(f"✗ {msg}")
        return 1

    ui.print_success(f"✓ Ollama {ollama_version} ready")

    # Get pre-existing models
    try:
        pre_existing_models = validator.get_installed_models()
    except Exception as e:
        _logger.warning(f"Could not get pre-existing models: {e}")
        pre_existing_models = []

    # Step 6: Pull selected model
    print()
    ui.print_header("📥 Downloading Models")
    print()

    models_to_pull = [selected_model.ollama_name]
    if embedding_model_name:
        models_to_pull.append(embedding_model_name)

    pulled_models = []
    failed_models = []

    for i, model_name in enumerate(models_to_pull, start=1):
        print(f"[{i}/{len(models_to_pull)}] Pulling {ui.colorize(model_name, ui.Colors.CYAN)}...")
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
            ui.print_error(f"✗ Failed to pull {model_name}: {error_msg}")
            print()

    # Step 7: Summary
    print()
    ui.print_header("📊 Setup Summary")
    print()

    if pulled_models:
        ui.print_success(f"✓ Successfully pulled {len(pulled_models)} model(s):")
        for model in pulled_models:
            print(f"  • {ui.colorize(model, ui.Colors.GREEN)}")
        print()

    if failed_models:
        ui.print_error(f"✗ Failed to pull {len(failed_models)} model(s):")
        for model, error in failed_models:
            print(f"  • {ui.colorize(model, ui.Colors.RED)}: {error}")
        print()

    # Step 8: Generate OpenCode configuration
    print()
    ui.print_header("⚙️ Configuration")
    print()

    # Generate reference config
    config_path = config.generate_opencode_config(
        model_name=selected_model.ollama_name,
        embedding_model=embedding_model_name,
        hw_info=hw_info
    )

    # Create installation manifest
    manifest_path = config.create_installation_manifest(
        model_name=selected_model.ollama_name,
        embedding_model=embedding_model_name,
        hw_info=hw_info
    )
    if manifest_path.exists():
        ui.print_success(f"✓ Created manifest: {manifest_path}")

    # Step 9: Display setup instructions
    config.display_opencode_setup_instructions(
        model_name=selected_model.ollama_name,
        embedding_model=embedding_model_name,
        hw_info=hw_info,
        config_path=config_path
    )

    # Step 10: Verification
    print()
    ui.print_header("✅ Setup Complete!")
    print()
    print("Next steps:")
    print("  1. Open IntelliJ IDEA")
    print("  2. Install OpenCode plugin (if not already)")
    print("  3. Configure OpenCode using the instructions above")
    print("  4. Start coding with AI assistance!")
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
