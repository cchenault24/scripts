"""
Prerequisites management for llama.cpp setup.

Handles installation of required tools with security validation.
"""

from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import List, Tuple
import shutil

from . import ui
from . import utils


class InstallMethod(Enum):
    """Installation methods for prerequisites."""
    HOMEBREW = "brew"
    PIPX = "pipx"
    OFFICIAL_SCRIPT = "official"


@dataclass
class Prerequisite:
    """Tool prerequisite definition."""
    name: str
    install_method: InstallMethod
    package_name: str
    binary_paths: List[Path]
    required: bool = True


# Tool catalog for llama.cpp setup
PREREQUISITES = [
    Prerequisite("git", InstallMethod.HOMEBREW, "git",
                 [Path("/usr/bin/git"), Path("/usr/local/bin/git"), Path("/opt/homebrew/bin/git")]),
    Prerequisite("gh", InstallMethod.HOMEBREW, "gh",
                 [Path("/usr/local/bin/gh"), Path("/opt/homebrew/bin/gh")]),
    Prerequisite("pipx", InstallMethod.HOMEBREW, "pipx",
                 [Path.home() / ".local/bin/pipx"]),
    Prerequisite("hf", InstallMethod.PIPX, "huggingface-hub[cli]",
                 [Path.home() / ".local/bin/hf"]),
    Prerequisite("bun", InstallMethod.OFFICIAL_SCRIPT, None,
                 [Path.home() / ".bun/bin/bun"]),
]


def is_tool_available(prereq: Prerequisite) -> bool:
    """Check if tool is available in PATH or known locations."""
    # Check PATH first
    if shutil.which(prereq.name):
        return True

    # Check known installation locations
    for binary_path in prereq.binary_paths:
        if binary_path.exists() and binary_path.is_file():
            # Ensure it's in PATH for current session
            utils.safely_add_to_path(binary_path.parent)
            return True

    return False


def install_via_homebrew(package_name: str, timeout: int = 300) -> Tuple[bool, str]:
    """Install package via Homebrew."""
    ui.print_info(f"Installing {package_name} via Homebrew...")

    code, output_lines = utils.stream_command_output(
        ["brew", "install", package_name],
        keywords=["downloading", "installing", "pouring", "error", "warning"],
        timeout=timeout
    )

    if code != 0:
        return False, f"Homebrew installation failed: {''.join(output_lines[-10:])}"

    return True, f"Installed {package_name} via Homebrew"


def install_via_pipx(package_name: str, timeout: int = 180) -> Tuple[bool, str]:
    """Install Python CLI tool via pipx."""
    ui.print_info(f"Installing {package_name} via pipx...")

    # Ensure pipx bin directory is in PATH
    pipx_bin = Path.home() / ".local/bin"
    if pipx_bin.exists():
        utils.safely_add_to_path(pipx_bin)

    # For huggingface-hub, ensure clean install
    if "huggingface-hub" in package_name:
        utils.run_command(["pipx", "uninstall", "huggingface-hub"], timeout=30)

    code, output_lines = utils.stream_command_output(
        ["pipx", "install", package_name, "--force"],
        keywords=["installing", "installed", "error", "warning"],
        timeout=timeout
    )

    if code != 0:
        return False, f"pipx installation failed: {''.join(output_lines[-10:])}"

    return True, f"Installed {package_name} via pipx"


def install_bun_official(timeout: int = 300) -> Tuple[bool, str]:
    """Install bun via official installer with security verification."""
    ui.print_info("Installing bun via official installer...")

    # Download installer to secure temp file
    installer_file = utils.create_secure_temp_file(prefix="bun-install", suffix=".sh")

    try:
        # Download installer
        code, stdout, stderr = utils.run_command([
            "curl", "-fsSL", "-o", str(installer_file),
            "https://bun.sh/install"
        ], timeout=60)

        if code != 0:
            return False, f"Failed to download bun installer: {stderr}"

        # Verify installer is a shell script
        try:
            content = installer_file.read_text()
            if not content.startswith('#!/'):
                return False, "Downloaded file is not a valid shell script"

            # Basic sanity checks for dangerous patterns
            dangerous_patterns = ['rm -rf /', 'curl | bash', 'eval $(']
            for pattern in dangerous_patterns:
                if pattern in content:
                    ui.print_warning(f"Installer contains suspicious pattern: {pattern}")
                    if not ui.prompt_yes_no("Continue anyway?", default=False):
                        return False, "Installation cancelled by user"
        except Exception as e:
            return False, f"Failed to verify installer: {e}"

        # Execute installer
        code, output_lines = utils.stream_command_output(
            ["bash", str(installer_file)],
            keywords=["installing", "installed", "error"],
            timeout=timeout
        )

        if code != 0:
            return False, f"Bun installation failed: {''.join(output_lines[-10:])}"

        # Add bun to PATH for current session
        bun_bin = Path.home() / ".bun/bin"
        if bun_bin.exists():
            utils.safely_add_to_path(bun_bin)

        return True, "Installed bun successfully"

    finally:
        # Cleanup
        if installer_file.exists():
            installer_file.unlink()


def install_all_prerequisites(force_reinstall: bool = False) -> Tuple[bool, str]:
    """
    Install all required prerequisites with progress tracking.

    Args:
        force_reinstall: If True, reinstall even if already present

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

    # Track installation results
    installed_tools = []
    failed_tools = []

    for prereq in PREREQUISITES:
        # Check if already installed (unless forcing)
        if not force_reinstall and is_tool_available(prereq):
            ui.print_success(f"{prereq.name} installed")
            continue

        # Tool needs installation
        ui.print_warning(f"{prereq.name} not found, installing...")

        try:
            if prereq.install_method == InstallMethod.HOMEBREW:
                success, msg = install_via_homebrew(prereq.package_name)

                # Special handling for pipx: ensure path configured
                if prereq.name == "pipx" and success:
                    utils.run_command(["pipx", "ensurepath"], timeout=30)
                    pipx_bin = Path.home() / ".local/bin"
                    if pipx_bin.exists():
                        utils.safely_add_to_path(pipx_bin)

            elif prereq.install_method == InstallMethod.PIPX:
                success, msg = install_via_pipx(prereq.package_name)

            elif prereq.install_method == InstallMethod.OFFICIAL_SCRIPT:
                if prereq.name == "bun":
                    success, msg = install_bun_official()
                else:
                    success, msg = False, f"Unknown tool for official install: {prereq.name}"
            else:
                success, msg = False, f"Unknown install method: {prereq.install_method}"

            if success:
                ui.print_success(msg)
                installed_tools.append(prereq.name)
            else:
                ui.print_error(msg)
                if prereq.required:
                    failed_tools.append((prereq.name, msg))

        except Exception as e:
            error_msg = f"Exception during {prereq.name} install: {e}"
            ui.print_error(error_msg)
            if prereq.required:
                failed_tools.append((prereq.name, error_msg))

    # Report results
    if failed_tools:
        return False, f"Failed to install required tools: {', '.join(t[0] for t in failed_tools)}"

    return True, "All prerequisites installed successfully"
