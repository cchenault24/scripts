"""
Ollama management.

Provides functions to check Ollama installation, Ollama API availability,
and interact with the Ollama API.
"""

import json
import os
import platform
import shutil
import subprocess
import urllib.error
import urllib.request
from typing import List, Tuple

from . import hardware
from . import ui
from . import utils
from .utils import get_unverified_ssl_context

# Ollama API configuration
# Ollama exposes an OpenAI-compatible API endpoint
OLLAMA_API_HOST = "localhost"
OLLAMA_API_PORT = 11434  # Default Ollama port
OLLAMA_API_BASE = f"http://{OLLAMA_API_HOST}:{OLLAMA_API_PORT}"
OLLAMA_OPENAI_ENDPOINT = f"{OLLAMA_API_BASE}/v1"  # OpenAI-compatible endpoint


def get_installation_instructions() -> str:
    """Get OS-specific Ollama installation instructions."""
    os_name = platform.system()
    
    if os_name == "Darwin":  # macOS
        # Check if Homebrew is available
        if shutil.which("brew"):
            return "brew install ollama"
        else:
            return "Download from https://ollama.com/download or install Homebrew first: /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    elif os_name == "Linux":
        return "curl -fsSL https://ollama.com/install.sh | sh"
    elif os_name == "Windows":
        return "Download installer from https://ollama.com/download"
    else:
        return "Visit https://ollama.com/download for installation instructions"


def install_ollama() -> Tuple[bool, str]:
    """
    Attempt to install Ollama automatically based on the operating system.
    
    Returns:
        Tuple of (success, message)
    """
    os_name = platform.system()
    ui.print_subheader("Installing Ollama")
    
    if os_name == "Darwin":  # macOS
        # Try Homebrew first
        if shutil.which("brew"):
            ui.print_info("Installing Ollama via Homebrew...")
            code, stdout, stderr = utils.run_command(["brew", "install", "ollama"], timeout=300)
            if code == 0:
                ui.print_success("Ollama installed successfully via Homebrew")
                # Verify installation
                ollama_path = shutil.which("ollama")
                if ollama_path:
                    version_code, version_out, _ = utils.run_command(["ollama", "--version"])
                    if version_code == 0:
                        return True, version_out.strip()
                    return True, "installed"
                return True, "installed"
            else:
                ui.print_error(f"Homebrew installation failed: {stderr}")
                return False, "Homebrew installation failed"
        else:
            ui.print_warning("Homebrew not found. Cannot install automatically.")
            ui.print_info("Please install Ollama manually:")
            ui.print_info("  1. Download from https://ollama.com/download")
            ui.print_info("  2. Or install Homebrew first, then run: brew install ollama")
            return False, "Homebrew not available"
    
    elif os_name == "Linux":
        ui.print_info("Installing Ollama via official install script...")
        ui.print_warning("This will download and run the Ollama install script.")
        ui.print_info("The script will install Ollama to ~/.local/bin or /usr/local/bin")
        
        # Download and run the install script
        try:
            import urllib.request
            install_script_url = "https://ollama.com/install.sh"
            req = urllib.request.Request(install_script_url)
            with urllib.request.urlopen(req, timeout=30, context=get_unverified_ssl_context()) as response:
                script_content = response.read().decode('utf-8')
            
            # Run the script
            process = subprocess.Popen(
                ["bash", "-s"],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            stdout, stderr = process.communicate(input=script_content, timeout=300)
            
            if process.returncode == 0:
                ui.print_success("Ollama installed successfully")
                # Verify installation
                ollama_path = shutil.which("ollama")
                if ollama_path:
                    version_code, version_out, _ = utils.run_command(["ollama", "--version"])
                    if version_code == 0:
                        return True, version_out.strip()
                    return True, "installed"
                return True, "installed"
            else:
                ui.print_error(f"Installation failed: {stderr}")
                return False, f"Installation failed: {stderr}"
        except Exception as e:
            ui.print_error(f"Failed to install Ollama: {e}")
            ui.print_info("Please install manually: curl -fsSL https://ollama.com/install.sh | sh")
            return False, str(e)
    
    else:
        ui.print_warning(f"Automatic installation not supported on {os_name}")
        ui.print_info("Please install Ollama manually from https://ollama.com/download")
        return False, f"Unsupported OS: {os_name}"


def check_ollama() -> Tuple[bool, str]:
    """Check if Ollama is installed and running."""
    ui.print_subheader("Checking Ollama Installation")
    
    # Check if ollama command exists
    ollama_path = shutil.which("ollama")
    if not ollama_path:
        ui.print_error("Ollama not found in PATH")
        print()
        ui.print_info("Ollama is required for this setup.")
        print()
        
        # Show installation instructions
        instructions = get_installation_instructions()
        os_name = platform.system()
        
        if os_name == "Darwin" and shutil.which("brew"):
            ui.print_info("Installation options:")
            ui.print_info("  Option 1 (Recommended): Automatic installation via Homebrew")
            ui.print_info("  Option 2: Manual download from https://ollama.com/download")
            print()
            
            if ui.prompt_yes_no("Would you like to install Ollama automatically via Homebrew?", default=True):
                success, version = install_ollama()
                if success:
                    # Re-check after installation - refresh PATH
                    # Try to refresh PATH by checking common locations
                    common_paths = [
                        os.path.expanduser("~/.local/bin"),
                        "/usr/local/bin",
                        "/opt/homebrew/bin",
                    ]
                    for path in common_paths:
                        if os.path.exists(os.path.join(path, "ollama")):
                            os.environ["PATH"] = f"{path}:{os.environ.get('PATH', '')}"
                            break
                    
                    ollama_path = shutil.which("ollama")
                    if ollama_path:
                        ui.print_success("Ollama installation verified")
                        # Continue to version check below (don't return yet)
                    else:
                        ui.print_warning("Ollama was installed but not found in PATH")
                        ui.print_info("You may need to restart your terminal or run: export PATH=\"$PATH:$HOME/.local/bin\"")
                        ui.print_info("After updating PATH, run this script again")
                        return False, version
                else:
                    ui.print_error("Automatic installation failed")
                    ui.print_info("Please install Ollama manually and try again")
                    return False, ""
            else:
                    ui.print_info("Manual installation instructions:")
                    ui.print_info(f"  Run: {instructions}")
                    ui.print_info("  Or download from: https://ollama.com/download")
                    return False, ""
        
        elif os_name == "Linux":
            ui.print_info("Installation options:")
            ui.print_info("  Option 1 (Recommended): Automatic installation via install script")
            ui.print_info("  Option 2: Manual download from https://ollama.com/download")
            print()
            
            if ui.prompt_yes_no("Would you like to install Ollama automatically?", default=True):
                success, version = install_ollama()
                if success:
                    # Re-check after installation - refresh PATH
                    # Try to refresh PATH by checking common locations
                    common_paths = [
                        os.path.expanduser("~/.local/bin"),
                        "/usr/local/bin",
                        "/opt/homebrew/bin",
                    ]
                    for path in common_paths:
                        if os.path.exists(os.path.join(path, "ollama")):
                            os.environ["PATH"] = f"{path}:{os.environ.get('PATH', '')}"
                            break
                    
                    ollama_path = shutil.which("ollama")
                    if ollama_path:
                        ui.print_success("Ollama installation verified")
                        # Continue to version check below (don't return yet)
                    else:
                        ui.print_warning("Ollama was installed but not found in PATH")
                        ui.print_info("You may need to restart your terminal or add ~/.local/bin to your PATH")
                        ui.print_info("After updating PATH, run this script again")
                        return False, version
                else:
                    ui.print_error("Automatic installation failed")
                    ui.print_info("Please install Ollama manually and try again")
                    return False, ""
            else:
                ui.print_info("Manual installation instructions:")
                ui.print_info(f"  Run: {instructions}")
                return False, ""
        
        else:
            # Windows or other OS - show manual instructions
            ui.print_info("Please install Ollama manually:")
            ui.print_info(f"  {instructions}")
            ui.print_info("  Or visit: https://ollama.com/download")
            return False, ""
    
    # If we get here, ollama_path should exist (either was already installed or just installed)
    # Check ollama version
    code, stdout, stderr = utils.run_command(["ollama", "--version"])
    if code != 0:
        ui.print_error(f"Failed to get Ollama version: {stderr}")
        return False, ""
    
    version = stdout.strip()
    ui.print_info(f"Ollama version: {version}")
    
    # Check if Ollama service is running by checking the API
    try:
        req = urllib.request.Request(f"{OLLAMA_API_BASE}/api/tags", method="GET")
        with urllib.request.urlopen(req, timeout=5, context=get_unverified_ssl_context()) as response:
            if response.status == 200:
                ui.print_success("Ollama is installed and running")
                return True, version
    except (urllib.error.URLError, urllib.error.HTTPError, OSError):
        ui.print_warning("Ollama is installed but the service may not be running")
        ui.print_info("Ollama will start automatically when you pull your first model")
        ui.print_info("You can also start it manually by running: ollama serve")
        # Don't fail here - Ollama can start on-demand
        return True, version
    
    ui.print_success("Ollama is installed and running")
    return True, version


def fetch_available_models_from_api(endpoint: str = None) -> List[str]:
    """
    Fetch list of available models from Ollama API.
    
    Args:
        endpoint: Optional API endpoint (defaults to OLLAMA_API_BASE)
    
    Returns:
        List of model names available via Ollama API
    """
    if endpoint is None:
        endpoint = OLLAMA_API_BASE
    
    available_models = []
    try:
        api_url = f"{endpoint}/api/tags"
        req = urllib.request.Request(api_url, method="GET")
        req.add_header("Content-Type", "application/json")
        
        with urllib.request.urlopen(req, timeout=5, context=get_unverified_ssl_context()) as response:
            if response.status == 200:
                data = json.loads(response.read().decode('utf-8'))
                if "models" in data:
                    for model in data["models"]:
                        model_name = model.get("name", "")
                        if model_name:
                            available_models.append(model_name)
    except (urllib.error.URLError, urllib.error.HTTPError, OSError, json.JSONDecodeError):
        pass
    
    return available_models


def check_ollama_api(hw_info: hardware.HardwareInfo) -> bool:
    """Check if Ollama API is available and accessible."""
    # Input validation
    if not hw_info:
        raise ValueError("hw_info is required")
    
    ui.print_subheader("Checking Ollama API")
    
    # Check if Ollama API is accessible
    api_reachable = False
    available_api_models = []
    
    try:
        req = urllib.request.Request(f"{OLLAMA_API_BASE}/api/tags", method="GET")
        req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=5, context=get_unverified_ssl_context()) as response:
            if response.status == 200:
                api_reachable = True
                hw_info.ollama_api_endpoint = OLLAMA_OPENAI_ENDPOINT
                ui.print_success("Ollama API is accessible")
                ui.print_info(f"API endpoint: {hw_info.ollama_api_endpoint}")
                
                # Fetch available models from API
                available_api_models = fetch_available_models_from_api()
                if available_api_models:
                    ui.print_info(f"Found {len(available_api_models)} model(s) installed")
                else:
                    ui.print_info("No models installed yet")
    except (urllib.error.URLError, urllib.error.HTTPError, OSError) as e:
        ui.print_warning("Could not reach Ollama API")
        ui.print_info("The API may not be running. Ollama will start automatically when you pull a model.")
        hw_info.ollama_api_endpoint = OLLAMA_OPENAI_ENDPOINT
        ui.print_info(f"API endpoint (default): {hw_info.ollama_api_endpoint}")
    
    # Check for existing models using ollama list command
    code, stdout, stderr = utils.run_command(["ollama", "list"])
    
    if code == 0:
        hw_info.ollama_available = True
        lines = stdout.strip().split("\n")
        if len(lines) > 1:  # Has models (first line is header)
            ui.print_info("Installed models:")
            for line in lines[1:]:
                if line.strip():
                    parts = line.split()
                    if parts:
                        model_name = parts[0]
                        print(f"    • {model_name}")
        else:
            ui.print_info("No models installed yet")
    else:
        # If ollama list fails, it might mean Ollama isn't running
        # But we'll still allow setup to continue
        hw_info.ollama_available = True
        ui.print_warning("Could not list models (Ollama may not be running)")
        ui.print_info("Models will be available after pulling")
    
    # Store available models for later verification
    hw_info.available_api_models = available_api_models
    
    # Show Apple Silicon optimization status
    if hw_info.has_apple_silicon:
        ui.print_success("Metal GPU acceleration will be used automatically for Apple Silicon")
    
    return True
