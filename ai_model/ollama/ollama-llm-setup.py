#!/usr/bin/env python3
"""
Ollama + Continue.dev Setup Script (v2.0)

An interactive Python script that helps you set up a locally hosted LLM
via Ollama and generates a continue.dev config.yaml for VS Code.

NEW in v2.0:
- Fixed model selection (GPT-OSS 20B + embedding model)
- Reliable model pulling with verification
- Auto-detection of installed IDEs
- Installation manifest for smart uninstallation

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

from __future__ import annotations

import logging
import subprocess
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
from lib import openwebui

# =============================================================================
# VPN Resilience: Configure environment at startup
# =============================================================================
# VPNs (especially corporate VPNs) can break localhost connections by modifying
# DNS resolution and routing tables. Using 127.0.0.1 instead of localhost and
# setting NO_PROXY ensures the model server remains accessible.
ollama.setup_vpn_resilient_environment()

# Module logger
_logger = logging.getLogger(__name__)


def get_pre_existing_models() -> list[str]:
    """Get list of models that exist before we start pulling."""
    try:
        return validator.get_installed_models()
    except (OSError, IOError, subprocess.SubprocessError) as e:
        # Ollama not available or command failed
        _logger.warning(f"Failed to detect pre-existing models: {type(e).__name__}: {e}")
        return []


def main() -> int:
    """Main entry point."""
    ui.clear_screen()
    
    ui.print_header("🚀 Ollama + Continue.dev Setup v2.0")
    ui.print_info("Installing GPT-OSS 20B + embedding model")
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
    
    # Step 4b: Record pre-existing models for manifest
    pre_existing_models = get_pre_existing_models()
    hw_info.ollama_available = True  # Mark that Ollama is available
    
    # Step 5: Model selection
    print()
    selected_models = model_selector.select_models(hw_info, installed_ides)
    
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
    # RAM calculation removed - installing fixed models
    
    print(f"  Selected {len(selected_models)} model(s):")
    for model in selected_models:
        roles_str = ", ".join(model.roles)
        print(f"    • {model.ollama_name} (~{model.ram_gb:.1f}GB RAM) - {roles_str}")
    print(f"  Total model RAM: ~{total_ram:.1f}GB")
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
    
    # Track created files for manifest (using set to avoid duplicates)
    created_files_set: set[Path] = set()
    
    # Step 9: Generate config
    print()
    config_path = config.generate_continue_config(models_for_config, hw_info, target_ide=target_ide)
    if config_path:
        created_files_set.add(config_path)
        # Also track JSON if both were created (avoid duplicates)
        json_path = config_path.with_suffix('.json')
        if json_path.exists() and json_path != config_path:
            created_files_set.add(json_path)
    
    # Step 10: Generate global-rule.md
    print()
    rule_path = config.generate_global_rule()
    if rule_path:
        created_files_set.add(rule_path)
    
    # Step 10b: Generate codebase awareness rules for Agent mode
    print()
    try:
        codebase_rules_path = config.generate_codebase_rules()
        if codebase_rules_path:
            created_files_set.add(codebase_rules_path)
        ui.print_info("Agent mode will use this file to understand your codebase")
    except Exception as e:
        ui.print_warning(f"Could not create codebase rules template: {e}")
        ui.print_warning("You can manually create ~/.continue/rules/codebase-context.md later")
    
    # Step 11: Generate .continueignore
    print()
    ignore_path = config.generate_continueignore()
    if ignore_path:
        created_files_set.add(ignore_path)
    
    # Step 12: Save setup summary
    print()
    summary_path = config.save_setup_summary(models_for_config, hw_info)
    if summary_path:
        created_files_set.add(summary_path)
    
    # Track OpenWebUI info for manifest (will be populated later if user chooses to install)
    openwebui_manifest_info = None
    
    # Step 13: Create installation manifest for uninstaller
    # Note: This will be updated at the end if OpenWebUI is installed
    print()
    ui.print_subheader("Creating Installation Manifest")
    # Convert set to list for manifest creation
    created_files = list(created_files_set)
    
    def update_manifest_with_openwebui():
        """Helper to update manifest with OpenWebUI info."""
        config.create_installation_manifest(
            installed_models=models_for_config,
            created_files=created_files,
            hw_info=hw_info,
            target_ide=target_ide,
            pre_existing_models=pre_existing_models,
            openwebui_info=openwebui_manifest_info
        )
    
    config.create_installation_manifest(
        installed_models=models_for_config,
        created_files=created_files,
        hw_info=hw_info,
        target_ide=target_ide,
        pre_existing_models=pre_existing_models
    )
    
    # Step 14: Show next steps
    print()
    # Check if we have an embedding model for the codebase awareness info
    has_embedding = any("embed" in m.roles for m in models_for_config)
    ide.show_next_steps(config_path, models_for_config, hw_info, target_ide=target_ide, has_embedding=has_embedding)
    
    # Step 15: Configure auto-start (macOS only)
    import platform
    if platform.system() == "Darwin":
        print()
        ui.print_subheader("Auto-Start Configuration")
        
        is_configured, details = ollama.check_ollama_autostart_status_macos()
        
        if is_configured:
            ui.print_success("Ollama is already configured to auto-start")
            ui.print_info(f"Method: {details}")
            
            # Verify it's actually running
            if ollama.verify_ollama_running():
                ui.print_success("Ollama service is currently running")
            else:
                ui.print_warning("Ollama is configured but not currently running")
                ui.print_info("It will start automatically on next boot")
                
                if ui.prompt_yes_no("Would you like to start Ollama now?", default=True):
                    if ollama.start_ollama_service():
                        ui.print_success("Ollama service started")
                    else:
                        ui.print_warning("Could not start Ollama automatically")
                        ui.print_info("Run 'ollama serve' manually or restart your Mac")
        else:
            ui.print_info("Ollama is not configured to start automatically on boot")
            ui.print_info("Without auto-start, you'll need to manually run 'ollama serve' after each reboot")
            print()
            
            if ui.prompt_yes_no("Would you like to set up Ollama to start automatically?", default=True):
                print()
                ui.print_info("Setting up Ollama auto-start using launchd...")
                ui.print_info("This will create a Launch Agent that starts Ollama when you log in")
                print()
                
                if ollama.setup_ollama_autostart_macos():
                    print()
                    ui.print_success("✅ Ollama will now start automatically when you boot your Mac")
                    ui.print_info("No manual 'ollama serve' needed after restart")
                    
                    # Track the plist file in manifest
                    plist_path = ollama.get_autostart_plist_path()
                    if plist_path and plist_path.exists():
                        created_files_set.add(plist_path)
                else:
                    print()
                    ui.print_warning("Could not set up auto-start")
                    ui.print_info("You can manually start Ollama with: ollama serve")
                    ui.print_info("Or set it up later with: brew services start ollama")
            else:
                print()
                ui.print_info("Skipping auto-start setup")
                ui.print_info("Remember to run 'ollama serve' after each reboot")
                ui.print_info("Or set it up later with: brew services start ollama")
        
        # Step 16: Configure shell profile for VPN resilience
        print()
        ui.print_subheader("VPN Resilience Configuration")
        ui.print_info("Corporate VPNs can break localhost connections by modifying DNS/routing")
        ui.print_info("Adding environment variables to ~/.zshrc for permanent VPN resilience")
        print()
        
        if ui.prompt_yes_no("Configure shell profile for VPN resilience?", default=True):
            if ollama.update_shell_profile_for_vpn():
                ui.print_success("VPN resilience configured successfully")
            else:
                ui.print_warning("Could not update shell profile automatically")
        else:
            ui.print_info("Skipping shell profile update")
            ui.print_info("You can manually add these to your ~/.zshrc if needed:")
            ui.print_info('  export OLLAMA_HOST="127.0.0.1:11434"')
            ui.print_info('  export NO_PROXY="localhost,127.0.0.1,::1"')
    
    # Step 17: Open WebUI Setup (optional)
    print()
    ui.print_subheader("Open WebUI Setup (Optional)")
    ui.print_info("Open WebUI provides a ChatGPT-like web interface for your local LLM")
    ui.print_info("Features:")
    print("  • 💬 Beautiful chat interface in your browser")
    print("  • 📁 File upload and document analysis")
    print("  • 🔍 RAG: Index documents for Q&A (uses your embedding model)")
    print("  • 💾 Conversation history")
    print("  • 🔒 100% local - no data leaves your machine")
    print()
    ui.print_info("Requirements: Docker Desktop (will help you install if needed)")
    print()
    
    openwebui_installed = False
    openwebui_url = None
    
    if ui.prompt_yes_no("Would you like to set up Open WebUI?", default=True):
        print()
        success, url = openwebui.setup_openwebui(hw_info)
        openwebui_installed = success
        openwebui_url = url
        
        if success and url:
            # Track in manifest
            openwebui_manifest_info = openwebui.get_openwebui_manifest_entry()
            
            # Update the manifest with OpenWebUI info
            update_manifest_with_openwebui()
            
            # Show next steps
            openwebui.show_openwebui_next_steps(url, models_for_config[0].ollama_name if models_for_config else "gpt-oss:20b")
    else:
        print()
        ui.print_info("Skipping Open WebUI setup")
        ui.print_info("You can set it up later by running this script again")
        ui.print_info("Or install manually: https://docs.openwebui.com/getting-started/")
    
    # Final summary
    print()
    ui.print_header("🎉 Setup Complete!")
    print()
    ui.print_success("Your local AI development environment is ready!")
    print()
    print("  📝 Continue.dev: IDE integration for coding assistance")
    if openwebui_installed and openwebui_url:
        print(f"  🌐 Open WebUI: {openwebui_url}")
    print(f"  🤖 Model: {models_for_config[0].ollama_name if models_for_config else 'gpt-oss:20b'}")
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
