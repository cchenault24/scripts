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
# Include both direct paths and macOS private paths (e.g., /etc -> /private/etc)
UNSAFE_PATHS = [
    "/usr/", "/System/", "/bin/", "/sbin/",
    "/Library/", "/Applications/",
    "/dev/", "/proc/", "/sys/",
    "/etc/", "/var/", "/opt/",
    "/private/etc/", "/private/var/", "/private/usr/",  # macOS symlink targets
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


def handle_ide_processes(running: Dict[str, List[str]]) -> bool:
    """
    Handle IDE processes only (not Ollama - we need it for model removal).
    
    Returns:
        True if safe to proceed, False to abort
    """
    if not any(running.values()):
        return True  # Nothing running
    
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
    
    if choice == 2:  # Cancel
        return False
    elif choice == 1:  # Manual
        ui.print_info("Please stop the processes manually, then run uninstaller again")
        return False
    else:  # Stop IDEs only
        return stop_ide_processes_gracefully(running)


def handle_running_processes(running: Dict[str, List[str]]) -> bool:
    """
    Handle running processes with user guidance.
    
    NOTE: This function is kept for backward compatibility but should not be used
    for uninstall flow. Use handle_ide_processes() instead.
    
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


def stop_ide_processes_gracefully(running: Dict[str, List[str]]) -> bool:
    """Stop IDE processes only (not Ollama)."""
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
    
    return True


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


def normalize_model_name(model_name: str) -> str:
    """
    Normalize model name for comparison.
    
    Handles tags like:
    - codellama:7b -> codellama:7b
    - codellama:7b-latest -> codellama:7b
    - codellama:7b-v0.1 -> codellama:7b
    
    Returns base model name with tag (without version suffixes).
    """
    if not model_name:
        return ""
    
    # Split on colon to separate model name and tag
    if ":" in model_name:
        base, tag = model_name.split(":", 1)
        # Remove version suffixes from tag (e.g., -latest, -v0.1, -q4_K_M)
        # Keep only the main tag part (e.g., 7b, 13b, 22b)
        tag_parts = tag.split("-")
        if tag_parts:
            # Keep the first part which is usually the size tag
            normalized_tag = tag_parts[0]
            return f"{base}:{normalized_tag}"
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
    
    # First check normalized versions to handle tag variations correctly
    # This distinguishes between different model sizes (e.g., 7b vs 13b)
    norm1 = normalize_model_name(model1)
    norm2 = normalize_model_name(model2)
    if norm1 == norm2:
        return True
    
    # If normalized names don't match, check base names for cases like:
    # nomic-embed-text vs nomic-embed-text:latest (where tag doesn't matter)
    base1 = model1.split(":")[0] if ":" in model1 else model1
    base2 = model2.split(":")[0] if ":" in model2 else model2
    
    # Only return True if base names match AND at least one has no tag
    # This handles cases like "nomic-embed-text" vs "nomic-embed-text:latest"
    if base1 == base2:
        # If both have tags and normalized names differ, they're different models
        has_tag1 = ":" in model1
        has_tag2 = ":" in model2
        if has_tag1 and has_tag2:
            # Both have tags but normalized names differ - different models
            return False
        # At least one has no tag - same model (tag is just a variant)
        return True
    
    return False


def get_installed_models() -> List[str]:
    """Get list of currently installed Ollama models."""
    code, stdout, stderr = utils.run_command(["ollama", "list"], timeout=10, clean_env=True)
    if code != 0:
        _logger.warning(f"Failed to list Ollama models: {stderr}")
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
    code, stdout, stderr = utils.run_command(["ollama", "rm", model_name], timeout=600, clean_env=True)
    if code != 0:
        _logger.warning(f"Failed to remove model {model_name}: {stderr}")
    return code == 0


def ensure_ollama_running_for_removal() -> bool:
    """
    Ensure Ollama service is running for model removal operations.
    
    Returns:
        True if Ollama is running (or was started), False if cannot start
    """
    from . import ollama
    
    # Check if Ollama is already running
    if ollama.verify_ollama_running():
        return True
    
    # Try to start Ollama
    ui.print_info("Ollama service is not running. Starting it for model removal...")
    if ollama.start_ollama_service():
        ui.print_success("Ollama service started")
        return True
    else:
        ui.print_error("Could not start Ollama service")
        ui.print_info("Model removal requires Ollama to be running")
        ui.print_info("Please start Ollama manually: ollama serve")
        return False


def find_actual_model_name(manifest_model_name: str, installed_models: List[str]) -> Optional[str]:
    """
    Find the actual model name in Ollama that matches the manifest model name.
    
    Handles cases where manifest has 'nomic-embed-text' but Ollama has 'nomic-embed-text:latest'.
    
    Returns:
        The actual model name from installed_models, or None if not found
    """
    # First try exact match
    if manifest_model_name in installed_models:
        return manifest_model_name
    
    # Try to find by base name (handles tag variations)
    # Handle cases like "test:model" vs "test:model:latest"
    manifest_base = manifest_model_name.split(":")[0] if ":" in manifest_model_name else manifest_model_name
    
    for installed_model in installed_models:
        installed_base = installed_model.split(":")[0] if ":" in installed_model else installed_model
        if manifest_base == installed_base:
            # Check if they overlap (same model, different tags)
            if models_overlap(manifest_model_name, installed_model):
                return installed_model
            # Also check if installed model starts with manifest model name
            # (handles "test:model" vs "test:model:latest")
            if installed_model.startswith(manifest_model_name + ":"):
                return installed_model
    
    return None


def remove_models(model_names: List[str]) -> int:
    """
    Remove multiple Ollama models, returns count removed.
    
    First queries `ollama list` to get actual installed models, then matches
    manifest model names to actual names and removes them using the exact names
    from `ollama list`.
    
    Ensures Ollama service is running before attempting removal.
    """
    if not model_names:
        return 0
    
    # Ensure Ollama is running (required for model removal)
    if not ensure_ollama_running_for_removal():
        ui.print_warning("Cannot remove models - Ollama service is not available")
        return 0
    
    # Get actual installed models from Ollama (run ollama list)
    installed_models = get_installed_models()
    if not installed_models:
        ui.print_warning("No models found in Ollama - cannot remove models")
        _logger.warning("get_installed_models() returned empty list")
        return 0
    
    # Match manifest model names to actual installed model names
    models_to_remove = []
    not_found = []
    
    for manifest_model_name in model_names:
        actual_name = find_actual_model_name(manifest_model_name, installed_models)
        if actual_name:
            models_to_remove.append(actual_name)
        else:
            not_found.append(manifest_model_name)
            _logger.warning(f"Could not find actual model name for manifest model: {manifest_model_name}")
            ui.print_warning(f"Model '{manifest_model_name}' not found in installed models")
    
    if not models_to_remove:
        ui.print_warning("No matching models found to remove")
        _logger.warning(f"None of the requested models ({model_names}) matched installed models ({installed_models})")
        return 0
    
    # Remove the matched models using their actual names from ollama list
    removed = 0
    for i, model in enumerate(models_to_remove, 1):
        ui.print_info(f"[{i}/{len(models_to_remove)}] Removing {model}...")
        if remove_model(model):
            ui.print_success(f"Removed {model}")
            removed += 1
        else:
            ui.print_error(f"Failed to remove {model}")
            _logger.error(f"Failed to remove model: {model}")
    
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
    intellij_removed: bool,
    autostart_removed: bool = False,
    ollama_removed: bool = False
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
    print(f"  Auto-Start Removed: {'Yes' if autostart_removed else 'No'}")
    print(f"  Ollama Application Removed: {'Yes' if ollama_removed else 'No'}")
    print()
    
    print(ui.colorize("━" * 60, ui.Colors.DIM))
    print(ui.colorize("Note:", ui.Colors.YELLOW + ui.Colors.BOLD))
    print()
    if ollama_removed:
        print("  • Ollama has been completely removed from your system")
        print("  • Pre-existing models were removed with Ollama")
        print("  • You can reinstall Ollama from https://ollama.com/download")
    else:
        print("  • Ollama itself was not uninstalled")
        print("  • Ollama Desktop app remains installed")
        print("  • Pre-existing models were kept")
    print("  • You can reinstall by running ollama-llm-setup.py again")
    print()
