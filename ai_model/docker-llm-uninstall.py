#!/usr/bin/env python3
"""
Docker Model Runner + Continue.dev Uninstaller

An interactive Python script that helps you uninstall components set up by
docker-llm-setup.py, including:
- Docker Model Runner models
- Continue.dev configuration files
- VS Code Continue.dev extension (optional)

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
            try:
                process.kill()
            except:
                pass
            # On Unix, try SIGTERM then SIGKILL
            if platform.system() != "Windows" and process.pid:
                try:
                    os.kill(process.pid, signal.SIGTERM)
                    import time
                    time.sleep(0.1)
                except:
                    pass
                try:
                    os.kill(process.pid, signal.SIGKILL)
                except:
                    pass
            try:
                process.wait(timeout=1)
            except:
                pass
            return -1, "", "Command timed out"
    except FileNotFoundError:
        return -1, "", f"Command not found: {cmd[0]}"
    except Exception as e:
        return -1, "", str(e)


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


def uninstall_config_files(restore_backup: bool = False) -> bool:
    """Uninstall Continue.dev config files."""
    print_subheader("Removing Continue.dev Configuration")
    
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


def uninstall_vscode_extension() -> bool:
    """Uninstall Continue.dev VS Code extension."""
    print_subheader("Removing VS Code Extension")
    
    code_path = shutil.which("code")
    if not code_path:
        print_warning("VS Code CLI not found. Cannot uninstall extension automatically.")
        print_info("You can uninstall manually:")
        print_info("  • Press Cmd+Shift+X (macOS) or Ctrl+Shift+X (Windows/Linux)")
        print_info("  • Search for 'Continue' and click Uninstall")
        return False
    
    # Check if extension is installed
    code, stdout, _ = run_command(["code", "--list-extensions"], timeout=10)
    if code != 0:
        print_warning("Could not list VS Code extensions")
        return False
    
    extension_id = "Continue.continue"
    if extension_id not in stdout:
        print_info("Continue.dev extension is not installed")
        return False
    
    # Uninstall the extension
    print_info(f"Uninstalling {extension_id}...")
    code, stdout, stderr = run_command(["code", "--uninstall-extension", extension_id], timeout=60)
    
    if code == 0:
        print_success("Extension uninstalled successfully")
        return True
    else:
        print_error(f"Failed to uninstall extension: {stderr or stdout}")
        print_info("You can uninstall manually:")
        print_info("  • Press Cmd+Shift+X (macOS) or Ctrl+Shift+X (Windows/Linux)")
        print_info("  • Search for 'Continue' and click Uninstall")
        return False


def show_summary(models_removed: int, config_removed: bool, extension_removed: bool) -> None:
    """Show uninstallation summary."""
    print_header("✅ Uninstallation Complete!")
    
    print(colorize("Summary:", Colors.GREEN + Colors.BOLD))
    print()
    
    print(f"  Docker Models Removed: {models_removed}")
    print(f"  Config Files Removed: {'Yes' if config_removed else 'No'}")
    print(f"  VS Code Extension Removed: {'Yes' if extension_removed else 'No'}")
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
        help="Skip VS Code extension removal"
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
            
            choice = prompt_choice(
                "What would you like to do with config files?",
                ["Remove config files", "Restore backup and remove generated config", "Keep config files"],
                default=0
            )
            
            if choice == 0:  # Remove
                if prompt_yes_no("Remove Continue.dev config files?", default=False):
                    config_removed = uninstall_config_files(restore_backup=False)
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
    
    # Step 3: Remove VS Code extension (optional)
    extension_removed = False
    if args.skip_extension:
        print()
        print_subheader("VS Code Extension")
        print_warning("Skipping VS Code extension removal (--skip-extension flag used)")
    else:
        print()
        print_subheader("VS Code Extension")
        
        code_path = shutil.which("code")
        if code_path:
            code, stdout, _ = run_command(["code", "--list-extensions"], timeout=10)
            if code == 0 and "Continue.continue" in stdout:
                if prompt_yes_no("Remove Continue.dev VS Code extension?", default=False):
                    extension_removed = uninstall_vscode_extension()
                else:
                    extension_removed = False
            else:
                print_info("Continue.dev extension is not installed")
                extension_removed = False
        else:
            print_info("VS Code CLI not found - cannot check extension status")
    
    # Show summary
    print()
    show_summary(models_removed, config_removed, extension_removed)
    
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
