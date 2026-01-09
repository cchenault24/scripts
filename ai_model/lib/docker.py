"""
Docker and Docker Model Runner management.

Provides functions to check Docker installation, Docker Model Runner availability,
and interact with the DMR API.
"""

import json
import shutil
import urllib.error
import urllib.request
from typing import List, Tuple

from . import hardware
from . import ui
from . import utils


# Docker Model Runner API configuration
# DMR exposes an OpenAI-compatible API endpoint
DMR_API_HOST = "localhost"
DMR_API_PORT = 12434  # Default Docker Model Runner port
DMR_API_BASE = f"http://{DMR_API_HOST}:{DMR_API_PORT}/v1"

# Alternative: Docker Model Runner can also be accessed via Docker socket
# For some setups, the endpoint might be different
DMR_SOCKET_ENDPOINT = "http://model-runner.docker.internal/v1"


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
        
        with urllib.request.urlopen(req, timeout=5) as response:
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
    
    # Docker Model Runner was introduced in Docker Desktop 4.40+
    # It uses the 'docker model' command namespace
    # Docs: https://docs.docker.com/ai/model-runner/
    code, stdout, stderr = utils.run_command(["docker", "model", "list"])
    
    if code == 0:
        hw_info.docker_model_runner_available = True
        ui.print_success("Docker Model Runner is available and running")
        
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
                with urllib.request.urlopen(req, timeout=5) as response:
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
