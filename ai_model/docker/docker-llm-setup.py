#!/usr/bin/env python3
"""
Docker Model Runner + Continue.dev Setup Script (v3.0)

Complete rewrite with AI fine-tuning capabilities:
- Hardware-aware tuning profile auto-detection
- Model parameter optimization
- Enhanced context management
- Comprehensive global rules

Optimized for Mac with Apple Silicon (M1/M2/M3/M4) using Docker Model Runner.

Requirements:
- Python 3.8+
- Docker Desktop 4.40+ (with Docker Model Runner enabled)
- macOS with Apple Silicon (recommended) or Linux/Windows with NVIDIA GPU

Author: AI-Generated for Local LLM Development
License: MIT
"""

from __future__ import annotations

import logging
import sys
from pathlib import Path

# Add docker directory to path
script_path = Path(__file__).resolve() if __file__ else Path(sys.argv[0]).resolve()
docker_dir = script_path.parent
docker_dir_str = str(docker_dir)
if docker_dir_str not in sys.path:
    sys.path.insert(0, docker_dir_str)

from lib import config
from lib import docker
from lib import hardware
from lib import ide
from lib import model_selector
from lib import tuning
from lib import ui
from lib import validator

# Configure VPN resilience at startup
docker.setup_vpn_resilient_environment()

_logger = logging.getLogger(__name__)


def main() -> int:
    """Main entry point."""
    try:
        ui.init_logging()
    except Exception:
        pass

    ui.clear_screen()
    
    ui.print_header("🚀 Docker Model Runner + Continue.dev Setup v3.0")
    ui.print_info("AI Fine-Tuning Edition")
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
    
    if not target_ide:
        target_ide = ["vscode"]
        ui.print_info("Defaulting to VS Code configuration")
    
    # Step 3: Check Docker
    print()
    docker_ok, docker_version = docker.check_docker()
    if not docker_ok:
        print()
        ui.print_error("Docker is required for this setup.")
        ui.print_info("Please install Docker Desktop from: https://docker.com/desktop")
        return 1
    
    hw_info.docker_version = docker_version
    
    # Step 4: Check Docker Model Runner
    print()
    dmr_ok = docker.check_docker_model_runner(hw_info)
    if not dmr_ok:
        print()
        ui.print_error("Docker Model Runner is required but not available.")
        return 1
    
    # Step 5: Validate Docker resource allocation
    print()
    resources_acceptable, should_continue = docker.validate_docker_resources(hw_info)
    if not should_continue:
        ui.print_info("Setup cancelled. Please adjust Docker Desktop settings and try again.")
        return 0
    
    # Step 6: Model selection (fixed: GPT-OSS 20B + nomic-embed-text)
    print()
    selected_models = model_selector.select_models(hw_info, installed_ides)
    
    if not selected_models:
        ui.print_error("No models selected. Aborting setup.")
        return 1
    
    # Step 7: Auto-detect tuning profile
    print()
    ui.print_subheader("AI Fine-Tuning Configuration")
    tier, tuning_profile, reason = tuning.auto_detect_tuning_profile(hw_info)
    ui.print_success(f"Selected {tier} tuning profile")
    ui.print_info(f"  {reason}")
    ui.print_info(f"  Temperature: {tuning_profile.temperature}, Context: {tuning_profile.context_length:,} tokens")
    print()
    
    # Step 8: Calculate optimal context size (model-aware)
    docker_ram_gib, _ = docker.detect_docker_allocated_ram_gib()
    if docker_ram_gib and selected_models:
        primary_model = selected_models[0]  # GPT-OSS 20B
        context_tokens, ctx_reason = docker.calculate_optimal_context_size(
            primary_model, docker_ram_gib, hw_info
        )
        
        # Check if Docker RAM is insufficient
        if "WARNING" in ctx_reason or "insufficient" in ctx_reason.lower():
            ui.print_warning("⚠️  Docker RAM allocation may be insufficient for the model")
            ui.print_warning(ctx_reason)
            print()
            ui.print_info("To fix this:")
            ui.print_info("  1. Open Docker Desktop")
            ui.print_info("  2. Go to Settings → Resources → Advanced")
            ui.print_info(f"  3. Increase Memory allocation to at least {primary_model.ram_gb + 2:.0f}GB")
            ui.print_info("  4. Click 'Apply & restart'")
            print()
            if not ui.prompt_yes_no("Continue with minimal context? (Model may fail to load)", default=False):
                ui.print_info("Setup cancelled. Please increase Docker memory allocation first.")
                return 0
        
        # Update tuning profile with calculated context
        tuning_profile.context_length = min(context_tokens, tuning_profile.context_length)
        hw_info.dmr_context_size_tokens = context_tokens
        hw_info.dmr_context_reason = ctx_reason
        ui.print_info(f"Optimized context: {context_tokens:,} tokens")
        if len(ctx_reason) > 100:
            ui.print_info(f"  {ctx_reason[:100]}...")
        else:
            ui.print_info(f"  {ctx_reason}")
    
    # Step 9: Pre-install validation
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
    
    # Step 10: Configuration summary
    print()
    ui.print_subheader("Configuration Summary")
    total_ram = sum(m.ram_gb for m in selected_models)
    
    print(f"  Models: {len(selected_models)}")
    for model in selected_models:
        roles_str = ", ".join(model.roles)
        print(f"    • {model.docker_name} (~{model.ram_gb:.1f}GB) - {roles_str}")
    print(f"  Total RAM: ~{total_ram:.1f}GB")
    print(f"  Tuning: {tier} profile (temp={tuning_profile.temperature}, context={tuning_profile.context_length:,})")
    print(f"  Target IDE(s): {', '.join(installed_ides) if installed_ides else 'VS Code'}")
    print()
    
    if not ui.prompt_yes_no("Proceed with this configuration?", default=True):
        ui.print_info("Setup cancelled. Run again to reconfigure.")
        return 0
    
    # Step 11: Pull models with verification
    print()
    setup_result = validator.pull_models_with_tracking(selected_models, hw_info)
    validator.display_setup_result(setup_result)
    
    if setup_result.complete_failure:
        ui.print_error("No models were installed. Please check your network connection.")
        return 1
    
    if setup_result.failed_models:
        action = validator.prompt_setup_action(setup_result)
        
        if action == "retry":
            setup_result = validator.retry_failed_models(setup_result, hw_info)
            validator.display_setup_result(setup_result)
        elif action == "exit":
            ui.print_info("Exiting. You can retry later with 'docker model pull <model>'")
            return 1
    
    models_for_config = setup_result.successful_models
    
    if not models_for_config:
        ui.print_error("No models available for configuration.")
        return 1
    
    # Step 12: Calculate context size for runtime configuration
    docker_ram_gib, _ = docker.detect_docker_allocated_ram_gib()
    if docker_ram_gib and models_for_config:
        primary_model = models_for_config[0]
        context_tokens, _ = docker.calculate_optimal_context_size(
            primary_model, docker_ram_gib, hw_info
        )
    else:
        context_tokens = tuning_profile.context_length
    
    # Step 13: Apply Docker Model Runner runtime settings
    print()
    try:
        docker.apply_dmr_runtime_settings(
            [m.docker_name for m in models_for_config],
            hw_info,
            context_tokens=context_tokens
        )
    except Exception as e:
        ui.print_warning(f"Could not apply Docker Model Runner runtime settings: {e}")
    
    # Step 14: Generate config with tuning profile
    print()
    config_path = config.generate_continue_config(
        models_for_config,
        hw_info,
        tuning_profile,
        target_ide
    )
    
    # Step 15: Generate global rules
    print()
    rule_path = config.generate_global_rule(tuning_profile)
    
    # Step 16: Generate codebase awareness rules
    print()
    try:
        codebase_rules_path = config.generate_codebase_rules()
        ui.print_info("Agent mode will use this file to understand your codebase")
    except Exception as e:
        ui.print_warning(f"Could not create codebase rules template: {e}")
    
    # Step 17: Generate .continueignore
    print()
    ignore_path = config.generate_continueignore()
    
    # Step 18: Save setup summary
    print()
    summary_path = config.save_setup_summary(models_for_config, hw_info, tuning_profile)
    
    # Step 19: Show next steps
    print()
    has_embedding = any("embed" in m.roles for m in models_for_config)
    ide.show_next_steps(config_path, models_for_config, hw_info, target_ide=target_ide, has_embedding=has_embedding)
    
    print()
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
