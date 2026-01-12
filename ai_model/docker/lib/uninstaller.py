"""
Smart Uninstaller Module for Docker Model Runner.

Provides manifest-based cleanup with:
- Targeted file scanning
- Process detection and handling
- Config customization detection
- Smart defaults (auto-remove cache, ask for models)
"""

import json
import logging
import os
import platform
import shutil
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

from . import ui
from . import utils
from .utils import get_unverified_ssl_context
from . import config as config_module

# Module logger
_logger = logging.getLogger(__name__)

# Safety limits for scanning
MAX_FILES_SCANNED = 10000
SCAN_TIMEOUT_SECONDS = 30

# Timeout constants
API_TIMEOUT = 5
PROCESS_TIMEOUT = 5

# Scan configuration
SCAN_CONFIG = {
    "~/.continue/": {
        "recursive": True,
        "max_depth": None,
        "look_for": ["fingerprint", "manifest_entry", "timestamp"],
        "description": "Continue.dev configuration directory"
    },
    "/tmp/": {
        "recursive": False,
        "pattern": "docker-setup-*",
        "look_for": ["fingerprint"],
        "description": "Temporary files"
    }
}

# Unsafe paths that should never be scanned
UNSAFE_PATHS = [
    "/usr/", "/System/", "/bin/", "/sbin/",
    "/Library/", "/Applications/",
    "/dev/", "/proc/", "/sys/",
    "/etc/", "/var/", "/opt/"
]


def create_empty_manifest() -> Dict[str, Any]:
    """Create empty manifest structure for fallback."""
    return {
        "version": "2.0",
        "timestamp": "",
        "installer_version": "unknown",
        "installer_type": "docker",
        "hardware_snapshot": {},
        "pre_existing": {
            "models": [],
            "backups": {}
        },
        "installed": {
            "models": [],
            "files": [],
            "cache_dirs": [],
            "ide_extensions": [],
            "docker_model_runner_available": False,
            "target_ides": []
        }
    }


def is_safe_location(path: Path) -> bool:
    """Check if location is safe to scan."""
    try:
        path_str = str(path.resolve())
    except (OSError, RuntimeError):
        # If we can't resolve, check the original path
        path_str = str(path)

    # Check if path starts with any unsafe prefix
    # Also check path components to catch cases like /private/etc/passwd
    path_parts = path_str.split('/')
    unsafe_components = {p.rstrip('/') for p in UNSAFE_PATHS if p}

    # Check if any path component matches an unsafe directory
    for part in path_parts:
        if part and f"/{part}/" in UNSAFE_PATHS:
            return False

    # Also check prefix match for direct unsafe paths
    return not any(path_str.startswith(unsafe) for unsafe in UNSAFE_PATHS)


def scan_for_orphaned_files(manifest: Dict[str, Any]) -> List[Tuple[Path, str]]:
    """Scan for files created by installer but not in manifest."""
    orphaned: List[Tuple[Path, str]] = []
    files_scanned = 0
    start_time = time.time()
    
    manifest_paths: Set[str] = set(
        f["path"] for f in manifest.get("installed", {}).get("files", [])
    )
    
    for location, scan_config in SCAN_CONFIG.items():
        location_path = Path(location).expanduser()
        
        if not location_path.exists():
            continue
        
        try:
            root_resolved = location_path.resolve()
        except (OSError, RuntimeError):
            continue
        
        if not is_safe_location(root_resolved):
            continue
        
        try:
            if scan_config.get("recursive"):
                files = location_path.rglob("*")
            else:
                pattern = scan_config.get("pattern", "*")
                files = location_path.glob(pattern)
            
            for filepath in files:
                if files_scanned >= MAX_FILES_SCANNED:
                    break
                
                if time.time() - start_time > SCAN_TIMEOUT_SECONDS:
                    break
                
                if not filepath.is_file():
                    continue
                
                files_scanned += 1
                
                try:
                    resolved_path = filepath.resolve()
                    try:
                        resolved_path.relative_to(root_resolved)
                    except ValueError:
                        continue
                except (OSError, RuntimeError):
                    continue
                
                if str(filepath) in manifest_paths:
                    continue
                
                status = config_module.is_our_file(filepath, manifest)
                if status is True:
                    orphaned.append((filepath, "certain"))
                elif status == "maybe":
                    orphaned.append((filepath, "uncertain"))
        
        except (OSError, IOError, PermissionError):
            continue
    
    return orphaned


def check_running_processes(manifest: Dict[str, Any]) -> Dict[str, List[str]]:
    """Detect processes related to our setup."""
    running = {
        "docker_model": [],
        "vscode": [],
        "intellij": [],
        "model_servers": []
    }
    
    # Check Docker
    code, _, _ = utils.run_command(["pgrep", "-f", "docker"], timeout=PROCESS_TIMEOUT)
    if code == 0:
        running["docker_model"] = ["Docker"]
    
    # Check VS Code
    if platform.system() == "Darwin":
        code, _, _ = utils.run_command(["pgrep", "-f", "Visual Studio Code"], timeout=PROCESS_TIMEOUT)
    else:
        code, _, _ = utils.run_command(["pgrep", "-f", "code"], timeout=PROCESS_TIMEOUT)
    if code == 0:
        running["vscode"] = ["VS Code"]
    
    # Check IntelliJ
    if platform.system() == "Darwin":
        code, _, _ = utils.run_command(["pgrep", "-f", "IntelliJ IDEA"], timeout=PROCESS_TIMEOUT)
    else:
        code, _, _ = utils.run_command(["pgrep", "-f", "idea"], timeout=PROCESS_TIMEOUT)
    if code == 0:
        running["intellij"] = ["IntelliJ IDEA"]
    
    return running


def handle_ide_processes(running: Dict[str, List[str]]) -> bool:
    """Handle IDE processes only."""
    if not any(running.values()):
        return True
    
    ui.print_warning("Found active IDE processes:")
    print()
    
    for process_type, processes in running.items():
        if processes:
            print(f"  • {process_type}: {', '.join(processes)}")
    
    print()
    ui.print_info("Recommendation:")
    if running.get("vscode") or running.get("intellij"):
        print("  1. Save your work in IDE")
        print("  2. Close IDE to uninstall extensions")
    print()
    
    choices = ["Stop processes and continue", "Let me handle it manually", "Cancel uninstall"]
    choice = ui.prompt_choice("How would you like to proceed?", choices, default=1)
    
    if choice == 2:
        return False
    elif choice == 1:
        ui.print_info("Please stop the processes manually, then run uninstaller again")
        return False
    else:
        return stop_ide_processes_gracefully(running)


def stop_ide_processes_gracefully(running: Dict[str, List[str]]) -> bool:
    """Stop IDE processes only."""
    if running.get("vscode") or running.get("intellij"):
        ui.print_warning("Please close your IDE(s) manually to avoid losing unsaved work")
        print()
        for ide_name in ["vscode", "intellij"]:
            if running.get(ide_name):
                display_name = "VS Code" if ide_name == "vscode" else "IntelliJ IDEA"
                if not ui.prompt_yes_no(f"Have you closed {display_name}?", default=False):
                    ui.print_info("Uninstall cancelled. Close IDE and try again.")
                    return False
    
    return True


def normalize_model_name(model_name: str) -> str:
    """
    Normalize model name for comparison.
    
    Extracts the base name and size tag (e.g., "7b", "13b") for comparison.
    This allows distinguishing between codellama:7b and codellama:13b.
    """
    if not model_name:
        return ""
    
    if ":" in model_name:
        base, tag = model_name.split(":", 1)
        # Extract size tag (e.g., "7b", "13b", "3b") from tag
        # Tags might be like "7b", "7b-q4", "latest", etc.
        tag_parts = tag.split("-")
        if tag_parts:
            # First part is usually the size (7b, 13b, etc.) or "latest"
            normalized_tag = tag_parts[0]
            # Only include tag if it's a size indicator (contains digits)
            if any(c.isdigit() for c in normalized_tag):
                return f"{base}:{normalized_tag}"
            # If it's "latest" or similar, return just base for comparison
            return base
        return model_name
    return model_name


def models_overlap(model1: str, model2: str) -> bool:
    """
    Check if two model names refer to the same model (handling tags).

    Examples:
    - codellama:7b and codellama:7b-latest -> True
    - codellama:7b and codellama:13b -> False
    - codellama:7b and starcoder2:3b -> False
    - nomic-embed-text and nomic-embed-text:latest -> True (same base, tag ignored)
    - nomic-embed-text:latest and nomic-embed-text -> True
    """
    if not model1 or not model2:
        return False

    # Normalize both model names for comparison
    normalized1 = normalize_model_name(model1)
    normalized2 = normalize_model_name(model2)

    # If normalized names are identical, they overlap
    if normalized1 == normalized2:
        return True

    # Special case for models without explicit tags (e.g., "nomic-embed-text" vs "nomic-embed-text:latest")
    # If one has a tag and the other doesn't, but their base names match, they overlap.
    base1 = model1.split(":")[0] if ":" in model1 else model1
    base2 = model2.split(":")[0] if ":" in model2 else model2

    if base1 == base2:
        # If one has a tag and the other doesn't, they are considered overlapping
        if (":" in model1 and ":" not in model2) or (":" not in model1 and ":" in model2):
            return True

    return False


def get_installed_models() -> List[str]:
    """Get list of currently installed Docker Model Runner models."""
    code, stdout, _ = utils.run_command(["docker", "model", "list"], timeout=10, clean_env=True)
    if code != 0:
        return []
    
    models = []
    lines = stdout.strip().split("\n")
    if len(lines) > 1:
        for line in lines[1:]:
            if line.strip():
                parts = line.split()
                if parts:
                    models.append(parts[0])
    return models


def remove_model(model_name: str) -> bool:
    """Remove a single Docker Model Runner model."""
    code, _, _ = utils.run_command(["docker", "model", "rm", model_name], timeout=600, clean_env=True)
    return code == 0


def find_actual_model_name(manifest_model_name: str, installed_models: List[str]) -> Optional[str]:
    """Find the actual model name in Docker that matches the manifest model name."""
    if manifest_model_name in installed_models:
        return manifest_model_name
    
    base_name = manifest_model_name.split(":")[0] if ":" in manifest_model_name else manifest_model_name
    
    for installed_model in installed_models:
        installed_base = installed_model.split(":")[0] if ":" in installed_model else installed_model
        if base_name == installed_base:
            if models_overlap(manifest_model_name, installed_model):
                return installed_model
    
    return None


def remove_models(model_names: List[str]) -> int:
    """Remove multiple Docker Model Runner models, returns count removed."""
    if not model_names:
        return 0
    
    installed_models = get_installed_models()
    if not installed_models:
        return 0
    
    models_to_remove = []
    
    for manifest_model_name in model_names:
        actual_name = find_actual_model_name(manifest_model_name, installed_models)
        if actual_name:
            models_to_remove.append(actual_name)
    
    if not models_to_remove:
        return 0
    
    removed = 0
    for i, model in enumerate(models_to_remove, 1):
        print(f"[{i}/{len(models_to_remove)}] Removing {model}...", end="", flush=True)
        if remove_model(model):
            print(" ✓")
            removed += 1
        else:
            print(" ✗")
    
    return removed


def check_vscode_extension_installed() -> bool:
    """Check if VS Code Continue.dev extension is installed."""
    code_path = shutil.which("code")
    if not code_path:
        return False
    
    code, stdout, _ = utils.run_command(["code", "--list-extensions"], timeout=10)
    if code != 0:
        return False
    
    return "Continue.continue" in stdout


def uninstall_vscode_extension() -> bool:
    """Uninstall Continue.dev VS Code extension."""
    code_path = shutil.which("code")
    if not code_path:
        ui.print_warning("VS Code CLI not found.")
        return False
    
    if not check_vscode_extension_installed():
        ui.print_info("Continue.dev extension is not installed")
        return False
    
    extension_id = "Continue.continue"
    ui.print_info(f"Uninstalling {extension_id}...")
    code, stdout, stderr = utils.run_command(["code", "--uninstall-extension", extension_id], timeout=60)
    
    if code == 0:
        ui.print_success("Extension uninstalled successfully")
        return True
    else:
        ui.print_error(f"Failed to uninstall extension: {stderr or stdout}")
        return False


def check_intellij_plugin_installed() -> Tuple[bool, List[Path]]:
    """Check if IntelliJ Continue plugin is installed."""
    plugin_paths = []
    
    if platform.system() == "Darwin":
        base_dirs = [Path.home() / "Library/Application Support/JetBrains"]
    elif platform.system() == "Linux":
        base_dirs = [Path.home() / ".local/share/JetBrains"]
    else:
        appdata = os.getenv("APPDATA", "")
        if appdata:
            base_dirs = [Path(appdata) / "JetBrains"]
        else:
            base_dirs = []
    
    for base_dir in base_dirs:
        if base_dir.exists():
            for product_dir in base_dir.iterdir():
                if product_dir.is_dir():
                    plugins_dir = product_dir / "plugins"
                    if plugins_dir.exists():
                        continue_plugin = plugins_dir / "Continue"
                        if continue_plugin.exists():
                            plugin_paths.append(continue_plugin)
    
    return len(plugin_paths) > 0, plugin_paths


def uninstall_intellij_plugin() -> bool:
    """Uninstall Continue plugin from IntelliJ IDEA."""
    is_installed, plugin_paths = check_intellij_plugin_installed()
    if not is_installed:
        ui.print_info("Continue plugin is not installed in IntelliJ IDEA")
        return False
    
    ui.print_info("Removing plugin directories...")
    removed_any = False
    for plugin_path in plugin_paths:
        try:
            if plugin_path.exists():
                shutil.rmtree(plugin_path)
                ui.print_success(f"Removed plugin from {plugin_path.parent.parent.name}")
                removed_any = True
        except (OSError, IOError, PermissionError, shutil.Error) as e:
            ui.print_error(f"Failed to remove {plugin_path}: {e}")
    
    if removed_any:
        ui.print_info("Note: You may need to restart IntelliJ IDEA for changes to take effect")
    
    return removed_any


def handle_ide_extensions() -> Dict[str, bool]:
    """Handle IDE extension removal with user choice."""
    removed = {"vscode": False, "intellij": False}
    
    if check_vscode_extension_installed():
        ui.print_subheader("VS Code Extension")
        ui.print_info("VS Code Continue.dev extension is installed")
        print()
        
        if ui.prompt_yes_no("Remove Continue.dev extension from VS Code?", default=False):
            removed["vscode"] = uninstall_vscode_extension()
        else:
            ui.print_info("Keeping VS Code extension")
    
    print()
    
    is_installed, _ = check_intellij_plugin_installed()
    if is_installed:
        ui.print_subheader("IntelliJ IDEA Plugin")
        ui.print_info("IntelliJ Continue plugin is installed")
        print()
        
        if ui.prompt_yes_no("Remove Continue plugin from IntelliJ IDEA?", default=False):
            removed["intellij"] = uninstall_intellij_plugin()
        else:
            ui.print_info("Keeping IntelliJ plugin")
    
    return removed


def show_uninstall_summary(
    models_removed: int,
    config_removed: int,
    temp_removed: int,
    vscode_removed: bool,
    intellij_removed: bool,
    docker_models_cleared: bool = False
) -> None:
    """Show uninstallation summary."""
    ui.print_header("✅ Uninstallation Complete!")
    
    print(ui.colorize("Summary:", ui.Colors.GREEN + ui.Colors.BOLD))
    print()
    
    print(f"  Models Removed: {models_removed}")
    print(f"  Config Files Removed: {config_removed}")
    print(f"  Temporary Files Removed: {temp_removed}")
    print(f"  VS Code Extension Removed: {'Yes' if vscode_removed else 'No'}")
    print(f"  IntelliJ Plugin Removed: {'Yes' if intellij_removed else 'No'}")
    print()
    
    print(ui.colorize("━" * 60, ui.Colors.DIM))
    print(ui.colorize("Note:", ui.Colors.YELLOW + ui.Colors.BOLD))
    print()
    print("  • Docker Desktop and Docker Model Runner were not uninstalled")
    print("  • Pre-existing models were kept")
    print("  • You can reinstall by running docker-llm-setup.py again")
    print()
