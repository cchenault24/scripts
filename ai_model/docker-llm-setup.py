#!/usr/bin/env python3
"""
Docker Model Runner + Continue.dev Setup Script

An interactive Python script that helps you set up a locally hosted LLM
via Docker Model Runner (DMR) and generates a continue.dev config.yaml for VS Code.

Optimized for Mac with Apple Silicon (M1/M2/M3/M4) using Docker Model Runner.

Requirements:
- Python 3.8+
- Docker Desktop 4.40+ (with Docker Model Runner enabled)
- macOS with Apple Silicon (recommended) or Linux/Windows with NVIDIA GPU

Docker Model Runner Commands:
- docker model pull <model>   - Download a model
- docker model run <model>    - Run a model interactively
- docker model list           - List available models
- docker model rm <model>     - Remove a model

Author: AI-Generated for Local LLM Development
License: MIT
"""

import sys

# Import from lib modules
from lib import config
from lib import docker
from lib import hardware
from lib import models
from lib import ui
from lib import vscode


def main() -> int:
    """Main entry point."""
    ui.clear_screen()
    
    ui.print_header("🚀 Docker Model Runner + Continue.dev Setup")
    ui.print_info("This script will help you set up a locally hosted LLM")
    ui.print_info("via Docker Model Runner and configure Continue.dev for VS Code.")
    print()
    
    if not ui.prompt_yes_no("Ready to begin setup?", default=True):
        ui.print_info("Setup cancelled. Run again when ready!")
        return 0
    
    # Install rich in background for better progress bars (non-blocking)
    models._install_rich_background()
    
    # Step 1: Hardware detection
    print()
    hw_info = hardware.detect_hardware()
    
    # Step 2: Check Docker
    print()
    docker_ok, docker_version = docker.check_docker()
    if not docker_ok:
        print()
        ui.print_error("Docker is required for this setup.")
        ui.print_info("Please install Docker Desktop from: https://docker.com/desktop")
        return 1
    
    hw_info.docker_version = docker_version
    
    # Step 3: Check Docker Model Runner
    print()
    dmr_ok = docker.check_docker_model_runner(hw_info)
    if not dmr_ok:
        print()
        ui.print_error("Docker Model Runner is required but not available.")
        return 1
    
    # Step 4: Model selection
    print()
    selected_models = models.select_models(hw_info)
    
    if not selected_models:
        ui.print_error("No models selected. Aborting setup.")
        return 1
    
    # Step 5: Confirm selection
    print()
    ui.print_subheader("Configuration Summary")
    total_ram = sum(m.ram_gb for m in selected_models)
    print(f"  Selected {len(selected_models)} model(s):")
    for model in selected_models:
        print(f"    • {model.name} (~{model.ram_gb}GB RAM)")
    print(f"  Total estimated RAM: ~{total_ram:.1f}GB")
    print()
    
    if not ui.prompt_yes_no("Proceed with this configuration?", default=True):
        ui.print_info("Setup cancelled. Run again to reconfigure.")
        return 0
    
    # Step 6: Pull models
    print()
    pulled_models = models.pull_models_docker(selected_models, hw_info)
    
    # Step 7: Generate config
    print()
    config_path = config.generate_continue_config(pulled_models, hw_info)
    
    # Step 8: Show next steps
    print()
    vscode.show_next_steps(config_path, pulled_models, hw_info)
    
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
