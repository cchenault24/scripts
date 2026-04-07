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
import platform
import shutil
import subprocess
import sys
import time
import warnings
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

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
from lib import utils
from lib import openwebui

# Module logger
_logger = logging.getLogger(__name__)


@dataclass
class SystemInfo:
    """Collected system information."""
    manifest: Dict[str, Any]
    ollama_installed: bool
    ollama_version: str
    ollama_running: bool
    install_method: str  # 'homebrew', 'manual', 'unknown'
    installed_models: List[str]  # From manifest, filtered
    pre_existing_models: List[str]
    actual_installed_models: List[str]  # From ollama list
    config_files: List[Path]
    customized_configs: List[Path]
    autostart_configured: bool
    autostart_details: str
    orphaned_files: List[tuple[Path, str]]
    vscode_extension: bool
    intellij_plugin: bool
    ollama_installed_by_script: bool  # True if we installed it during uninstall
    openwebui_status: Dict[str, Any]  # Open WebUI container status


@dataclass
class UninstallChoices:
    """User choices for what to uninstall."""
    models_to_remove: List[str]
    remove_configs: bool
    stop_service: bool
    remove_autostart: bool
    uninstall_ollama: bool
    remove_vscode: bool
    remove_intellij: bool
    remove_openwebui: bool
    remove_openwebui_data: bool
    remove_openwebui_image: bool


@dataclass
class UninstallResults:
    """Actual results of uninstallation."""
    models_removed: int
    configs_removed: int
    service_stopped: bool
    autostart_removed: bool
    ollama_uninstalled: bool
    vscode_removed: bool
    intellij_removed: bool
    temp_files_removed: int
    errors: List[str]
    openwebui_container_removed: bool
    openwebui_data_removed: bool
    openwebui_image_removed: bool


def load_manifest() -> dict[str, Any] | None:
    """Load installation manifest if it exists."""
    manifest_path = Path.home() / ".continue" / "setup-manifest.json"
    
    if not manifest_path.exists():
        return None
    
    try:
        with open(manifest_path, 'r') as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        _logger.warning(f"Manifest file is corrupt: {manifest_path}: {e}")
        warnings.warn(f"Installation manifest is unreadable: {e}", UserWarning)
        return {"_unreadable_manifest": True}
    except (OSError, IOError, PermissionError) as e:
        _logger.warning(f"Failed to read manifest: {manifest_path}: {e}")
        return None


def detect_install_method() -> str:
    """Detect how Ollama was installed."""
    if platform.system() == "Darwin":
        # Check if installed via Homebrew
        code, _, _ = utils.run_command(
            ["brew", "list", "ollama"], timeout=5, clean_env=True
        )
        if code == 0:
            return "homebrew"
    
    # Check if ollama binary exists
    if shutil.which("ollama"):
        return "manual"
    
    return "unknown"


def gather_system_info(args: Any) -> SystemInfo:
    """
    Phase 1: Gather all system information silently.
    
    Returns:
        SystemInfo with all collected data
    """
    # Load manifest
    manifest = load_manifest()
    if manifest and manifest.get("_unreadable_manifest"):
        manifest = uninstaller.create_empty_manifest()
    elif not manifest:
        manifest = uninstaller.create_empty_manifest()
    
    # Check if Ollama is installed (simple check without prompting)
    ollama_path = shutil.which("ollama")
    ollama_installed_by_script = False
    
    if not ollama_path:
        # Ollama not found - automatically install via Homebrew if available (silently)
        if platform.system() == "Darwin" and shutil.which("brew"):
            # Install silently via Homebrew
            code, _, stderr = utils.run_command(["brew", "install", "ollama"], timeout=300, clean_env=True)
            if code == 0:
                # Refresh PATH to find newly installed Ollama
                common_paths = [
                    os.path.expanduser("~/.local/bin"),
                    "/usr/local/bin",
                    "/opt/homebrew/bin",
                ]
                for path in common_paths:
                    if os.path.exists(os.path.join(path, "ollama")):
                        os.environ["PATH"] = f"{path}:{os.environ.get('PATH', '')}"
                        break
                
                ollama_path = shutil.which("ollama")
                if ollama_path:
                    ollama_installed_by_script = True
                # If installation failed silently, we'll detect it below
    
    # Check Ollama installation and get version
    if ollama_path:
        ollama_ok = True
        code, stdout, _ = utils.run_command(["ollama", "--version"], timeout=5, clean_env=True)
        if code == 0:
            ollama_version = stdout.strip()
        else:
            ollama_version = "unknown"
    else:
        ollama_ok = False
        ollama_version = ""
    
    ollama_running = ollama.verify_ollama_running() if ollama_ok else False
    
    # Start Ollama if installed but not running (needed for model queries) - silently
    if ollama_ok and not ollama_running:
        # Start Ollama service silently (no UI output)
        try:
            # Try to start via launchd first (macOS)
            if platform.system() == "Darwin":
                plist_path = Path.home() / "Library" / "LaunchAgents" / "com.ollama.server.plist"
                if plist_path.exists():
                    utils.run_command(["launchctl", "load", str(plist_path)], timeout=10, clean_env=True)
                    # Wait silently for service to start
                    for _ in range(15):
                        time.sleep(1)
                        if ollama.verify_ollama_running():
                            ollama_running = True
                            break
                    if ollama_running:
                        pass  # Success, continue silently
                else:
                    # Start temporarily in background
                    subprocess.Popen(
                        ["ollama", "serve"],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        start_new_session=True
                    )
                    # Wait silently for service to start
                    for _ in range(15):
                        time.sleep(1)
                        if ollama.verify_ollama_running():
                            ollama_running = True
                            break
            else:
                # Linux/other - start in background
                subprocess.Popen(
                    ["ollama", "serve"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True
                )
                # Wait silently for service to start
                for _ in range(15):
                    time.sleep(1)
                    if ollama.verify_ollama_running():
                        ollama_running = True
                        break
        except Exception:
            # Silently fail - we'll handle it when trying to remove models
            pass
    
    # Detect install method - if we installed it, it's homebrew
    if ollama_installed_by_script:
        install_method = "homebrew"
    else:
        install_method = detect_install_method() if ollama_ok else "unknown"
    
    # Get models from manifest
    installed_models_raw = manifest.get("installed", {}).get("models", [])
    pre_existing = manifest.get("pre_existing", {}).get("models", [])
    
    # Filter out overlapping models
    filtered_installed = []
    for model in installed_models_raw:
        model_name = model.get("name", "")
        if not model_name:
            continue
        
        overlaps = False
        for pre_existing_name in pre_existing:
            if uninstaller.models_overlap(model_name, pre_existing_name):
                overlaps = True
                break
        
        if not overlaps:
            filtered_installed.append(model)
    
    installed_models = [m.get("name") for m in filtered_installed if m.get("name")]
    
    # Get actual installed models from Ollama (if running)
    actual_installed_models = []
    if ollama_running:
        actual_installed_models = uninstaller.get_installed_models()
    
    # Check config files
    config_files = [
        Path.home() / ".continue" / "config.yaml",
        Path.home() / ".continue" / "config.json",
        Path.home() / ".continue" / "rules" / "global-rule.md",
        Path.home() / ".continue" / ".continueignore"
    ]
    existing_configs = [f for f in config_files if f.exists()]
    
    # Check for customizations
    customized_configs = []
    for config_path in existing_configs:
        status = config.check_config_customization(config_path, manifest)
        if status == "modified":
            customized_configs.append(config_path)
    
    # Check autostart (macOS only)
    autostart_configured = False
    autostart_details = ""
    if platform.system() == "Darwin":
        autostart_configured, autostart_details = ollama.check_ollama_autostart_status_macos()
    
    # Scan for orphaned files
    orphaned_files = uninstaller.scan_for_orphaned_files(manifest)
    
    # Check IDE extensions
    vscode_extension = uninstaller.check_vscode_extension_installed()
    intellij_plugin, _ = uninstaller.check_intellij_plugin_installed()
    
    # Check Open WebUI status
    openwebui_status = openwebui.get_openwebui_status()
    
    return SystemInfo(
        manifest=manifest,
        ollama_installed=ollama_ok,
        ollama_version=ollama_version if ollama_ok else "",
        ollama_running=ollama_running,
        install_method=install_method,
        installed_models=installed_models,
        pre_existing_models=pre_existing,
        actual_installed_models=actual_installed_models,
        config_files=existing_configs,
        customized_configs=customized_configs,
        autostart_configured=autostart_configured,
        autostart_details=autostart_details,
        orphaned_files=orphaned_files,
        vscode_extension=vscode_extension,
        intellij_plugin=intellij_plugin,
        ollama_installed_by_script=ollama_installed_by_script,
        openwebui_status=openwebui_status
    )


def display_system_scan(info: SystemInfo) -> None:
    """Display system scan results."""
    ui.print_subheader("System Scan")
    
    # Ollama status
    if info.ollama_installed:
        method_str = f" ({info.install_method})" if info.install_method != "unknown" else ""
        status_str = "running" if info.ollama_running else "stopped"
        ui.print_info(f"✓ Ollama v{info.ollama_version}{method_str}, {status_str}")
    else:
        ui.print_info("✗ Ollama not installed")
    
    # Models
    if info.installed_models:
        ui.print_info(f"✓ {len(info.installed_models)} model(s) installed by setup")
    elif info.actual_installed_models:
        # No manifest models, but we found models in Ollama
        ui.print_info(f"✓ {len(info.actual_installed_models)} model(s) found in Ollama")
    if info.pre_existing_models:
        ui.print_info(f"✓ {len(info.pre_existing_models)} pre-existing model(s) (will be kept)")
    
    # Config files
    if info.config_files:
        ui.print_info(f"✓ {len(info.config_files)} config file(s)")
        if info.customized_configs:
            ui.print_info(f"  ({len(info.customized_configs)} customized)")
    
    # Autostart
    if info.autostart_configured:
        ui.print_info(f"✓ Auto-start enabled ({info.autostart_details})")
    
    # IDE extensions
    if info.vscode_extension:
        ui.print_info("✓ VS Code extension installed")
    if info.intellij_plugin:
        ui.print_info("✓ IntelliJ plugin installed")
    
    # Open WebUI
    if info.openwebui_status.get("container_exists"):
        status_str = "running" if info.openwebui_status.get("container_running") else "stopped"
        ui.print_info(f"✓ Open WebUI container ({status_str})")
    
    print()


def prompt_all_choices(info: SystemInfo, args: Any) -> UninstallChoices:
    """
    Phase 2: Ask ALL questions upfront.
    
    Returns:
        UninstallChoices with all user decisions
    """
    choices = UninstallChoices(
        models_to_remove=[],
        remove_configs=False,
        stop_service=False,
        remove_autostart=False,
        uninstall_ollama=False,
        remove_vscode=False,
        remove_intellij=False,
        remove_openwebui=False,
        remove_openwebui_data=False,
        remove_openwebui_image=False
    )
    
    ui.print_subheader("Uninstall Configuration")
    print()
    
    # Models - use actual installed models if manifest filtering removed everything
    available_models = info.installed_models if info.installed_models else info.actual_installed_models
    
    if not args.skip_models and available_models:
        # Show what we know about models
        if info.installed_models:
            model_options = ["Remove all", "Select models", "Keep all"]
            choice = ui.prompt_choice(
                f"Models to remove ({len(info.installed_models)} installed by setup):",
                model_options,
                default=2
            )
            
            if choice == 0:  # Remove all
                choices.models_to_remove = info.installed_models
            elif choice == 1:  # Select
                indices = ui.prompt_multi_choice(
                    "Select models to remove:",
                    info.installed_models,
                    min_selections=0
                )
                if indices:
                    choices.models_to_remove = [info.installed_models[i] for i in indices]
        elif info.actual_installed_models:
            # No manifest models, but we found models in Ollama
            ui.print_info(f"Found {len(info.actual_installed_models)} installed model(s):")
            for model in info.actual_installed_models:
                print(f"  • {model}")
            print()
            
            model_options = ["Remove all", "Select models", "Keep all"]
            choice = ui.prompt_choice(
                "Models to remove:",
                model_options,
                default=2
            )
            
            if choice == 0:  # Remove all
                choices.models_to_remove = info.actual_installed_models
            elif choice == 1:  # Select
                indices = ui.prompt_multi_choice(
                    "Select models to remove:",
                    info.actual_installed_models,
                    min_selections=0
                )
                if indices:
                    choices.models_to_remove = [info.actual_installed_models[i] for i in indices]
    elif args.skip_models:
        ui.print_info("Skipping model removal (--skip-models)")
    
    # Config files
    if not args.skip_config and info.config_files:
        if info.customized_configs:
            ui.print_warning(f"{len(info.customized_configs)} config file(s) have customizations")
            ui.print_info("Backups will be created automatically")
            print()
        
        file_list = ", ".join([f.name for f in info.config_files])
        choices.remove_configs = ui.prompt_yes_no(
            f"Remove configuration files ({file_list})?",
            default=True
        )
    elif args.skip_config:
        ui.print_info("Skipping config removal (--skip-config)")
    
    # Stop service - only needed if uninstalling Ollama completely
    # We'll stop it automatically if needed, no need to ask
    
    # Autostart - only prompt if auto-start is actually configured
    if info.autostart_configured:
        choices.remove_autostart = ui.prompt_yes_no(
            "Remove Ollama auto-start configuration?",
            default=True
        )
    
    # IDE extensions
    if not args.skip_extension:
        if not args.skip_vscode and info.vscode_extension:
            choices.remove_vscode = ui.prompt_yes_no(
                "Remove VS Code extension?",
                default=False
            )
        
        if not args.skip_intellij and info.intellij_plugin:
            choices.remove_intellij = ui.prompt_yes_no(
                "Remove IntelliJ plugin?",
                default=False
            )
    
    # Open WebUI
    if info.openwebui_status.get("container_exists"):
        print()
        status_str = "running" if info.openwebui_status.get("container_running") else "stopped"
        ui.print_info(f"Open WebUI container is {status_str}")
        
        choices.remove_openwebui = ui.prompt_yes_no(
            "Remove Open WebUI container?",
            default=True
        )
        
        if choices.remove_openwebui:
            choices.remove_openwebui_data = ui.prompt_yes_no(
                "Also remove Open WebUI data (chat history, settings)?",
                default=False
            )
            
            choices.remove_openwebui_image = ui.prompt_yes_no(
                "Remove Docker image to free disk space (~2GB)?",
                default=False
            )
    
    # Uninstall Ollama completely
    if info.ollama_installed:
        print()
        ui.print_warning("Uninstalling Ollama will remove:")
        ui.print_info("  • Ollama application and CLI")
        ui.print_info("  • All Ollama data and models (~/.ollama)")
        ui.print_info("  • Application caches")
        print()
        choices.uninstall_ollama = ui.prompt_yes_no(
            "Uninstall Ollama completely?",
            default=False
        )
    
    return choices


def show_plan_summary(info: SystemInfo, choices: UninstallChoices) -> None:
    """Show preview of what will happen."""
    ui.print_subheader("Plan Preview")
    print()
    
    if choices.models_to_remove:
        ui.print_info(f"• Remove {len(choices.models_to_remove)} model(s)")
    if choices.remove_configs:
        ui.print_info(f"• Remove {len(info.config_files)} config file(s)")
    if choices.remove_autostart:
        ui.print_info("• Remove auto-start configuration")
    if choices.remove_vscode:
        ui.print_info("• Remove VS Code extension")
    if choices.remove_intellij:
        ui.print_info("• Remove IntelliJ plugin")
    if choices.remove_openwebui:
        ui.print_info("• Remove Open WebUI container")
        if choices.remove_openwebui_data:
            ui.print_info("  • Also remove Open WebUI data")
        if choices.remove_openwebui_image:
            ui.print_info("  • Also remove Docker image")
    if choices.uninstall_ollama:
        ui.print_info("• Uninstall Ollama completely")
    
    if not any([
        choices.models_to_remove,
        choices.remove_configs,
        choices.remove_autostart,
        choices.remove_vscode,
        choices.remove_intellij,
        choices.remove_openwebui,
        choices.uninstall_ollama
    ]):
        ui.print_info("• No actions selected")
    
    print()


def execute_uninstall(info: SystemInfo, choices: UninstallChoices) -> UninstallResults:
    """
    Phase 3: Execute all actions quietly.
    
    Only shows progress bars and failures.
    """
    results = UninstallResults(
        models_removed=0,
        configs_removed=0,
        service_stopped=False,
        autostart_removed=False,
        ollama_uninstalled=False,
        vscode_removed=False,
        intellij_removed=False,
        temp_files_removed=0,
        errors=[],
        openwebui_container_removed=False,
        openwebui_data_removed=False,
        openwebui_image_removed=False
    )
    
    # Remove models
    if choices.models_to_remove:
        ui.print_subheader("Removing Models")
        # Skip if Ollama is not installed
        if not info.ollama_installed:
            ui.print_info("Skipping model removal - Ollama is not installed")
        else:
            # Ensure Ollama is running
            if not info.ollama_running:
                if uninstaller.ensure_ollama_running_for_removal():
                    info.ollama_running = True
            
            if info.ollama_running:
                removed = uninstaller.remove_models(choices.models_to_remove)
                results.models_removed = removed
                # Check if all models were removed
                if removed < len(choices.models_to_remove):
                    failed = len(choices.models_to_remove) - removed
                    results.errors.append(f"Failed to remove {failed} model(s)")
            else:
                results.errors.append("Cannot remove models - Ollama service not available")
        print()
    
    # Remove config files
    if choices.remove_configs:
        ui.print_subheader("Removing Configuration Files")
        for config_path in info.config_files:
            # Create backup for customized files
            if config_path in info.customized_configs:
                timestamp = int(time.time())
                backup = config_path.with_suffix(f".pre-uninstall-{timestamp}{config_path.suffix}")
                try:
                    shutil.copy(config_path, backup)
                except Exception as e:
                    results.errors.append(f"Could not backup {config_path.name}: {e}")
            
            # Remove file
            try:
                config_path.unlink()
                results.configs_removed += 1
            except Exception as e:
                results.errors.append(f"Could not remove {config_path.name}: {e}")
        print()
    
    # Remove autostart
    if choices.remove_autostart:
        ui.print_subheader("Removing Auto-Start")
        if ollama.remove_ollama_autostart_macos():
            results.autostart_removed = True
        else:
            results.errors.append("Could not remove auto-start configuration")
        print()
    
    # Stop service automatically if uninstalling Ollama completely
    if choices.uninstall_ollama and info.ollama_running:
        ui.print_subheader("Stopping Ollama Service")
        try:
            subprocess.run(["pkill", "ollama"], timeout=5, check=False)
            time.sleep(2)
            if not ollama.verify_ollama_running():
                results.service_stopped = True
            else:
                results.errors.append("Ollama service may still be running")
        except Exception as e:
            results.errors.append(f"Could not stop Ollama service: {e}")
        print()
    
    # Remove IDE extensions
    if choices.remove_vscode:
        ui.print_subheader("Removing VS Code Extension")
        results.vscode_removed = uninstaller.uninstall_vscode_extension()
        print()
    
    if choices.remove_intellij:
        ui.print_subheader("Removing IntelliJ Plugin")
        results.intellij_removed = uninstaller.uninstall_intellij_plugin()
        print()
    
    # Remove Open WebUI
    if choices.remove_openwebui:
        ui.print_subheader("Removing Open WebUI")
        openwebui_results = openwebui.uninstall_openwebui(
            remove_data=choices.remove_openwebui_data,
            remove_image=choices.remove_openwebui_image
        )
        results.openwebui_container_removed = openwebui_results.get("container_removed", False)
        results.openwebui_data_removed = openwebui_results.get("data_removed", False)
        results.openwebui_image_removed = openwebui_results.get("image_removed", False)
        print()
    
    # Uninstall Ollama
    if choices.uninstall_ollama:
        ui.print_subheader("Uninstalling Ollama")
        if info.install_method == "homebrew":
            ui.print_info("Using Homebrew to uninstall...")
            code, _, stderr = utils.run_command(
                ["brew", "uninstall", "ollama"], timeout=60, clean_env=True
            )
            if code == 0:
                results.ollama_uninstalled = True
            else:
                results.errors.append(f"Homebrew uninstall failed: {stderr}")
        else:
            success, errors = ollama.remove_ollama()
            results.ollama_uninstalled = success
            results.errors.extend(errors)
        print()
    
    # Clean up temp files (always do this silently)
    ui.print_subheader("Cleaning Temporary Files")
    auto_remove_paths: List[Path] = []
    
    cache_dir = Path.home() / ".continue" / "cache"
    if cache_dir.exists():
        auto_remove_paths.append(cache_dir)
    
    summary_path = Path.home() / ".continue" / "setup-summary.json"
    if summary_path.exists():
        auto_remove_paths.append(summary_path)
    
    continue_dir = Path.home() / ".continue"
    if continue_dir.exists():
        for backup_file in continue_dir.glob("*.backup_*"):
            auto_remove_paths.append(backup_file)
        for backup_file in continue_dir.glob("*.pre-uninstall-*"):
            auto_remove_paths.append(backup_file)
    
    for filepath, status in info.orphaned_files:
        if status == "certain":
            auto_remove_paths.append(filepath)
    
    for path in auto_remove_paths:
        try:
            if path.exists():
                if path.is_dir():
                    shutil.rmtree(path)
                else:
                    path.unlink()
                results.temp_files_removed += 1
        except Exception as e:
            results.errors.append(f"Could not remove {path.name}: {e}")
    
    # Remove manifest
    manifest_path = Path.home() / ".continue" / "setup-manifest.json"
    if manifest_path.exists():
        try:
            manifest_path.unlink()
        except Exception as e:
            results.errors.append(f"Could not remove manifest: {e}")
    
    # If Ollama was installed by this script, remove it at the end
    if info.ollama_installed_by_script:
        ui.print_subheader("Removing Ollama (installed by uninstaller)")
        # Stop service first if running
        if info.ollama_running:
            try:
                subprocess.run(["pkill", "ollama"], timeout=5, check=False)
                time.sleep(2)
            except Exception as e:
                results.errors.append(f"Could not stop Ollama service: {e}")
        
        # Uninstall via Homebrew (since we installed it via Homebrew)
        if info.install_method == "homebrew":
            ui.print_info("Uninstalling Ollama via Homebrew...")
            code, _, stderr = utils.run_command(
                ["brew", "uninstall", "ollama"], timeout=60, clean_env=True
            )
            if code == 0:
                ui.print_success("Ollama removed successfully")
                results.ollama_uninstalled = True
            else:
                results.errors.append(f"Failed to remove Ollama: {stderr}")
        else:
            # Fallback: try to remove manually
            success, errors = ollama.remove_ollama()
            results.ollama_uninstalled = success
            results.errors.extend(errors)
        print()
    
    return results


def print_accurate_summary(results: UninstallResults, info: SystemInfo) -> None:
    """Phase 4: Report actual results only."""
    ui.print_header("✅ Uninstallation Complete")
    print()
    
    if results.models_removed > 0:
        ui.print_success(f"✓ Removed {results.models_removed} model(s)")
    if results.configs_removed > 0:
        ui.print_success(f"✓ Removed {results.configs_removed} configuration file(s)")
    if results.service_stopped:
        ui.print_success("✓ Stopped Ollama service")
    if results.autostart_removed:
        ui.print_success("✓ Removed auto-start configuration")
    if results.vscode_removed:
        ui.print_success("✓ Removed VS Code extension")
    if results.intellij_removed:
        ui.print_success("✓ Removed IntelliJ plugin")
    if results.ollama_uninstalled:
        ui.print_success("✓ Uninstalled Ollama completely")
    if results.openwebui_container_removed:
        ui.print_success("✓ Removed Open WebUI container")
    if results.openwebui_data_removed:
        ui.print_success("✓ Removed Open WebUI data")
    if results.openwebui_image_removed:
        ui.print_success("✓ Removed Open WebUI Docker image")
    if results.temp_files_removed > 0:
        ui.print_info(f"✓ Cleaned {results.temp_files_removed} temporary file(s)")
    
    # Show errors if any
    if results.errors:
        print()
        ui.print_warning("Some operations had errors:")
        for error in results.errors:
            ui.print_info(f"  • {error}")
    
    # Show what remains
    print()
    if not results.ollama_uninstalled and info.ollama_installed:
        ui.print_info("ℹ Ollama remains installed - reinstall configs with ollama-llm-setup.py")
    elif results.ollama_uninstalled:
        ui.print_info("ℹ Ollama has been completely removed from your system")
    
    print()


def main() -> int:
    """Main uninstaller entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Uninstall Ollama + Continue.dev setup",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--skip-models", action="store_true", help="Skip Ollama model removal")
    parser.add_argument("--skip-config", action="store_true", help="Skip config file removal")
    parser.add_argument("--skip-extension", action="store_true", help="Skip IDE extension removal")
    parser.add_argument("--skip-vscode", action="store_true", help="Skip VS Code extension removal")
    parser.add_argument("--skip-intellij", action="store_true", help="Skip IntelliJ plugin removal")
    
    args = parser.parse_args()
    
    ui.clear_screen()
    ui.print_header("🗑️  Ollama + Continue.dev Uninstaller v2.0")
    print()
    
    # Phase 1: Gather all info silently
    info = gather_system_info(args)
    
    # Display system scan
    display_system_scan(info)
    
    # Phase 2: Ask all questions upfront
    choices = prompt_all_choices(info, args)
    
    # Show plan preview
    show_plan_summary(info, choices)
    
    # Confirm proceed
    if not ui.prompt_yes_no("Proceed with uninstallation?", default=True):
        ui.print_info("Uninstallation cancelled")
        return 0
    
    print()
    
    # Phase 3: Execute quietly
    results = execute_uninstall(info, choices)
    
    # Phase 4: Report accurate results
    print_accurate_summary(results, info)
    
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
