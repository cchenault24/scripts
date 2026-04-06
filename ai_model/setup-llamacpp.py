#!/usr/bin/env python3
"""
llama.cpp + OpenCode Setup Script (Modular Version)

Streamlined setup for Gemma 4 models via llama.cpp backend with OpenCode.
Uses refactored modules for security, maintainability, and testability.

NEW in v2.0 (Modular):
- Secure tool installation with PATH validation
- Cryptographic verification for downloads
- PR security verification with rollback
- Parallel installation option (llama.cpp + model)
- Comprehensive error handling and timeouts

Requirements:
- Python 3.8+
- macOS with Apple Silicon (M1/M2/M3/M4)
- 16GB+ RAM (24GB+ recommended)

Author: AI-Generated for Local LLM Development
License: MIT
"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path
from typing import Optional, Tuple

# Add project root to path
script_path = Path(__file__).resolve()
project_root = script_path.parent
if str(project_root) not in sys.path:
    sys.path.insert(0, str(project_root))

# Import refactored modules
from lib import hardware
from lib import llamacpp
from lib import model_catalog
from lib import opencode
from lib import opencode_builder
from lib import prerequisites
from lib import ui
from lib import utils

# Module logger
_logger = logging.getLogger(__name__)


def select_model_interactive(hw_info: hardware.HardwareInfo) -> Tuple[str, str, int]:
    """
    Interactive model selection based on hardware using unified catalog.

    Returns:
        Tuple of (model_key, hf_repo, context_size)
    """
    print()
    ui.print_subheader("Model Selection")
    print()

    # Get llama.cpp model catalog
    catalog = model_catalog.get_model_catalog(model_catalog.Backend.LLAMACPP)

    # Filter models by RAM
    suitable_models = model_catalog.filter_models_by_ram(catalog, hw_info.ram_gb)

    if not suitable_models:
        ui.print_error(f"Insufficient RAM ({hw_info.ram_gb:.0f}GB) for any Gemma 4 model")
        raise SystemExit("Hardware requirements not met: Minimum 4GB RAM required")

    # Get recommended model
    recommended_model = model_catalog.get_recommended_model(
        model_catalog.Backend.LLAMACPP,
        hw_info
    )

    # Display hardware info
    print(f"Detected: {hw_info.apple_chip_model or hw_info.cpu_brand}, {hw_info.ram_gb:.0f}GB RAM")
    print()
    print("Available models:")
    print()

    # Display model options
    for i, (key, model) in enumerate(suitable_models.items(), 1):
        is_recommended = (recommended_model and model == recommended_model)
        marker = ui.colorize(" ★ RECOMMENDED", ui.Colors.GREEN) if is_recommended else ""

        print(f"  {i}. {ui.colorize(model.name, ui.Colors.CYAN)}{marker}")
        print(f"     RAM: ~{model.ram_gb}GB")
        print(f"     {model.description}")
        print()

    # Prompt for selection
    model_keys = list(suitable_models.keys())
    default_idx = model_keys.index(
        next((k for k, v in suitable_models.items() if v == recommended_model), model_keys[0])
    ) + 1 if recommended_model else 1

    while True:
        try:
            choice = input(f"Select model (1-{len(suitable_models)}) [{default_idx}]: ").strip() or str(default_idx)
            choice_num = int(choice)

            if 1 <= choice_num <= len(suitable_models):
                model_key = model_keys[choice_num - 1]
                selected_model = suitable_models[model_key]
                break

            print(ui.colorize(f"Please enter 1-{len(suitable_models)}", ui.Colors.RED))
        except ValueError:
            print(ui.colorize("Please enter a valid number", ui.Colors.RED))
        except KeyboardInterrupt:
            print()
            raise SystemExit("Setup cancelled")

    # Select context size (if multiple options available)
    if len(selected_model.contexts) > 1:
        print()
        print("Context window options:")
        for i, ctx_opt in enumerate(selected_model.contexts, 1):
            print(f"  {i}. {ctx_opt.description}")

        default_ctx = 1
        while True:
            try:
                choice = input(f"Select context (1-{len(selected_model.contexts)}) [{default_ctx}]: ").strip() or str(default_ctx)
                choice_num = int(choice)

                if 1 <= choice_num <= len(selected_model.contexts):
                    context_option = selected_model.contexts[choice_num - 1]
                    context_size = context_option.size
                    break

                print(ui.colorize(f"Please enter 1-{len(selected_model.contexts)}", ui.Colors.RED))
            except ValueError:
                print(ui.colorize("Please enter a valid number", ui.Colors.RED))
            except KeyboardInterrupt:
                print()
                raise SystemExit("Setup cancelled")
    else:
        # Use default context
        context_option = selected_model.get_default_context()
        context_size = context_option.size

    print()
    ui.print_success(f"Selected: {selected_model.name} with {context_size} context")

    return model_key, selected_model.get_identifier(), context_size


def main(argv: Optional[list] = None) -> int:
    """Main entry point."""
    # Parse arguments
    parser = argparse.ArgumentParser(
        description="llama.cpp + OpenCode Setup (Modular)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--force-reinstall", action="store_true",
                       help="Force reinstall even if already installed")
    parser.add_argument("--no-pr-build", action="store_true",
                       help="Skip custom OpenCode PR build")
    parser.add_argument("--skip-verification", action="store_true",
                       help="Skip security verification (NOT RECOMMENDED)")
    parser.add_argument("--parallel", action="store_true",
                       help="Install llama.cpp and model in parallel (faster, needs 24GB+ RAM)")

    args = parser.parse_args(argv)

    ui.clear_screen()
    ui.print_header("🚀 llama.cpp + OpenCode Setup v2.0 (Modular)")
    ui.print_info("Gemma 4 with tool calling support via llama.cpp")
    print()

    if not ui.prompt_yes_no("Ready to begin setup?", default=True):
        ui.print_info("Setup cancelled")
        return 0

    # Step 1: Hardware detection
    print()
    hw_info = hardware.detect_hardware()

    # Validate minimum requirements
    if hw_info.ram_gb < 16:
        ui.print_error("Insufficient RAM for llama.cpp setup")
        print(f"  Detected: {hw_info.ram_gb:.1f}GB")
        print(f"  Minimum: 16GB")
        return 1

    # Step 2: Install prerequisites
    print()
    ui.print_header("📦 Installing Prerequisites")
    print()

    success, msg = prerequisites.install_all_prerequisites(force_reinstall=args.force_reinstall)
    if not success:
        ui.print_error(msg)
        return 1

    ui.print_success(msg)

    # Step 3: Model selection
    model_key, hf_repo, context_size = select_model_interactive(hw_info)

    # Step 4: Check disk space
    print()
    model_size_estimate = MODELS[model_key]["ram_gb"] * 1.2  # Rough estimate
    success, msg = llamacpp.check_disk_space(model_size_estimate + 5)  # +5GB buffer
    if not success:
        ui.print_error(msg)
        return 1
    ui.print_success(msg)

    # Step 5: Install llama.cpp and download model
    print()
    ui.print_header("📥 Installing llama.cpp and Model")
    print()

    if args.parallel and hw_info.ram_gb >= 24:
        ui.print_info("Using parallel installation (llama.cpp + model simultaneously)")
        print()

        import concurrent.futures
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            future_llama = executor.submit(
                llamacpp.install_llama_cpp_homebrew,
                force=args.force_reinstall,
                use_head=True
            )
            future_model = executor.submit(
                llamacpp.download_model_from_hf,
                hf_repo,
                force=args.force_reinstall
            )

            llama_success, llama_msg = future_llama.result()
            model_success, model_msg = future_model.result()
    else:
        # Sequential installation
        if args.parallel:
            ui.print_warning("Parallel mode requires 24GB+ RAM, using sequential installation")
            print()

        llama_success, llama_msg = llamacpp.install_llama_cpp_homebrew(
            force=args.force_reinstall,
            use_head=True
        )

        if llama_success:
            ui.print_success(llama_msg)
            print()

        model_success, model_msg = llamacpp.download_model_from_hf(
            hf_repo,
            force=args.force_reinstall
        )

    if not llama_success:
        ui.print_error(llama_msg)
        return 1

    if not model_success:
        ui.print_error(model_msg)
        print()
        ui.print_warning("Model download failed, but you can download manually later")
        if not ui.prompt_yes_no("Continue with setup anyway?", default=True):
            return 1
    else:
        ui.print_success(model_msg)

    # Step 6: Install OpenCode
    print()
    ui.print_header("📦 Installing OpenCode")
    print()

    success, msg = opencode_builder.install_opencode_official(force=args.force_reinstall)
    if not success:
        ui.print_error(msg)
        return 1
    ui.print_success(msg)

    # Step 7: Build custom OpenCode (optional)
    if not args.no_pr_build:
        print()
        ui.print_header("🔧 Building Custom OpenCode")
        print()

        success, msg = opencode_builder.build_opencode_with_pr(
            pr_number=16531,
            force=args.force_reinstall,
            skip_verification=args.skip_verification
        )

        if not success:
            ui.print_error(msg)
            print()
            ui.print_warning("Custom build failed, but official OpenCode is installed")
            if not ui.prompt_yes_no("Continue with official version?", default=True):
                return 1
        else:
            ui.print_success(msg)

    # Step 8: Generate configurations
    print()
    ui.print_header("⚙️ Generating Configurations")
    print()

    model_name = MODELS[model_key]["name"]
    success, msg = opencode.generate_opencode_config_llamacpp(
        model_name,
        context_size,
        hw_info,
        force=args.force_reinstall
    )
    if success:
        ui.print_success(msg)

    success, msg = opencode.generate_agents_md(force=args.force_reinstall)
    if success:
        ui.print_success(msg)

    success, msg = opencode.generate_build_prompt(force=args.force_reinstall)
    if success:
        ui.print_success(msg)

    # Step 9: Display usage instructions
    print()
    ui.print_header("✅ Setup Complete!")
    print()
    print("🎯 Ready to code with AI assistance!")
    print()
    print("Next steps:")
    print()
    print(ui.colorize("1. Start llama-server:", ui.Colors.CYAN + ui.Colors.BOLD))
    llama_server = "llama-server"
    print(f"   {ui.colorize(f'{llama_server} -hf {hf_repo} --port 3456 -ngl 99 -c {context_size} --jinja', ui.Colors.GREEN)}")
    print()
    print("   Wait for: \"listening on http://127.0.0.1:3456\"")
    print()
    print(ui.colorize("2. Test the server:", ui.Colors.CYAN + ui.Colors.BOLD))
    print(f"   {ui.colorize('curl http://127.0.0.1:3456/health', ui.Colors.GREEN)}")
    print()
    print(ui.colorize("3. Run OpenCode:", ui.Colors.CYAN + ui.Colors.BOLD))
    print(f"   {ui.colorize('cd /path/to/your/project', ui.Colors.GREEN)}")
    print(f"   {ui.colorize('opencode', ui.Colors.GREEN)}  # Opens interactive TUI")
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
