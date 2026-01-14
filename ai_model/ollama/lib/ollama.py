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
from typing import Any, Dict, List, Optional, Tuple

from . import hardware
from . import ui
from . import utils
from .utils import get_unverified_ssl_context

# Launch Agent configuration
LAUNCH_AGENT_LABEL = "com.ollama.server"
LAUNCH_AGENT_PLIST = f"{LAUNCH_AGENT_LABEL}.plist"

# Ollama API configuration
# Ollama exposes an OpenAI-compatible API endpoint
# IMPORTANT: Use 127.0.0.1 instead of localhost for VPN resilience
# VPNs can modify DNS/routing and break localhost resolution
OLLAMA_API_HOST = "127.0.0.1"  # Use IP address for VPN resilience
OLLAMA_API_PORT = 11434  # Default Ollama port
OLLAMA_API_BASE = f"http://{OLLAMA_API_HOST}:{OLLAMA_API_PORT}"
OLLAMA_OPENAI_ENDPOINT = f"{OLLAMA_API_BASE}/v1"  # OpenAI-compatible endpoint

# VPN-resilient environment variables
VPN_RESILIENT_ENV = {
    "OLLAMA_HOST": f"{OLLAMA_API_HOST}:{OLLAMA_API_PORT}",
    "NO_PROXY": "localhost,127.0.0.1,::1",
}


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
    
    On macOS, if auto-start is configured, uses launchd to start it.
    Otherwise, starts a temporary process and optionally offers to set up auto-start.
    
    Returns:
        True if Ollama is now running, False otherwise
    """
    import subprocess
    
    # First check if Ollama is already running
    if verify_ollama_running():
        return True  # Already running
    
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
                if verify_ollama_running():
                    return True
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass  # pgrep not available or timed out, continue to start
    
    # On macOS, check if auto-start is configured and use it
    if platform.system() == "Darwin":
        is_configured, details = check_ollama_autostart_status_macos()
        if is_configured:
            plist_path = get_autostart_plist_path()
            if plist_path and plist_path.exists():
                ui.print_info("Using configured auto-start to start Ollama...")
                # Load/start the launch agent
                code, stdout, stderr = utils.run_command(
                    ["launchctl", "load", str(plist_path)],
                    timeout=10
                )
                
                if code == 0:
                    # Wait for service to start
                    ui.print_info("Waiting for Ollama service to start...")
                    for attempt in range(15):
                        time.sleep(1)
                        if verify_ollama_running():
                            ui.print_success("Ollama service started via auto-start")
                            return True
                    
                    # Check if it's loaded even if API not ready yet
                    code2, stdout2, _ = utils.run_command(
                        ["launchctl", "list", LAUNCH_AGENT_LABEL],
                        timeout=5
                    )
                    if code2 == 0:
                        ui.print_warning("Ollama auto-start loaded but API not ready yet")
                        ui.print_info("It should be available shortly")
                        return True
                else:
                    # Auto-start exists but couldn't load - fall through to temporary start
                    ui.print_warning(f"Could not load auto-start: {stderr}")
                    ui.print_info("Starting Ollama temporarily...")
    
    # Start Ollama service temporarily (will be killed when terminal/script exits)
    ui.print_info("Starting Ollama service...")
    
    # Check for port conflicts before starting
    if check_port_in_use(OLLAMA_API_PORT):
        port_info = get_port_process_info(OLLAMA_API_PORT)
        if port_info:
            ui.print_warning(f"Port {OLLAMA_API_PORT} is in use by process {port_info['pid']} ({port_info['command']})")
            ui.print_info("You may need to stop that process first")
            ui.print_info(f"  Try: kill {port_info['pid']}")
        else:
            ui.print_warning(f"Port {OLLAMA_API_PORT} appears to be in use")
            ui.print_info("Another process may be using this port")
    
    try:
        # Check if Ollama is installed
        if not shutil.which("ollama"):
            ui.print_error("Ollama command not found in PATH")
            ui.print_info("Please ensure Ollama is installed")
            ui.print_info("  macOS: brew install ollama")
            ui.print_info("  Or download from: https://ollama.com/download")
            return False
        
        # Create VPN-resilient environment
        # - Remove SSH_AUTH_SOCK to prevent Go HTTP client issues
        # - Set OLLAMA_HOST to use 127.0.0.1 instead of localhost
        # - Set NO_PROXY to prevent VPN proxy interception
        clean_env = {k: v for k, v in os.environ.items() if k != 'SSH_AUTH_SOCK'}
        clean_env['OLLAMA_HOST'] = VPN_RESILIENT_ENV['OLLAMA_HOST']
        clean_env['NO_PROXY'] = VPN_RESILIENT_ENV['NO_PROXY']
        
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
            if verify_ollama_running():
                ui.print_success("Ollama service started successfully")
                
                # On macOS, warn if not using auto-start
                if platform.system() == "Darwin":
                    is_configured, _ = check_ollama_autostart_status_macos()
                    if not is_configured:
                        ui.print_warning("⚠️  Ollama is running temporarily and will stop when you close this terminal")
                        ui.print_info("To keep Ollama running permanently, set up auto-start during setup")
                
                return True
        
        # Check if process is still running
        if process.poll() is None:
            ui.print_warning("Ollama process started but API not responding yet")
            ui.print_info("It may take a few more seconds to be ready")
            ui.print_info("Check logs if issues persist")
            return True  # Process is running, API might be slow to start
        else:
            ui.print_error("Failed to start Ollama service")
            ui.print_info("The process exited unexpectedly")
            ui.print_info("Check if Ollama is installed correctly: ollama --version")
            return False
            
    except (FileNotFoundError, OSError) as e:
        ui.print_error(f"Could not start Ollama service: {e}")
        
        # Provide troubleshooting info
        if not shutil.which("ollama"):
            ui.print_error("Ollama command not found in PATH")
            ui.print_info("Please install Ollama first")
        else:
            ui.print_info("Troubleshooting steps:")
            ui.print_info("  1. Verify Ollama is installed: ollama --version")
            ui.print_info("  2. Try starting manually: ollama serve")
            ui.print_info("  3. Check for port conflicts: lsof -i :11434")
        
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
    
    VPN Resilience:
    - Configures OLLAMA_HOST=127.0.0.1:11434 to bypass DNS resolution
    - Sets NO_PROXY to prevent VPN from intercepting local connections
    - Uses KeepAlive=true for automatic restart on failure
    
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
    
    # VPN-resilient plist with EnvironmentVariables for OLLAMA_HOST and NO_PROXY
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
    
    <!-- VPN Resilience: KeepAlive ensures Ollama restarts on VPN connect/disconnect -->
    <key>KeepAlive</key>
    <true/>
    
    <key>StandardOutPath</key>
    <string>/tmp/ollama.log</string>
    
    <key>StandardErrorPath</key>
    <string>/tmp/ollama.error.log</string>
    
    <!-- VPN Resilience: Environment variables to bypass DNS/proxy issues -->
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <!-- Use 127.0.0.1 instead of localhost to bypass VPN DNS modifications -->
        <key>OLLAMA_HOST</key>
        <string>{OLLAMA_API_HOST}:{OLLAMA_API_PORT}</string>
        <!-- Prevent VPN from intercepting local connections -->
        <key>NO_PROXY</key>
        <string>localhost,127.0.0.1,::1</string>
    </dict>
    
    <key>ProcessType</key>
    <string>Background</string>
    
    <key>Nice</key>
    <integer>0</integer>
    
    <key>ThrottleInterval</key>
    <integer>10</integer>
    
    <key>WorkingDirectory</key>
    <string>{os.path.expanduser('~')}</string>
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


# =============================================================================
# Port and Process Management Functions
# =============================================================================

def check_port_in_use(port: int) -> bool:
    """
    Check if a port is already in use.
    
    Args:
        port: Port number to check
        
    Returns:
        True if port is in use, False otherwise
    """
    import socket
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(1)
            result = s.connect_ex(('localhost', port))
            return result == 0
    except Exception:
        return False


def get_port_process_info(port: int) -> Optional[Dict[str, str]]:
    """
    Get information about the process using a port.
    
    Args:
        port: Port number to check
        
    Returns:
        Dict with 'pid' and 'command' keys, or None if not found
    """
    try:
        # Use lsof on macOS/Linux
        code, stdout, _ = utils.run_command(
            ["lsof", "-i", f":{port}", "-P", "-n", "-t"],
            timeout=5
        )
        if code == 0 and stdout.strip():
            pid = stdout.strip().split('\n')[0]
            # Get command name for this PID
            code2, stdout2, _ = utils.run_command(
                ["ps", "-p", pid, "-o", "comm="],
                timeout=5
            )
            command = stdout2.strip() if code2 == 0 and stdout2.strip() else "unknown"
            return {
                "pid": pid,
                "command": command
            }
    except Exception:
        pass
    return None


def get_ollama_process_info() -> Dict[str, Any]:
    """
    Get information about running Ollama processes.
    
    Returns:
        Dict with process information
    """
    info: Dict[str, Any] = {
        "pids": [],
        "count": 0,
        "via_launchd": False
    }
    
    try:
        # Check for processes
        code, stdout, _ = utils.run_command(
            ["pgrep", "-f", "ollama serve"],
            timeout=5
        )
        if code == 0 and stdout.strip():
            pids = [pid.strip() for pid in stdout.strip().split('\n') if pid.strip()]
            info["pids"] = pids
            info["count"] = len(pids)
        
        # Check if running via launchd (macOS)
        if platform.system() == "Darwin":
            code2, stdout2, _ = utils.run_command(
                ["launchctl", "list", LAUNCH_AGENT_LABEL],
                timeout=5
            )
            if code2 == 0:
                info["via_launchd"] = True
    except Exception:
        pass
    
    return info


def get_autostart_plist_path() -> Optional[Path]:
    """
    Get the path to the Ollama Launch Agent plist file.
    
    Returns:
        Path to the plist file, or None if not on macOS
    """
    if platform.system() != "Darwin":
        return None
    return Path.home() / "Library" / "LaunchAgents" / LAUNCH_AGENT_PLIST


# =============================================================================
# Service Status and Management Functions
# =============================================================================

def get_ollama_service_status() -> Dict[str, Any]:
    """
    Get comprehensive status of Ollama service.
    
    Returns:
        Dict with status information:
        - running: bool - Is Ollama currently running?
        - api_accessible: bool - Can we reach the API?
        - auto_start_configured: bool - Is auto-start set up?
        - auto_start_method: str - How is auto-start configured (launchd/systemd/etc)
        - process_info: dict - Process details if running
        - port_in_use: bool - Is port 11434 in use?
        - port_process: dict - Info about process using port (if different from Ollama)
    """
    status: Dict[str, Any] = {
        "running": False,
        "api_accessible": False,
        "auto_start_configured": False,
        "auto_start_method": None,
        "process_info": {},
        "port_in_use": False,
        "port_process": None,
    }
    
    # Check if API is accessible
    status["api_accessible"] = verify_ollama_running()
    status["running"] = status["api_accessible"]
    
    # Check auto-start configuration
    if platform.system() == "Darwin":
        is_configured, details = check_ollama_autostart_status_macos()
        status["auto_start_configured"] = is_configured
        status["auto_start_method"] = details if is_configured else None
    
    # Check port usage
    status["port_in_use"] = check_port_in_use(OLLAMA_API_PORT)
    
    # Get process info if running
    if status["running"]:
        status["process_info"] = get_ollama_process_info()
    
    # Check if port is used by something other than Ollama
    if status["port_in_use"] and not status["running"]:
        port_info = get_port_process_info(OLLAMA_API_PORT)
        if port_info:
            status["port_process"] = port_info
    
    return status


def stop_ollama_service() -> bool:
    """
    Stop Ollama service gracefully.
    
    On macOS, tries to stop via launchd first, then falls back to pkill.
    
    Returns:
        True if stopped successfully or not running, False on error
    """
    if not verify_ollama_running():
        ui.print_info("Ollama is not running")
        return True
    
    # Try to stop via launchd first (macOS)
    if platform.system() == "Darwin":
        plist_path = get_autostart_plist_path()
        if plist_path and plist_path.exists():
            ui.print_info("Stopping Ollama via Launch Agent...")
            code, _, stderr = utils.run_command(
                ["launchctl", "unload", str(plist_path)],
                timeout=10
            )
            if code == 0:
                # Wait a moment and verify
                time.sleep(2)
                if not verify_ollama_running():
                    ui.print_success("Ollama service stopped")
                    return True
                else:
                    ui.print_warning("Launch Agent unloaded but Ollama still running")
                    # Fall through to pkill
    
    # Fallback: kill process
    ui.print_info("Stopping Ollama process...")
    try:
        code, _, _ = utils.run_command(["pkill", "ollama"], timeout=5, clean_env=True)
        time.sleep(2)
        if not verify_ollama_running():
            ui.print_success("Ollama service stopped")
            return True
        else:
            ui.print_warning("Ollama may still be running")
            return False
    except Exception as e:
        ui.print_error(f"Failed to stop Ollama: {e}")
        return False


def restart_ollama_service() -> bool:
    """
    Restart Ollama service.
    
    Stops the service if running, then starts it again.
    
    Returns:
        True if restart successful, False otherwise
    """
    ui.print_info("Restarting Ollama service...")
    stop_ollama_service()
    time.sleep(2)
    return start_ollama_service()


def remove_ollama() -> Tuple[bool, List[str]]:
    """
    Remove Ollama installation from the system.
    
    Based on official Ollama uninstall documentation:
    https://docs.ollama.com/macos#uninstall
    
    Returns:
        Tuple of (success, list_of_errors):
        - success: True if removal was successful
        - list_of_errors: List of error messages for items that couldn't be removed
    """
    errors: List[str] = []
    removed_items: List[str] = []
    
    # Check if Ollama is running
    if verify_ollama_running():
        ui.print_warning("Ollama is currently running")
        ui.print_info("Attempting to stop Ollama service...")
        
        # Try to stop Ollama
        try:
            code, _, _ = utils.run_command(["pkill", "ollama"], timeout=5, clean_env=True)
            time.sleep(2)  # Give it time to stop
        except Exception as e:
            errors.append(f"Could not stop Ollama service: {e}")
    
    # Check if installed via Homebrew (macOS)
    is_homebrew_install = False
    if platform.system() == "Darwin" and shutil.which("brew"):
        try:
            code, stdout, _ = utils.run_command(["brew", "list", "ollama"], timeout=5, clean_env=True)
            if code == 0:
                is_homebrew_install = True
                ui.print_info("Detected Ollama installed via Homebrew")
                ui.print_warning("For Homebrew installations, it's recommended to use: brew uninstall ollama")
                ui.print_info("This script will attempt to remove files, but Homebrew-managed files may remain")
                print()
        except Exception:
            pass  # Ignore errors checking Homebrew
    
    # Remove auto-start configuration first (if exists)
    if platform.system() == "Darwin":
        autostart_removed = remove_ollama_autostart_macos()
        if autostart_removed:
            removed_items.append("Auto-start configuration")
    
    # Paths to remove (macOS)
    paths_to_remove = []
    
    if platform.system() == "Darwin":
        # Application
        paths_to_remove.append(("/Applications/Ollama.app", "Ollama application"))
        
        # CLI binary
        paths_to_remove.append(("/usr/local/bin/ollama", "Ollama CLI binary"))
        
        # Application Support
        app_support = Path.home() / "Library" / "Application Support" / "Ollama"
        paths_to_remove.append((str(app_support), "Application Support directory"))
        
        # Saved Application State
        saved_state = Path.home() / "Library" / "Saved Application State" / "com.electron.ollama.savedState"
        paths_to_remove.append((str(saved_state), "Saved Application State"))
        
        # Caches
        cache1 = Path.home() / "Library" / "Caches" / "com.electron.ollama"
        paths_to_remove.append((str(cache1), "Electron cache"))
        
        cache2 = Path.home() / "Library" / "Caches" / "ollama"
        paths_to_remove.append((str(cache2), "Ollama cache"))
        
        # WebKit cache
        webkit_cache = Path.home() / "Library" / "WebKit" / "com.electron.ollama"
        paths_to_remove.append((str(webkit_cache), "WebKit cache"))
    
    # User data directory (all platforms)
    ollama_data = Path.home() / ".ollama"
    paths_to_remove.append((str(ollama_data), "Ollama data directory (~/.ollama)"))
    
    # Remove each path
    for path_str, description in paths_to_remove:
        path = Path(path_str)
        
        if not path.exists():
            continue
        
        try:
            if path.is_dir():
                shutil.rmtree(path)
                removed_items.append(description)
                ui.print_success(f"Removed: {description}")
            elif path.is_file() or path.is_symlink():
                # For /usr/local/bin/ollama, might need sudo
                if path_str == "/usr/local/bin/ollama":
                    # Try without sudo first
                    try:
                        path.unlink()
                        removed_items.append(description)
                        ui.print_success(f"Removed: {description}")
                    except PermissionError:
                        # Need sudo - inform user
                        errors.append(f"{description} requires sudo to remove. Run: sudo rm {path_str}")
                        ui.print_warning(f"{description} requires sudo. Run: sudo rm {path_str}")
                else:
                    path.unlink()
                    removed_items.append(description)
                    ui.print_success(f"Removed: {description}")
        except PermissionError as e:
            error_msg = f"{description}: Permission denied. May need sudo."
            errors.append(error_msg)
            ui.print_warning(f"Could not remove {description}: Permission denied")
        except (OSError, IOError, shutil.Error) as e:
            error_msg = f"{description}: {e}"
            errors.append(error_msg)
            ui.print_warning(f"Could not remove {description}: {e}")
    
    # Summary
    if removed_items:
        ui.print_success(f"Removed {len(removed_items)} item(s)")
    
    if errors:
        ui.print_warning(f"Could not remove {len(errors)} item(s) (see details above)")
        ui.print_info("You may need to remove these manually or use sudo")
    
    # Verify removal
    ollama_exists = shutil.which("ollama")
    if ollama_exists:
        if is_homebrew_install:
            errors.append("Ollama CLI still found. If installed via Homebrew, run: brew uninstall ollama")
            ui.print_warning("Ollama CLI still found in PATH")
            ui.print_info("If installed via Homebrew, run: brew uninstall ollama")
        else:
            errors.append("Ollama CLI still found in PATH. May need to restart terminal or check other locations.")
            ui.print_warning("Ollama CLI still found in PATH")
    else:
        ui.print_success("Ollama CLI no longer found in PATH")
    
    # If Homebrew install, suggest proper uninstall method
    if is_homebrew_install and ollama_exists:
        ui.print_info("")
        ui.print_info("To complete removal of Homebrew-installed Ollama:")
        ui.print_info("  brew uninstall ollama")
    
    success = len(errors) == 0
    return success, errors


# =============================================================================
# VPN Resilience Functions
# =============================================================================

def setup_vpn_resilient_environment() -> None:
    """
    Configure environment variables for VPN resilience.
    
    VPNs (especially corporate VPNs) can break localhost connections by:
    - Modifying DNS resolution
    - Changing routing tables
    - Intercepting connections via proxy
    
    This function sets environment variables to bypass these issues.
    """
    # Use 127.0.0.1 instead of localhost to bypass DNS
    os.environ['OLLAMA_HOST'] = VPN_RESILIENT_ENV['OLLAMA_HOST']
    
    # Prevent proxy interception of local connections
    os.environ['NO_PROXY'] = VPN_RESILIENT_ENV['NO_PROXY']
    
    # Remove SSH_AUTH_SOCK which can cause HTTPS corruption with some Go HTTP clients
    os.environ.pop('SSH_AUTH_SOCK', None)


def verify_model_server(retry_on_failure: bool = True, max_retries: int = 3) -> bool:
    """
    Verify that the Ollama model server is accessible and restart if needed.
    
    This function is VPN-resilient - it uses curl with -k flag to handle
    corporate SSL interception and tests the 127.0.0.1 endpoint.
    
    Args:
        retry_on_failure: If True, attempt to restart the service on failure
        max_retries: Maximum number of restart attempts
    
    Returns:
        True if server is accessible, False otherwise
    """
    import subprocess
    
    api_url = f"{OLLAMA_API_BASE}/api/version"
    
    # Use curl -k to handle corporate SSL interception
    def check_server() -> bool:
        try:
            result = subprocess.run(
                ["curl", "-k", "-s", "-f", "--connect-timeout", "5", api_url],
                capture_output=True,
                timeout=10
            )
            return result.returncode == 0
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            return False
    
    # First check
    if check_server():
        return True
    
    if not retry_on_failure:
        return False
    
    # Server not responding, try to restart
    ui.print_warning("Ollama model server not responding, attempting restart...")
    
    for attempt in range(max_retries):
        ui.print_info(f"Restart attempt {attempt + 1}/{max_retries}...")
        
        # Try to restart the service
        if restart_ollama_service():
            # Wait for service to be ready
            time.sleep(3)
            
            if check_server():
                ui.print_success("Ollama model server is now accessible")
                return True
        
        if attempt < max_retries - 1:
            time.sleep(2)  # Wait before next attempt
    
    ui.print_error("Failed to restore Ollama model server connectivity")
    ui.print_info("Please check Ollama logs: /tmp/ollama.log and /tmp/ollama.error.log")
    return False


def update_shell_profile_for_vpn() -> bool:
    """
    Update ~/.zshrc with VPN-resilient environment variables.
    
    Appends the following if not already present:
    - export OLLAMA_HOST="127.0.0.1:11434"
    - export NO_PROXY="localhost,127.0.0.1,::1"
    - unset SSH_AUTH_SOCK
    
    Returns:
        True if profile was updated or already configured, False on error
    """
    zshrc_path = Path.home() / ".zshrc"
    
    # VPN-resilient shell configuration block
    vpn_config_marker = "# Ollama VPN Resilience Configuration"
    vpn_config_block = f'''
{vpn_config_marker}
# Use IP address instead of localhost to bypass VPN DNS modifications
export OLLAMA_HOST="127.0.0.1:11434"
# Prevent VPN proxy from intercepting local connections
export NO_PROXY="localhost,127.0.0.1,::1"
# Prevent SSH_AUTH_SOCK from corrupting HTTPS connections
unset SSH_AUTH_SOCK
# End Ollama VPN Resilience Configuration
'''
    
    try:
        # Check if already configured
        if zshrc_path.exists():
            current_content = zshrc_path.read_text()
            if vpn_config_marker in current_content:
                ui.print_info("VPN resilience already configured in ~/.zshrc")
                return True
        else:
            current_content = ""
        
        # Backup existing .zshrc
        if zshrc_path.exists():
            backup_path = zshrc_path.with_suffix(".zshrc.backup")
            shutil.copy(zshrc_path, backup_path)
            ui.print_info(f"Backed up existing .zshrc to {backup_path}")
        
        # Append VPN configuration
        with open(zshrc_path, "a") as f:
            f.write(vpn_config_block)
        
        ui.print_success("Updated ~/.zshrc with VPN-resilient configuration")
        ui.print_info("Run 'source ~/.zshrc' or open a new terminal to apply changes")
        return True
        
    except (OSError, IOError, PermissionError) as e:
        ui.print_warning(f"Could not update ~/.zshrc: {e}")
        ui.print_info("You can manually add the following to your shell profile:")
        ui.print_info('  export OLLAMA_HOST="127.0.0.1:11434"')
        ui.print_info('  export NO_PROXY="localhost,127.0.0.1,::1"')
        ui.print_info('  unset SSH_AUTH_SOCK')
        return False


def get_vpn_resilient_api_base() -> str:
    """
    Get the VPN-resilient API base URL.
    
    Returns:
        The API base URL using 127.0.0.1 instead of localhost
    """
    return OLLAMA_API_BASE
