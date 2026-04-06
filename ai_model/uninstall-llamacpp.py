#!/usr/bin/env python3
"""
llama.cpp + OpenCode Uninstaller

Removes all components installed by setup-llamacpp.py or setup-gemma4-working.sh:
- llama.cpp build directory
- Downloaded GGUF models (HuggingFace cache)
- OpenCode custom build (optional - keeps official install)
- Configuration files
- Prerequisites (optional)

Author: AI-Generated
License: MIT
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path
from typing import List, Tuple

# Add project root to path
script_path = Path(__file__).resolve()
project_root = script_path.parent
if str(project_root) not in sys.path:
    sys.path.insert(0, str(project_root))

from lib import ui

# Colors
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
RED = '\033[0;31m'
BLUE = '\033[0;34m'
NC = '\033[0m'  # No Color


def print_header(text: str) -> None:
    """Print styled header."""
    print(f"\n{BLUE}{'═' * 60}{NC}")
    print(f"{BLUE}  {text}{NC}")
    print(f"{BLUE}{'═' * 60}{NC}\n")


def print_status(text: str, success: bool = True) -> None:
    """Print status message."""
    symbol = f"{GREEN}✓{NC}" if success else f"{RED}✗{NC}"
    print(f"{symbol} {text}")


def print_info(text: str) -> None:
    """Print info message."""
    print(f"{BLUE}ℹ{NC} {text}")


def print_warning(text: str) -> None:
    """Print warning message."""
    print(f"{YELLOW}⚠{NC} {text}")


def get_size_str(path: Path) -> str:
    """Get human-readable size of path."""
    try:
        if path.is_file():
            size_bytes = path.stat().st_size
        elif path.is_dir():
            size_bytes = sum(f.stat().st_size for f in path.rglob('*') if f.is_file())
        else:
            return "unknown"

        # Convert to human readable
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if size_bytes < 1024.0:
                return f"{size_bytes:.1f}{unit}"
            size_bytes /= 1024.0
        return f"{size_bytes:.1f}PB"
    except Exception:
        return "unknown"


def check_llama_server_running() -> bool:
    """Check if llama-server is running."""
    try:
        result = subprocess.run(
            ["pgrep", "-f", "llama-server"],
            capture_output=True,
            timeout=5
        )
        return result.returncode == 0
    except Exception:
        return False


def kill_llama_server() -> bool:
    """Kill running llama-server processes."""
    try:
        subprocess.run(["pkill", "-f", "llama-server"], timeout=10, check=False)
        return True
    except Exception:
        return False


def scan_system() -> dict:
    """Scan system for installed components."""
    components = {
        'llama_build': None,
        'llama_homebrew': False,
        'hf_models': [],
        'opencode_custom': None,
        'opencode_backup': None,
        'config_files': [],
        'prerequisites': []
    }

    # Check llama.cpp build directory
    llama_build = Path("/tmp/llama-cpp-build")
    if llama_build.exists():
        components['llama_build'] = llama_build

    # Check Homebrew llama.cpp
    try:
        result = subprocess.run(
            ["brew", "list", "llama.cpp"],
            capture_output=True,
            timeout=5
        )
        components['llama_homebrew'] = (result.returncode == 0)
    except Exception:
        pass

    # Check HuggingFace cache for GGUF models
    hf_cache = Path.home() / ".cache/huggingface/hub"
    if hf_cache.exists():
        gemma_patterns = [
            "models--ggml-org--gemma-4-*",
            "models--google--gemma-4-*"
        ]
        for pattern in gemma_patterns:
            components['hf_models'].extend(hf_cache.glob(pattern))

    # Check OpenCode custom build
    opencode_bin = Path.home() / ".opencode/bin/opencode"
    if opencode_bin.exists():
        components['opencode_custom'] = opencode_bin

    opencode_backup = Path.home() / ".opencode/bin/opencode.backup"
    if opencode_backup.exists():
        components['opencode_backup'] = opencode_backup

    # Check config files
    config_locations = [
        Path.home() / ".config/opencode/opencode.jsonc",
        Path.home() / ".config/opencode/opencode.json",
        Path.home() / ".config/opencode/AGENTS.md",
        Path.home() / ".config/opencode/prompts/build.txt",
    ]
    components['config_files'] = [f for f in config_locations if f.exists()]

    # Check prerequisites
    prereqs_to_check = [
        ("huggingface-hub", ["pipx", "list"]),
        ("llama.cpp (Homebrew)", ["brew", "list", "llama.cpp"]),
    ]

    for name, cmd in prereqs_to_check:
        try:
            result = subprocess.run(cmd, capture_output=True, timeout=5)
            if result.returncode == 0 and name.split()[0].lower() in result.stdout.decode().lower():
                components['prerequisites'].append(name)
        except Exception:
            pass

    return components


def display_scan_results(components: dict) -> None:
    """Display what was found on the system."""
    print_header("System Scan Results")

    # llama.cpp
    if components['llama_build']:
        size = get_size_str(components['llama_build'])
        print_status(f"llama.cpp source build found ({size})")
        print(f"  Location: {components['llama_build']}")
    else:
        print_info("No llama.cpp source build found")

    if components['llama_homebrew']:
        print_status("llama.cpp installed via Homebrew")

    # Models
    if components['hf_models']:
        total_size = sum(
            sum(f.stat().st_size for f in model_dir.rglob('*') if f.is_file())
            for model_dir in components['hf_models']
        )
        size_gb = total_size / (1024**3)
        print_status(f"{len(components['hf_models'])} Gemma 4 model(s) in HuggingFace cache (~{size_gb:.1f}GB)")
        for model in components['hf_models']:
            model_name = model.name.replace('models--', '').replace('--', '/')
            print(f"  • {model_name}")
    else:
        print_info("No Gemma 4 models found in cache")

    # OpenCode
    if components['opencode_custom']:
        print_status("OpenCode custom build installed")
    if components['opencode_backup']:
        print_status("OpenCode backup found (original version)")
    if not components['opencode_custom'] and not components['opencode_backup']:
        print_info("No OpenCode custom build found")

    # Config files
    if components['config_files']:
        print_status(f"{len(components['config_files'])} configuration file(s)")
        for config in components['config_files']:
            print(f"  • {config.relative_to(Path.home())}")
    else:
        print_info("No configuration files found")

    # Prerequisites
    if components['prerequisites']:
        print_status(f"{len(components['prerequisites'])} prerequisite(s) installed")
        for prereq in components['prerequisites']:
            print(f"  • {prereq}")

    print()


def prompt_removal_choices(components: dict) -> dict:
    """Ask user what to remove."""
    choices = {
        'llama_build': False,
        'llama_homebrew': False,
        'hf_models': False,
        'opencode_custom': False,
        'restore_opencode_backup': False,
        'config_files': False,
        'prerequisites': False
    }

    print_header("Uninstall Configuration")

    # llama.cpp build
    if components['llama_build']:
        choices['llama_build'] = ui.prompt_yes_no(
            f"Remove llama.cpp source build? ({get_size_str(components['llama_build'])})",
            default=True
        )

    # llama.cpp Homebrew
    if components['llama_homebrew']:
        choices['llama_homebrew'] = ui.prompt_yes_no(
            "Uninstall llama.cpp (Homebrew)?",
            default=False
        )

    # Models
    if components['hf_models']:
        total_gb = sum(
            sum(f.stat().st_size for f in m.rglob('*') if f.is_file())
            for m in components['hf_models']
        ) / (1024**3)

        print()
        print_warning(f"Model cache: ~{total_gb:.1f}GB")
        print_info("Models are stored in ~/.cache/huggingface and reusable")
        choices['hf_models'] = ui.prompt_yes_no(
            "Remove downloaded Gemma 4 models?",
            default=False
        )

    # OpenCode
    if components['opencode_custom']:
        print()
        if components['opencode_backup']:
            print_info("You have a backup of the original OpenCode")
            choices['opencode_custom'] = ui.prompt_yes_no(
                "Remove custom OpenCode build?",
                default=True
            )
            if choices['opencode_custom']:
                choices['restore_opencode_backup'] = ui.prompt_yes_no(
                    "Restore original OpenCode from backup?",
                    default=True
                )
        else:
            print_warning("No backup found - removing will uninstall OpenCode")
            choices['opencode_custom'] = ui.prompt_yes_no(
                "Remove custom OpenCode build?",
                default=False
            )

    # Config files
    if components['config_files']:
        print()
        choices['config_files'] = ui.prompt_yes_no(
            f"Remove {len(components['config_files'])} configuration file(s)?",
            default=True
        )

    # Prerequisites
    if components['prerequisites']:
        print()
        print_info("Prerequisites are shared with other tools")
        choices['prerequisites'] = ui.prompt_yes_no(
            "Uninstall prerequisites (huggingface-hub, etc.)?",
            default=False
        )

    return choices


def show_plan(components: dict, choices: dict) -> None:
    """Show what will be removed."""
    print_header("Uninstall Plan")

    actions = []

    if choices['llama_build']:
        actions.append(f"Remove llama.cpp source build ({get_size_str(components['llama_build'])})")

    if choices['llama_homebrew']:
        actions.append("Uninstall llama.cpp (Homebrew)")

    if choices['hf_models']:
        count = len(components['hf_models'])
        actions.append(f"Remove {count} Gemma 4 model(s) from cache")

    if choices['opencode_custom']:
        if choices['restore_opencode_backup']:
            actions.append("Remove custom OpenCode and restore backup")
        else:
            actions.append("Remove custom OpenCode build")

    if choices['config_files']:
        count = len(components['config_files'])
        actions.append(f"Remove {count} configuration file(s)")

    if choices['prerequisites']:
        actions.append("Uninstall prerequisites")

    if not actions:
        print_info("No actions selected")
    else:
        for action in actions:
            print(f"  • {action}")

    print()


def execute_uninstall(components: dict, choices: dict) -> Tuple[int, List[str]]:
    """Execute the uninstallation."""
    success_count = 0
    errors = []

    # Stop llama-server if running
    if check_llama_server_running():
        print_header("Stopping llama-server")
        print_info("Killing running llama-server processes...")
        if kill_llama_server():
            print_status("llama-server stopped")
        else:
            print_warning("Could not stop llama-server (may need manual kill)")
        print()

    # Remove llama.cpp build
    if choices['llama_build'] and components['llama_build']:
        print_header("Removing llama.cpp Build")
        try:
            shutil.rmtree(components['llama_build'])
            print_status(f"Removed: {components['llama_build']}")
            success_count += 1
        except Exception as e:
            errors.append(f"Failed to remove llama.cpp build: {e}")
            print_status(f"Failed: {e}", success=False)
        print()

    # Uninstall llama.cpp (Homebrew)
    if choices['llama_homebrew']:
        print_header("Uninstalling llama.cpp (Homebrew)")
        try:
            result = subprocess.run(
                ["brew", "uninstall", "llama.cpp"],
                capture_output=True,
                timeout=60,
                text=True
            )
            if result.returncode == 0:
                print_status("llama.cpp uninstalled via Homebrew")
                success_count += 1
            else:
                errors.append(f"Homebrew uninstall failed: {result.stderr}")
                print_status(f"Failed: {result.stderr}", success=False)
        except Exception as e:
            errors.append(f"Failed to uninstall via Homebrew: {e}")
            print_status(f"Failed: {e}", success=False)
        print()

    # Remove models
    if choices['hf_models'] and components['hf_models']:
        print_header("Removing Models")
        for model_dir in components['hf_models']:
            try:
                model_name = model_dir.name.replace('models--', '').replace('--', '/')
                shutil.rmtree(model_dir)
                print_status(f"Removed: {model_name}")
                success_count += 1
            except Exception as e:
                errors.append(f"Failed to remove {model_dir.name}: {e}")
                print_status(f"Failed: {model_dir.name}: {e}", success=False)
        print()

    # Remove/restore OpenCode
    if choices['opencode_custom'] and components['opencode_custom']:
        print_header("Removing Custom OpenCode Build")
        try:
            components['opencode_custom'].unlink()
            print_status("Removed custom OpenCode binary")
            success_count += 1

            if choices['restore_opencode_backup'] and components['opencode_backup']:
                shutil.copy(components['opencode_backup'], components['opencode_custom'])
                components['opencode_backup'].unlink()
                print_status("Restored original OpenCode from backup")
                success_count += 1
        except Exception as e:
            errors.append(f"Failed to remove/restore OpenCode: {e}")
            print_status(f"Failed: {e}", success=False)
        print()

    # Remove config files
    if choices['config_files'] and components['config_files']:
        print_header("Removing Configuration Files")
        for config in components['config_files']:
            try:
                config.unlink()
                print_status(f"Removed: {config.relative_to(Path.home())}")
                success_count += 1
            except Exception as e:
                errors.append(f"Failed to remove {config.name}: {e}")
                print_status(f"Failed: {config.name}: {e}", success=False)

        # Remove empty parent directories
        try:
            opencode_config = Path.home() / ".config/opencode"
            if opencode_config.exists() and not any(opencode_config.iterdir()):
                opencode_config.rmdir()
                print_info("Removed empty config directory")
        except Exception:
            pass

        print()

    # Uninstall prerequisites
    if choices['prerequisites']:
        print_header("Uninstalling Prerequisites")
        if "huggingface-hub" in str(components['prerequisites']):
            try:
                result = subprocess.run(
                    ["pipx", "uninstall", "huggingface-hub"],
                    capture_output=True,
                    timeout=60,
                    text=True
                )
                if result.returncode == 0:
                    print_status("huggingface-hub uninstalled")
                    success_count += 1
                else:
                    errors.append(f"Failed to uninstall huggingface-hub: {result.stderr}")
                    print_status(f"Failed: {result.stderr}", success=False)
            except Exception as e:
                errors.append(f"Failed to uninstall huggingface-hub: {e}")
                print_status(f"Failed: {e}", success=False)
        print()

    return success_count, errors


def print_summary(success_count: int, errors: List[str]) -> None:
    """Print final summary."""
    print_header("Uninstall Complete")

    if success_count > 0:
        print_status(f"Successfully removed {success_count} component(s)")

    if errors:
        print()
        print_warning(f"{len(errors)} error(s) occurred:")
        for error in errors:
            print(f"  • {error}")

    print()
    print_info("You can run setup-llamacpp.py or setup-gemma4-working.sh to reinstall")
    print()


def main() -> int:
    """Main uninstaller entry point."""
    print_header("llama.cpp + OpenCode Uninstaller")

    # Scan system
    print_info("Scanning system for installed components...")
    print()
    components = scan_system()

    # Display what we found
    display_scan_results(components)

    # Check if anything to remove
    has_components = any([
        components['llama_build'],
        components['llama_homebrew'],
        components['hf_models'],
        components['opencode_custom'],
        components['config_files'],
        components['prerequisites']
    ])

    if not has_components:
        print_info("Nothing to uninstall - system is clean")
        return 0

    # Prompt for choices
    choices = prompt_removal_choices(components)

    # Show plan
    show_plan(components, choices)

    # Confirm
    if not ui.prompt_yes_no("Proceed with uninstallation?", default=True):
        print_info("Uninstall cancelled")
        return 0

    print()

    # Execute
    success_count, errors = execute_uninstall(components, choices)

    # Summary
    print_summary(success_count, errors)

    return 0 if not errors else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print()
        print(f"{YELLOW}⚠{NC} Uninstall interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"{RED}✗{NC} Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
