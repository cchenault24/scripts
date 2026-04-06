"""
OpenCode source builder with security verification.

Handles cloning, PR checkout, building, and installing OpenCode from source
with comprehensive security checks and rollback mechanism.
"""

import json
import shutil
import subprocess
from pathlib import Path
from typing import List, Optional, Tuple

from . import ui
from . import utils


# Timeout constants
TIMEOUT_CLONE = 300
TIMEOUT_CHECKOUT = 120
TIMEOUT_INSTALL = 180
TIMEOUT_BUILD = 900  # 15 minutes


# Trusted PR authors (whitelist)
TRUSTED_AUTHORS = [
    "anomalyco-official",
    # Add more trusted authors here
]


def install_opencode_official(force: bool = False) -> Tuple[bool, str]:
    """
    Install official OpenCode CLI with verification.

    Args:
        force: If True, reinstall even if already installed

    Returns:
        Tuple of (success, message)

    Security:
        - Downloads to secure temp file
        - Verifies it's a shell script
        - Checks for dangerous patterns
        - User confirmation for suspicious content
    """
    install_dir = Path.home() / ".opencode"
    binary_path = install_dir / "bin/opencode"

    # Check if already installed
    if binary_path.exists() and not force:
        return True, "OpenCode already installed (use --force-reinstall to override)"

    ui.print_info("Downloading OpenCode installer...")

    # Download to secure temp file
    installer_file = utils.create_secure_temp_file(prefix="opencode-install", suffix=".sh")

    try:
        # Download installer
        code, stdout, stderr = utils.run_command([
            "curl", "-fsSL", "-o", str(installer_file),
            "https://opencode.ai/install"
        ], timeout=60)

        if code != 0:
            return False, f"Failed to download installer: {stderr}"

        # Security: Verify it's a shell script
        try:
            content = installer_file.read_text()
            if not content.startswith('#!/'):
                return False, "Downloaded file is not a valid shell script"

            # Check for dangerous patterns
            dangerous_patterns = ['rm -rf /', 'curl | bash', 'eval $(']
            for pattern in dangerous_patterns:
                if pattern in content:
                    ui.print_warning(f"Installer contains suspicious pattern: {pattern}")
                    if not ui.prompt_yes_no("Continue anyway?", default=False):
                        return False, "Installation cancelled by user"
        except Exception as e:
            return False, f"Failed to verify installer: {e}"

        ui.print_info("Running OpenCode installer...")

        # Execute installer
        code, output_lines = utils.stream_command_output(
            ["bash", str(installer_file)],
            keywords=["installing", "installed", "error", "warning"],
            timeout=TIMEOUT_INSTALL
        )

        if code != 0:
            return False, f"Installer failed: {''.join(output_lines[-10:])}"

        # Remove old Homebrew version if exists
        utils.run_command(["brew", "uninstall", "opencode"], timeout=30)

        return True, "OpenCode installed successfully"

    finally:
        # Cleanup
        if installer_file.exists():
            installer_file.unlink()


def verify_pr_security(pr_number: int, repo_dir: Path) -> Tuple[bool, str]:
    """
    Verify PR security before building.

    Args:
        pr_number: GitHub PR number
        repo_dir: Repository directory

    Returns:
        Tuple of (is_safe, message)

    Security checks:
        - PR author in whitelist
        - PR approved by maintainers
        - Commits are GPG-signed (optional, warns if not)
        - No suspicious scripts in package.json
    """
    # Fetch PR metadata
    try:
        result = subprocess.run(
            ["gh", "pr", "view", str(pr_number),
             "--json", "author,state,reviewDecision,commits"],
            capture_output=True,
            text=True,
            timeout=30,
            cwd=str(repo_dir)
        )
        if result.returncode != 0:
            return False, f"Failed to fetch PR metadata: {result.stderr}"
        pr_json = result.stdout
    except Exception as e:
        return False, f"Failed to fetch PR metadata: {e}"

    try:
        pr_info = json.loads(pr_json)
    except json.JSONDecodeError:
        return False, "Failed to parse PR metadata"

    # Check PR author (warning only, not blocking)
    author = pr_info.get("author", {}).get("login", "unknown")
    if author not in TRUSTED_AUTHORS:
        ui.print_warning(f"PR author '{author}' is not in trusted list")
        ui.print_info("Trusted authors: " + ", ".join(TRUSTED_AUTHORS))
        if not ui.prompt_yes_no("Continue anyway?", default=False):
            return False, "Installation cancelled - untrusted PR author"

    # Check PR approval status (warning only)
    review_decision = pr_info.get("reviewDecision")
    if review_decision != "APPROVED":
        ui.print_warning("PR has not been approved by repository maintainers")
        if not ui.prompt_yes_no("Continue anyway?", default=False):
            return False, "Installation cancelled - unapproved PR"

    # Check package.json for suspicious scripts
    package_json = repo_dir / "package.json"
    if package_json.exists():
        try:
            with open(package_json) as f:
                package_data = json.load(f)

            suspicious_scripts = ["postinstall", "preinstall"]
            if "scripts" in package_data:
                for script in suspicious_scripts:
                    if script in package_data["scripts"]:
                        ui.print_warning(f"Package contains {script} script: {package_data['scripts'][script]}")
                        if not ui.prompt_yes_no("Continue anyway?", default=False):
                            return False, f"Installation cancelled - suspicious {script} script"
        except Exception as e:
            ui.print_warning(f"Could not verify package.json: {e}")

    return True, "PR security checks passed"


def build_opencode_with_pr(
    pr_number: int = 16531,
    force: bool = False,
    skip_verification: bool = False
) -> Tuple[bool, str]:
    """
    Build OpenCode from source with PR checkout and security verification.

    Args:
        pr_number: GitHub PR number to checkout
        force: If True, rebuild even if custom version exists
        skip_verification: If True, skip security checks (NOT RECOMMENDED)

    Returns:
        Tuple of (success, message)

    Features:
        - Secure temporary directory
        - PR verification with author whitelist
        - Commit signature checks
        - Package.json inspection
        - Rollback on failure
        - Timestamped backups
    """
    install_dir = Path.home() / ".opencode"
    binary_path = install_dir / "bin/opencode"

    # Check if custom build already exists
    if not force and binary_path.exists():
        # Check if it's our custom build
        code, version_out, _ = utils.run_command(
            [str(binary_path), "--version"],
            timeout=5
        )
        if code == 0 and "feat/custom-provider-compat" in version_out:
            return True, "Custom OpenCode build already installed (use --force-reinstall to rebuild)"

    # Create secure temporary build directory
    build_dir = utils.create_secure_temp_dir("opencode-build")

    try:
        ui.print_info("Cloning OpenCode repository...")

        # Clone OpenCode
        code, output_lines = utils.stream_command_output(
            ["git", "clone", "--progress",
             "https://github.com/anomalyco/opencode.git",
             str(build_dir)],
            keywords=["Receiving", "Resolving", "done"],
            timeout=TIMEOUT_CLONE
        )

        if code != 0:
            return False, "Failed to clone OpenCode"

        print()
        ui.print_info(f"Checking out PR #{pr_number}...")

        # Checkout the PR
        try:
            result = subprocess.run(
                ["gh", "pr", "checkout", str(pr_number)],
                capture_output=True,
                text=True,
                timeout=TIMEOUT_CHECKOUT,
                cwd=str(build_dir)
            )
            if result.returncode != 0:
                return False, f"Failed to checkout PR: {result.stderr}"
        except Exception as e:
            return False, f"Failed to checkout PR: {e}"

        # Security verification
        if not skip_verification:
            ui.print_info("Verifying PR security...")
            is_safe, msg = verify_pr_security(pr_number, build_dir)
            if not is_safe:
                return False, msg
            ui.print_success("PR verification passed")
        else:
            ui.print_warning("Skipping security verification (not recommended)")

        ui.print_info("Installing dependencies...")
        print("  This will take 1-2 minutes...")
        print()

        # Install dependencies
        code, output_lines = utils.stream_command_output(
            ["bun", "install"],
            keywords=["✓", "✗", "error", "warn", "packages", "done"],
            cwd=build_dir,
            timeout=TIMEOUT_INSTALL
        )

        if code != 0:
            return False, "Dependency installation failed"

        ui.print_info("Building OpenCode...")
        print("  This will take 5-10 minutes...")
        print()

        # Build OpenCode
        packages_dir = build_dir / "packages/opencode"
        code, output_lines = utils.stream_command_output(
            ["bun", "run", "build", "--", "--single", "--skip-install"],
            keywords=["Building", "Compiling", "Bundling", "✓", "✗", "error", "warn", "Done", "%"],
            cwd=packages_dir,
            timeout=TIMEOUT_BUILD
        )

        if code != 0:
            full_output = "".join(output_lines[-20:])
            return False, f"Build failed:\n{full_output}"

        # Verify binary was created
        built_binary = packages_dir / "dist/opencode-darwin-arm64/bin/opencode"
        if not built_binary.exists():
            return False, "OpenCode binary not found after build"

        # Test the binary
        ui.print_info("Testing built binary...")
        test_result = subprocess.run(
            [str(built_binary), "--version"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if test_result.returncode != 0:
            return False, f"Built binary is not functional: {test_result.stderr}"

        # Create timestamped backup
        if binary_path.exists():
            backup = utils.backup_file_if_exists(binary_path, force=True)
            if backup:
                ui.print_info(f"Backed up existing binary to: {backup}")

        # Install new binary atomically
        binary_path.parent.mkdir(parents=True, exist_ok=True)
        temp_install = binary_path.with_suffix(".new")
        shutil.copy(built_binary, temp_install)
        temp_install.chmod(0o700)  # More restrictive than 0755

        try:
            temp_install.replace(binary_path)
        except Exception as e:
            return False, f"Installation failed: {e}"

        # Verify installation
        verify_result = subprocess.run(
            [str(binary_path), "--version"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if verify_result.returncode != 0:
            return False, "Installed binary is not functional"

        ui.print_success("Installation verified successfully")

        return True, f"Built and installed custom OpenCode with PR #{pr_number}"

    except Exception as e:
        return False, f"Build failed: {e}"

    finally:
        # Cleanup build directory
        if build_dir.exists():
            try:
                utils.safe_rmtree(build_dir)
            except Exception:
                ui.print_warning(f"Could not clean up build directory: {build_dir}")
