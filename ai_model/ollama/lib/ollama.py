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
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import List, Optional, Tuple

from . import hardware
from . import ui
from . import utils
from .utils import get_unverified_ssl_context

# Launch Agent configuration
LAUNCH_AGENT_LABEL = "com.ollama.server"
LAUNCH_AGENT_PLIST = f"{LAUNCH_AGENT_LABEL}.plist"

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
            # Use -k flag for corporate SSL compatibility
            return "Download from https://ollama.com/download or install Homebrew first: /bin/bash -c \"$(curl -k -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    elif os_name == "Linux":
        # Use -k flag for corporate SSL compatibility
        return "curl -k -fsSL https://ollama.com/install.sh | sh"
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
                    version_code, version_out, _ = utils.run_command(["ollama", "--version"], clean_env=True)
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
        process = None
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
                    version_code, version_out, _ = utils.run_command(["ollama", "--version"], clean_env=True)
                    if version_code == 0:
                        return True, version_out.strip()
                    return True, "installed"
                return True, "installed"
            else:
                ui.print_error(f"Installation failed: {stderr}")
                return False, f"Installation failed: {stderr}"
        except subprocess.TimeoutExpired:
            # Clean up the process on timeout
            if process:
                process.kill()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
            ui.print_error("Installation timed out")
            ui.print_info("Please install manually: curl -k -fsSL https://ollama.com/install.sh | sh")
            return False, "Installation timed out"
        except Exception as e:
            ui.print_error(f"Failed to install Ollama: {e}")
            ui.print_info("Please install manually: curl -k -fsSL https://ollama.com/install.sh | sh")
            return False, str(e)
        finally:
            # Ensure process is cleaned up
            if process and process.poll() is None:
                process.kill()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
    
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
    code, stdout, stderr = utils.run_command(["ollama", "--version"], clean_env=True)
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


def start_ollama_service() -> bool:
    """
    Start Ollama service if it's not already running.
    
    Returns:
        True if Ollama is now running, False otherwise
    """
    import subprocess
    
    # First check if Ollama is already running
    try:
        req = urllib.request.Request(f"{OLLAMA_API_BASE}/api/tags", method="GET")
        with urllib.request.urlopen(req, timeout=2, context=get_unverified_ssl_context()) as response:
            if response.status == 200:
                return True  # Already running
    except (urllib.error.URLError, urllib.error.HTTPError, OSError):
        pass  # Not running, continue to start it
    
    # Check if ollama process is running
    try:
        result = subprocess.run(
            ["pgrep", "-f", "ollama serve"],
            capture_output=True,
            timeout=2
        )
        if result.returncode == 0:
            # Process exists but API not responding - wait a bit
            ui.print_info("Ollama process found, waiting for API to be ready...")
            for _ in range(10):  # Wait up to 10 seconds
                time.sleep(1)
                try:
                    req = urllib.request.Request(f"{OLLAMA_API_BASE}/api/tags", method="GET")
                    with urllib.request.urlopen(req, timeout=2, context=get_unverified_ssl_context()) as response:
                        if response.status == 200:
                            return True
                except (urllib.error.URLError, urllib.error.HTTPError, OSError):
                    continue
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass  # pgrep not available or timed out, continue to start
    
    # Start Ollama service
    ui.print_info("Starting Ollama service...")
    try:
        # Create clean environment without SSH_AUTH_SOCK
        # SSH_AUTH_SOCK causes Go's HTTP library to fail in Ollama
        clean_env = {k: v for k, v in os.environ.items() if k != 'SSH_AUTH_SOCK'}
        
        # Start ollama serve in background
        process = subprocess.Popen(
            ["ollama", "serve"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
            env=clean_env  # Pass clean environment
        )
        
        # Wait for API to become available (up to 15 seconds)
        ui.print_info("Waiting for Ollama API to be ready...")
        for attempt in range(15):
            time.sleep(1)
            try:
                req = urllib.request.Request(f"{OLLAMA_API_BASE}/api/tags", method="GET")
                with urllib.request.urlopen(req, timeout=2, context=get_unverified_ssl_context()) as response:
                    if response.status == 200:
                        ui.print_success("Ollama service started successfully")
                        return True
            except (urllib.error.URLError, urllib.error.HTTPError, OSError):
                continue
        
        # Check if process is still running
        if process.poll() is None:
            ui.print_warning("Ollama process started but API not responding yet")
            ui.print_info("It may take a few more seconds to be ready")
            return True  # Process is running, API might be slow to start
        else:
            ui.print_error("Failed to start Ollama service")
            return False
            
    except (FileNotFoundError, OSError) as e:
        ui.print_error(f"Could not start Ollama service: {e}")
        return False


def check_ollama_api(hw_info: hardware.HardwareInfo) -> bool:
    """Check if Ollama API is available and accessible. Starts Ollama if needed."""
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
        ui.print_info("Attempting to start Ollama service...")
        
        # Try to start Ollama
        if start_ollama_service():
            # Wait a moment and check again
            time.sleep(2)
            try:
                req = urllib.request.Request(f"{OLLAMA_API_BASE}/api/tags", method="GET")
                req.add_header("Content-Type", "application/json")
                with urllib.request.urlopen(req, timeout=5, context=get_unverified_ssl_context()) as response:
                    if response.status == 200:
                        api_reachable = True
                        hw_info.ollama_api_endpoint = OLLAMA_OPENAI_ENDPOINT
                        ui.print_success("Ollama API is now accessible")
                        ui.print_info(f"API endpoint: {hw_info.ollama_api_endpoint}")
                        
                        # Fetch available models from API
                        available_api_models = fetch_available_models_from_api()
                        if available_api_models:
                            ui.print_info(f"Found {len(available_api_models)} model(s) installed")
                        else:
                            ui.print_info("No models installed yet")
            except (urllib.error.URLError, urllib.error.HTTPError, OSError):
                ui.print_warning("Ollama service started but API not yet ready")
                ui.print_info("It should be available shortly")
        else:
            ui.print_warning("Could not start Ollama service automatically")
            ui.print_info("You may need to start it manually: ollama serve")
        
        hw_info.ollama_api_endpoint = OLLAMA_OPENAI_ENDPOINT
        ui.print_info(f"API endpoint (default): {hw_info.ollama_api_endpoint}")
    
    # Check for existing models using ollama list command
    code, stdout, stderr = utils.run_command(["ollama", "list"], clean_env=True)
    
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
    
    # Return True if API is reachable or if we successfully started Ollama
    # Return False only if we couldn't start it and it's definitely not available
    if api_reachable:
        return True
    elif hw_info.ollama_available:  # ollama list succeeded, so Ollama is working
        return True
    else:
        # Couldn't reach API and couldn't start service - but still return True
        # to allow setup to continue (user can start manually)
        return True


# =============================================================================
# macOS Auto-Start Functions (launchd Launch Agent)
# =============================================================================

def setup_ollama_autostart_macos() -> bool:
    """
    Set up Ollama to start automatically on macOS using launchd.
    
    Creates a Launch Agent plist file at:
    ~/Library/LaunchAgents/com.ollama.server.plist
    
    This is more reliable than Homebrew services and works regardless
    of how Ollama was installed.
    
    Returns:
        True if setup successful, False otherwise
    """
    if platform.system() != "Darwin":
        ui.print_warning("Auto-start via launchd is only available on macOS")
        return False
    
    # Find ollama path
    ollama_path = shutil.which("ollama")
    if not ollama_path:
        ui.print_error("Cannot find ollama command")
        return False
    
    # Make path absolute
    ollama_path = os.path.abspath(ollama_path)
    
    plist_content = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{LAUNCH_AGENT_LABEL}</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>{ollama_path}</string>
        <string>serve</string>
    </array>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <true/>
    
    <key>StandardOutPath</key>
    <string>/tmp/ollama.log</string>
    
    <key>StandardErrorPath</key>
    <string>/tmp/ollama.error.log</string>
    
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    
    <key>ProcessType</key>
    <string>Background</string>
    
    <key>Nice</key>
    <integer>0</integer>
</dict>
</plist>
"""
    
    # Create LaunchAgents directory if it doesn't exist
    launch_agents_dir = Path.home() / "Library" / "LaunchAgents"
    try:
        launch_agents_dir.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        ui.print_error(f"Cannot create LaunchAgents directory: {e}")
        return False
    
    # Write plist file
    plist_path = launch_agents_dir / LAUNCH_AGENT_PLIST
    
    try:
        # Check if file already exists
        if plist_path.exists():
            ui.print_warning(f"Launch Agent already exists at {plist_path}")
            if not ui.prompt_yes_no("Overwrite existing configuration?", default=True):
                return False
            # Unload existing first
            utils.run_command(["launchctl", "unload", str(plist_path)], timeout=5)
        
        # Write new plist file
        with open(plist_path, 'w') as f:
            f.write(plist_content)
        
        ui.print_success(f"Created Launch Agent: {plist_path}")
        ui.print_info(f"Ollama path: {ollama_path}")
        
        # Load the launch agent immediately
        code, stdout, stderr = utils.run_command(
            ["launchctl", "load", str(plist_path)],
            timeout=10
        )
        
        if code == 0:
            ui.print_success("Launch Agent loaded successfully")
            
            # Wait a moment for service to start
            time.sleep(2)
            
            # Verify Ollama is running
            if verify_ollama_running():
                ui.print_success("Ollama service is now running")
                ui.print_success("Ollama will start automatically on boot")
                return True
            else:
                ui.print_warning("Launch Agent loaded but Ollama may not be running yet")
                ui.print_info("It should start within a few seconds")
                ui.print_info("Check logs at: /tmp/ollama.log and /tmp/ollama.error.log")
                return True
        else:
            ui.print_error(f"Failed to load Launch Agent: {stderr}")
            ui.print_info("The Launch Agent was created but couldn't be loaded")
            ui.print_info("It will start automatically on next boot")
            ui.print_info("To start it now manually, run:")
            ui.print_info(f"  launchctl load {plist_path}")
            return True  # Still return True since file was created
            
    except PermissionError as e:
        ui.print_error(f"Permission denied: {e}")
        ui.print_info("You may need to run this script with appropriate permissions")
        return False
    except Exception as e:
        ui.print_error(f"Failed to create Launch Agent: {e}")
        return False


def remove_ollama_autostart_macos() -> bool:
    """
    Remove Ollama auto-start configuration on macOS.
    
    Unloads and removes the Launch Agent plist file.
    
    Returns:
        True if removal successful or nothing to remove, False on error
    """
    if platform.system() != "Darwin":
        ui.print_info("Auto-start removal via launchd is only available on macOS")
        return True
    
    plist_path = Path.home() / "Library" / "LaunchAgents" / LAUNCH_AGENT_PLIST
    
    if not plist_path.exists():
        ui.print_info("No Launch Agent configuration found")
        return True
    
    try:
        ui.print_info(f"Found Launch Agent: {plist_path}")
        
        # Unload the launch agent first
        code, stdout, stderr = utils.run_command(
            ["launchctl", "unload", str(plist_path)],
            timeout=10
        )
        
        if code == 0:
            ui.print_success("Launch Agent unloaded")
        else:
            # May fail if already unloaded - that's OK
            ui.print_warning(f"Could not unload Launch Agent (may not be loaded): {stderr}")
        
        # Remove the plist file
        plist_path.unlink()
        ui.print_success("Removed Launch Agent configuration")
        ui.print_info("Ollama will no longer start automatically on boot")
        
        return True
        
    except Exception as e:
        ui.print_error(f"Failed to remove Launch Agent: {e}")
        return False


def check_ollama_autostart_status_macos() -> Tuple[bool, str]:
    """
    Check if Ollama is configured to start automatically on macOS.
    
    Returns:
        Tuple of (is_configured, details)
        - is_configured: True if auto-start is set up
        - details: String describing the configuration method or status
    """
    if platform.system() != "Darwin":
        return False, "Not macOS"
    
    plist_path = Path.home() / "Library" / "LaunchAgents" / LAUNCH_AGENT_PLIST
    
    # Check for Launch Agent
    if plist_path.exists():
        # Verify it's loaded
        code, stdout, stderr = utils.run_command(
            ["launchctl", "list"],
            timeout=5
        )
        
        if code == 0 and LAUNCH_AGENT_LABEL in stdout:
            return True, f"Launch Agent (loaded, path: {plist_path})"
        else:
            return True, f"Launch Agent (created but not loaded, path: {plist_path})"
    
    # Check if Homebrew service is running (secondary check)
    if shutil.which("brew"):
        code, stdout, _ = utils.run_command(["brew", "services", "list"], timeout=5)
        if code == 0 and "ollama" in stdout.lower():
            if "started" in stdout.lower():
                return True, "Homebrew services (running)"
            else:
                return True, "Homebrew services (configured but not running)"
    
    # Check if Ollama Desktop app is handling auto-start
    # (Ollama Desktop has its own auto-start mechanism)
    ollama_app_path = Path("/Applications/Ollama.app")
    if ollama_app_path.exists():
        # Check if Ollama app is in login items (this is harder to detect)
        # For now, just note that the app exists
        pass
    
    return False, "Not configured"


def verify_ollama_running() -> bool:
    """
    Verify that Ollama service is currently running.
    
    Returns:
        True if Ollama is running and responding, False otherwise
    """
    try:
        req = urllib.request.Request(f"{OLLAMA_API_BASE}/api/tags")
        with urllib.request.urlopen(req, timeout=3, context=get_unverified_ssl_context()) as response:
            return response.status == 200
    except Exception:
        return False


def get_autostart_plist_path() -> Optional[Path]:
    """
    Get the path to the Ollama Launch Agent plist file.
    
    Returns:
        Path to the plist file, or None if not on macOS
    """
    if platform.system() != "Darwin":
        return None
    return Path.home() / "Library" / "LaunchAgents" / LAUNCH_AGENT_PLIST


def check_ssh_environment_pollution() -> bool:
    """
    Check if SSH_AUTH_SOCK is set and warn user.
    
    SSH_AUTH_SOCK (set by macOS SSH agent for git) causes Ollama to fail with
    "ssh: no key found" errors due to a bug in Go's HTTP library. This happens
    because Go's HTTP client incorrectly tries to use SSH certificates for HTTPS
    when this variable is set.
    
    Returns:
        True if SSH_AUTH_SOCK is set (potential issue), False otherwise
    """
    ssh_auth_sock = os.environ.get('SSH_AUTH_SOCK')
    
    if ssh_auth_sock:
        ui.print_warning("Detected SSH_AUTH_SOCK environment variable")
        # Only show truncated path for privacy
        display_path = ssh_auth_sock[:50] + "..." if len(ssh_auth_sock) > 50 else ssh_auth_sock
        ui.print_info(f"Value: {display_path}")
        ui.print_info("This can cause Ollama model pulls to fail with 'ssh: no key found' errors")
        ui.print_info("The script will automatically use clean environment when calling Ollama")
        print()
        return True
    
    return False
