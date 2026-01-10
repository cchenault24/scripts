#!/usr/bin/env python3
"""
Ollama + Continue.dev Smart Uninstaller (v2.0)

An interactive Python script that helps you uninstall components set up by
ollama-llm-setup.py, including:
- Ollama models (only ones we installed, keeping pre-existing)
- Continue.dev configuration files (with customization detection)
- VS Code Continue.dev extension (optional, asks first)
- IntelliJ IDEA Continue plugin (optional, asks first)

NEW in v2.0:
- Manifest-based tracking of installed components
- Smart detection of user customizations
- Automatic cleanup of cache/temp files
- Keeps pre-existing models
- Detects running processes

Author: AI-Generated for Local LLM Development
License: MIT
"""

from __future__ import annotations

import json
import logging
import os
import shutil
import sys
import warnings
from pathlib import Path
from typing import Any, List

# Add ollama directory to path so we can import lib modules
script_path = Path(__file__).resolve() if __file__ else Path(sys.argv[0]).resolve()
ollama_dir = script_path.parent

ollama_dir_str = str(ollama_dir)
if ollama_dir_str not in sys.path:
    sys.path.insert(0, ollama_dir_str)

from lib import ui
from lib import config
from lib import uninstaller
from lib import ollama

# Module logger
_logger = logging.getLogger(__name__)


def load_manifest() -> dict[str, Any] | None:
    """
    Load installation manifest if it exists.
    
    Returns:
        Manifest dict, or {"_unreadable_manifest": True} if corrupt,
        or None if missing.
    """
    manifest_path = Path.home() / ".continue" / "setup-manifest.json"
    
    if not manifest_path.exists():
        return None
    
    try:
        with open(manifest_path, 'r') as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        # Manifest exists but is corrupt
        _logger.warning(f"Manifest file is corrupt: {manifest_path}: {e}")
        warnings.warn(f"Installation manifest is unreadable: {e}", UserWarning)
        return {"_unreadable_manifest": True}
    except (OSError, IOError, PermissionError) as e:
        # File access issues
        _logger.warning(f"Failed to read manifest: {manifest_path}: {e}")
        return None


def main() -> int:
    """Main uninstaller entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Uninstall Ollama + Continue.dev setup",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--skip-ollama-checks",
        action="store_true",
        help="Skip Ollama checks (useful if Ollama is hanging)"
    )
    parser.add_argument(
        "--skip-models",
        action="store_true",
        help="Skip Ollama model removal"
    )
    parser.add_argument(
        "--skip-config",
        action="store_true",
        help="Skip config file removal"
    )
    parser.add_argument(
        "--skip-extension",
        action="store_true",
        help="Skip both VS Code extension and IntelliJ plugin removal"
    )
    parser.add_argument(
        "--skip-vscode",
        action="store_true",
        help="Skip VS Code extension removal only"
    )
    parser.add_argument(
        "--skip-intellij",
        action="store_true",
        help="Skip IntelliJ plugin removal only"
    )
    
    args = parser.parse_args()
    
    ui.clear_screen()
    
    ui.print_header("🗑️  Ollama + Continue.dev Uninstaller v2.0")
    ui.print_info("This will remove components installed by ollama-llm-setup.py")
    print()
    
    # Step 1: Load manifest
    manifest = load_manifest()
    
    if manifest and manifest.get("_unreadable_manifest"):
        ui.print_warning("Installation manifest is corrupt or unreadable")
        ui.print_info("Will use fingerprint-based detection")
        manifest = uninstaller.create_empty_manifest()
    elif manifest:
        ui.print_success("Found installation manifest")
        ui.print_info(f"Installed on: {manifest.get('timestamp', 'unknown')}")
        ui.print_info(f"Installer version: {manifest.get('installer_version', 'unknown')}")
    else:
        ui.print_warning("No installation manifest found")
        ui.print_info("Will use fingerprint-based detection")
        manifest = uninstaller.create_empty_manifest()
    
    print()
    
    if not ui.prompt_yes_no("Ready to begin uninstallation?", default=True):
        ui.print_info("Uninstallation cancelled")
        return 0
    
    # Step 2: Check running processes
    print()
    ui.print_subheader("Checking Running Processes")
    running = uninstaller.check_running_processes(manifest)
    if not uninstaller.handle_running_processes(running):
        return 0
    
    # Step 3: Scan for orphaned files
    print()
    ui.print_subheader("Scanning for Installed Components")
    
    orphaned_files = uninstaller.scan_for_orphaned_files(manifest)
    if orphaned_files:
        certain = [f for f, s in orphaned_files if s == "certain"]
        uncertain = [f for f, s in orphaned_files if s == "uncertain"]
        if certain:
            ui.print_info(f"Found {len(certain)} files created by installer")
        if uncertain:
            ui.print_info(f"Found {len(uncertain)} files that might be ours")
    else:
        ui.print_success("No orphaned files found")
    
    # Step 4: Remove models (ask first)
    models_removed = 0
    if args.skip_models:
        print()
        ui.print_subheader("Ollama Models")
        ui.print_warning("Skipping Ollama model removal (--skip-models flag used)")
    else:
        installed_models = manifest.get("installed", {}).get("models", [])
        pre_existing = manifest.get("pre_existing", {}).get("models", [])
        
        if installed_models:
            print()
            ui.print_subheader("Ollama Models")
            
            ui.print_info(f"Found {len(installed_models)} model(s) installed by setup:")
            for model in installed_models:
                name = model.get("name", "unknown")
                size = model.get("size_gb", 0)
                print(f"  • {name} (~{size:.1f}GB)")
            print()
            
            if pre_existing:
                ui.print_info("Models you had before setup (will be kept):")
                for model in pre_existing:
                    print(f"  • {model}")
                print()
            
            choice = ui.prompt_choice(
                "What would you like to do with installed models?",
                ["Remove all installed models", "Select models to remove", "Keep all models"],
                default=2
            )
            
            if choice == 0:  # Remove all
                model_names = [m.get("name") for m in installed_models if m.get("name")]
                if model_names and ui.prompt_yes_no(f"Remove {len(model_names)} installed models?", default=False):
                    print()
                    models_removed = uninstaller.remove_models(model_names)
            
            elif choice == 1:  # Select
                model_names = [m.get("name") for m in installed_models if m.get("name")]
                if model_names:
                    indices = ui.prompt_multi_choice(
                        "Select models to remove:",
                        model_names,
                        min_selections=0
                    )
                    if indices:
                        selected = [model_names[i] for i in indices]
                        print()
                        models_removed = uninstaller.remove_models(selected)
            else:  # Keep all
                ui.print_info("Keeping all Ollama models")
        else:
            # No manifest models - check current models
            print()
            ui.print_subheader("Ollama Models")
            current_models = uninstaller.get_installed_models()
            
            if current_models:
                ui.print_info(f"Found {len(current_models)} installed model(s):")
                for model in current_models:
                    print(f"  • {model}")
                print()
                
                choice = ui.prompt_choice(
                    "What would you like to do with Ollama models?",
                    ["Remove all models", "Select models to remove", "Keep all models"],
                    default=2
                )
                
                if choice == 0:  # Remove all
                    if ui.prompt_yes_no(f"Remove all {len(current_models)} models?", default=False):
                        print()
                        models_removed = uninstaller.remove_models(current_models)
                elif choice == 1:  # Select
                    indices = ui.prompt_multi_choice(
                        "Select models to remove:",
                        current_models,
                        min_selections=0
                    )
                    if indices:
                        selected = [current_models[i] for i in indices]
                        print()
                        models_removed = uninstaller.remove_models(selected)
            else:
                ui.print_info("No Ollama models found")
    
    # Step 5: Remove config files (detect customization)
    config_removed = 0
    if args.skip_config:
        print()
        ui.print_subheader("Configuration Files")
        ui.print_warning("Skipping config file removal (--skip-config flag used)")
    else:
        print()
        ui.print_subheader("Configuration Files")
        
        config_files = [
            Path.home() / ".continue" / "config.yaml",
            Path.home() / ".continue" / "config.json",
            Path.home() / ".continue" / "rules" / "global-rule.md",
            Path.home() / ".continue" / ".continueignore"
        ]
        
        for config_path in config_files:
            if config_path.exists():
                if uninstaller.handle_config_removal(config_path, manifest):
                    config_removed += 1
        
        if config_removed == 0:
            ui.print_info("No config files were removed")
    
    # Step 6: Auto-remove cache, temp files, backups
    print()
    ui.print_subheader("Cleaning Up Temporary Files")
    
    auto_remove_paths: List[Path] = []
    
    # Cache directory
    cache_dir = Path.home() / ".continue" / "cache"
    if cache_dir.exists():
        auto_remove_paths.append(cache_dir)
    
    # Setup summary
    summary_path = Path.home() / ".continue" / "setup-summary.json"
    if summary_path.exists():
        auto_remove_paths.append(summary_path)
    
    # Timestamped backup files (but keep original backups)
    continue_dir = Path.home() / ".continue"
    if continue_dir.exists():
        for backup_file in continue_dir.glob("*.backup_*"):
            auto_remove_paths.append(backup_file)
        for backup_file in continue_dir.glob("*.pre-uninstall-*"):
            auto_remove_paths.append(backup_file)
    
    # Orphaned files (certain ones only)
    for filepath, status in orphaned_files:
        if status == "certain":
            auto_remove_paths.append(filepath)
    
    temp_removed = 0
    for path in auto_remove_paths:
        try:
            if path.exists():
                if path.is_dir():
                    shutil.rmtree(path)
                else:
                    path.unlink()
                temp_removed += 1
                ui.print_success(f"Removed: {path.name}")
        except (OSError, IOError, PermissionError, shutil.Error) as e:
            ui.print_warning(f"Could not remove {path.name}: {e}")
    
    if temp_removed == 0:
        ui.print_info("No temporary files found to remove")
    
    # Step 7: Remove IDE extensions (ask first)
    ide_removed = {"vscode": False, "intellij": False}
    
    if args.skip_extension:
        print()
        ui.print_subheader("IDE Extensions")
        ui.print_warning("Skipping IDE extension removal (--skip-extension flag used)")
    else:
        skip_vscode = args.skip_vscode
        skip_intellij = args.skip_intellij
        
        print()
        ui.print_subheader("IDE Extensions")
        
        if not skip_vscode:
            if uninstaller.check_vscode_extension_installed():
                ui.print_info("VS Code Continue.dev extension is installed")
                ui.print_info("(Extension can be used with other LLM providers like Claude API)")
                print()
                
                if ui.prompt_yes_no("Remove Continue.dev extension from VS Code?", default=False):
                    ide_removed["vscode"] = uninstaller.uninstall_vscode_extension()
                else:
                    ui.print_info("Keeping VS Code extension")
            else:
                ui.print_info("VS Code Continue.dev extension not installed")
        else:
            ui.print_warning("Skipping VS Code extension (--skip-vscode flag used)")
        
        print()
        
        if not skip_intellij:
            is_installed, _ = uninstaller.check_intellij_plugin_installed()
            if is_installed:
                ui.print_info("IntelliJ Continue plugin is installed")
                ui.print_info("(Plugin can be used with other LLM providers)")
                print()
                
                if ui.prompt_yes_no("Remove Continue plugin from IntelliJ IDEA?", default=False):
                    ide_removed["intellij"] = uninstaller.uninstall_intellij_plugin()
                else:
                    ui.print_info("Keeping IntelliJ plugin")
            else:
                ui.print_info("IntelliJ Continue plugin not installed")
        else:
            ui.print_warning("Skipping IntelliJ plugin (--skip-intellij flag used)")
    
    # Step 8: Remove auto-start configuration (macOS only)
    import platform
    autostart_removed = False
    
    if platform.system() == "Darwin":
        print()
        ui.print_subheader("Auto-Start Configuration")
        
        is_configured, details = ollama.check_ollama_autostart_status_macos()
        
        if is_configured:
            ui.print_info(f"Ollama is configured to auto-start: {details}")
            print()
            
            if ui.prompt_yes_no("Remove auto-start configuration?", default=True):
                print()
                if ollama.remove_ollama_autostart_macos():
                    autostart_removed = True
                else:
                    ui.print_warning("Could not remove auto-start configuration")
                    ui.print_info("You may need to remove it manually:")
                    ui.print_info("  rm ~/Library/LaunchAgents/com.ollama.server.plist")
                    ui.print_info("  launchctl remove com.ollama.server")
            else:
                ui.print_info("Keeping auto-start configuration")
        else:
            ui.print_info("No auto-start configuration found")
    
    # Step 8b: Remove Ollama application (optional)
    ollama_removed = False
    print()
    ui.print_subheader("Ollama Application")
    
    # Check if Ollama is installed
    ollama_ok, ollama_version = ollama.check_ollama()
    
    if ollama_ok:
        ui.print_info(f"Ollama is installed (version: {ollama_version})")
        ui.print_warning("This will remove Ollama completely from your system")
        ui.print_warning("This includes:")
        ui.print_info("  • Ollama application")
        ui.print_info("  • Ollama CLI binary")
        ui.print_info("  • All Ollama data and models (~/.ollama)")
        ui.print_info("  • Application caches and support files")
        print()
        
        if ui.prompt_yes_no("Remove Ollama application completely?", default=False):
            print()
            success, errors = ollama.remove_ollama()
            
            if success:
                ollama_removed = True
                ui.print_success("Ollama has been removed from your system")
            else:
                ui.print_warning("Ollama removal completed with some errors")
                if errors:
                    ui.print_info("Items that couldn't be removed:")
                    for error in errors:
                        ui.print_info(f"  • {error}")
                    print()
                    ui.print_info("You may need to remove these manually or use sudo")
        else:
            ui.print_info("Keeping Ollama installation")
    else:
        ui.print_info("Ollama is not installed or not found")
    
    # Step 9: Remove manifest itself
    manifest_path = Path.home() / ".continue" / "setup-manifest.json"
    if manifest_path.exists():
        try:
            manifest_path.unlink()
            ui.print_success("Removed installation manifest")
        except (OSError, IOError, PermissionError) as e:
            ui.print_warning(f"Could not remove manifest: {e}")
    
    # Step 10: Summary
    print()
    uninstaller.show_uninstall_summary(
        models_removed=models_removed,
        config_removed=config_removed,
        temp_removed=temp_removed,
        vscode_removed=ide_removed.get("vscode", False),
        intellij_removed=ide_removed.get("intellij", False),
        autostart_removed=autostart_removed,
        ollama_removed=ollama_removed
    )
    
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print()
        ui.print_warning("Uninstallation interrupted by user.")
        sys.exit(130)
    except Exception as e:
        ui.print_error(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
