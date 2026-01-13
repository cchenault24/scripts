"""
Docker and Docker Model Runner management.

Provides functions to check Docker installation, Docker Model Runner availability,
and interact with the DMR API.
"""

import json
import re
import shutil
import socket
import urllib.error
import urllib.request
from typing import List, Optional, Tuple

from . import hardware
from . import models
from . import ui
from . import utils
from .utils import get_unverified_ssl_context

# Docker Model Runner API configuration
# DMR exposes an OpenAI-compatible API endpoint
DMR_API_HOST = "localhost"
DMR_API_PORT = 12434  # Default Docker Model Runner port
DMR_API_BASE = f"http://{DMR_API_HOST}:{DMR_API_PORT}/v1"

# Alternative: Docker Model Runner can also be accessed via Docker socket
# For some setups, the endpoint might be different
DMR_SOCKET_ENDPOINT = "http://model-runner.docker.internal/v1"


def _is_port_open(host: str, port: int, timeout_s: float = 0.5) -> bool:
    """Return True if TCP connect succeeds."""
    try:
        with socket.create_connection((host, port), timeout=timeout_s):
            return True
    except OSError:
        return False


def check_dmr_port_conflict() -> Tuple[bool, str]:
    """
    Detect whether localhost:12434 is usable by Docker Model Runner.

    Returns:
        (ok, message)
        - ok=True: port is free OR appears to be DMR
        - ok=False: port is in use by a non-DMR service
    """
    host, port = DMR_API_HOST, DMR_API_PORT
    if not _is_port_open(host, port):
        return True, f"Port {host}:{port} is available (nothing listening)"

    # Something is listening - verify it's DMR (OpenAI-compatible /v1/models)
    try:
        req = urllib.request.Request(f"{DMR_API_BASE}/models", method="GET")
        req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=2, context=get_unverified_ssl_context()) as response:
            if response.status == 200:
                return True, f"Port {host}:{port} is in use by Docker Model Runner (API reachable)"
    except Exception:
        pass

    return False, f"Port {host}:{port} is in use by another service (DMR API not detected)"


def detect_docker_allocated_ram_gib() -> Tuple[Optional[float], str]:
    """
    Best-effort detection of Docker Engine/VM memory allocation.

    For Docker Desktop this typically corresponds to the VM memory allocation.

    Returns:
        (ram_gib, reason)
    """
    # Preferred: bytes from docker info template
    code, stdout, stderr = utils.run_command(["docker", "info", "--format", "{{.MemTotal}}"], timeout=10)
    if code == 0:
        s = (stdout or "").strip()
        if s.isdigit():
            try:
                bytes_total = int(s)
                gib = bytes_total / (1024 ** 3)
                return gib, f"Detected Docker memory from `docker info --format {{.MemTotal}}` ({gib:.2f} GiB)"
            except Exception:
                pass

    # Fallback: parse "Total Memory:" line from docker info
    code, stdout, stderr2 = utils.run_command(["docker", "info"], timeout=10)
    if code == 0:
        for line in (stdout or "").splitlines():
            if "Total Memory:" not in line:
                continue
            # Examples: " Total Memory: 7.775GiB" or "Total Memory: 15.5GiB"
            m = re.search(r"Total Memory:\s*([0-9.]+)\s*([A-Za-z]+)", line)
            if not m:
                continue
            try:
                val = float(m.group(1))
                unit = m.group(2)
                unit_lower = unit.lower()
                if unit_lower.startswith("g"):
                    return val, f"Detected Docker memory from `docker info` ({val:.2f} {unit})"
                if unit_lower.startswith("m"):
                    return val / 1024.0, f"Detected Docker memory from `docker info` ({val:.2f} {unit})"
            except Exception:
                continue

    err = (stderr or stderr2 or "").strip()
    return None, f"Could not detect Docker memory allocation ({err or 'no details'})"


def select_context_size_tokens(docker_ram_gib: Optional[float]) -> Tuple[int, str]:
    """
    Select context size tokens based on Docker allocated RAM.

    Mapping (per requirements):
    - 8-11GB   ->  8,192
    - 12-15GB  -> 16,384
    - 16-23GB  -> 24,576
    - 24-31GB  -> 32,768
    - 32GB+    -> 49,152

    Default: 32,768 if detection fails.
    """
    if docker_ram_gib is None:
        return 32768, "Docker RAM detection failed; defaulting to 32,768 tokens (safe default)"

    # Use conservative banding for fractional/edge values: round down to safest matching tier.
    if docker_ram_gib < 12:
        return 8192, f"Docker RAM ~{docker_ram_gib:.1f}GiB (<12GiB); selecting 8,192 tokens"
    if docker_ram_gib < 16:
        return 16384, f"Docker RAM ~{docker_ram_gib:.1f}GiB (12-15GiB); selecting 16,384 tokens"
    if docker_ram_gib < 24:
        return 24576, f"Docker RAM ~{docker_ram_gib:.1f}GiB (16-23GiB); selecting 24,576 tokens"
    if docker_ram_gib < 32:
        return 32768, f"Docker RAM ~{docker_ram_gib:.1f}GiB (24-31GiB); selecting 32,768 tokens"
    return 49152, f"Docker RAM ~{docker_ram_gib:.1f}GiB (32GiB+); selecting 49,152 tokens"


def configure_docker_model_context(model_name: str, context_tokens: int) -> bool:
    """Configure Docker Model Runner context size for a model."""
    code, stdout, stderr = utils.run_command(
        ["docker", "model", "configure", f"--context-size={context_tokens}", model_name],
        timeout=30
    )
    if code == 0:
        ui.print_success(f"Configured DMR context-size={context_tokens} for {model_name}")
        return True
    ui.print_warning(f"Could not configure context-size for {model_name}: {stderr.strip() or stdout.strip()}")
    return False


def configure_model_runner_restart_policy() -> bool:
    """
    Configure Docker Model Runner container(s) to auto-start on reboot.

    Applies: docker update --restart unless-stopped <container>
    """
    code, stdout, stderr = utils.run_command(["docker", "ps", "-a", "--format", "{{.ID}}\t{{.Names}}\t{{.Image}}"], timeout=10)
    if code != 0:
        ui.print_warning(f"Could not list containers to set restart policy: {stderr.strip()}")
        return False

    candidates: List[str] = []
    for line in (stdout or "").splitlines():
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        cid, name, image = parts[0].strip(), parts[1].strip(), parts[2].strip()
        hay = f"{name} {image}".lower()
        if "model-runner" in hay or "modelrunner" in hay:
            candidates.append(cid or name)

    if not candidates:
        ui.print_warning("Could not find a Docker Model Runner container to set restart policy on.")
        ui.print_info("Once DMR has started at least once, re-run this script or run:")
        print(ui.colorize("    docker ps -a | grep -i model-runner", ui.Colors.CYAN))
        return False

    ok_any = False
    for cid in candidates:
        code, stdout, stderr = utils.run_command(["docker", "update", "--restart", "unless-stopped", cid], timeout=10)
        if code == 0:
            ok_any = True
            ui.print_success(f"Set restart policy: unless-stopped ({cid})")
        else:
            ui.print_warning(f"Failed to set restart policy for {cid}: {stderr.strip() or stdout.strip()}")
    return ok_any


def apply_dmr_runtime_settings(
    model_names: List[str],
    hw_info: hardware.HardwareInfo,
    also_configure_model: str = "gpt-oss:20B-UD-Q6_K_XL",
) -> None:
    """
    Apply runtime settings to Docker Model Runner:
    - Configure per-model context size (docker model configure --context-size=...)
    - Configure container restart policy (--restart unless-stopped)
    """
    ui.print_subheader("Configuring Docker Model Runner Runtime")

    # Validate Docker daemon is running before issuing changes
    code, _, stderr = utils.run_command(["docker", "info"], timeout=10)
    if code != 0:
        ui.print_warning("Docker daemon is not running; skipping DMR runtime configuration.")
        ui.print_info("Start Docker Desktop and re-run to apply context sizing + auto-start settings.")
        return

    # Determine context tokens (prefer values computed earlier)
    context_tokens = hw_info.dmr_context_size_tokens if hw_info and hw_info.dmr_context_size_tokens else 0
    reason = hw_info.dmr_context_reason if hw_info else ""
    if context_tokens <= 0:
        docker_ram_gib, ram_reason = detect_docker_allocated_ram_gib()
        context_tokens, ctx_reason = select_context_size_tokens(docker_ram_gib)
        reason = f"{ctx_reason}. {ram_reason}"

    ui.print_info(f"Configuring DMR context-size={context_tokens} ({reason or 'dynamic sizing'})")

    # Configure restart policy so the model runner comes back after reboot
    configure_model_runner_restart_policy()

    # Configure requested default model explicitly (even if user didn't select it)
    if also_configure_model:
        configure_docker_model_context(also_configure_model, context_tokens)

    # Configure selected/pulled models (dedupe)
    seen: set[str] = set()
    for name in model_names:
        n = (name or "").strip()
        if not n or n in seen:
            continue
        seen.add(n)
        configure_docker_model_context(n, context_tokens)


def check_docker() -> Tuple[bool, str]:
    """Check if Docker is installed and running."""
    ui.print_subheader("Checking Docker Installation")

    # Check if docker command exists
    if not shutil.which("docker"):
        ui.print_error("Docker not found in PATH")
        return False, ""

    # Check docker version
    code, stdout, stderr = utils.run_command(["docker", "--version"])
    if code != 0:
        ui.print_error(f"Failed to get Docker version: {stderr}")
        return False, ""

    version = stdout.strip()
    ui.print_info(f"Docker version: {version}")

    # Check if Docker daemon is running
    code, stdout, stderr = utils.run_command(["docker", "info"])
    if code != 0:
        ui.print_error("Docker daemon is not running")
        ui.print_info("Please start Docker Desktop and try again")
        return False, version

    ui.print_success("Docker is installed and running")
    return True, version


def check_docker_model_runner_status() -> Tuple[bool, str]:
    """
    Simple check if Docker Model Runner is available (no side effects).

    This is a quiet check suitable for the uninstaller that doesn't print
    anything or require hardware info.

    Returns:
        Tuple of (is_available, message)
    """
    # Check if docker command exists
    if not shutil.which("docker"):
        return False, "Docker not found"

    # Check if Docker daemon is running
    code, _, _ = utils.run_command(["docker", "info"], timeout=5)
    if code != 0:
        return False, "Docker daemon not running"

    # Check Docker Model Runner
    code, stdout, stderr = utils.run_command(["docker", "model", "list"], timeout=5)

    if code == 0:
        return True, "Docker Model Runner is available"

    error_lower = stderr.lower()
    if "unknown command" in error_lower or "not found" in error_lower:
        return False, "Docker Model Runner is not enabled"

    return False, f"Docker Model Runner check failed: {stderr[:100] if stderr else 'Unknown error'}"


def fetch_available_models_from_api(endpoint: str) -> List[str]:
    """
    Fetch list of available models from Docker Model Runner API.
    According to docs: https://docs.docker.com/ai/model-runner/api-reference/
    The API exposes OpenAI-compatible endpoints including /models
    """
    available_models = []
    try:
        api_url = f"{endpoint}/models"
        req = urllib.request.Request(api_url, method="GET")
        req.add_header("Content-Type", "application/json")

        with urllib.request.urlopen(req, timeout=5, context=get_unverified_ssl_context()) as response:
            if response.status == 200:
                data = json.loads(response.read().decode('utf-8'))
                if "data" in data:
                    for model in data["data"]:
                        model_id = model.get("id", "")
                        if model_id:
                            available_models.append(model_id)
    except (urllib.error.URLError, urllib.error.HTTPError, OSError, json.JSONDecodeError):
        pass

    return available_models


def check_docker_model_runner(hw_info: hardware.HardwareInfo) -> bool:
    """Check if Docker Model Runner is available."""
    # Input validation
    if not hw_info:
        raise ValueError("hw_info is required")

    ui.print_subheader("Checking Docker Model Runner (DMR)")

    # Port conflict detection (localhost:12434)
    ok_port, port_msg = check_dmr_port_conflict()
    if ok_port:
        ui.print_info(port_msg)
    else:
        ui.print_warning(port_msg)
        ui.print_warning("Docker Model Runner may not be able to start until this port conflict is resolved.")
        ui.print_info("If you need DMR on 12434, stop the conflicting service or change its port.")

    # Docker Model Runner was introduced in Docker Desktop 4.40+
    # It uses the 'docker model' command namespace
    # Docs: https://docs.docker.com/ai/model-runner/
    code, stdout, stderr = utils.run_command(["docker", "model", "list"])

    if code == 0:
        hw_info.docker_model_runner_available = True
        ui.print_success("Docker Model Runner is available and running")

        # Dynamic context sizing based on Docker RAM allocation
        docker_ram_gib, ram_reason = detect_docker_allocated_ram_gib()
        if docker_ram_gib is not None:
            hw_info.docker_allocated_ram_gib = docker_ram_gib
        context_tokens, ctx_reason = select_context_size_tokens(docker_ram_gib)
        hw_info.dmr_context_size_tokens = context_tokens
        hw_info.dmr_context_reason = f"{ctx_reason}. {ram_reason}"

        ui.print_info(f"Selected contextLength={context_tokens} tokens ({ctx_reason})")
        ui.print_info("If you want a larger context window, increase Docker Desktop → Resources → Memory.")

        # Determine the API endpoint
        # Try the standard localhost endpoint first
        hw_info.dmr_api_endpoint = DMR_API_BASE

        # Check if we can reach the API
        api_reachable = False
        available_api_models = []
        for endpoint in [DMR_API_BASE, DMR_SOCKET_ENDPOINT, "http://localhost:8080/v1"]:
            try:
                req = urllib.request.Request(f"{endpoint}/models", method="GET")
                req.add_header("Content-Type", "application/json")
                with urllib.request.urlopen(req, timeout=5, context=get_unverified_ssl_context()) as response:
                    if response.status == 200:
                        hw_info.dmr_api_endpoint = endpoint
                        api_reachable = True
                        ui.print_info(f"API endpoint: {endpoint}")
                        # Fetch available models from API
                        available_api_models = fetch_available_models_from_api(endpoint)
                        if available_api_models:
                            ui.print_info(f"Found {len(available_api_models)} model(s) via API")
                        break
            except (urllib.error.URLError, urllib.error.HTTPError, OSError):
                continue

        if not api_reachable:
            ui.print_info(f"API endpoint (default): {hw_info.dmr_api_endpoint}")
            ui.print_warning("Could not verify API endpoint - it may start when a model runs")

        # Store available models for later verification
        hw_info.available_api_models = available_api_models

        # Store empty list - we only support fixed models (GPT-OSS and nomic-embed-text)
        hw_info.available_docker_hub_models = []

        # Check for existing models
        lines = stdout.strip().split("\n")
        if len(lines) > 1:  # Has models (first line is header)
            ui.print_info("Installed models:")
            for line in lines[1:]:
                if line.strip():
                    parts = line.split()
                    if parts:
                        print(f"    • {parts[0]}")
        else:
            ui.print_info("No models installed yet")

        # Show Apple Silicon optimization status
        if hw_info.has_apple_silicon:
            ui.print_success("Metal GPU acceleration enabled for Apple Silicon")

        return True

    # Check if it's just not enabled or not installed
    error_lower = stderr.lower()
    if "unknown command" in error_lower or "docker model" in error_lower or "not found" in error_lower:
        ui.print_warning("Docker Model Runner is not enabled")
        print()
        ui.print_info("Docker Model Runner requires Docker Desktop 4.40 or later.")
        print()

        if hw_info.os_name == "Darwin":
            ui.print_info(ui.colorize("To enable on macOS:", ui.Colors.BOLD))
            ui.print_info("  1. Open Docker Desktop")
            ui.print_info("  2. Click the ⚙️ Settings icon (top right)")
            ui.print_info("  3. Go to 'Features in development' or 'Beta features'")
            ui.print_info("  4. Enable 'Docker Model Runner' or 'Enable Docker AI'")
            ui.print_info("  5. Click 'Apply & restart'")
            print()
            ui.print_info("Or run this command:")
            print(ui.colorize("     docker desktop enable model-runner --tcp 12434", ui.Colors.CYAN))
        else:
            ui.print_info("To enable Docker Model Runner:")
            ui.print_info("  1. Open Docker Desktop")
            ui.print_info("  2. Go to Settings → Features in development")
            ui.print_info("  3. Enable 'Docker Model Runner' or 'Enable Docker AI'")
            ui.print_info("  4. Click 'Apply & restart'")

        print()

        if ui.prompt_yes_no("Would you like to continue setup anyway (config will be generated but models won't be pulled)?"):
            hw_info.dmr_api_endpoint = DMR_API_BASE
            return True
        return False

    ui.print_error(f"Error checking Docker Model Runner: {stderr}")
    return False


def get_docker_memory_allocation() -> Optional[float]:
    """
    Get Docker memory allocation in GB.

    Returns:
        Memory allocation in GB as float, or None if unable to detect
    """
    try:
        code, stdout, _ = utils.run_command(
            ["docker", "info", "--format", "{{.MemTotal}}"],
            timeout=10,
            clean_env=True
        )
        if code == 0 and stdout.strip():
            # Docker returns memory in bytes
            mem_bytes = int(stdout.strip())
            mem_gb = mem_bytes / (1024 ** 3)
            return mem_gb
    except (ValueError, OSError):
        pass
    return None


def get_docker_cpu_allocation() -> Optional[int]:
    """
    Get Docker CPU allocation.

    Returns:
        Number of CPUs allocated to Docker, or None if unable to detect
    """
    try:
        code, stdout, _ = utils.run_command(
            ["docker", "info", "--format", "{{.NCPU}}"],
            timeout=10,
            clean_env=True
        )
        if code == 0 and stdout.strip():
            cpu_count = int(stdout.strip())
            return cpu_count
    except (ValueError, OSError):
        pass
    return None


def validate_docker_resources(hw_info: hardware.HardwareInfo) -> Tuple[bool, bool]:
    """
    Validate Docker resource allocation (memory and CPU).

    Checks:
    - Docker memory allocation vs system RAM
    - Recommends: Total RAM - 8GB (for macOS + React Native app)
    - Minimum acceptable: 8GB after allocation (16GB total system RAM minimum)
    - Warns if allocation is too high (within 7GB of total system RAM)

    Args:
        hw_info: Hardware information containing system RAM

    Returns:
        Tuple of (is_acceptable, should_continue):
        - is_acceptable: True if resources meet minimum requirements
        - should_continue: True if user wants to proceed (or resources are acceptable)
    """
    ui.print_subheader("Validating Docker Resource Allocation")

    system_ram_gb = hw_info.ram_gb
    docker_mem_gb = get_docker_memory_allocation()
    docker_cpu = get_docker_cpu_allocation()

    # Display current allocation
    if docker_mem_gb is not None:
        ui.print_info(f"Docker Memory Allocation: {docker_mem_gb:.1f}GB")
    else:
        ui.print_warning("Could not detect Docker memory allocation")

    if docker_cpu is not None:
        ui.print_info(f"Docker CPU Allocation: {docker_cpu} cores")
    else:
        ui.print_info("Could not detect Docker CPU allocation")

    ui.print_info(f"System RAM: {system_ram_gb:.1f}GB")
    print()

    # Calculate recommendations
    recommended_mem_gb = max(0, system_ram_gb - 8.0)  # Reserve 8GB for macOS + React Native app
    minimum_system_ram = 16.0  # Minimum total system RAM
    minimum_available = 8.0  # Minimum available after Docker allocation

    # Determine CPU recommendation based on system
    if hw_info.cpu_cores > 0:
        # Recommend 6-10 CPUs depending on system
        if hw_info.cpu_cores >= 10:
            recommended_cpu = 10
        elif hw_info.cpu_cores >= 8:
            recommended_cpu = 8
        else:
            recommended_cpu = min(6, hw_info.cpu_cores)
    else:
        recommended_cpu = 6

    # Check if system RAM meets minimum
    if system_ram_gb < minimum_system_ram:
        ui.print_error(f"System RAM ({system_ram_gb:.1f}GB) is below minimum ({minimum_system_ram:.0f}GB)")
        ui.print_error("This setup requires at least 16GB total system RAM")
        print()
        if not ui.prompt_yes_no("Continue anyway? (Not recommended)", default=False):
            return False, False
        return False, True

    # If we couldn't detect Docker memory, warn but allow continuation
    if docker_mem_gb is None:
        ui.print_warning("Could not verify Docker memory allocation")
        ui.print_info("Please verify Docker Desktop settings manually")
        print()
        ui.print_info("Recommended settings:")
        ui.print_info(f"  Memory: {recommended_mem_gb:.1f}GB (Total RAM - 8GB)")
        ui.print_info(f"  CPUs: {recommended_cpu} cores")
        print()
        if ui.prompt_yes_no("Continue with setup?", default=True):
            return True, True
        return False, False

    # Calculate available RAM after Docker allocation
    available_after_docker = system_ram_gb - docker_mem_gb

    # Check if allocation is too high (within 7GB of total system RAM)
    if available_after_docker < 7.0:
        ui.print_warning("Docker memory allocation is very high")
        ui.print_warning(f"Only {available_after_docker:.1f}GB will remain for macOS and your React app")
        ui.print_warning("This may starve the system and cause performance issues")
        print()

    # Check if below minimum available
    is_below_minimum = available_after_docker < minimum_available

    # Check if significantly different from recommendation
    mem_diff = abs(docker_mem_gb - recommended_mem_gb)
    is_suboptimal = mem_diff > 2.0 or is_below_minimum  # More than 2GB difference or below minimum

    if is_suboptimal:
        ui.print_warning("Docker resource allocation is suboptimal")
        print()

        # Show current vs recommended
        print(ui.colorize("Current Configuration:", ui.Colors.BOLD))
        print(f"  Memory: {docker_mem_gb:.1f}GB allocated")
        print(f"  Available for system/apps: {available_after_docker:.1f}GB")
        if docker_cpu is not None:
            print(f"  CPUs: {docker_cpu} cores")
        print()

        print(ui.colorize("Recommended Configuration:", ui.Colors.BOLD))
        print(f"  Memory: {recommended_mem_gb:.1f}GB (Total RAM - 8GB)")
        print(f"  Available for system/apps: 8.0GB")
        print(f"  CPUs: {recommended_cpu} cores")
        print()

        # Explanation
        ui.print_info("Why these settings?")
        ui.print_info("  • We need ~8GB reserved for macOS system operations")
        ui.print_info("  • Your React app also needs memory to run")
        ui.print_info("  • Too much Docker memory can starve the system")
        print()

        # Instructions
        ui.print_info(ui.colorize("How to adjust:", ui.Colors.BOLD))
        ui.print_info("  1. Open Docker Desktop")
        ui.print_info("  2. Click the ⚙️ Settings icon (top right)")
        ui.print_info("  3. Go to 'Resources' → 'Advanced'")
        ui.print_info("  4. Adjust the following:")
        print(ui.colorize(f"     • Memory: Set to {recommended_mem_gb:.1f}GB", ui.Colors.CYAN))
        print(ui.colorize(f"     • CPUs: Set to {recommended_cpu} cores", ui.Colors.CYAN))
        ui.print_info("  5. Click 'Apply & restart'")
        print()

        if is_below_minimum:
            ui.print_error(f"Available RAM ({available_after_docker:.1f}GB) is below minimum ({minimum_available:.0f}GB)")
            ui.print_error("This may cause system instability and app crashes")
            print()
            if not ui.prompt_yes_no("Continue anyway? (Not recommended)", default=False):
                return False, False
            return False, True
        else:
            if not ui.prompt_yes_no("Continue with current settings? (Recommended to adjust first)", default=False):
                return False, False
            return False, True
    else:
        # Resources are acceptable
        ui.print_success("Docker resource allocation looks good")
        if docker_cpu is not None and docker_cpu < recommended_cpu:
            ui.print_info(f"Note: Consider increasing CPU allocation to {recommended_cpu} cores for better performance")
        print()
        return True, True
