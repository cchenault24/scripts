"""
llama.cpp backend operations.

Handles llama.cpp installation via Homebrew and GGUF model downloads from HuggingFace.
"""

import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import Optional, Tuple

from . import ui
from . import utils


# Timeout constants (seconds)
TIMEOUT_QUICK = 10
TIMEOUT_STANDARD = 60
TIMEOUT_MODERATE = 180
TIMEOUT_BUILD = 600
TIMEOUT_MODEL_DOWNLOAD = 7200  # 2 hours


def ensure_hf_token() -> Optional[str]:
    """
    Ensure HuggingFace token is available for authenticated downloads.

    Checks environment variable HF_TOKEN, prompts if not found.

    Returns:
        Token string if available, None if user skips

    Note:
        Some models require authentication. Token can be obtained from:
        https://huggingface.co/settings/tokens
    """
    # Check environment first
    token = os.environ.get("HF_TOKEN")
    if token:
        ui.print_success("HuggingFace token found in environment")
        return token

    # Prompt user
    ui.print_warning("HuggingFace token not found in environment (HF_TOKEN)")
    print()
    print("Some models require authentication to download.")
    print("You can:")
    print("  1. Set environment variable: export HF_TOKEN=hf_...")
    print("  2. Enter token now (will not be saved)")
    print("  3. Skip (may fail for gated models)")
    print()
    print("Get token from: https://huggingface.co/settings/tokens")
    print()

    if ui.prompt_yes_no("Do you have a HuggingFace token to enter?", default=False):
        token = input("Enter HF_TOKEN: ").strip()
        if token:
            # Set for current session only
            os.environ["HF_TOKEN"] = token
            ui.print_success("Token set for this session")
            return token

    ui.print_info("Continuing without HuggingFace token")
    ui.print_warning("Some models may fail to download")
    return None


def install_llama_cpp_homebrew(
    force: bool = False,
    show_progress: bool = True,
    use_head: bool = True
) -> Tuple[bool, str]:
    """
    Install llama.cpp via Homebrew.

    Args:
        force: If True, reinstall even if already installed
        show_progress: Show installation progress
        use_head: If True, install from --HEAD (latest git)
                  If False, install stable release (recommended for security)

    Returns:
        Tuple of (success, message)

    Security Note:
        Using --HEAD installs untested code from git HEAD. For production,
        consider using a pinned version instead.
    """
    # Check if already installed
    llama_server = shutil.which("llama-server")
    if llama_server and not force:
        # Get version
        code, version_out, _ = utils.run_command(
            ["llama-server", "--version"],
            timeout=TIMEOUT_QUICK
        )

        version_info = version_out.strip() if code == 0 else "unknown version"
        return True, f"llama.cpp already installed ({version_info}) - skipping"

    if show_progress:
        action = "Reinstalling" if force else "Installing"
        ui.print_info(f"{action} llama.cpp via Homebrew...")

        if use_head:
            ui.print_warning("Using --HEAD to get latest Gemma 4 fixes (untested code)")
            print("  This will take 2-5 minutes...")
        else:
            print("  Using stable release (recommended)")
        print()

    # Uninstall if forcing
    if force:
        subprocess.run(["brew", "uninstall", "llama.cpp"],
                      capture_output=True,
                      timeout=TIMEOUT_STANDARD)

    # Build install command
    install_cmd = ["brew", "install", "llama.cpp"]
    if use_head:
        install_cmd.append("--HEAD")

    # Install with streaming output
    code, output_lines = utils.stream_command_output(
        install_cmd,
        keywords=["downloading", "building", "installing", "cloning", "==", "error", "warning"],
        show_progress=show_progress,
        timeout=TIMEOUT_BUILD
    )

    if code != 0:
        full_output = "".join(output_lines[-20:])
        return False, f"Homebrew installation failed:\n{full_output}"

    # Verify installation
    llama_server = shutil.which("llama-server")
    if not llama_server:
        return False, "llama-server not found in PATH after installation"

    # Get version
    code, version_out, _ = utils.run_command(
        ["llama-server", "--version"],
        timeout=TIMEOUT_QUICK
    )

    version_info = version_out.strip() if code == 0 else "unknown"

    return True, f"Installed llama.cpp successfully ({version_info})"


def download_model_from_hf(
    model_repo: str,
    force: bool = False,
    show_progress: bool = True,
    verify_checksum: Optional[str] = None
) -> Tuple[bool, str]:
    """
    Download GGUF model from HuggingFace with security validation.

    Args:
        model_repo: HuggingFace model repository (e.g., "ggml-org/gemma-4-31B-it-GGUF:Q4_K_M")
        force: If True, re-download even if cached
        show_progress: Show download progress
        verify_checksum: Optional SHA-256 checksum to verify (recommended)

    Returns:
        Tuple of (success, message)

    Security:
        - Validates repo_id format (prevents injection)
        - Validates filename (prevents path traversal)
        - Optional checksum verification
    """
    try:
        # Parse repo and file
        if ':' not in model_repo:
            return False, f"Invalid model format: {model_repo} (expected 'repo:file')"

        repo_id, filename = model_repo.rsplit(':', 1)

        # Security: Validate repo_id format
        if not utils.validate_repo_id(repo_id):
            return False, f"Invalid repository ID: {repo_id} (must match org/repo-name)"

        # Add .gguf extension if not present
        if not filename.endswith('.gguf'):
            filename = f"{filename}.gguf"

        # Security: Validate filename
        if not utils.validate_filename(filename):
            return False, f"Invalid filename: {filename} (contains illegal characters)"

        # Ensure HuggingFace token is available (for authenticated/gated models)
        ensure_hf_token()

        # Check if model is already cached
        cache_dir = Path.home() / ".cache/huggingface/hub"
        repo_cache_name = repo_id.replace('/', '--')
        repo_cache_dir = cache_dir / f"models--{repo_cache_name}"

        if repo_cache_dir.exists() and not force:
            # Use glob for faster search
            import glob
            pattern = str(repo_cache_dir / "snapshots" / "*" / filename)
            matches = glob.glob(pattern)

            if matches:
                model_file = Path(matches[0])
                file_size_gb = model_file.stat().st_size / (1024**3)

                # Verify checksum if provided
                if verify_checksum:
                    ui.print_info("Verifying cached model checksum...")
                    if not utils.verify_file_checksum(model_file, verify_checksum):
                        ui.print_warning("Checksum mismatch, re-downloading...")
                    else:
                        return True, f"Model already downloaded: {filename} ({file_size_gb:.1f}GB) - verified"

                return True, f"Model already downloaded: {filename} ({file_size_gb:.1f}GB) - skipping"

        if show_progress:
            ui.print_info(f"Downloading model from HuggingFace...")
            print(f"  Repository: {repo_id}")
            print(f"  File: {filename}")
            print()
            print("  This may take 10-30 minutes depending on your connection...")
            print("  Download is resumable if interrupted")
            print()

        # Get path to 'hf' command
        hf_cli_path = shutil.which("hf")
        if not hf_cli_path:
            # Check known pipx location
            hf_cli_fallback = Path.home() / ".local/bin/hf"
            if hf_cli_fallback.exists():
                hf_cli_path = str(hf_cli_fallback)
            else:
                return False, "HuggingFace CLI ('hf' command) not found. Install prerequisites first."

        # Download with progress and timeout
        # Note: --local-dir-use-symlinks removed as it's not available in all hf CLI versions
        code, output_lines = utils.stream_command_output(
            [hf_cli_path, "download", repo_id, filename],
            keywords=["Downloading", "Download", "fetching", "%", "MB", "GB", "100%", "done"],
            show_progress=show_progress,
            timeout=TIMEOUT_MODEL_DOWNLOAD
        )

        if code != 0:
            error_msg = "".join(output_lines[-10:])
            return False, f"Model download failed: {error_msg}"

        # Verify download succeeded
        if not cache_dir.exists():
            return False, "HuggingFace cache directory not found after download"

        # Verify checksum if provided
        if verify_checksum:
            ui.print_info("Verifying downloaded model checksum...")
            import glob
            pattern = str(repo_cache_dir / "snapshots" / "*" / filename)
            matches = glob.glob(pattern)

            if matches:
                model_file = Path(matches[0])
                if not utils.verify_file_checksum(model_file, verify_checksum):
                    return False, "Checksum verification failed! File may be corrupted or tampered."
                ui.print_success("Checksum verified successfully")

        return True, f"Model downloaded successfully: {filename}"

    except Exception as e:
        return False, f"Download failed: {e}"


def check_disk_space(required_gb: float) -> Tuple[bool, str]:
    """
    Check if sufficient disk space is available.

    Args:
        required_gb: Required space in GB

    Returns:
        Tuple of (sufficient, message)
    """
    cache_dir = Path.home() / ".cache/huggingface"
    cache_dir.mkdir(parents=True, exist_ok=True)

    stat = shutil.disk_usage(cache_dir)
    available_gb = stat.free / (1024**3)

    if available_gb < required_gb:
        return False, f"Insufficient disk space: {available_gb:.1f}GB available, {required_gb:.1f}GB required"

    return True, f"Sufficient disk space: {available_gb:.1f}GB available"
