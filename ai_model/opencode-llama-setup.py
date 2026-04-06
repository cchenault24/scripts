#!/usr/bin/env python3
"""
OpenCode + llama.cpp Setup Script (Simplified)

Automated installer for OpenCode with Gemma 4 via llama.cpp.
Based on the guide in README.md (April 2026) with latest community updates.

UPDATE (April 6, 2026): Gemma 4 fixes are now in llama.cpp HEAD!
- No longer need to build from source
- Install via: brew install llama.cpp --HEAD
- Source: erikji comment on guide

This setup works around Ollama's Gemma 4 tool calling bugs by using:
- llama.cpp (Homebrew HEAD version with Gemma 4 fixes)
- Custom OpenCode build with tool-call compatibility layer (PR #16531)

Requirements:
- macOS Apple Silicon (M1/M2/M3/M4)
- 24GB+ RAM (32GB recommended for 26B model, 16GB works with E4B)
- Homebrew, git, gh CLI, bun

Author: AI-Generated from README.md guide + community updates
License: MIT
"""

from __future__ import annotations

import argparse
import logging
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Optional, Tuple

# Add project root to path
script_path = Path(__file__).resolve()
project_root = script_path.parent
if str(project_root) not in sys.path:
    sys.path.insert(0, str(project_root))

# Import from lib modules
from lib import hardware
from lib import ui
from lib import utils

# Module logger
_logger = logging.getLogger(__name__)

# Build directories
LLAMA_CPP_BUILD_DIR = Path("/tmp/llama-cpp-build")
OPENCODE_BUILD_DIR = Path("/tmp/opencode-build")
OPENCODE_INSTALL_DIR = Path.home() / ".opencode"

# llama.cpp PR numbers
LLAMA_CPP_TOKENIZER_PR = 21343  # Gemma 4 tokenizer fix


def install_prerequisites() -> Tuple[bool, str]:
    """
    Check and auto-install required tools.

    Returns:
        Tuple of (success, message)
    """
    # Check Homebrew first (required for other installs)
    if not shutil.which("brew"):
        ui.print_error("Homebrew not found")
        print()
        print("Install Homebrew first:")
        print('  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"')
        return False, "Homebrew is required"

    ui.print_success("Homebrew installed")

    # Add known installation directories to PATH first (if they exist)
    # This ensures we can find tools even if current shell doesn't have them in PATH
    bun_bin_dir = Path.home() / ".bun" / "bin"
    pipx_bin_dir = Path.home() / ".local" / "bin"

    known_paths = [bun_bin_dir, pipx_bin_dir]
    for bin_dir in known_paths:
        if bin_dir.exists() and str(bin_dir) not in os.environ.get("PATH", ""):
            os.environ["PATH"] = f"{bin_dir}:{os.environ.get('PATH', '')}"

    # Tools to install via different methods
    tools_to_check = [
        ("git", "brew", "git"),
        ("gh", "brew", "gh"),
        ("pipx", "brew", "pipx"),  # For installing Python CLI tools
        ("hf", "pipx", "huggingface-hub[cli]"),  # HuggingFace CLI via pipx
        ("bun", "official", None),  # Bun uses its own installer
    ]

    for tool, install_method, package_name in tools_to_check:
        # For bun and hf, check both PATH and known installation locations
        if tool == "bun":
            bun_binary = bun_bin_dir / "bun"
            tool_found = shutil.which(tool) or (bun_binary.exists() and bun_binary.is_file())
        elif tool == "hf":
            hf_binary = pipx_bin_dir / "hf"
            tool_found = shutil.which(tool) or (hf_binary.exists() and hf_binary.is_file())
        else:
            tool_found = shutil.which(tool)

        if tool_found:
            ui.print_success(f"{tool} installed")
            continue

        # Tool is missing, install it
        ui.print_warning(f"{tool} not found, installing...")

        if install_method == "brew":
            code, stdout, stderr = utils.run_command([
                "brew", "install", package_name
            ], timeout=300)

            if code != 0:
                return False, f"Failed to install {tool} via Homebrew: {stderr}"

            ui.print_success(f"Installed {tool} via Homebrew")

            # Special handling for pipx: ensure path is configured
            if tool == "pipx":
                utils.run_command(["pipx", "ensurepath"], timeout=30)
                # Add pipx bin to current session PATH
                if pipx_bin_dir.exists() and str(pipx_bin_dir) not in os.environ.get("PATH", ""):
                    os.environ["PATH"] = f"{pipx_bin_dir}:{os.environ.get('PATH', '')}"

        elif install_method == "pipx":
            # Install Python CLI tool via pipx
            ui.print_info(f"Installing {tool} via pipx...")

            # For huggingface-hub, use --force to ensure clean install with proper certifi
            if package_name == "huggingface-hub[cli]":
                # Try to uninstall first in case it was partially installed
                utils.run_command(["pipx", "uninstall", "huggingface-hub"], timeout=30)

            code, stdout, stderr = utils.run_command([
                "pipx", "install", package_name, "--force"
            ], timeout=180)

            if code != 0:
                return False, f"Failed to install {tool} via pipx: {stderr}"

            ui.print_success(f"Installed {tool} via pipx")

            # Refresh PATH to pick up newly installed tool
            if pipx_bin_dir.exists() and str(pipx_bin_dir) not in os.environ.get("PATH", ""):
                os.environ["PATH"] = f"{pipx_bin_dir}:{os.environ.get('PATH', '')}"

        elif install_method == "official" and tool == "bun":
            # Install bun via official installer
            ui.print_info("Installing bun via official installer...")
            code, stdout, stderr = utils.run_command([
                "bash", "-c",
                "curl -fsSL https://bun.sh/install | bash"
            ], timeout=300)

            if code != 0:
                return False, f"Failed to install bun: {stderr}"

            # Add bun to PATH for current session
            if bun_bin_dir.exists():
                os.environ["PATH"] = f"{bun_bin_dir}:{os.environ.get('PATH', '')}"

            ui.print_success("Installed bun")

    return True, "All prerequisites installed"


def parse_model_repo(model_repo: str) -> Tuple[str, str]:
    """
    Parse model repository string into repo_id and filename.

    Args:
        model_repo: Format "ggml-org/gemma-4-31B-it-GGUF:Q4_K_M"

    Returns:
        Tuple of (repo_id, filename)

    Example:
        >>> parse_model_repo("ggml-org/gemma-4-31B-it-GGUF:Q4_K_M")
        ("ggml-org/gemma-4-31B-it-GGUF", "gemma-4-31B-it-Q4_K_M.gguf")
    """
    if ':' not in model_repo:
        raise ValueError(f"Invalid model format: {model_repo} (expected 'repo:quantization')")

    repo_id, quantization = model_repo.rsplit(':', 1)

    # Extract model name from repo_id
    # Format: "ggml-org/gemma-4-31B-it-GGUF" -> "gemma-4-31B-it"
    repo_name = repo_id.split('/')[-1]  # Get "gemma-4-31B-it-GGUF"

    # Remove "-GGUF" suffix if present
    if repo_name.endswith('-GGUF'):
        model_name = repo_name[:-5]  # Remove last 5 chars ("-GGUF")
    else:
        model_name = repo_name

    # Construct filename: model-name-quantization.gguf
    # Example: "gemma-4-31B-it-Q4_K_M.gguf"
    filename = f"{model_name}-{quantization}.gguf"

    return repo_id, filename


def download_model_from_hf(model_repo: str, force: bool = False, show_progress: bool = True) -> Tuple[bool, str]:
    """
    Download GGUF model from HuggingFace.

    Args:
        model_repo: HuggingFace model repository (e.g., "ggml-org/gemma-4-31B-it-GGUF:Q4_K_M")
        force: If True, re-download even if cached
        show_progress: If True, show download progress

    Returns:
        Tuple of (success, message)
    """
    try:
        # Parse repo and filename
        repo_id, filename = parse_model_repo(model_repo)

        # Check if model is already cached
        cache_dir = Path.home() / ".cache" / "huggingface" / "hub"
        # HuggingFace uses a specific naming scheme for cached repos
        # Format: models--<org>--<repo-name>
        repo_cache_name = repo_id.replace('/', '--')
        repo_cache_dir = cache_dir / f"models--{repo_cache_name}"

        if repo_cache_dir.exists() and not force:
            # Check if the specific file exists in the cache
            # HuggingFace stores files in snapshots/<hash>/<filename>
            snapshots_dir = repo_cache_dir / "snapshots"
            if snapshots_dir.exists():
                # Check all snapshots for the file
                for snapshot in snapshots_dir.iterdir():
                    if snapshot.is_dir():
                        model_file = snapshot / filename
                        if model_file.exists():
                            file_size_gb = model_file.stat().st_size / (1024**3)
                            return True, f"Model already downloaded: {filename} ({file_size_gb:.1f}GB) - skipping"

        if show_progress:
            ui.print_info(f"Downloading model from HuggingFace...")
            print(f"  Repository: {repo_id}")
            print(f"  File: {filename}")
            print()
            print("  This may take 10-30 minutes depending on your connection...")
            print("  Download is resumable if interrupted")
            print()

        # Get path to 'hf' command (should be installed in prerequisites)
        hf_cli_path = shutil.which("hf")

        if not hf_cli_path:
            # Check known pipx location
            pipx_bin = Path.home() / ".local" / "bin"
            hf_cli_path = pipx_bin / "hf"

            if not hf_cli_path.exists():
                return False, "HuggingFace CLI ('hf' command) not found. Run with --force-reinstall to reinstall prerequisites."

        # Use full path to 'hf' command (convert Path to string if needed)
        hf_cli_cmd = str(hf_cli_path) if isinstance(hf_cli_path, Path) else hf_cli_path

        # Download the model with progress
        import subprocess
        process = subprocess.Popen(
            [hf_cli_cmd, "download", repo_id, filename, "--local-dir-use-symlinks", "False"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )

        # Show download progress
        for line in process.stdout:
            if show_progress:
                # Print progress lines
                line_stripped = line.rstrip()
                if line_stripped and any(keyword in line_stripped for keyword in
                    ['Downloading', 'Download', 'fetching', '%', 'MB', 'GB', '100%', 'done']):
                    print(f"  {line_stripped}")

        process.wait()

        if process.returncode != 0:
            return False, f"Model download failed with exit code {process.returncode}"

        # Verify model was downloaded
        if not cache_dir.exists():
            return False, "HuggingFace cache directory not found after download"

        return True, f"Model downloaded successfully: {filename}"

    except Exception as e:
        return False, f"Download failed: {e}"


def install_llama_cpp_homebrew(force: bool = False, show_progress: bool = True) -> Tuple[bool, str]:
    """
    Install llama.cpp via Homebrew (with Gemma 4 fixes in HEAD).

    As of April 2026, Gemma 4 fixes are merged into llama.cpp HEAD.
    Source: https://github.com/ggml-org/llama.cpp (erikji comment)

    Args:
        force: If True, reinstall even if already installed
        show_progress: If True, show installation progress

    Returns:
        Tuple of (success, message)
    """
    try:
        # Check if already installed
        llama_server = shutil.which("llama-server")
        if llama_server and not force:
            # Get version
            code, version_out, stderr = utils.run_command([
                "llama-server", "--version"
            ], timeout=10)

            version_info = version_out.strip() if code == 0 else "unknown version"
            return True, f"llama.cpp already installed ({version_info}) - skipping"

        if show_progress:
            if force:
                ui.print_info("Reinstalling llama.cpp via Homebrew...")
            else:
                ui.print_info("Installing llama.cpp via Homebrew...")
            print("  Using --HEAD to get latest Gemma 4 fixes")
            print("  This will take 2-5 minutes ...")
            print()

        # Install from HEAD to get latest fixes (with real-time output)
        import subprocess

        # If forcing, uninstall first
        if force:
            subprocess.run(["brew", "uninstall", "llama.cpp"],
                         capture_output=True, timeout=60)

        process = subprocess.Popen(
            ["brew", "install", "llama.cpp", "--HEAD"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )

        # Show output in real-time
        output_lines = []
        for line in process.stdout:
            if show_progress:
                # Print important lines
                if any(keyword in line.lower() for keyword in ['downloading', 'building', 'installing', 'cloning', '==>', 'error', 'warning']):
                    print(f"  {line.rstrip()}")
            output_lines.append(line)

        process.wait()

        if process.returncode != 0:
            full_output = "".join(output_lines)
            return False, f"Homebrew installation failed:\n{full_output[-500:]}"

        # Verify installation
        llama_server = shutil.which("llama-server")
        if not llama_server:
            return False, "llama-server not found in PATH after installation"

        # Get version
        code, version_out, stderr = utils.run_command([
            "llama-server", "--version"
        ], timeout=10)

        version_info = version_out.strip() if code == 0 else "unknown"

        return True, f"Installed llama.cpp successfully ({version_info})"

    except Exception as e:
        return False, f"Installation failed: {e}"


def install_opencode_official(force: bool = False) -> Tuple[bool, str]:
    """
    Install official OpenCode CLI.

    Args:
        force: If True, reinstall even if already installed

    Returns:
        Tuple of (success, message)
    """
    try:
        # Check if already installed
        if (OPENCODE_INSTALL_DIR / "bin" / "opencode").exists() and not force:
            return True, "OpenCode already installed (use --force-reinstall to override)"

        ui.print_info("Downloading OpenCode installer...")

        # Download installer
        install_script = Path("/tmp/opencode-install.sh")
        code, stdout, stderr = utils.run_command([
            "curl", "-fsSL", "-o", str(install_script),
            "https://opencode.ai/install"
        ], timeout=60)

        if code != 0:
            return False, f"Failed to download installer: {stderr}"

        ui.print_info("Running OpenCode installer...")

        # Run installer
        code, stdout, stderr = utils.run_command([
            "bash", str(install_script)
        ], timeout=300)

        if code != 0:
            return False, f"Installer failed: {stderr}"

        # Remove old Homebrew version if exists
        utils.run_command(["brew", "uninstall", "opencode"], timeout=30)

        return True, "OpenCode installed successfully"

    except Exception as e:
        return False, f"Installation failed: {e}"


def build_opencode_with_pr(pr_number: int = 16531, force: bool = False) -> Tuple[bool, str]:
    """
    Build OpenCode from source with tool-call compatibility PR.

    Args:
        pr_number: GitHub PR number to checkout
        force: If True, rebuild even if custom version exists

    Returns:
        Tuple of (success, message)
    """
    try:
        # Check if custom build already exists
        if not force:
            binary_path = OPENCODE_INSTALL_DIR / "bin" / "opencode"
            if binary_path.exists():
                # Check if it's the custom build by looking at version
                code, version_out, _ = utils.run_command([
                    str(binary_path), "--version"
                ], timeout=5)
                if code == 0 and "feat/custom-provider-compat" in version_out:
                    return True, f"Custom OpenCode build already installed (use --force-reinstall to rebuild)"

        # Clean up old build
        if OPENCODE_BUILD_DIR.exists():
            shutil.rmtree(OPENCODE_BUILD_DIR)

        ui.print_info("Cloning OpenCode repository...")

        # Clone OpenCode (with clean progress bar)
        import subprocess
        import sys
        import re

        process = subprocess.Popen(
            ["git", "clone", "--progress",
             "https://github.com/anomalyco/opencode.git",
             str(OPENCODE_BUILD_DIR)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )

        # Show clean progress bar (single line, updated in place)
        last_phase = None
        for line in process.stdout:
            # Extract progress from git output
            if "Receiving objects:" in line:
                match = re.search(r'Receiving objects:\s+(\d+)%', line)
                if match:
                    percent = int(match.group(1))
                    if last_phase != "receiving":
                        sys.stdout.write("\n  Downloading... ")
                        last_phase = "receiving"
                    # Update progress bar in place
                    bar_length = 40
                    filled = int(bar_length * percent / 100)
                    bar = '█' * filled + '░' * (bar_length - filled)
                    sys.stdout.write(f"\r  Downloading... {bar} {percent}%")
                    sys.stdout.flush()

            elif "Resolving deltas:" in line:
                match = re.search(r'Resolving deltas:\s+(\d+)%', line)
                if match:
                    percent = int(match.group(1))
                    if last_phase != "resolving":
                        sys.stdout.write("\n  Resolving...    ")
                        last_phase = "resolving"
                    # Update progress bar in place
                    bar_length = 40
                    filled = int(bar_length * percent / 100)
                    bar = '█' * filled + '░' * (bar_length - filled)
                    sys.stdout.write(f"\r  Resolving...    {bar} {percent}%")
                    sys.stdout.flush()

            elif "done." in line.lower():
                sys.stdout.write("\n")
                sys.stdout.flush()

        process.wait()

        if process.returncode != 0:
            return False, f"Failed to clone OpenCode"

        print()
        ui.print_info(f"Checking out PR #{pr_number}...")

        # Checkout the PR
        os.chdir(OPENCODE_BUILD_DIR)
        code, stdout, stderr = utils.run_command([
            "gh", "pr", "checkout", str(pr_number)
        ], timeout=120)

        if code != 0:
            return False, f"Failed to checkout PR: {stderr}"

        ui.print_info("Installing dependencies...")
        print("  This will take 1-2 minutes...")
        print()

        # Install dependencies (with real-time output)
        import subprocess
        process = subprocess.Popen(
            ["bun", "install"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            cwd=OPENCODE_BUILD_DIR
        )

        # Show progress
        for line in process.stdout:
            if any(keyword in line for keyword in ['✓', '✗', 'error', 'warn', 'packages', 'done']):
                print(f"  {line.rstrip()}")

        process.wait()

        if process.returncode != 0:
            return False, f"Dependency installation failed"

        ui.print_info("Building OpenCode...")
        print("  This will take 5-10 minutes ...")
        print()

        # Build OpenCode (with real-time output)
        import subprocess
        os.chdir(OPENCODE_BUILD_DIR / "packages" / "opencode")

        process = subprocess.Popen(
            ["bun", "run", "build", "--", "--single", "--skip-install"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )

        # Show build progress
        build_lines = []
        for line in process.stdout:
            build_lines.append(line)
            # Show important build steps
            if any(keyword in line for keyword in ['Building', 'Compiling', 'Bundling', '✓', '✗', 'error', 'warn', 'Done', '%']):
                print(f"  {line.rstrip()}")

        process.wait()

        if process.returncode != 0:
            full_output = "".join(build_lines)
            return False, f"Build failed:\n{full_output[-500:]}"

        # Verify binary was created
        binary_path = OPENCODE_BUILD_DIR / "packages" / "opencode" / "dist" / "opencode-darwin-arm64" / "bin" / "opencode"
        if not binary_path.exists():
            return False, "OpenCode binary not found after build"

        # Back up original
        original = OPENCODE_INSTALL_DIR / "bin" / "opencode"
        backup = OPENCODE_INSTALL_DIR / "bin" / "opencode.backup"
        if original.exists():
            shutil.copy(original, backup)

        # Install custom build
        original.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(binary_path, original)
        original.chmod(0o755)

        return True, f"Built and installed custom OpenCode with PR #{pr_number}"

    except Exception as e:
        return False, f"Build failed: {e}"


def get_model_choice(hw_info: hardware.HardwareInfo) -> Tuple[str, int]:
    """
    Get model and context size choice based on hardware.

    Args:
        hw_info: Hardware information

    Returns:
        Tuple of (model_name, context_size)
    """
    ram_gb = hw_info.ram_gb

    print()
    ui.print_subheader("Model Selection")
    print()

    # All Gemma 4 model variants available in GGUF format from ggml-org
    # Verified to exist on HuggingFace as of April 2026
    models = [
        {
            "name": "Gemma 4 2B (Efficient)",
            "hf_repo": "ggml-org/gemma-4-E2B-it-GGUF:Q8_0",  # Note: Q4_K_M not available for E2B
            "ram_gb": 2.5,
            "min_ram": 4,
            "max_ram": 12,
            "description": "Fast, efficient model for basic coding tasks. Best for lower-RAM systems.",
            "contexts": [
                (32768, "32K context (~3GB RAM)"),
            ]
        },
        {
            "name": "Gemma 4 4B (Balanced)",
            "hf_repo": "ggml-org/gemma-4-E4B-it-GGUF:Q4_K_M",
            "ram_gb": 4.5,
            "min_ram": 8,
            "max_ram": 16,
            "description": "Balanced performance and quality. Good for general coding.",
            "contexts": [
                (32768, "32K context (~5GB RAM)"),
            ]
        },
        {
            "name": "Gemma 4 26B (High Quality)",
            "hf_repo": "ggml-org/gemma-4-26B-A4B-it-GGUF:Q4_K_M",
            "ram_gb": 16.0,
            "min_ram": 16,
            "max_ram": 32,
            "description": "High quality 26B model, excellent balance of performance and capability.",
            "contexts": [
                (32768, "32K context (~17GB RAM) - Basic tasks"),
                (65536, "64K context (~20GB RAM) - Longer sessions") if ram_gb >= 32 else None,
                (131072, "128K context (~25GB RAM) - Maximum") if ram_gb >= 40 else None,
            ]
        },
        {
            "name": "Gemma 4 31B (Maximum Quality)",
            "hf_repo": "ggml-org/gemma-4-31B-it-GGUF:Q4_K_M",
            "ram_gb": 20.0,
            "min_ram": 24,
            "max_ram": 64,
            "description": "Largest model, best quality for high-RAM systems. Slower but most capable.",
            "contexts": [
                (32768, "32K context (~21GB RAM)"),
                (65536, "64K context (~24GB RAM)") if ram_gb >= 32 else None,
                (131072, "128K context (~28GB RAM)") if ram_gb >= 40 else None,
            ]
        },
    ]

    # Filter models suitable for current hardware
    suitable_models = [m for m in models if m["min_ram"] <= ram_gb]

    if not suitable_models:
        ui.print_error(f"Insufficient RAM ({ram_gb:.0f}GB) for any Gemma 4 model")
        ui.print_info("Minimum required: 4GB RAM")
        raise SystemExit(1)

    # Find recommended model (largest that fits well)
    recommended_idx = None
    for i, model in enumerate(suitable_models):
        if model["min_ram"] <= ram_gb <= model["max_ram"]:
            recommended_idx = i

    # Display models with suitability indicators
    print(f"Detected: {hw_info.apple_chip_model or hw_info.cpu_brand}, {ram_gb:.0f}GB RAM")
    print()
    print("Available models:")
    print()

    for i, model in enumerate(suitable_models, 1):
        # Mark recommended model
        is_recommended = (recommended_idx is not None and i - 1 == recommended_idx)
        marker = ui.colorize(" ★ RECOMMENDED", ui.Colors.GREEN) if is_recommended else ""

        # Check if RAM is in optimal range
        ram_ok = model["min_ram"] <= ram_gb <= model["max_ram"]
        ram_indicator = "✓" if ram_ok else "⚠"
        ram_color = ui.Colors.GREEN if ram_ok else ui.Colors.YELLOW

        print(f"  {i}. {ui.colorize(model['name'], ui.Colors.CYAN)}{marker}")
        print(f"     {ui.colorize(ram_indicator, ram_color)} RAM: ~{model['ram_gb']}GB (requires {model['min_ram']}-{model['max_ram']}GB)")
        print(f"     {model['description']}")
        print()

    # Prompt for model selection
    default_choice = (recommended_idx + 1) if recommended_idx is not None else 1
    while True:
        try:
            choice = input(f"Select model (1-{len(suitable_models)}) or press Enter for recommended [{default_choice}]: ").strip()
            if not choice:
                choice = str(default_choice)

            choice_num = int(choice)
            if 1 <= choice_num <= len(suitable_models):
                selected_model = suitable_models[choice_num - 1]

                # Warn if outside optimal range
                if not (selected_model["min_ram"] <= ram_gb <= selected_model["max_ram"]):
                    if ram_gb < selected_model["min_ram"]:
                        ui.print_warning(
                            f"\n⚠️  Warning: {selected_model['name']} requires {selected_model['min_ram']}GB+ RAM, "
                            f"but you have {ram_gb:.0f}GB."
                        )
                    else:
                        ui.print_warning(
                            f"\n⚠️  Note: {selected_model['name']} is optimized for {selected_model['max_ram']}GB or less. "
                            f"You have {ram_gb:.0f}GB - consider a larger model."
                        )
                    confirm = input("Continue with this model? (y/N): ").strip().lower()
                    if confirm != 'y':
                        print()
                        continue

                break
            else:
                print(ui.colorize(f"Please enter 1-{len(suitable_models)}", ui.Colors.RED))
        except ValueError:
            print(ui.colorize("Please enter a valid number", ui.Colors.RED))
        except KeyboardInterrupt:
            print()
            raise SystemExit("Setup cancelled")

    print()
    print(f"Selected: {ui.colorize(selected_model['name'], ui.Colors.CYAN)}")
    print()

    # Display context options
    print("Context window options:")
    context_options = [c for c in selected_model["contexts"] if c is not None]
    for i, (ctx, desc) in enumerate(context_options, 1):
        print(f"  {i}. {desc}")
    print()

    # Determine recommended context based on available RAM
    # Rule: Use largest context that fits comfortably in RAM
    recommended_idx = 1  # Default to smallest (safest)

    if len(context_options) >= 3 and ram_gb >= 40:
        recommended_idx = 3  # 128K context
    elif len(context_options) >= 2 and ram_gb >= 32:
        recommended_idx = 2  # 64K context
    else:
        recommended_idx = 1  # 32K context

    # Prompt for context size
    while True:
        try:
            choice = input(f"Select context (1-{len(context_options)}) or press Enter for recommended [{recommended_idx}]: ").strip()
            if not choice:
                choice = str(recommended_idx)

            choice_num = int(choice)
            if 1 <= choice_num <= len(context_options):
                context_size = context_options[choice_num - 1][0]
                break
            else:
                print(ui.colorize(f"Please enter 1-{len(context_options)}", ui.Colors.RED))
        except ValueError:
            print(ui.colorize("Please enter a valid number", ui.Colors.RED))
        except KeyboardInterrupt:
            print()
            raise SystemExit("Setup cancelled")

    print()
    ui.print_success(f"Selected: {context_size} context window")
    print()

    return selected_model["hf_repo"], context_size


def generate_opencode_config(
    context_size: int,
    force: bool = False
) -> Tuple[bool, str]:
    """
    Generate global OpenCode configuration file.

    Args:
        context_size: Context window size
        force: If True, overwrite existing config

    Returns:
        Tuple of (success, message)
    """
    # Use OpenCode's standard config directory
    config_dir = Path.home() / ".config" / "opencode"
    config_dir.mkdir(parents=True, exist_ok=True)

    config_file = config_dir / "opencode.jsonc"

    # Check if config already exists
    if config_file.exists() and not force:
        return True, f"Config already exists: {config_file} - skipping (use --force-reinstall to overwrite)"

    config_content = f'''{{
  "$schema": "https://opencode.ai/config.json",
  "provider": {{
    "llama": {{
      "npm": "@ai-sdk/openai-compatible",
      "name": "llama.cpp (local)",
      "options": {{
        "baseURL": "http://127.0.0.1:3456/v1",
        "toolParser": [
          {{ "type": "raw-function-call" }},
          {{ "type": "json" }}
        ]
      }},
      "models": {{
        "gemma4": {{
          "name": "Gemma 4 (Local)",
          "tool_call": true,
          "limit": {{
            "context": {context_size},
            "output": 8192
          }}
        }}
      }}
    }}
  }},
  "model": "llama/gemma4",
  "agent": {{
    "build": {{
      "prompt": "{{file:~/.config/opencode/prompts/build.txt}}",
      "permission": {{
        "edit": "allow",
        "bash": "allow",
        "webfetch": "allow"
      }}
    }}
  }}
}}'''

    try:
        # Backup existing config if forcing
        if config_file.exists() and force:
            backup_file = config_dir / "opencode.jsonc.backup"
            shutil.copy(config_file, backup_file)
            ui.print_info(f"Backed up existing config to: {backup_file}")

        config_file.write_text(config_content)
        action = "Updated" if force else "Created"
        return True, f"{action} global config: {config_file}"
    except Exception as e:
        return False, f"Failed to create config: {e}"


def generate_agents_md(force: bool = False) -> Tuple[bool, str]:
    """
    Generate global AGENTS.md with tool instructions for Gemma 4.

    Args:
        force: If True, overwrite existing file

    Returns:
        Tuple of (success, message)
    """
    # Use OpenCode's standard config directory
    config_dir = Path.home() / ".config" / "opencode"
    config_dir.mkdir(parents=True, exist_ok=True)

    agents_file = config_dir / "AGENTS.md"

    # Check if file already exists
    if agents_file.exists() and not force:
        return True, f"AGENTS.md already exists: {agents_file} - skipping (use --force-reinstall to overwrite)"

    agents_content = '''# OpenCode Agent Instructions

## Tool Usage Guidelines

When using tools, follow these exact parameter names:

### File Operations

**Read files:**
```
{
  "name": "read",
  "arguments": {
    "path": "path/to/file.txt"
  }
}
```

**Edit files:**
```
{
  "name": "edit",
  "arguments": {
    "path": "path/to/file.txt",
    "instructions": "what to change"
  }
}
```

**Create files:**
```
{
  "name": "write",
  "arguments": {
    "path": "path/to/file.txt",
    "content": "file contents"
  }
}
```

### Shell Commands

**Run bash commands:**
```
{
  "name": "bash",
  "arguments": {
    "command": "ls -la"
  }
}
```

### Web Access

**Fetch web pages:**
```
{
  "name": "webfetch",
  "arguments": {
    "url": "https://example.com",
    "query": "what information to extract"
  }
}
```

## Important Rules

1. Always use exact parameter names shown above
2. For file paths, use forward slashes (/)
3. For bash commands, test with simple commands first
4. Check tool results before proceeding
5. If a tool fails, read the error and try again with corrections
'''

    try:
        # Backup existing file if forcing
        if agents_file.exists() and force:
            backup_file = config_dir / "AGENTS.md.backup"
            shutil.copy(agents_file, backup_file)

        agents_file.write_text(agents_content)
        action = "Updated" if force else "Created"
        return True, f"{action} global guide: {agents_file}"
    except Exception as e:
        return False, f"Failed to create AGENTS.md: {e}"


def generate_build_prompt(force: bool = False) -> Tuple[bool, str]:
    """
    Generate global build.txt prompt for the build agent.

    Args:
        force: If True, overwrite existing file

    Returns:
        Tuple of (success, message)
    """
    # Use OpenCode's standard config directory
    config_dir = Path.home() / ".config" / "opencode"
    prompt_dir = config_dir / "prompts"
    prompt_dir.mkdir(parents=True, exist_ok=True)

    prompt_file = prompt_dir / "build.txt"

    # Check if file already exists
    if prompt_file.exists() and not force:
        return True, f"Build prompt already exists: {prompt_file} - skipping (use --force-reinstall to overwrite)"

    prompt_content = '''You are a software build agent. Your job is to help users build and modify code.

Available tools:
- read(path): Read file contents
- edit(path, instructions): Edit files
- write(path, content): Create new files
- bash(command): Run shell commands
- webfetch(url, query): Fetch information from the web

Guidelines:
1. Always read files before editing
2. Use bash to run builds, tests, and git commands
3. Check results after each operation
4. Ask for clarification if requirements are unclear
5. Follow the tool parameter names exactly as shown in AGENTS.md
'''

    try:
        # Backup existing file if forcing
        if prompt_file.exists() and force:
            backup_file = prompt_dir / "build.txt.backup"
            shutil.copy(prompt_file, backup_file)

        prompt_file.write_text(prompt_content)
        action = "Updated" if force else "Created"
        return True, f"{action} global prompt: {prompt_file}"
    except Exception as e:
        return False, f"Failed to create build prompt: {e}"


def display_usage_instructions(
    model_repo: str,
    context_size: int
):
    """
    Display instructions for using the setup.

    Args:
        model_repo: HuggingFace model repository
        context_size: Context window size
    """
    print()
    ui.print_header("🚀 Setup Complete!")
    print()

    print("Next steps:")
    print()

    print(ui.colorize("1. Start llama-server:", ui.Colors.CYAN + ui.Colors.BOLD))
    llama_server = shutil.which("llama-server") or "llama-server"
    print(f"   {ui.colorize(f'{llama_server} -hf {model_repo} --port 3456 -ngl 99 -c {context_size} --jinja', ui.Colors.GREEN)}")
    print()
    print("   Wait for: \"listening on http://127.0.0.1:3456\"")
    print()

    print(ui.colorize("2. Test the server:", ui.Colors.CYAN + ui.Colors.BOLD))
    print(f"   {ui.colorize('curl http://127.0.0.1:3456/health', ui.Colors.GREEN)}")
    print("   Should return: {\"status\":\"ok\"}")
    print()

    print(ui.colorize("3. Run OpenCode:", ui.Colors.CYAN + ui.Colors.BOLD))
    print(f"   {ui.colorize('cd /path/to/your/project', ui.Colors.GREEN)}")
    print(f"   {ui.colorize('opencode', ui.Colors.GREEN)}  # Opens TUI")
    print()
    print("   Or run a command:")
    print(f"   {ui.colorize('opencode run \"create a hello.txt file\"', ui.Colors.GREEN)}")
    print()

    config_dir = Path.home() / ".config" / "opencode"
    print(ui.colorize("Global config files created:", ui.Colors.CYAN + ui.Colors.BOLD))
    print(f"  • {config_dir}/opencode.jsonc")
    print(f"  • {config_dir}/AGENTS.md")
    print(f"  • {config_dir}/prompts/build.txt")
    print()

    print(ui.colorize("Tips:", ui.Colors.YELLOW + ui.Colors.BOLD))
    print("  • Run llama-server in a separate terminal, or in background:")
    print(f"    {ui.colorize(f'{llama_server} [args] > ~/llama-server.log 2>&1 &', ui.Colors.GREEN)}")
    print()
    print("  • Model is cached at: ~/.cache/huggingface/hub/")
    print("  • The -hf flag will use the cached model (no re-download)")
    print()
    print("  • Global config applies to all projects unless overridden locally")


def main(argv: Optional[list] = None) -> int:
    """Main entry point."""
    # Parse command-line arguments
    parser = argparse.ArgumentParser(
        description="OpenCode + llama.cpp Setup (Simplified)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 opencode-llama-setup.py
  python3 opencode-llama-setup.py --force-reinstall

This script installs:
  • llama.cpp via Homebrew (with Gemma 4 fixes)
  • Custom OpenCode build with tool-call compatibility
  • Configuration files for your project
        """
    )
    parser.add_argument(
        "--force-reinstall",
        action="store_true",
        help="Force reinstall even if OpenCode is already installed"
    )
    parser.add_argument(
        "--no-interactive",
        action="store_true",
        help="Run without interactive prompts (use defaults)"
    )

    args = parser.parse_args(argv)

    ui.clear_screen()

    ui.print_header("🚀 OpenCode + llama.cpp Setup (Simplified)")
    ui.print_info("Gemma 4 with tool calling support")
    ui.print_info("Based on April 2026 guide + community updates")
    print()
    ui.print_success("NEW: Using Homebrew (no source build needed!)")
    print()

    if args.force_reinstall:
        ui.print_warning("Force reinstall enabled - will rebuild everything")
        print()

    # Pre-flight check: Show what will be done
    print()
    ui.print_subheader("Pre-flight Check")
    print()

    actions_planned = []
    actions_skipped = []

    # Check prerequisites
    missing_tools = []
    for tool in ["git", "gh", "pipx", "hf", "bun"]:
        if not shutil.which(tool):
            missing_tools.append(tool)

    if missing_tools:
        actions_planned.append(f"Install missing tools: {', '.join(missing_tools)}")
    else:
        actions_skipped.append("All prerequisites already installed")

    # Check llama.cpp
    if shutil.which("llama-server") and not args.force_reinstall:
        actions_skipped.append("llama.cpp already installed")
    else:
        actions_planned.append("Install llama.cpp via Homebrew")

    # Check OpenCode
    opencode_bin = OPENCODE_INSTALL_DIR / "bin" / "opencode"
    if opencode_bin.exists() and not args.force_reinstall:
        actions_skipped.append("OpenCode already installed")
    else:
        actions_planned.append("Install and build custom OpenCode")

    # Check config files
    config_dir = Path.home() / ".config" / "opencode"
    config_file = config_dir / "opencode.jsonc"
    agents_file = config_dir / "AGENTS.md"
    prompt_file = config_dir / "prompts" / "build.txt"

    config_files_exist = config_file.exists() and agents_file.exists() and prompt_file.exists()
    if config_files_exist and not args.force_reinstall:
        actions_skipped.append("Configuration files already exist")
    else:
        actions_planned.append("Generate global configuration files")

    # Display summary
    if actions_planned:
        ui.print_info("Will perform:")
        for action in actions_planned:
            print(f"  ✓ {action}")
        print()

    if actions_skipped:
        ui.print_success("Already completed:")
        for action in actions_skipped:
            print(f"  • {action}")
        print()

    # If everything is already done, offer to skip
    if not actions_planned and actions_skipped:
        ui.print_success("Setup is already complete!")
        print()
        ui.print_info("Use --force-reinstall to rebuild everything")
        print()
        if not ui.prompt_yes_no("Continue anyway to verify setup?", default=False):
            return 0

    if not args.no_interactive:
        if not ui.prompt_yes_no("Ready to begin setup?", default=True):
            ui.print_info("Setup cancelled. Run again when ready!")
            return 0

    # Step 1: Install prerequisites
    print()
    ui.print_subheader("Prerequisites")

    success, msg = install_prerequisites()
    if not success:
        ui.print_error(msg)
        return 1

    ui.print_success(msg)

    # Step 2: Detect hardware
    print()
    hw_info = hardware.detect_hardware()

    # Validate RAM
    if hw_info.ram_gb < 16:
        ui.print_error("Insufficient RAM for Gemma 4 models")
        print("  Minimum: 16GB RAM")
        print(f"  Detected: {hw_info.ram_gb:.0f}GB RAM")
        return 1

    if hw_info.ram_gb < 24:
        ui.print_warning("Limited RAM detected")
        print(f"  Recommended: 24GB+ RAM for 26B model")
        print(f"  Detected: {hw_info.ram_gb:.0f}GB RAM")
        print(f"  You can use the E4B model (~10GB)")
        print()
        if not ui.prompt_yes_no("Continue anyway?", default=True):
            return 0

    # Step 3: Select model and context size (always prompt user)
    model_repo, context_size = get_model_choice(hw_info)

    # Step 4: Install llama.cpp via Homebrew
    print()
    ui.print_header("📦 Installing llama.cpp")
    print()

    success, msg = install_llama_cpp_homebrew(force=args.force_reinstall, show_progress=True)
    if not success:
        ui.print_error(msg)
        return 1

    ui.print_success(msg)

    # Step 5: Download the selected model
    print()
    ui.print_header("📥 Downloading Model")
    print()

    success, msg = download_model_from_hf(model_repo, force=args.force_reinstall, show_progress=True)
    if not success:
        ui.print_error(msg)
        print()
        ui.print_warning("Model download failed, but you can download manually later:")
        # Parse to get correct filename for manual download command
        try:
            repo_id, filename = parse_model_repo(model_repo)
            print(f"  hf download {repo_id} {filename}")
        except ValueError:
            print(f"  hf download {model_repo.replace(':', ' ')}")
        print()
        if not ui.prompt_yes_no("Continue with setup anyway?", default=True):
            return 1
    else:
        ui.print_success(msg)

    # Step 6: Install OpenCode official
    print()
    ui.print_header("📦 Installing OpenCode")
    print()

    success, msg = install_opencode_official(force=args.force_reinstall)
    if not success:
        ui.print_error(msg)
        return 1

    ui.print_success(msg)

    # Step 7: Build OpenCode with PR
    print()
    ui.print_header("🔧 Building Custom OpenCode")
    print()

    success, msg = build_opencode_with_pr(force=args.force_reinstall)
    if not success:
        ui.print_error(msg)
        return 1

    ui.print_success(msg)

    # Step 8: Generate global configuration files
    print()
    ui.print_header("⚙️ Generating Global Configuration")
    print()

    # Generate config
    success, msg = generate_opencode_config(context_size, force=args.force_reinstall)
    if success:
        ui.print_success(msg)
    else:
        ui.print_error(msg)
        return 1

    # Generate AGENTS.md
    success, msg = generate_agents_md(force=args.force_reinstall)
    if success:
        ui.print_success(msg)
    else:
        ui.print_error(msg)
        return 1

    # Generate build prompt
    success, msg = generate_build_prompt(force=args.force_reinstall)
    if success:
        ui.print_success(msg)
    else:
        ui.print_error(msg)
        return 1

    # Step 9: Display usage instructions
    display_usage_instructions(model_repo, context_size)

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print()
        ui.print_warning("Setup interrupted by user")
        sys.exit(130)
    except Exception as e:
        _logger.exception("Unexpected error during setup")
        ui.print_error(f"Setup failed: {type(e).__name__}: {e}")
        sys.exit(1)
