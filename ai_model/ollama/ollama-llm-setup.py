#!/usr/bin/env python3
"""
Ollama + Continue.dev Setup Script

An interactive Python script that helps you set up a locally hosted LLM
via Ollama and generates a continue.dev config.yaml for VS Code.

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

# Import from lib modules (from ollama/lib/)
from lib import config
from lib import ollama
from lib import hardware
from lib import ide
from lib import models
from lib import ui


def main() -> int:
    """Main entry point."""
    ui.clear_screen()
    
    ui.print_header("🚀 Ollama + Continue.dev Setup")
    ui.print_info("This script will help you set up a locally hosted LLM")
    ui.print_info("via Ollama and configure Continue.dev for VS Code and IntelliJ IDEA.")
    print()
    
    if not ui.prompt_yes_no("Ready to begin setup?", default=True):
        ui.print_info("Setup cancelled. Run again when ready!")
        return 0
    
    # Install rich in background for better progress bars (non-blocking)
    models._install_rich_background()
    
    # Step 1: Hardware detection
    print()
    hw_info = hardware.detect_hardware()
    
    # Step 2: IDE selection
    print()
    ui.print_subheader("IDE Selection")
    ide_choices = ["VS Code only", "IntelliJ only", "Both"]
    ide_choice_idx = ui.prompt_choice("Which IDE(s) do you want to configure?", ide_choices, default=2)
    
    # Map choice to target_ide list
    if ide_choice_idx == 0:
        target_ide = ["vscode"]
    elif ide_choice_idx == 1:
        target_ide = ["intellij"]
    else:  # Both
        target_ide = ["vscode", "intellij"]
    
    ide_names = []
    if "vscode" in target_ide:
        ide_names.append("VS Code")
    if "intellij" in target_ide:
        ide_names.append("IntelliJ IDEA")
    ui.print_success(f"Selected: {', '.join(ide_names)}")
    
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
    
    # Step 5: Preset selection
    print()
    preset = models.select_preset(hw_info)
    
    # Step 6: Model selection
    print()
    if preset and preset != "Custom":
        # Get portfolio option based on preset
        ui.print_info(f"Generating {preset} portfolio recommendation...")
        selected_models = models.get_portfolio_option_by_preset(hw_info, preset)
        
        if not selected_models:
            ui.print_warning("Could not generate portfolio recommendation. Falling back to manual selection.")
            selected_models = models.select_models(hw_info)
        else:
            # Display what was selected
            options = models.generate_portfolio_options(hw_info)
            for option_name, models_list, _ in options:
                if models_list == selected_models:
                    ui.print_success(f"Selected {preset} preset: {option_name}")
                    break
            print()
    else:
        # Custom selection - show all options
        selected_models = models.select_models(hw_info)
    
    if not selected_models:
        ui.print_error("No models selected. Aborting setup.")
        return 1
    
    # Step 7: Display RAM usage
    print()
    models.display_ram_usage(selected_models, hw_info)
    
    # Step 8: Validate selection
    print()
    ui.print_subheader("Safety Validation")
    is_valid, warnings = models.validate_model_selection(selected_models, hw_info)
    
    if warnings:
        for warning in warnings:
            ui.print_warning(warning)
        print()
    
    if not is_valid:
        ui.print_error("Validation failed. Please adjust your model selection.")
        if not ui.prompt_yes_no("Continue anyway? (Not recommended)", default=False):
            ui.print_info("Setup cancelled.")
            return 0
    
    # Step 9: Confirm selection
    print()
    ui.print_subheader("Configuration Summary")
    total_ram = sum(m.ram_gb for m in selected_models)
    print(f"  Selected {len(selected_models)} model(s):")
    for model in selected_models:
        variant_info = f" ({model.selected_variant})" if model.selected_variant else ""
        print(f"    • {model.name}{variant_info} (~{model.ram_gb:.1f}GB RAM)")
    print(f"  Total estimated RAM: ~{total_ram:.1f}GB")
    print(f"  Target IDE(s): {', '.join(ide_names)}")
    print()
    
    if not ui.prompt_yes_no("Proceed with this configuration?", default=True):
        ui.print_info("Setup cancelled. Run again to reconfigure.")
        return 0
    
    # Step 10: Pull models
    print()
    pulled_models = models.pull_models_ollama(selected_models, hw_info)
    
    # Step 11: Generate config
    print()
    config_path = config.generate_continue_config(pulled_models, hw_info, target_ide=target_ide)
    
    # Step 12: Generate global-rule.md
    print()
    rule_path = config.generate_global_rule()
    
    # Step 13: Generate .continueignore
    print()
    ignore_path = config.generate_continueignore()
    
    # Step 14: Save setup summary
    print()
    summary_path = config.save_setup_summary(pulled_models, hw_info)
    
    # Step 15: Show next steps
    print()
    ide.show_next_steps(config_path, pulled_models, hw_info, target_ide=target_ide)
    
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
