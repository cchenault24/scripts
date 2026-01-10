"""
IDE integration functionality for VS Code, Cursor, and IntelliJ IDEA.

Provides functions to:
- Auto-detect installed IDEs (VS Code, Cursor, IntelliJ IDEA)
- Install extensions/plugins
- Restart IDEs
- Display next steps
"""

import os
import platform
import shutil
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Dict, List, Optional

from . import hardware
from . import ui
from . import utils
from .utils import get_unverified_ssl_context


# =============================================================================
# IDE AUTO-DETECTION
# =============================================================================

def detect_installed_ides() -> List[str]:
    """
    Auto-detect installed IDEs that support Continue.dev.
    
    Scans for:
    - VS Code (Visual Studio Code)
    - Cursor
    - IntelliJ IDEA (Community and Ultimate)
    
    Returns:
        List of installed IDE names
    """
    installed = []
    
    # Check VS Code
    if is_vscode_installed():
        installed.append("VS Code")
    
    # Check Cursor
    if is_cursor_installed():
        installed.append("Cursor")
    
    # Check IntelliJ IDEA
    if is_intellij_installed():
        installed.append("IntelliJ IDEA")
    
    return installed


def is_vscode_installed() -> bool:
    """Check if VS Code is installed."""
    # Check CLI in PATH
    if shutil.which("code"):
        return True
    
    # Check common installation paths
    if platform.system() == "Darwin":
        app_paths = [
            Path("/Applications/Visual Studio Code.app"),
            Path.home() / "Applications/Visual Studio Code.app",
        ]
        for path in app_paths:
            if path.exists():
                return True
    elif platform.system() == "Linux":
        paths = [
            Path("/usr/bin/code"),
            Path("/usr/share/code"),
            Path.home() / ".local/share/applications/code.desktop",
        ]
        for path in paths:
            if path.exists():
                return True
    elif platform.system() == "Windows":
        paths = [
            Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/Microsoft VS Code/Code.exe",
            Path("C:/Program Files/Microsoft VS Code/Code.exe"),
        ]
        for path in paths:
            if path.exists():
                return True
    
    return False


def is_cursor_installed() -> bool:
    """Check if Cursor IDE is installed."""
    # Check CLI in PATH
    if shutil.which("cursor"):
        return True
    
    # Check common installation paths
    if platform.system() == "Darwin":
        app_paths = [
            Path("/Applications/Cursor.app"),
            Path.home() / "Applications/Cursor.app",
        ]
        for path in app_paths:
            if path.exists():
                return True
    elif platform.system() == "Linux":
        paths = [
            Path("/usr/bin/cursor"),
            Path.home() / ".local/share/applications/cursor.desktop",
        ]
        for path in paths:
            if path.exists():
                return True
    elif platform.system() == "Windows":
        paths = [
            Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/Cursor/Cursor.exe",
        ]
        for path in paths:
            if path.exists():
                return True
    
    return False


def is_intellij_installed() -> bool:
    """Check if IntelliJ IDEA is installed."""
    # Check CLI in PATH
    if shutil.which("idea"):
        return True
    
    # Check common installation paths
    if platform.system() == "Darwin":
        app_paths = [
            Path("/Applications/IntelliJ IDEA.app"),
            Path("/Applications/IntelliJ IDEA Ultimate.app"),
            Path("/Applications/IntelliJ IDEA Community Edition.app"),
        ]
        for path in app_paths:
            if path.exists():
                return True
    elif platform.system() == "Linux":
        paths = [
            Path("/usr/local/bin/idea"),
            Path("/opt/idea"),
            Path.home() / ".local/share/JetBrains/Toolbox/scripts/idea",
        ]
        for path in paths:
            if path.exists():
                return True
    elif platform.system() == "Windows":
        paths = [
            Path("C:/Program Files/JetBrains/IntelliJ IDEA/bin/idea64.exe"),
            Path(os.environ.get("LOCALAPPDATA", "")) / "JetBrains/Toolbox/scripts/idea.bat",
        ]
        for path in paths:
            if path.exists():
                return True
    
    return False


def get_ide_info() -> Dict[str, bool]:
    """
    Get detailed information about installed IDEs.
    
    Returns:
        Dictionary mapping IDE names to installation status
    """
    return {
        "vscode": is_vscode_installed(),
        "cursor": is_cursor_installed(),
        "intellij": is_intellij_installed(),
    }


def display_detected_ides() -> List[str]:
    """
    Detect and display installed IDEs.
    
    Returns:
        List of installed IDE names
    """
    installed = detect_installed_ides()
    
    if installed:
        ide_str = ", ".join(installed)
        ui.print_success(f"Detected IDEs: {ide_str}")
    else:
        ui.print_warning("No supported IDEs detected")
        ui.print_info("Continue.dev supports: VS Code, Cursor, IntelliJ IDEA")
    
    return installed


def install_vscode_extension(extension_id: str) -> bool:
    """Install a VS Code extension using the CLI."""
    # Check if VS Code CLI is available
    code_path = shutil.which("code")
    if not code_path:
        return False
    
    # Check if extension is already installed
    code, stdout, _ = utils.run_command(["code", "--list-extensions"], timeout=10)
    if code == 0 and extension_id in stdout:
        return True  # Already installed
    
    # Install the extension
    code, stdout, stderr = utils.run_command(["code", "--install-extension", extension_id], timeout=60)
    return code == 0


def detect_intellij_cli() -> Optional[str]:
    """
    Detect IntelliJ IDEA CLI command.
    
    Returns:
        Path to IntelliJ CLI if found, None otherwise.
    """
    # Check if 'idea' command is in PATH
    idea_path = shutil.which("idea")
    if idea_path:
        return idea_path
    
    # Check common macOS installation path
    if platform.system() == "Darwin":
        common_paths = [
            "/Applications/IntelliJ IDEA.app/Contents/MacOS/idea",
            "/Applications/IntelliJ IDEA Ultimate.app/Contents/MacOS/idea",
            "/Applications/IntelliJ IDEA Community Edition.app/Contents/MacOS/idea",
        ]
        for path in common_paths:
            if Path(path).exists():
                return path
    
    # Check common Linux paths
    if platform.system() == "Linux":
        common_paths = [
            "/usr/local/bin/idea",
            "/opt/idea/bin/idea.sh",
            Path.home() / ".local/share/JetBrains/Toolbox/scripts/idea",
        ]
        for path in common_paths:
            if isinstance(path, Path):
                if path.exists():
                    return str(path)
            elif Path(path).exists():
                return path
    
    # Check Windows paths
    if platform.system() == "Windows":
        common_paths = [
            Path.home() / "AppData/Local/JetBrains/Toolbox/scripts/idea.bat",
            "C:/Program Files/JetBrains/IntelliJ IDEA/bin/idea64.exe",
        ]
        for path in common_paths:
            if path.exists():
                return str(path)
    
    return None


def install_intellij_plugin(plugin_id: str) -> bool:
    """
    Install an IntelliJ IDEA plugin using the CLI.
    
    Args:
        plugin_id: Plugin ID (e.g., "Continue.continue")
    
    Returns:
        True if installation successful or already installed, False otherwise.
    """
    idea_path = detect_intellij_cli()
    if not idea_path:
        return False
    
    # Check if plugin is already installed
    # Note: IntelliJ CLI doesn't have a simple list command, so we'll try to install
    # and check the result. If it's already installed, the command may still succeed.
    
    # Install the plugin
    # IntelliJ CLI plugin installation syntax may vary, but typically:
    # idea --install-plugin <plugin_id>
    # or for newer versions: idea install-plugin <plugin_id>
    code, stdout, stderr = utils.run_command([idea_path, "install-plugin", plugin_id], timeout=60)
    
    # Also try alternative syntax
    if code != 0:
        code, stdout, stderr = utils.run_command([idea_path, "--install-plugin", plugin_id], timeout=60)
    
    return code == 0


def restart_vscode() -> bool:
    """Restart VS Code (macOS only for now)."""
    if platform.system() != "Darwin":
        return False
    
    try:
        # Quit VS Code
        utils.run_command(["killall", "Visual Studio Code"], timeout=5)
        time.sleep(1)
        # Reopen VS Code
        utils.run_command(["open", "-a", "Visual Studio Code"], timeout=5)
        return True
    except Exception:
        return False


def restart_intellij() -> bool:
    """
    Restart IntelliJ IDEA (macOS only for now).
    
    Returns:
        True if restart successful, False otherwise.
    """
    if platform.system() != "Darwin":
        return False
    
    try:
        # Quit IntelliJ IDEA
        utils.run_command(["killall", "IntelliJ IDEA"], timeout=5)
        time.sleep(1)
        # Reopen IntelliJ IDEA
        utils.run_command(["open", "-a", "IntelliJ IDEA"], timeout=5)
        return True
    except Exception:
        return False


def start_model_server(model_name: str) -> Optional[subprocess.Popen]:
    """
    Verify Ollama API is running (Ollama runs as a service, no need to start per-model).
    
    Args:
        model_name: Name of the model (e.g., "llama3.2:3b")
    
    Returns:
        None (Ollama runs as a service, models are loaded on-demand via API)
        
    Note:
        Ollama runs as a background service. Models are loaded on-demand when
        requested via the API. There's no need to start a separate server per model.
    """
    # Ollama runs as a service - just verify the API is accessible
    try:
        req = urllib.request.Request("http://localhost:11434/api/tags", method="GET")
        with urllib.request.urlopen(req, timeout=2, context=get_unverified_ssl_context()) as response:
            if response.status == 200:
                # API is running - Ollama service is active
                return None  # No process to return - Ollama is a service
    except (urllib.error.URLError, urllib.error.HTTPError, OSError):
        # API not accessible - Ollama service may not be running
        pass
    
    return None


def _get_model_attr(model, attr: str, default=None):
    """Get attribute from model, supporting both object and dict access."""
    if hasattr(model, attr):
        return getattr(model, attr)
    elif isinstance(model, dict) and attr in model:
        return model[attr]
    return default


def show_next_steps(
    config_path: Path, 
    model_list: List, 
    hw_info: hardware.HardwareInfo,
    target_ide: List[str] = ["vscode"]
) -> None:
    """
    Display next steps after setup.
    
    Args:
        config_path: Path to the generated config file
        model_list: List of configured models (ModelInfo or RecommendedModel)
        hw_info: Hardware information
        target_ide: List of IDEs to configure (e.g., ["vscode"], ["intellij"], or ["vscode", "intellij"])
    """
    ui.print_header("✅ Setup Complete!")
    
    print(ui.colorize("Installation Summary:", ui.Colors.GREEN + ui.Colors.BOLD))
    print()
    print(f"  Hardware: {hw_info.apple_chip_model or hw_info.cpu_brand}")
    print(f"  Tier: {hw_info.get_tier_label()}")
    if hw_info.has_apple_silicon:
        print(f"  GPU: Metal acceleration enabled ({hw_info.ram_gb:.0f}GB unified memory)")
    print(f"  API Endpoint: {hw_info.ollama_api_endpoint}")
    print()
    print(f"  Models Configured: {len(model_list)}")
    for model in model_list:
        roles = _get_model_attr(model, 'roles', [])
        roles_str = ", ".join(roles) if roles else "general"
        name = _get_model_attr(model, 'name', 'Unknown')
        ram_gb = _get_model_attr(model, 'ram_gb', 0)
        print(f"    • {name} ({roles_str}) - ~{ram_gb}GB")
    print()
    print(f"  Config: {config_path}")
    print()
    
    print(ui.colorize("━" * 60, ui.Colors.DIM))
    print(ui.colorize("Next Steps:", ui.Colors.YELLOW + ui.Colors.BOLD))
    print()
    
    step = 1
    
    # IDE-specific installation steps
    if "vscode" in target_ide:
        # Step: Install Continue.dev extension in VS Code
        print(f"  {step}. Install Continue.dev extension in VS Code:")
        
        # Check if VS Code CLI is available
        vscode_available = shutil.which("code") is not None
        
        if vscode_available:
            # Check if already installed
            code, stdout, _ = utils.run_command(["code", "--list-extensions"], timeout=10)
            already_installed = code == 0 and "Continue.continue" in stdout
            
            if already_installed:
                ui.print_success("    Continue.dev extension is already installed")
            else:
                if ui.prompt_yes_no("    Install Continue.dev extension automatically?", default=True):
                    ui.print_info("    Installing Continue.dev extension...")
                    if install_vscode_extension("Continue.continue"):
                        ui.print_success("    Continue.dev extension installed successfully")
                    else:
                        ui.print_warning("    Failed to install automatically. Please install manually:")
                        if hw_info.os_name == "Darwin":
                            print(ui.colorize("       • Press Cmd+Shift+X → Search 'Continue' → Install", ui.Colors.DIM))
                        else:
                            print(ui.colorize("       • Press Ctrl+Shift+X → Search 'Continue' → Install", ui.Colors.DIM))
                else:
                    ui.print_info("    Skipping automatic installation.")
                    if hw_info.os_name == "Darwin":
                        print(ui.colorize("     • Press Cmd+Shift+X to open Extensions", ui.Colors.DIM))
                        print(ui.colorize("     • Search for 'Continue' and install", ui.Colors.DIM))
                    else:
                        print(ui.colorize("     • Press Ctrl+Shift+X to open Extensions", ui.Colors.DIM))
                        print(ui.colorize("     • Search for 'Continue' and install", ui.Colors.DIM))
        else:
            ui.print_info("    VS Code CLI not found. Please install manually:")
            if hw_info.os_name == "Darwin":
                print(ui.colorize("     • Press Cmd+Shift+X to open Extensions", ui.Colors.DIM))
                print(ui.colorize("     • Search for 'Continue' and install", ui.Colors.DIM))
            else:
                print(ui.colorize("     • Press Ctrl+Shift+X to open Extensions", ui.Colors.DIM))
                print(ui.colorize("     • Search for 'Continue' and install", ui.Colors.DIM))
        print()
        step += 1
    
    if "intellij" in target_ide:
        # Step: Install Continue plugin in IntelliJ
        print(f"  {step}. Install Continue plugin in IntelliJ IDEA:")
        
        # Check if IntelliJ CLI is available
        intellij_available = detect_intellij_cli() is not None
        
        if intellij_available:
            # Note: IntelliJ plugin installation via CLI is less reliable than VS Code
            # So we'll primarily provide manual instructions
            ui.print_info("    IntelliJ IDEA detected. Please install the Continue plugin manually:")
            if hw_info.os_name == "Darwin":
                print(ui.colorize("       • Open IntelliJ IDEA", ui.Colors.DIM))
                print(ui.colorize("       • Preferences → Plugins (or Cmd+, then Plugins)", ui.Colors.DIM))
                print(ui.colorize("       • Search for 'Continue'", ui.Colors.DIM))
                print(ui.colorize("       • Click 'Install' on the Continue plugin", ui.Colors.DIM))
            else:
                print(ui.colorize("       • Open IntelliJ IDEA", ui.Colors.DIM))
                print(ui.colorize("       • Settings → Plugins (or Ctrl+Alt+S then Plugins)", ui.Colors.DIM))
                print(ui.colorize("       • Search for 'Continue'", ui.Colors.DIM))
                print(ui.colorize("       • Click 'Install' on the Continue plugin", ui.Colors.DIM))
        else:
            ui.print_info("    IntelliJ IDEA CLI not found. Please install the Continue plugin manually:")
            if hw_info.os_name == "Darwin":
                print(ui.colorize("     • Open IntelliJ IDEA", ui.Colors.DIM))
                print(ui.colorize("     • Preferences → Plugins (or Cmd+, then Plugins)", ui.Colors.DIM))
                print(ui.colorize("     • Search for 'Continue' and install", ui.Colors.DIM))
            else:
                print(ui.colorize("     • Open IntelliJ IDEA", ui.Colors.DIM))
                print(ui.colorize("     • Settings → Plugins (or Ctrl+Alt+S then Plugins)", ui.Colors.DIM))
                print(ui.colorize("     • Search for 'Continue' and install", ui.Colors.DIM))
        print()
        step += 1
    
    # Step: Ollama setup (shared for both IDEs)
    if hw_info.ollama_available:
        print(f"  {step}. Verify Ollama is running:")
        print(ui.colorize("     ollama list", ui.Colors.CYAN))
        print()
        step += 1
        
        # Run a model if needed
        chat_models = [m for m in model_list if "chat" in _get_model_attr(m, 'roles', [])]
        if chat_models:
            print(f"  {step}. Start the model server (if not already running):")
            
            # Use Ollama model name directly (no conversion needed)
            model_to_run = _get_model_attr(chat_models[0], 'ollama_name', '')
            # If model has a variant, include it
            selected_variant = _get_model_attr(chat_models[0], 'selected_variant', None)
            if selected_variant:
                if ":" not in model_to_run:
                    model_to_run = f"{model_to_run}:{selected_variant}"
            
            # Check if API is already running
            api_running = False
            try:
                req = urllib.request.Request(f"{hw_info.ollama_api_endpoint}/models", method="GET")
                with urllib.request.urlopen(req, timeout=2, context=get_unverified_ssl_context()) as response:
                    if response.status == 200:
                        api_running = True
            except (urllib.error.URLError, urllib.error.HTTPError, OSError):
                pass
            
            if api_running:
                ui.print_success("    Model server is already running")
            else:
                if ui.prompt_yes_no("    Start the model server now?", default=True):
                    ui.print_info("    Starting model server in background...")
                    process = start_model_server(model_to_run)
                    if process:
                        ui.print_success("    Model server started")
                        ui.print_info("    (Server is running in background)")
                    else:
                        ui.print_warning("    Failed to start automatically. Start manually with:")
                        print(ui.colorize(f"       ollama run {model_to_run}", ui.Colors.CYAN))
                else:
                    ui.print_info("    Start manually with:")
                    print(ui.colorize(f"       ollama run {model_to_run}", ui.Colors.CYAN))
            print()
            step += 1
    else:
        print(f"  {step}. Start Ollama service:")
        ui.print_info("    Ollama should run automatically as a background service.")
        ui.print_info("    If it's not running, start it with:")
        print(ui.colorize("       ollama serve", ui.Colors.CYAN))
        print()
        step += 1
        
        print(f"  {step}. Pull the models:")
        for model in model_list:
            ollama_name = _get_model_attr(model, 'ollama_name', '')
            print(ui.colorize(f"     ollama pull {ollama_name}", ui.Colors.CYAN))
        print()
        step += 1
    
    # Step: Restart IDE(s) (automated if possible)
    if "vscode" in target_ide:
        print(f"  {step}. Restart VS Code:")
        
        # Check if VS Code is running
        vscode_running = False
        if hw_info.os_name == "Darwin":
            code, _, _ = utils.run_command(["pgrep", "-f", "Visual Studio Code"], timeout=5)
            vscode_running = code == 0
        else:
            code, _, _ = utils.run_command(["pgrep", "-f", "code"], timeout=5)
            vscode_running = code == 0
        
        if vscode_running:
            if ui.prompt_yes_no("    Restart VS Code automatically now?", default=False):
                ui.print_warning("    This will close all VS Code windows. Make sure you've saved your work!")
                if ui.prompt_yes_no("    Continue with restart?", default=False):
                    if restart_vscode():
                        ui.print_success("    VS Code restarted")
                    else:
                        ui.print_warning("    Failed to restart automatically. Please restart manually:")
                        if hw_info.os_name == "Darwin":
                            print(ui.colorize("       • Quit VS Code completely (Cmd+Q)", ui.Colors.DIM))
                        else:
                            print(ui.colorize("       • Close all VS Code windows", ui.Colors.DIM))
                        print(ui.colorize("       • Reopen VS Code", ui.Colors.DIM))
                else:
                    ui.print_info("    Skipping automatic restart.")
                    if hw_info.os_name == "Darwin":
                        print(ui.colorize("     • Quit VS Code completely (Cmd+Q)", ui.Colors.DIM))
                    else:
                        print(ui.colorize("     • Close all VS Code windows", ui.Colors.DIM))
                    print(ui.colorize("     • Reopen VS Code", ui.Colors.DIM))
            else:
                ui.print_info("    Please restart VS Code manually:")
                if hw_info.os_name == "Darwin":
                    print(ui.colorize("     • Quit VS Code completely (Cmd+Q)", ui.Colors.DIM))
                else:
                    print(ui.colorize("     • Close all VS Code windows", ui.Colors.DIM))
                print(ui.colorize("     • Reopen VS Code", ui.Colors.DIM))
        else:
            ui.print_info("    VS Code is not running. Open VS Code when ready.")
        print()
        step += 1
    
    if "intellij" in target_ide:
        print(f"  {step}. Restart IntelliJ IDEA:")
        
        # Check if IntelliJ is running
        intellij_running = False
        if hw_info.os_name == "Darwin":
            code, _, _ = utils.run_command(["pgrep", "-f", "IntelliJ IDEA"], timeout=5)
            intellij_running = code == 0
        else:
            code, _, _ = utils.run_command(["pgrep", "-f", "idea"], timeout=5)
            intellij_running = code == 0
        
        if intellij_running:
            if ui.prompt_yes_no("    Restart IntelliJ IDEA automatically now?", default=False):
                ui.print_warning("    This will close all IntelliJ IDEA windows. Make sure you've saved your work!")
                if ui.prompt_yes_no("    Continue with restart?", default=False):
                    if restart_intellij():
                        ui.print_success("    IntelliJ IDEA restarted")
                    else:
                        ui.print_warning("    Failed to restart automatically. Please restart manually:")
                        if hw_info.os_name == "Darwin":
                            print(ui.colorize("       • Quit IntelliJ IDEA completely (Cmd+Q)", ui.Colors.DIM))
                        else:
                            print(ui.colorize("       • Close all IntelliJ IDEA windows", ui.Colors.DIM))
                        print(ui.colorize("       • Reopen IntelliJ IDEA", ui.Colors.DIM))
                else:
                    ui.print_info("    Skipping automatic restart.")
                    if hw_info.os_name == "Darwin":
                        print(ui.colorize("     • Quit IntelliJ IDEA completely (Cmd+Q)", ui.Colors.DIM))
                    else:
                        print(ui.colorize("     • Close all IntelliJ IDEA windows", ui.Colors.DIM))
                    print(ui.colorize("     • Reopen IntelliJ IDEA", ui.Colors.DIM))
            else:
                ui.print_info("    Please restart IntelliJ IDEA manually:")
                if hw_info.os_name == "Darwin":
                    print(ui.colorize("     • Quit IntelliJ IDEA completely (Cmd+Q)", ui.Colors.DIM))
                else:
                    print(ui.colorize("     • Close all IntelliJ IDEA windows", ui.Colors.DIM))
                print(ui.colorize("     • Reopen IntelliJ IDEA", ui.Colors.DIM))
        else:
            ui.print_info("    IntelliJ IDEA is not running. Open IntelliJ IDEA when ready.")
        print()
        step += 1
    
    # Step: Start using (IDE-specific keyboard shortcuts)
    print(f"  {step}. Start coding with AI:")
    
    if "vscode" in target_ide:
        if len(target_ide) > 1:
            print(ui.colorize("     VS Code shortcuts:", ui.Colors.DIM))
        if hw_info.os_name == "Darwin":
            print(ui.colorize("     • Cmd+L - Open Continue.dev chat", ui.Colors.DIM))
            print(ui.colorize("     • Cmd+K - Inline code edits", ui.Colors.DIM))
            print(ui.colorize("     • Cmd+I - Quick actions", ui.Colors.DIM))
        else:
            print(ui.colorize("     • Ctrl+L - Open Continue.dev chat", ui.Colors.DIM))
            print(ui.colorize("     • Ctrl+K - Inline code edits", ui.Colors.DIM))
            print(ui.colorize("     • Ctrl+I - Quick actions", ui.Colors.DIM))
    
    if "intellij" in target_ide:
        if len(target_ide) > 1:
            print(ui.colorize("     IntelliJ IDEA shortcuts:", ui.Colors.DIM))
        if hw_info.os_name == "Darwin":
            print(ui.colorize("     • Cmd+J - Open Continue chat", ui.Colors.DIM))
            print(ui.colorize("     • Cmd+Shift+J - Inline edit", ui.Colors.DIM))
        else:
            print(ui.colorize("     • Ctrl+J - Open Continue chat", ui.Colors.DIM))
            print(ui.colorize("     • Ctrl+Shift+J - Inline edit", ui.Colors.DIM))
    
    # Shared features
    print(ui.colorize("     • @Codebase - Semantic code search", ui.Colors.DIM))
    print(ui.colorize("     • @file - Reference specific files", ui.Colors.DIM))
    print()
    
    print(ui.colorize("━" * 60, ui.Colors.DIM))
    print(ui.colorize("Useful Commands:", ui.Colors.BLUE + ui.Colors.BOLD))
    print()
    print("  Check installed models:")
    print(ui.colorize("     ollama list", ui.Colors.CYAN))
    print()
    print("  Run a model interactively:")
    if model_list:
        model_name = _get_model_attr(model_list[0], 'ollama_name', '')
        selected_variant = _get_model_attr(model_list[0], 'selected_variant', None)
        if selected_variant and ":" not in model_name:
            model_name = f"{model_name}:{selected_variant}"
        print(ui.colorize(f"     ollama run {model_name}", ui.Colors.CYAN))
    else:
        print(ui.colorize("     ollama run <model-name>", ui.Colors.CYAN))
    print()
    print("  Remove a model:")
    print(ui.colorize("     ollama rm <model-name>", ui.Colors.CYAN))
    print()
    print("  View config:")
    print(ui.colorize(f"     cat {config_path}", ui.Colors.CYAN))
    print()
    
    print(ui.colorize("━" * 60, ui.Colors.DIM))
    print(ui.colorize("Documentation:", ui.Colors.BLUE + ui.Colors.BOLD))
    print()
    print("  • Continue.dev: https://docs.continue.dev")
    print("  • Ollama: https://ollama.com/docs")
    if hw_info.has_apple_silicon:
        print("  • Apple Silicon optimization: Metal acceleration is automatic")
    print()
    
    # IntelliJ-specific verification instructions
    if "intellij" in target_ide:
        print(ui.colorize("━" * 60, ui.Colors.DIM))
        print(ui.colorize("IntelliJ IDEA Verification:", ui.Colors.BLUE + ui.Colors.BOLD))
        print()
        print("  To verify the Continue plugin loaded your config correctly:")
        print(ui.colorize("     • Open IntelliJ IDEA", ui.Colors.DIM))
        print(ui.colorize("     • Press Cmd+J (or Ctrl+J) to open Continue", ui.Colors.DIM))
        print(ui.colorize("     • Check that your models appear in the model selector", ui.Colors.DIM))
        print(ui.colorize("     • If models don't appear, check:", ui.Colors.DIM))
        print(ui.colorize("       - Config file exists: ~/.continue/config.json", ui.Colors.DIM))
        print(ui.colorize("       - Model server is running: ollama list", ui.Colors.DIM))
        print(ui.colorize("       - Restart IntelliJ IDEA if needed", ui.Colors.DIM))
        print()
