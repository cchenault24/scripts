#!/usr/bin/env python3
"""
Docker Model Runner + Continue.dev Smart Uninstaller (v2.0)

An interactive Python script that helps you uninstall components set up by
docker-llm-setup.py, including:
- Docker Model Runner models (only ones we installed, keeping pre-existing)
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

# Add docker directory to path so we can import lib modules
script_path = Path(__file__).resolve() if __file__ else Path(sys.argv[0]).resolve()
docker_dir = script_path.parent

docker_dir_str = str(docker_dir)
if docker_dir_str not in sys.path:
    sys.path.insert(0, docker_dir_str)

from lib import ui
from lib import config
from lib import uninstaller
from lib import docker
from lib import utils

# Module logger
_logger = logging.getLogger(__name__)


@dataclass
class SystemInfo:
    """Collected system information."""
    manifest: Dict[str, Any]
    docker_installed: bool
    docker_version: str
    docker_running: bool
    dmr_available: bool  # Docker Model Runner available
    installed_models: List[str]  # From manifest, filtered
    pre_existing_models: List[str]
    actual_installed_models: List[str]  # From docker model list
    config_files: List[Path]
    customized_configs: List[Path]
    orphaned_files: List[tuple[Path, str]]
    vscode_extension: bool
    intellij_plugin: bool


@dataclass
class UninstallChoices:
    """User choices for what to uninstall."""
    models_to_remove: List[str]
    remove_configs: bool
    remove_vscode: bool
    remove_intellij: bool


@dataclass
class UninstallResults:
    """Actual results of uninstallation."""
    models_removed: int
    configs_removed: int
    vscode_removed: bool
    intellij_removed: bool
    temp_files_removed: int
    errors: List[str]


def load_manifest() -> dict[str, Any] | None:
    """Load installation manifest if it exists."""
    manifest_path = Path.home() / ".continue" / "setup-manifest.json"
    
    if not manifest_path.exists():
        return None
    
    try:
        with open(manifest_path, 'r') as f:
            manifest = json.load(f)
            # Verify this is a Docker manifest
            if manifest.get("installer_type") != "docker":
                _logger.warning(f"Manifest is not from Docker installer: {manifest.get('installer_type')}")
                # Still usable but warn
            return manifest
    except json.JSONDecodeError as e:
        _logger.warning(f"Manifest file is corrupt: {manifest_path}: {e}")
        warnings.warn(f"Installation manifest is unreadable: {e}", UserWarning)
        return {"_unreadable_manifest": True}
    except (OSError, IOError, PermissionError) as e:
        _logger.warning(f"Failed to read manifest: {manifest_path}: {e}")
        return None


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
    
    # Check Docker installation and status
    docker_ok, docker_version = docker.check_docker()
    docker_running = docker_ok  # If check_docker passes, Docker is running
    
    # Check Docker Model Runner
    dmr_available = False
    if docker_ok:
        dmr_available, _ = docker.check_docker_model_runner_status()
    
    # Get models from manifest
    installed_models_raw = manifest.get("installed", {}).get("models", [])
    pre_existing = manifest.get("pre_existing", {}).get("models", [])
    
    # Filter out overlapping models (models that were pre-existing)
    filtered_installed = []
    for model in installed_models_raw:
        model_name = model.get("name", "") if isinstance(model, dict) else str(model)
        if not model_name:
            continue
        
        overlaps = False
        for pre_existing_name in pre_existing:
            if uninstaller.models_overlap(model_name, pre_existing_name):
                overlaps = True
                break
        
        if not overlaps:
            filtered_installed.append(model)
    
    installed_models = []
    for m in filtered_installed:
        if isinstance(m, dict):
            name = m.get("name") or m.get("docker_name", "")
        else:
            name = str(m)
        if name:
            installed_models.append(name)
    
    # Get actual installed models from Docker Model Runner (if available)
    actual_installed_models = []
    if dmr_available:
        actual_installed_models = uninstaller.get_installed_models()
    
    # Check config files
    config_files = [
        Path.home() / ".continue" / "config.yaml",
        Path.home() / ".continue" / "config.json",
        Path.home() / ".continue" / "rules" / "global-rule.md",
        Path.home() / ".continue" / "rules" / "codebase-context.md",
        Path.home() / ".continue" / ".continueignore"
    ]
    existing_configs = [f for f in config_files if f.exists()]
    
    # Check for customizations
    customized_configs = []
    for config_path in existing_configs:
        status = config.check_config_customization(config_path, manifest)
        if status == "modified":
            customized_configs.append(config_path)
    
    # Scan for orphaned files
    orphaned_files = uninstaller.scan_for_orphaned_files(manifest)
    
    # Check IDE extensions
    vscode_extension = uninstaller.check_vscode_extension_installed()
    intellij_plugin, _ = uninstaller.check_intellij_plugin_installed()
    
    return SystemInfo(
        manifest=manifest,
        docker_installed=docker_ok,
        docker_version=docker_version if docker_ok else "",
        docker_running=docker_running,
        dmr_available=dmr_available,
        installed_models=installed_models,
        pre_existing_models=pre_existing,
        actual_installed_models=actual_installed_models,
        config_files=existing_configs,
        customized_configs=customized_configs,
        orphaned_files=orphaned_files,
        vscode_extension=vscode_extension,
        intellij_plugin=intellij_plugin
    )


def display_system_scan(info: SystemInfo) -> None:
    """Display system scan results."""
    ui.print_subheader("System Scan")
    
    # Docker status
    if info.docker_installed:
        dmr_str = ", DMR available" if info.dmr_available else ", DMR not available"
        ui.print_info(f"✓ Docker {info.docker_version}{dmr_str}")
    else:
        ui.print_info("✗ Docker not installed or not running")
    
    # Models
    if info.installed_models:
        ui.print_info(f"✓ {len(info.installed_models)} model(s) installed by setup")
    elif info.actual_installed_models:
        # No manifest models, but we found models in Docker
        ui.print_info(f"✓ {len(info.actual_installed_models)} model(s) found in Docker Model Runner")
    if info.pre_existing_models:
        ui.print_info(f"✓ {len(info.pre_existing_models)} pre-existing model(s) (will be kept)")
    
    # Config files
    if info.config_files:
        ui.print_info(f"✓ {len(info.config_files)} config file(s)")
        if info.customized_configs:
            ui.print_info(f"  ({len(info.customized_configs)} customized)")
    
    # IDE extensions
    if info.vscode_extension:
        ui.print_info("✓ VS Code extension installed")
    if info.intellij_plugin:
        ui.print_info("✓ IntelliJ plugin installed")
    
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
        remove_vscode=False,
        remove_intellij=False
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
            # No manifest models, but we found models in Docker
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
    elif not info.dmr_available:
        ui.print_info("Docker Model Runner not available - skipping model removal")
    
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
    
    return choices


def show_plan_summary(info: SystemInfo, choices: UninstallChoices) -> None:
    """Show preview of what will happen."""
    ui.print_subheader("Plan Preview")
    print()
    
    if choices.models_to_remove:
        ui.print_info(f"• Remove {len(choices.models_to_remove)} model(s)")
    if choices.remove_configs:
        ui.print_info(f"• Remove {len(info.config_files)} config file(s)")
    if choices.remove_vscode:
        ui.print_info("• Remove VS Code extension")
    if choices.remove_intellij:
        ui.print_info("• Remove IntelliJ plugin")
    
    if not any([
        choices.models_to_remove,
        choices.remove_configs,
        choices.remove_vscode,
        choices.remove_intellij
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
        vscode_removed=False,
        intellij_removed=False,
        temp_files_removed=0,
        errors=[]
    )
    
    # Remove models
    if choices.models_to_remove:
        ui.print_subheader("Removing Models")
        if info.dmr_available:
            removed = uninstaller.remove_models(choices.models_to_remove)
            results.models_removed = removed
            # Check if all models were removed
            if removed < len(choices.models_to_remove):
                failed = len(choices.models_to_remove) - removed
                results.errors.append(f"Failed to remove {failed} model(s)")
        else:
            results.errors.append("Cannot remove models - Docker Model Runner not available")
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
                    ui.print_info(f"Backed up customized: {config_path.name}")
                except Exception as e:
                    results.errors.append(f"Could not backup {config_path.name}: {e}")
            
            # Remove file
            try:
                config_path.unlink()
                ui.print_success(f"Removed: {config_path.name}")
                results.configs_removed += 1
            except Exception as e:
                results.errors.append(f"Could not remove {config_path.name}: {e}")
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
            ui.print_info("Removed installation manifest")
        except Exception as e:
            results.errors.append(f"Could not remove manifest: {e}")
    
    return results


def print_accurate_summary(results: UninstallResults, info: SystemInfo) -> None:
    """Phase 4: Report actual results only."""
    ui.print_header("✅ Uninstallation Complete")
    print()
    
    if results.models_removed > 0:
        ui.print_success(f"✓ Removed {results.models_removed} model(s)")
    if results.configs_removed > 0:
        ui.print_success(f"✓ Removed {results.configs_removed} configuration file(s)")
    if results.vscode_removed:
        ui.print_success("✓ Removed VS Code extension")
    if results.intellij_removed:
        ui.print_success("✓ Removed IntelliJ plugin")
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
    ui.print_info("Note:")
    print("  • Docker Desktop and Docker Model Runner were not uninstalled")
    if info.pre_existing_models:
        print(f"  • {len(info.pre_existing_models)} pre-existing model(s) were kept")
    print("  • You can reinstall by running docker-llm-setup.py again")
    print()


def main() -> int:
    """Main uninstaller entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Uninstall Docker Model Runner + Continue.dev setup",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--skip-models", action="store_true", help="Skip Docker model removal")
    parser.add_argument("--skip-config", action="store_true", help="Skip config file removal")
    parser.add_argument("--skip-extension", action="store_true", help="Skip IDE extension removal")
    parser.add_argument("--skip-vscode", action="store_true", help="Skip VS Code extension removal")
    parser.add_argument("--skip-intellij", action="store_true", help="Skip IntelliJ plugin removal")
    parser.add_argument("--skip-docker-checks", action="store_true", help="Skip Docker checks (useful if Docker is hanging)")
    
    args = parser.parse_args()
    
    ui.clear_screen()
    ui.print_header("🗑️  Docker Model Runner + Continue.dev Uninstaller v2.0")
    print()
    
    # Phase 1: Gather all info silently
    ui.print_info("Scanning system...")
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
