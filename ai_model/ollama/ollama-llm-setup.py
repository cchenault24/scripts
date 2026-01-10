#!/usr/bin/env python3
"""
Ollama + Continue.dev Setup Script (v2.0)

An interactive Python script that helps you set up a locally hosted LLM
via Ollama and generates a continue.dev config.yaml for VS Code.

NEW in v2.0:
- Smart model recommendations that fit your RAM
- Tier-based RAM reservation (40%/35%/30%)
- Single "best recommendation" approach with [Accept]/[Customize]
- Reliable model pulling with verification and fallbacks
- Auto-detection of installed IDEs

Optimized for Mac with Apple Silicon (M1/M2/M3/M4) using Ollama.

Requirements:
- Python 3.8+
- Ollama installed (https://ollama.com)
- macOS with Apple Silicon (recommended) or Linux/Windows with NVIDIA GPU

Ollama Commands:
- ollama pull <model>   - Download a model
- ollama run <model>    - Run a model interactively
- ollama list           - List available models
- ollama rm <model>     - Remove a model

Author: AI-Generated for Local LLM Development
License: MIT
"""

import sys
import os
from pathlib import Path

# Add ollama directory to path so we can import lib modules
# Use absolute path to ensure it works from any directory
script_path = Path(__file__).resolve() if __file__ else Path(sys.argv[0]).resolve()
ollama_dir = script_path.parent

# Ensure the ollama_dir is in sys.path (so we import from ollama/lib/)
ollama_dir_str = str(ollama_dir)
if ollama_dir_str not in sys.path:
    sys.path.insert(0, ollama_dir_str)

# Import from lib modules
from lib import config
from lib import ollama
from lib import hardware
from lib import ide
from lib import ui
from lib import model_selector
from lib import validator


def main() -> int:
    """Main entry point with new smart recommendation flow."""
    ui.clear_screen()
    
    ui.print_header("🚀 Ollama + Continue.dev Setup v2.0")
    ui.print_info("Smart model recommendations that fit your hardware")
    ui.print_info("Powered by Continue.dev + Ollama")
    print()
    
    if not ui.prompt_yes_no("Ready to begin setup?", default=True):
        ui.print_info("Setup cancelled. Run again when ready!")
        return 0
    
    # Step 1: Hardware detection
    print()
    hw_info = hardware.detect_hardware()
    
    # Step 2: Auto-detect installed IDEs
    print()
    ui.print_subheader("Detecting Installed IDEs")
    installed_ides = ide.detect_installed_ides()
    
    if installed_ides:
        ide_str = ", ".join(installed_ides)
        ui.print_success(f"Found: {ide_str}")
    else:
        ui.print_warning("No supported IDEs detected")
        ui.print_info("Continue.dev supports: VS Code, Cursor, IntelliJ IDEA")
    
    # Map detected IDEs to target_ide list
    target_ide = []
    if "VS Code" in installed_ides or "Cursor" in installed_ides:
        target_ide.append("vscode")
    if "IntelliJ IDEA" in installed_ides:
        target_ide.append("intellij")
    
    # Default to vscode if no IDEs detected
    if not target_ide:
        target_ide = ["vscode"]
        ui.print_info("Defaulting to VS Code configuration")
    
    # Step 3: Check Ollama (with automatic installation prompt)
    print()
    ollama_ok, ollama_version = ollama.check_ollama()
    if not ollama_ok:
        print()
        ui.print_error("Ollama installation is required to continue.")
        ui.print_info("Please install Ollama and run this script again.")
        return 1
    
    hw_info.ollama_version = ollama_version
    
    # Step 4: Check Ollama API
    print()
    ollama_api_ok = ollama.check_ollama_api(hw_info)
    if not ollama_api_ok:
        print()
        ui.print_error("Ollama API is not accessible.")
        ui.print_info("Please ensure Ollama service is running.")
        return 1
    
    # Step 5: Smart model selection (new approach)
    print()
    selected_models = model_selector.select_models_smart(hw_info, installed_ides)
    
    if not selected_models:
        ui.print_error("No models selected. Aborting setup.")
        return 1
    
    # Step 6: Pre-install validation
    print()
    ui.print_subheader("Pre-Installation Validation")
    is_valid, warnings = validator.validate_pre_install(selected_models, hw_info)
    
    if warnings:
        for warning in warnings:
            ui.print_warning(warning)
        print()
    
    if not is_valid:
        ui.print_error("Validation failed. Please check warnings above.")
        if not ui.prompt_yes_no("Continue anyway? (Not recommended)", default=False):
            ui.print_info("Setup cancelled.")
            return 0
    else:
        ui.print_success("Validation passed")
    
    # Step 7: Confirm selection
    print()
    ui.print_subheader("Configuration Summary")
    total_ram = sum(m.ram_gb for m in selected_models)
    usable_ram = model_selector.get_usable_ram(hw_info)
    buffer = usable_ram - total_ram
    
    print(f"  Selected {len(selected_models)} model(s):")
    for model in selected_models:
        roles_str = ", ".join(model.roles)
        print(f"    • {model.ollama_name} (~{model.ram_gb:.1f}GB RAM) - {roles_str}")
    print(f"  Total RAM: ~{total_ram:.1f}GB / {usable_ram:.1f}GB usable ({buffer:.1f}GB buffer)")
    print(f"  Target IDE(s): {', '.join(installed_ides) if installed_ides else 'VS Code'}")
    print()
    
    if not ui.prompt_yes_no("Proceed with this configuration?", default=True):
        ui.print_info("Setup cancelled. Run again to reconfigure.")
        return 0
    
    # Step 8: Pull models with verification
    print()
    setup_result = validator.pull_models_with_tracking(selected_models, hw_info)
    
    # Display setup result with actionable feedback
    validator.display_setup_result(setup_result)
    
    # Handle partial or complete failure
    if setup_result.complete_failure:
        ui.print_error("No models were installed. Please check your network connection.")
        return 1
    
    # Prompt for next action if there were failures
    if setup_result.failed_models:
        action = validator.prompt_setup_action(setup_result)
        
        if action == "retry":
            # Retry failed models
            setup_result = validator.retry_failed_models(setup_result, hw_info)
            validator.display_setup_result(setup_result)
        elif action == "exit":
            ui.print_info("Exiting. You can retry later with 'ollama pull <model>'")
            return 1
    
    # Use successfully installed models for config
    models_for_config = setup_result.successful_models
    
    if not models_for_config:
        ui.print_error("No models available for configuration.")
        return 1
    
    # Step 9: Generate config
    print()
    config_path = config.generate_continue_config(models_for_config, hw_info, target_ide=target_ide)
    
    # Step 10: Generate global-rule.md
    print()
    config.generate_global_rule()  # Return value not needed
    
    # Step 11: Generate .continueignore
    print()
    config.generate_continueignore()  # Return value not needed
    
    # Step 12: Save setup summary
    print()
    config.save_setup_summary(models_for_config, hw_info)  # Return value not needed
    
    # Step 13: Show next steps
    print()
    ide.show_next_steps(config_path, models_for_config, hw_info, target_ide=target_ide)
    
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print()
        ui.print_warning("Setup interrupted by user.")
        sys.exit(130)
    except Exception as e:
        ui.print_error(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
