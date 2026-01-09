#!/usr/bin/env python3
"""
Docker Model Runner + Continue.dev Uninstaller

An interactive Python script that helps you uninstall components set up by
docker-llm-setup.py, including:
- Docker Model Runner models
- Continue.dev configuration files
- VS Code Continue.dev extension (optional)
- IntelliJ IDEA Continue plugin (optional)

Author: AI-Generated for Local LLM Development
License: MIT
"""

import json
import os
import platform
import shutil
import signal
import subprocess
import sys
from pathlib import Path
from typing import List, Optional, Tuple

# ANSI color codes for terminal output
class Colors:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RED = "\033[91m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    BLUE = "\033[94m"
    MAGENTA = "\033[95m"
    CYAN = "\033[96m"
    WHITE = "\033[97m"


def colorize(text: str, color: str) -> str:
    """Apply color to text."""
    return f"{color}{text}{Colors.RESET}"


def print_header(text: str) -> None:
    """Print a styled header."""
    width = max(60, len(text) + 10)
    print()
    print(colorize("═" * width, Colors.CYAN))
    print(colorize(f"  {text}", Colors.CYAN + Colors.BOLD))
    print(colorize("═" * width, Colors.CYAN))
    print()


def print_subheader(text: str) -> None:
    """Print a styled subheader."""
    print()
    print(colorize(f"▸ {text}", Colors.BLUE + Colors.BOLD))
    print(colorize("─" * 50, Colors.DIM))


def print_success(text: str) -> None:
    """Print success message."""
    print(colorize(f"✓ {text}", Colors.GREEN))


def print_error(text: str) -> None:
    """Print error message."""
    print(colorize(f"✗ {text}", Colors.RED))


def print_warning(text: str) -> None:
    """Print warning message."""
    print(colorize(f"⚠ {text}", Colors.YELLOW))


def print_info(text: str) -> None:
    """Print info message."""
    print(colorize(f"ℹ {text}", Colors.BLUE))


def clear_screen() -> None:
    """Clear the terminal screen."""
    os.system("cls" if platform.system() == "Windows" else "clear")


def prompt_yes_no(question: str, default: bool = True) -> bool:
    """Prompt user for yes/no answer."""
    suffix = "[Y/n]" if default else "[y/N]"
    while True:
        response = input(f"{colorize('?', Colors.CYAN)} {question} {colorize(suffix, Colors.DIM)}: ").strip().lower()
        if not response:
            return default
        if response in ("y", "yes"):
            return True
        if response in ("n", "no"):
            return False
        print_warning("Please enter 'y' or 'n'")


def prompt_choice(question: str, choices: List[str], default: int = 0) -> int:
    """Prompt user to select from choices."""
    print(f"\n{colorize('?', Colors.CYAN)} {question}")
    for i, choice in enumerate(choices):
        marker = colorize("●", Colors.GREEN) if i == default else colorize("○", Colors.DIM)
        print(f"  {marker} [{i + 1}] {choice}")
    
    while True:
        response = input(f"\n  Enter choice (1-{len(choices)}) [{default + 1}]: ").strip()
        if not response:
            return default
        try:
            idx = int(response) - 1
            if 0 <= idx < len(choices):
                return idx
        except ValueError:
            pass
        print_warning(f"Please enter a number between 1 and {len(choices)}")


def prompt_multi_choice(question: str, choices: List[str], min_selections: int = 0) -> List[int]:
    """Prompt user to select multiple choices."""
    selected = []
    
    while True:
        print(f"\n{colorize('?', Colors.CYAN)} {question}")
        print(colorize("  (Enter numbers separated by commas, or 'a' for all, 'n' for none)", Colors.DIM))
        
        for i, choice in enumerate(choices):
            marker = colorize("●", Colors.GREEN) if i in selected else colorize("○", Colors.DIM)
            print(f"  {marker} [{i + 1}] {choice}")
        
        response = input(f"\n  Selection [{','.join(str(i+1) for i in selected) or 'none'}]: ").strip().lower()
        
        if not response:
            if len(selected) >= min_selections:
                return selected
            print_warning(f"Please select at least {min_selections} option(s)")
            continue
        
        if response == "a":
            return list(range(len(choices)))
        if response == "n":
            if min_selections == 0:
                return []
            print_warning(f"Please select at least {min_selections} option(s)")
            continue
        
        try:
            new_selected = []
            for part in response.split(","):
                part = part.strip()
                if "-" in part:
                    start, end = map(int, part.split("-"))
                    new_selected.extend(range(start - 1, end))
                else:
                    new_selected.append(int(part) - 1)
            
            new_selected = [i for i in new_selected if 0 <= i < len(choices)]
            if len(new_selected) >= min_selections:
                return list(set(new_selected))
            print_warning(f"Please select at least {min_selections} option(s)")
        except ValueError:
            print_warning("Invalid input. Enter numbers separated by commas")


def run_command(cmd: List[str], capture: bool = True, timeout: int = 300, show_progress: bool = False) -> Tuple[int, str, str]:
    """Run a shell command and return (returncode, stdout, stderr).
    Uses aggressive timeout handling to prevent hanging."""
    process = None
    try:
        # Use Popen for better timeout control
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        
        try:
            stdout, stderr = process.communicate(timeout=timeout)
            return process.returncode, stdout or "", stderr or ""
        except subprocess.TimeoutExpired:
            # Force kill the process aggressively
            if process is not None:
                try:
                    process.kill()
                except (OSError, ProcessLookupError):
                    pass
                # On Unix, try SIGTERM then SIGKILL
                if platform.system() != "Windows" and process.pid:
                    try:
                        os.kill(process.pid, signal.SIGTERM)
                        import time
                        time.sleep(0.1)
                    except (OSError, ProcessLookupError):
                        pass
                    try:
                        os.kill(process.pid, signal.SIGKILL)
                    except (OSError, ProcessLookupError):
                        pass
                try:
                    process.wait(timeout=1)
                except (subprocess.TimeoutExpired, OSError):
                    pass
            return -1, "", "Command timed out"
    except FileNotFoundError:
        return -1, "", f"Command not found: {cmd[0]}"
    except Exception as e:
        return -1, "", str(e)
    finally:
        # Ensure process is cleaned up even if unexpected exception occurs
        if process is not None:
            try:
                # Check if process is still running
                if process.poll() is None:
                    # Process is still running, terminate it
                    try:
                        process.terminate()
                        process.wait(timeout=2)
                    except (subprocess.TimeoutExpired, OSError, ProcessLookupError):
                        # Force kill if it doesn't terminate gracefully
                        try:
                            process.kill()
                            process.wait(timeout=1)
                        except (subprocess.TimeoutExpired, OSError, ProcessLookupError):
                            pass
            except (OSError, ProcessLookupError):
                # Process may already be terminated, ignore
                pass


def check_docker() -> Tuple[bool, str]:
    """Check if Docker is installed and running. Returns (success, message)."""
    if not shutil.which("docker"):
        return False, "Docker command not found"
    
    # Use shorter timeout for quick check
    code, _, stderr = run_command(["docker", "info"], timeout=5, show_progress=False)
    if code == 0:
        return True, "Docker is running"
    elif "Cannot connect" in stderr or "Is the docker daemon running" in stderr.lower():
        return False, "Docker daemon is not running"
    elif code == -1:
        return False, "Docker check timed out"
    else:
        return False, f"Docker check failed: {stderr[:100] if stderr else 'Unknown error'}"


def check_docker_model_runner() -> Tuple[bool, str]:
    """Check if Docker Model Runner is available. Returns (success, message)."""
    # Use shorter timeout for quick check
    code, _, stderr = run_command(["docker", "model", "list"], timeout=5, show_progress=False)
    if code == 0:
        return True, "Docker Model Runner is available"
    elif "unknown command" in stderr.lower() or "not found" in stderr.lower():
        return False, "Docker Model Runner is not enabled"
    elif code == -1:
        return False, "Docker Model Runner check timed out"
    else:
        return False, f"Docker Model Runner check failed: {stderr[:100] if stderr else 'Unknown error'}"


def list_docker_models() -> List[str]:
    """List all installed Docker models."""
    code, stdout, _ = run_command(["docker", "model", "list"], timeout=10, show_progress=False)
    if code != 0:
        return []
    
    models = []
    lines = stdout.strip().split("\n")
    if len(lines) > 1:  # Has models (first line is header)
        for line in lines[1:]:
            if line.strip():
                parts = line.split()
                if parts:
                    models.append(parts[0])
    
    return models


def remove_docker_model(model_name: str) -> bool:
    """Remove a Docker model."""
    code, stdout, stderr = run_command(["docker", "model", "rm", model_name], timeout=600)
    if code == 0:
        return True
    else:
        print_error(f"Failed to remove {model_name}: {stderr or stdout}")
        return False


def is_generated_config(config_path: Path) -> bool:
    """Check if a config file was generated by docker-llm-setup.py."""
    if not config_path.exists():
        return False
    
    try:
        with open(config_path, "r") as f:
            content = f.read()
            
            # For YAML files, check for signature comment
            if config_path.suffix in (".yaml", ".yml"):
                return "Generated by docker-llm-setup.py" in content or "Docker Model Runner" in content
            
            # For JSON files, check for Docker Model Runner API endpoint pattern
            elif config_path.suffix == ".json":
                # Check if it contains Docker Model Runner API endpoint
                # DMR typically uses localhost:12434 or model-runner.docker.internal
                return ("localhost:12434" in content or 
                        "model-runner.docker.internal" in content or
                        ":12434" in content)
            
            return False
    except Exception:
        return False


def get_config_files() -> Tuple[Optional[Path], Optional[Path], Optional[Path]]:
    """Get Continue.dev config file paths."""
    continue_dir = Path.home() / ".continue"
    config_yaml = continue_dir / "config.yaml"
    config_json = continue_dir / "config.json"
    backup_yaml = continue_dir / "config.yaml.backup"
    
    return config_yaml, config_json, backup_yaml


def uninstall_models(models: List[str]) -> int:
    """Uninstall Docker models."""
    if not models:
        print_info("No models to remove")
        return 0
    
    print_subheader("Removing Docker Models")
    print_info(f"Found {len(models)} model(s) to remove")
    print()
    
    removed = 0
    for i, model in enumerate(models, 1):
        print(f"[{i}/{len(models)}] Removing {model}...")
        if remove_docker_model(model):
            print_success(f"Removed {model}")
            removed += 1
        else:
            print_warning(f"Could not remove {model}")
        print()
    
    return removed


def uninstall_config_files(restore_backup: bool = False, warn_shared: bool = True) -> bool:
    """
    Uninstall Continue.dev config files.
    
    Args:
        restore_backup: Whether to restore backup before removing
        warn_shared: Whether to warn that config is shared between IDEs
    """
    print_subheader("Removing Continue.dev Configuration")
    
    if warn_shared:
        print_info("Note: Config files are shared between VS Code and IntelliJ IDEA")
        print()
    
    config_yaml, config_json, backup_yaml = get_config_files()
    
    removed_any = False
    
    # Check and remove config.yaml
    if config_yaml and config_yaml.exists():
        if is_generated_config(config_yaml):
            if restore_backup and backup_yaml and backup_yaml.exists():
                print_info(f"Restoring backup: {backup_yaml}")
                try:
                    shutil.copy(backup_yaml, config_yaml)
                    print_success(f"Restored backup to {config_yaml}")
                    removed_any = True
                except Exception as e:
                    print_error(f"Failed to restore backup: {e}")
                    if prompt_yes_no("Remove config.yaml anyway?", default=True):
                        try:
                            config_yaml.unlink()
                            print_success(f"Removed {config_yaml}")
                            removed_any = True
                        except Exception as e:
                            print_error(f"Failed to remove: {e}")
            else:
                try:
                    config_yaml.unlink()
                    print_success(f"Removed {config_yaml}")
                    removed_any = True
                except Exception as e:
                    print_error(f"Failed to remove {config_yaml}: {e}")
        else:
            print_warning(f"{config_yaml} exists but doesn't appear to be generated by docker-llm-setup.py")
            if prompt_yes_no("Remove it anyway?", default=False):
                try:
                    config_yaml.unlink()
                    print_success(f"Removed {config_yaml}")
                    removed_any = True
                except Exception as e:
                    print_error(f"Failed to remove: {e}")
    
    # Check and remove config.json
    if config_json and config_json.exists():
        if is_generated_config(config_json):
            try:
                config_json.unlink()
                print_success(f"Removed {config_json}")
                removed_any = True
            except Exception as e:
                print_error(f"Failed to remove {config_json}: {e}")
        else:
            print_warning(f"{config_json} exists but doesn't appear to be generated by docker-llm-setup.py")
            if prompt_yes_no("Remove it anyway?", default=False):
                try:
                    config_json.unlink()
                    print_success(f"Removed {config_json}")
                    removed_any = True
                except Exception as e:
                    print_error(f"Failed to remove: {e}")
    
    # Remove backup if it exists and we're not restoring
    if backup_yaml and backup_yaml.exists() and not restore_backup:
        if prompt_yes_no(f"Remove backup file {backup_yaml}?", default=False):
            try:
                backup_yaml.unlink()
                print_success(f"Removed {backup_yaml}")
            except Exception as e:
                print_error(f"Failed to remove backup: {e}")
    
    if not removed_any:
        print_info("No config files found to remove")
    
    return removed_any


def check_vscode_extension_installed() -> bool:
    """Check if VS Code Continue.dev extension is installed."""
    code_path = shutil.which("code")
    if not code_path:
        return False
    
    code, stdout, _ = run_command(["code", "--list-extensions"], timeout=10)
    if code != 0:
        return False
    
    return "Continue.continue" in stdout


def check_intellij_plugin_installed() -> Tuple[bool, List[Path]]:
    """
    Check if IntelliJ Continue plugin is installed.
    
    Returns:
        Tuple of (is_installed, list of plugin paths found)
    """
    plugin_paths = []
    
    # Check common plugin directories based on OS
    if platform.system() == "Darwin":
        base_dirs = [
            Path.home() / "Library/Application Support/JetBrains",
        ]
    elif platform.system() == "Linux":
        base_dirs = [
            Path.home() / ".local/share/JetBrains",
        ]
    else:  # Windows
        appdata = os.getenv("APPDATA", "")
        if appdata:
            base_dirs = [Path(appdata) / "JetBrains"]
        else:
            base_dirs = []
    
    for base_dir in base_dirs:
        if base_dir.exists():
            # Search for Continue plugin in any JetBrains product
            for product_dir in base_dir.iterdir():
                if product_dir.is_dir():
                    plugins_dir = product_dir / "plugins"
                    if plugins_dir.exists():
                        continue_plugin = plugins_dir / "Continue"
                        if continue_plugin.exists():
                            plugin_paths.append(continue_plugin)
    
    return len(plugin_paths) > 0, plugin_paths


def check_intellij_running() -> bool:
    """Check if IntelliJ IDEA is currently running."""
    if platform.system() == "Darwin":
        code, _, _ = run_command(["pgrep", "-f", "IntelliJ IDEA"], timeout=5)
        return code == 0
    elif platform.system() == "Linux":
        code, _, _ = run_command(["pgrep", "-f", "idea"], timeout=5)
        return code == 0
    else:  # Windows
        code, _, _ = run_command(["tasklist", "/FI", "IMAGENAME eq idea64.exe"], timeout=5)
        return code == 0


def uninstall_vscode_extension() -> bool:
    """Uninstall Continue.dev VS Code extension."""
    print_subheader("Removing VS Code Extension")
    
    code_path = shutil.which("code")
    if not code_path:
        print_warning("VS Code CLI not found. Cannot uninstall extension automatically.")
        print_info("You can uninstall manually:")
        if platform.system() == "Darwin":
            print_info("  • Press Cmd+Shift+X → Search for 'Continue' → Click Uninstall")
        else:
            print_info("  • Press Ctrl+Shift+X → Search for 'Continue' → Click Uninstall")
        return False
    
    # Check if extension is installed
    if not check_vscode_extension_installed():
        print_info("Continue.dev extension is not installed")
        return False
    
    # Uninstall the extension
    extension_id = "Continue.continue"
    print_info(f"Uninstalling {extension_id}...")
    code, stdout, stderr = run_command(["code", "--uninstall-extension", extension_id], timeout=60)
    
    if code == 0:
        print_success("Extension uninstalled successfully")
        return True
    else:
        print_error(f"Failed to uninstall extension: {stderr or stdout}")
        print_info("You can uninstall manually:")
        if platform.system() == "Darwin":
            print_info("  • Press Cmd+Shift+X → Search for 'Continue' → Click Uninstall")
        else:
            print_info("  • Press Ctrl+Shift+X → Search for 'Continue' → Click Uninstall")
        return False


def uninstall_intellij_plugin() -> bool:
    """Uninstall Continue plugin from IntelliJ IDEA."""
    print_subheader("Removing IntelliJ IDEA Plugin")
    
    # Check if plugin is installed
    is_installed, plugin_paths = check_intellij_plugin_installed()
    if not is_installed:
        print_info("Continue plugin is not installed in IntelliJ IDEA")
        return False
    
    # Check if IntelliJ is running
    if check_intellij_running():
        print_warning("IntelliJ IDEA is currently running")
        print_info("Please close IntelliJ IDEA before uninstalling the plugin")
        if not prompt_yes_no("Continue anyway? (Plugin may not be fully removed)", default=False):
            return False
    
    # Try using IntelliJ CLI if available
    idea_path = shutil.which("idea")
    if not idea_path:
        # Check common installation paths
        if platform.system() == "Darwin":
            common_paths = [
                "/Applications/IntelliJ IDEA.app/Contents/MacOS/idea",
                "/Applications/IntelliJ IDEA Ultimate.app/Contents/MacOS/idea",
                "/Applications/IntelliJ IDEA Community Edition.app/Contents/MacOS/idea",
            ]
        elif platform.system() == "Linux":
            common_paths = [
                "/usr/local/bin/idea",
                str(Path.home() / ".local/share/JetBrains/Toolbox/scripts/idea"),
            ]
        else:  # Windows
            common_paths = [
                str(Path.home() / "AppData/Local/JetBrains/Toolbox/scripts/idea.bat"),
            ]
        
        for path in common_paths:
            if os.path.exists(path):
                idea_path = path
                break
    
    # Try CLI uninstallation (may not be supported in all versions)
    if idea_path:
        print_info("Attempting to uninstall via IntelliJ CLI...")
        # Note: IntelliJ CLI plugin management syntax varies by version
        # Try common patterns
        code, _, _ = run_command([idea_path, "uninstall-plugin", "Continue.continue"], timeout=30)
        if code == 0:
            print_success("Plugin uninstalled via CLI")
            return True
        # Try alternative syntax
        code, _, _ = run_command([idea_path, "--uninstall-plugin", "Continue.continue"], timeout=30)
        if code == 0:
            print_success("Plugin uninstalled via CLI")
            return True
    
    # Manual removal fallback - delete plugin directories
    print_info("Removing plugin directories manually...")
    removed_any = False
    for plugin_path in plugin_paths:
        try:
            if plugin_path.exists():
                shutil.rmtree(plugin_path)
                print_success(f"Removed plugin from {plugin_path.parent.parent.name}")
                removed_any = True
        except Exception as e:
            print_error(f"Failed to remove {plugin_path}: {e}")
    
    if removed_any:
        print_success("Plugin directories removed")
        print_info("Note: You may need to restart IntelliJ IDEA for changes to take effect")
        return True
    else:
        print_warning("Could not remove plugin automatically")
        print_info("You can uninstall manually:")
        if platform.system() == "Darwin":
            print_info("  • Open IntelliJ IDEA")
            print_info("  • Preferences → Plugins (or Cmd+, then Plugins)")
            print_info("  • Search for 'Continue' → Click Uninstall")
        else:
            print_info("  • Open IntelliJ IDEA")
            print_info("  • Settings → Plugins (or Ctrl+Alt+S then Plugins)")
            print_info("  • Search for 'Continue' → Click Uninstall")
        return False


def show_summary(
    models_removed: int, 
    config_removed: bool, 
    vscode_removed: bool,
    intellij_removed: bool
) -> None:
    """Show uninstallation summary."""
    print_header("✅ Uninstallation Complete!")
    
    print(colorize("Summary:", Colors.GREEN + Colors.BOLD))
    print()
    
    print(f"  Docker Models Removed: {models_removed}")
    print(f"  Config Files Removed: {'Yes' if config_removed else 'No'}")
    print(f"  VS Code Extension Removed: {'Yes' if vscode_removed else 'No'}")
    print(f"  IntelliJ Plugin Removed: {'Yes' if intellij_removed else 'No'}")
    print()
    
    print(colorize("━" * 60, Colors.DIM))
    print(colorize("Note:", Colors.YELLOW + Colors.BOLD))
    print()
    print("  • Docker Model Runner itself is not uninstalled")
    print("  • Docker Desktop remains installed")
    print("  • You can reinstall by running docker-llm-setup.py again")
    print()


def main() -> int:
    """Main entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Uninstall Docker Model Runner + Continue.dev setup",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--skip-docker-checks",
        action="store_true",
        help="Skip Docker and Docker Model Runner checks (useful if Docker is hanging)"
    )
    parser.add_argument(
        "--skip-models",
        action="store_true",
        help="Skip Docker model removal"
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
    
    clear_screen()
    
    print_header("🗑️  Docker Model Runner + Continue.dev Uninstaller")
    print_info("This script will help you remove components installed by docker-llm-setup.py")
    print()
    
    if not prompt_yes_no("Ready to begin uninstallation?", default=True):
        print_info("Uninstallation cancelled.")
        return 0
    
    # Check Docker (with option to skip if hanging)
    if args.skip_docker_checks:
        print()
        print_subheader("Checking Docker")
        print_warning("Skipping Docker checks (--skip-docker-checks flag used)")
        docker_ok = False
        dmr_available = False
    else:
        print()
        print_subheader("Checking Docker")
        print_info("Checking Docker status (this may take a few seconds)...")
        try:
            docker_ok, docker_msg = check_docker()
            if docker_ok:
                print_success(docker_msg)
            else:
                print_warning(docker_msg)
                print_info("Some operations may be skipped")
        except KeyboardInterrupt:
            print()
            print_warning("Docker check interrupted")
            if prompt_yes_no("Skip Docker checks and continue?", default=True):
                docker_ok = False
                docker_msg = "Skipped"
            else:
                print_info("Uninstallation cancelled.")
                return 0
        
        # Check Docker Model Runner (with option to skip if hanging)
        if docker_ok:
            print_info("Checking Docker Model Runner...")
            try:
                dmr_available, dmr_msg = check_docker_model_runner()
                if dmr_available:
                    print_success(dmr_msg)
                else:
                    print_warning(dmr_msg)
                    print_info("Model removal will be skipped")
            except KeyboardInterrupt:
                print()
                print_warning("Docker Model Runner check interrupted")
                if prompt_yes_no("Skip Docker Model Runner checks and continue?", default=True):
                    dmr_available = False
                    dmr_msg = "Skipped"
                else:
                    print_info("Uninstallation cancelled.")
                    return 0
        else:
            dmr_available = False
            dmr_msg = "Docker not available"
    
    # Step 1: Remove Docker models
    models_removed = 0
    if args.skip_models:
        print()
        print_subheader("Docker Models")
        print_warning("Skipping Docker model removal (--skip-models flag used)")
    elif dmr_available:
        print()
        print_subheader("Docker Models")
        models = list_docker_models()
        
        if models:
            print_info(f"Found {len(models)} installed model(s):")
            for model in models:
                print(f"  • {model}")
            print()
            
            choice = prompt_choice(
                "What would you like to do with Docker models?",
                ["Remove all models", "Select models to remove", "Keep all models"],
                default=0
            )
            
            if choice == 0:  # Remove all
                if prompt_yes_no("Remove all Docker models?", default=False):
                    models_removed = uninstall_models(models)
            elif choice == 1:  # Select
                if models:
                    selected_indices = prompt_multi_choice(
                        "Select models to remove:",
                        models,
                        min_selections=0
                    )
                    if selected_indices:
                        selected_models = [models[i] for i in selected_indices]
                        if prompt_yes_no(f"Remove {len(selected_models)} selected model(s)?", default=False):
                            models_removed = uninstall_models(selected_models)
            else:  # Keep all
                print_info("Keeping all Docker models")
        else:
            print_info("No Docker models found")
    else:
        print()
        print_subheader("Docker Models")
        print_info("Docker Model Runner not available - skipping model removal")
    
    # Step 2: Remove config files
    config_removed = False
    if args.skip_config:
        print()
        print_subheader("Continue.dev Configuration Files")
        print_warning("Skipping config file removal (--skip-config flag used)")
    else:
        print()
        config_yaml, config_json, backup_yaml = get_config_files()
        config_exists = (config_yaml and config_yaml.exists()) or (config_json and config_json.exists())
        
        if config_exists:
            print_subheader("Continue.dev Configuration Files")
            
            if config_yaml and config_yaml.exists():
                print_info(f"Found: {config_yaml}")
            if config_json and config_json.exists():
                print_info(f"Found: {config_json}")
            if backup_yaml and backup_yaml.exists():
                print_info(f"Backup available: {backup_yaml}")
            print()
            
            # Check if both IDEs might be using the config
            vscode_has_extension = check_vscode_extension_installed()
            intellij_has_plugin, _ = check_intellij_plugin_installed()
            
            if vscode_has_extension or intellij_has_plugin:
                print_warning("Config files are shared between VS Code and IntelliJ IDEA")
                if vscode_has_extension and intellij_has_plugin:
                    print_info("Both IDEs appear to have Continue installed")
                elif vscode_has_extension:
                    print_info("VS Code has Continue extension installed")
                elif intellij_has_plugin:
                    print_info("IntelliJ IDEA has Continue plugin installed")
                print()
            
            choice = prompt_choice(
                "What would you like to do with config files?",
                ["Remove config files", "Restore backup and remove generated config", "Keep config files"],
                default=0
            )
            
            if choice == 0:  # Remove
                if vscode_has_extension or intellij_has_plugin:
                    if not prompt_yes_no("This config is shared between IDEs. Remove anyway?", default=False):
                        print_info("Keeping config files")
                    else:
                        config_removed = uninstall_config_files(restore_backup=False, warn_shared=False)
                else:
                    if prompt_yes_no("Remove Continue.dev config files?", default=False):
                        config_removed = uninstall_config_files(restore_backup=False, warn_shared=False)
            elif choice == 1:  # Restore backup
                if backup_yaml and backup_yaml.exists():
                    if prompt_yes_no("Restore backup and remove generated config?", default=False):
                        config_removed = uninstall_config_files(restore_backup=True)
                else:
                    print_warning("No backup file found")
                    if prompt_yes_no("Remove config files anyway?", default=False):
                        config_removed = uninstall_config_files(restore_backup=False)
            else:  # Keep
                print_info("Keeping config files")
        else:
            print()
            print_subheader("Continue.dev Configuration Files")
            print_info("No config files found")
    
    # Step 3: Remove IDE extensions/plugins
    vscode_removed = False
    intellij_removed = False
    
    # Check which IDEs have Continue installed
    vscode_installed = check_vscode_extension_installed()
    intellij_installed, intellij_paths = check_intellij_plugin_installed()
    
    # Determine which IDEs to process based on flags
    skip_vscode = args.skip_extension or args.skip_vscode
    skip_intellij = args.skip_extension or args.skip_intellij
    
    # If both are installed and neither is skipped, ask which to uninstall
    if vscode_installed and intellij_installed and not skip_vscode and not skip_intellij:
        print()
        print_subheader("IDE Extensions/Plugins")
        print_info("Found Continue installed in both VS Code and IntelliJ IDEA")
        print()
        
        choice = prompt_choice(
            "Which IDE(s) would you like to uninstall Continue from?",
            ["VS Code only", "IntelliJ only", "Both", "Neither (skip plugin removal)"],
            default=2
        )
        
        if choice == 0:  # VS Code only
            skip_intellij = True
        elif choice == 1:  # IntelliJ only
            skip_vscode = True
        elif choice == 3:  # Neither
            skip_vscode = True
            skip_intellij = True
    
    # Process VS Code extension
    if skip_vscode:
        if vscode_installed:
            print()
            print_subheader("VS Code Extension")
            print_warning("Skipping VS Code extension removal")
    elif vscode_installed:
        print()
        print_subheader("VS Code Extension")
        if prompt_yes_no("Remove Continue.dev VS Code extension?", default=False):
            vscode_removed = uninstall_vscode_extension()
    elif not vscode_installed:
        print()
        print_subheader("VS Code Extension")
        print_info("Continue.dev extension is not installed in VS Code")
    
    # Process IntelliJ plugin
    if skip_intellij:
        if intellij_installed:
            print()
            print_subheader("IntelliJ IDEA Plugin")
            print_warning("Skipping IntelliJ plugin removal")
    elif intellij_installed:
        print()
        print_subheader("IntelliJ IDEA Plugin")
        if prompt_yes_no("Remove Continue plugin from IntelliJ IDEA?", default=False):
            intellij_removed = uninstall_intellij_plugin()
    elif not intellij_installed:
        print()
        print_subheader("IntelliJ IDEA Plugin")
        print_info("Continue plugin is not installed in IntelliJ IDEA")
    
    # Show summary
    print()
    show_summary(models_removed, config_removed, vscode_removed, intellij_removed)
    
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print()
        print_warning("Uninstallation interrupted by user.")
        sys.exit(130)
    except Exception as e:
        print_error(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
