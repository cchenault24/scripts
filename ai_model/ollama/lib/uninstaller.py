"""
Smart Uninstaller Module.

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
        "pattern": "ollama-setup-*",
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
            "ollama_available": False,
            "target_ides": []
        }
    }


def is_safe_location(path: Path) -> bool:
    """Check if location is safe to scan."""
    path_str = str(path.resolve())
    return not any(path_str.startswith(unsafe) for unsafe in UNSAFE_PATHS)


def scan_for_orphaned_files(manifest: Dict[str, Any]) -> List[Tuple[Path, str]]:
    """
    Scan for files created by installer but not in manifest.
    
    Security: Prevents symlink escapes by checking resolved paths stay within root.
    Performance: Pre-builds manifest path set to avoid O(n²) lookups.
    
    Returns:
        List of tuples (filepath, status) where status is "certain" or "uncertain"
    """
    orphaned: List[Tuple[Path, str]] = []
    files_scanned = 0
    start_time = time.time()
    
    # Pre-build set of manifest paths for O(1) lookup (fixes O(n²) issue)
    manifest_paths: Set[str] = set(
        f["path"] for f in manifest.get("installed", {}).get("files", [])
    )
    
    for location, scan_config in SCAN_CONFIG.items():
        location_path = Path(location).expanduser()
        
        if not location_path.exists():
            continue
        
        # Resolve root once for symlink escape prevention
        try:
            root_resolved = location_path.resolve()
        except (OSError, RuntimeError):
            ui.print_warning(f"Cannot resolve path: {location}")
            continue
        
        # Safety check
        if not is_safe_location(root_resolved):
            ui.print_warning(f"Skipping unsafe location: {location}")
            continue
        
        try:
            if scan_config.get("recursive"):
                files = location_path.rglob("*")
            else:
                pattern = scan_config.get("pattern", "*")
                files = location_path.glob(pattern)
            
            for filepath in files:
                # Safety limits
                if files_scanned >= MAX_FILES_SCANNED:
                    ui.print_warning(f"Reached scan limit at {location}")
                    break
                
                if time.time() - start_time > SCAN_TIMEOUT_SECONDS:
                    ui.print_warning(f"Scan timeout at {location}")
                    break
                
                if not filepath.is_file():
                    continue
                
                files_scanned += 1
                
                # Symlink escape prevention: ensure resolved path is under root
                try:
                    resolved_path = filepath.resolve()
                    # Check if resolved path is under the root directory
                    try:
                        resolved_path.relative_to(root_resolved)
                    except ValueError:
                        # Path escapes root via symlink - skip with warning
                        _logger.debug(f"Skipping symlink escape: {filepath} -> {resolved_path}")
                        continue
                except (OSError, RuntimeError):
                    continue
                
                # Skip if already in manifest (O(1) lookup now)
                if str(filepath) in manifest_paths:
                    continue
                
                # Check if it's ours
                status = config_module.is_our_file(filepath, manifest)
                if status is True:
                    orphaned.append((filepath, "certain"))
                elif status == "maybe":
                    orphaned.append((filepath, "uncertain"))
        
        except (OSError, IOError, PermissionError) as e:
            ui.print_warning(f"Error scanning {location}: {e}")
            continue
    
    return orphaned


def check_running_processes(manifest: Dict[str, Any]) -> Dict[str, List[str]]:
    """Detect processes related to our setup."""
    running = {
        "ollama_serve": [],
        "vscode": [],
        "intellij": [],
        "model_servers": []
    }
    
    # Check Ollama service
    code, _, _ = utils.run_command(["pgrep", "-f", "ollama serve"], timeout=PROCESS_TIMEOUT)
    if code == 0:
        running["ollama_serve"] = ["Ollama service"]
    
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
    
    # Check for active models via Ollama API
    try:
        req = urllib.request.Request("http://localhost:11434/api/ps", method="GET")
        with urllib.request.urlopen(req, timeout=2, context=get_unverified_ssl_context()) as response:
            if response.status == 200:
                data = json.loads(response.read())
                if data.get("models"):
                    running["model_servers"] = [m.get("name", "unknown") for m in data["models"]]
    except (urllib.error.URLError, urllib.error.HTTPError, json.JSONDecodeError, OSError, TimeoutError) as e:
        # API not available or returned invalid data - no active models
        # Log for debugging but don't fail
        _logger.debug(f"Failed to check active models via Ollama API: {type(e).__name__}: {e}")
    
    return running


def handle_running_processes(running: Dict[str, List[str]]) -> bool:
    """
    Handle running processes with user guidance.
    
    Returns:
        True if safe to proceed, False to abort
    """
    if not any(running.values()):
        return True  # Nothing running
    
    ui.print_warning("Found active processes related to this setup:")
    print()
    
    for process_type, processes in running.items():
        if processes:
            if process_type == "model_servers":
                print(f"  • Active models: {', '.join(processes)}")
            else:
                print(f"  • {process_type}: {', '.join(processes)}")
    
    print()
    ui.print_info("Recommendation:")
    if running.get("vscode") or running.get("intellij"):
        print("  1. Save your work in IDE")
        print("  2. Close IDE to uninstall extensions")
    if running.get("model_servers"):
        print("  3. Stop using models (close Continue.dev)")
    if running.get("ollama_serve"):
        print("  4. Ollama service will be stopped")
    print()
    
    choices = ["Stop processes and continue", "Let me handle it manually", "Cancel uninstall"]
    choice = ui.prompt_choice("How would you like to proceed?", choices, default=1)
    
    if choice == 2:  # Cancel
        return False
    elif choice == 1:  # Manual
        ui.print_info("Please stop the processes manually, then run uninstaller again")
        return False
    else:  # Stop all
        return stop_processes_gracefully(running)


def stop_processes_gracefully(running: Dict[str, List[str]]) -> bool:
    """Stop processes with grace period."""
    # IDEs - ask user to close manually
    if running.get("vscode") or running.get("intellij"):
        ui.print_warning("Please close your IDE(s) manually to avoid losing unsaved work")
        print()
        for ide_name in ["vscode", "intellij"]:
            if running.get(ide_name):
                display_name = "VS Code" if ide_name == "vscode" else "IntelliJ IDEA"
                if not ui.prompt_yes_no(f"Have you closed {display_name}?", default=False):
                    ui.print_info("Uninstall cancelled. Close IDE and try again.")
                    return False
    
    # Ollama service
    if running.get("ollama_serve"):
        ui.print_info("Stopping Ollama service...")
        utils.run_command(["pkill", "ollama"], timeout=PROCESS_TIMEOUT)
        time.sleep(2)
        ui.print_success("Ollama stopped")
    
    return True


def handle_config_removal(config_path: Path, manifest: Dict[str, Any]) -> bool:
    """
    Handle config file removal with customization detection.
    
    Returns:
        True if file was removed/handled, False if kept
    """
    status = config_module.check_config_customization(config_path, manifest)
    
    if status == "missing":
        ui.print_info(f"{config_path.name} already removed")
        return True
    
    elif status == "modified":
        ui.print_warning(f"{config_path.name} has been customized by you")
        print()
        
        choices = [
            "Remove (lose customizations)",
            "Create backup then remove",
            "Keep file"
        ]
        
        # Check if backup exists
        backups = manifest.get("pre_existing", {}).get("backups", {})
        for key, backup_path_str in backups.items():
            if Path(backup_path_str).exists():
                choices.insert(1, "Restore original backup")
                break
        
        choice = ui.prompt_choice(
            f"What would you like to do with {config_path.name}?",
            choices,
            default=len(choices) - 1  # Default to keep
        )
        
        if choice == len(choices) - 1:  # Keep
            ui.print_info(f"Keeping {config_path.name}")
            return False
        
        elif "Create backup" in choices[choice]:
            # Create backup
            timestamp = int(time.time())
            backup = config_path.with_suffix(f".pre-uninstall-{timestamp}{config_path.suffix}")
            shutil.copy(config_path, backup)
            ui.print_success(f"Backup created: {backup.name}")
            config_path.unlink()
            ui.print_success(f"Removed {config_path.name}")
            return True
        
        elif "Restore original backup" in choices[choice]:
            # Find and restore backup
            for key, backup_path_str in backups.items():
                backup_path = Path(backup_path_str)
                if backup_path.exists():
                    shutil.copy(backup_path, config_path)
                    ui.print_success(f"Restored original config from backup")
                    break
            return True
        
        else:  # Remove
            config_path.unlink()
            ui.print_success(f"Removed {config_path.name}")
            return True
    
    elif status == "unknown":
        ui.print_warning(f"{config_path.name} was not created by our installer")
        if ui.prompt_yes_no(f"Remove anyway?", default=False):
            config_path.unlink()
            ui.print_success(f"Removed {config_path.name}")
            return True
        return False
    
    else:  # unchanged
        if ui.prompt_yes_no(f"Remove {config_path.name}?", default=True):
            config_path.unlink()
            ui.print_success(f"Removed {config_path.name}")
            return True
        return False


def get_installed_models() -> List[str]:
    """Get list of currently installed Ollama models."""
    code, stdout, _ = utils.run_command(["ollama", "list"], timeout=10)
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
    """Remove a single Ollama model."""
    code, stdout, stderr = utils.run_command(["ollama", "rm", model_name], timeout=600)
    if code == 0:
        return True
    else:
        ui.print_error(f"Failed to remove {model_name}: {stderr or stdout}")
        return False


def remove_models(model_names: List[str]) -> int:
    """Remove multiple Ollama models, returns count removed."""
    if not model_names:
        return 0
    
    removed = 0
    for i, model in enumerate(model_names, 1):
        print(f"[{i}/{len(model_names)}] Removing {model}...")
        if remove_model(model):
            ui.print_success(f"Removed {model}")
            removed += 1
        else:
            ui.print_warning(f"Could not remove {model}")
    
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
        ui.print_warning("VS Code CLI not found. Cannot uninstall extension automatically.")
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
    else:  # Windows
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
    
    # Check VS Code
    if check_vscode_extension_installed():
        ui.print_subheader("VS Code Extension")
        ui.print_info("VS Code Continue.dev extension is installed")
        ui.print_info("(Extension can be used with other LLM providers like Claude API)")
        print()
        
        if ui.prompt_yes_no("Remove Continue.dev extension from VS Code?", default=False):
            removed["vscode"] = uninstall_vscode_extension()
        else:
            ui.print_info("Keeping VS Code extension")
    else:
        ui.print_info("VS Code Continue.dev extension not installed")
    
    print()
    
    # Check IntelliJ
    is_installed, _ = check_intellij_plugin_installed()
    if is_installed:
        ui.print_subheader("IntelliJ IDEA Plugin")
        ui.print_info("IntelliJ Continue plugin is installed")
        ui.print_info("(Plugin can be used with other LLM providers)")
        print()
        
        if ui.prompt_yes_no("Remove Continue plugin from IntelliJ IDEA?", default=False):
            removed["intellij"] = uninstall_intellij_plugin()
        else:
            ui.print_info("Keeping IntelliJ plugin")
    else:
        ui.print_info("IntelliJ Continue plugin not installed")
    
    return removed


def show_uninstall_summary(
    models_removed: int,
    config_removed: int,
    temp_removed: int,
    vscode_removed: bool,
    intellij_removed: bool
) -> None:
    """Show uninstallation summary."""
    ui.print_header("✅ Uninstallation Complete!")
    
    print(ui.colorize("Summary:", ui.Colors.GREEN + ui.Colors.BOLD))
    print()
    
    print(f"  Ollama Models Removed: {models_removed}")
    print(f"  Config Files Removed: {config_removed}")
    print(f"  Temporary Files Removed: {temp_removed}")
    print(f"  VS Code Extension Removed: {'Yes' if vscode_removed else 'No'}")
    print(f"  IntelliJ Plugin Removed: {'Yes' if intellij_removed else 'No'}")
    print()
    
    print(ui.colorize("━" * 60, ui.Colors.DIM))
    print(ui.colorize("Note:", ui.Colors.YELLOW + ui.Colors.BOLD))
    print()
    print("  • Ollama itself is not uninstalled")
    print("  • Pre-existing models were kept")
    print("  • You can reinstall by running ollama-llm-setup.py again")
    print()
