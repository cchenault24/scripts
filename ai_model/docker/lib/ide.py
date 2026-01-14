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
from pathlib import Path
from typing import List, Optional

from . import hardware
from . import models
from . import ui
from . import utils
from .model_selector import RecommendedModel


def detect_installed_ides() -> List[str]:
    """Auto-detect installed IDEs that support Continue.dev."""
    installed = []
    
    if is_vscode_installed():
        installed.append("VS Code")
    
    if is_cursor_installed():
        installed.append("Cursor")
    
    if is_intellij_installed():
        installed.append("IntelliJ IDEA")
    
    return installed


def is_vscode_installed() -> bool:
    """Check if VS Code is installed."""
    if shutil.which("code"):
        return True
    
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
    if shutil.which("cursor"):
        return True
    
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
    if shutil.which("idea"):
        return True
    
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


def install_vscode_extension(extension_id: str) -> bool:
    """Install a VS Code extension using the CLI."""
    code_path = shutil.which("code")
    if not code_path:
        return False
    
    code, stdout, _ = utils.run_command(["code", "--list-extensions"], timeout=10)
    if code == 0 and extension_id in stdout:
        return True
    
    code, stdout, stderr = utils.run_command(["code", "--install-extension", extension_id], timeout=60)
    return code == 0


def detect_intellij_cli() -> Optional[str]:
    """Detect IntelliJ IDEA CLI command."""
    idea_path = shutil.which("idea")
    if idea_path:
        return idea_path
    
    if platform.system() == "Darwin":
        common_paths = [
            "/Applications/IntelliJ IDEA.app/Contents/MacOS/idea",
            "/Applications/IntelliJ IDEA Ultimate.app/Contents/MacOS/idea",
            "/Applications/IntelliJ IDEA Community Edition.app/Contents/MacOS/idea",
        ]
        for path in common_paths:
            if Path(path).exists():
                return path
    
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
    """Install an IntelliJ IDEA plugin using the CLI."""
    idea_path = detect_intellij_cli()
    if not idea_path:
        return False
    
    code, stdout, stderr = utils.run_command([idea_path, "install-plugin", plugin_id], timeout=60)
    if code != 0:
        code, stdout, stderr = utils.run_command([idea_path, "--install-plugin", plugin_id], timeout=60)
    
    return code == 0


def restart_vscode() -> bool:
    """Restart VS Code (macOS only for now)."""
    if platform.system() != "Darwin":
        return False
    
    try:
        utils.run_command(["killall", "Visual Studio Code"], timeout=5)
        time.sleep(1)
        utils.run_command(["open", "-a", "Visual Studio Code"], timeout=5)
        return True
    except Exception:
        return False


def restart_intellij() -> bool:
    """Restart IntelliJ IDEA (macOS only for now)."""
    if platform.system() != "Darwin":
        return False
    
    try:
        utils.run_command(["killall", "IntelliJ IDEA"], timeout=5)
        time.sleep(1)
        utils.run_command(["open", "-a", "IntelliJ IDEA"], timeout=5)
        return True
    except Exception:
        return False


def show_next_steps(
    config_path: Path,
    model_list: List[RecommendedModel],
    hw_info: hardware.HardwareInfo,
    target_ide: List[str] = ["vscode"],
    has_embedding: bool = True
) -> None:
    """Display next steps after setup."""
    ui.print_header("✅ Setup Complete!")
    
    print(ui.colorize("Installation Summary:", ui.Colors.GREEN + ui.Colors.BOLD))
    print()
    print(f"  Hardware: {hw_info.apple_chip_model or hw_info.cpu_brand}")
    if hw_info.has_apple_silicon:
        print(f"  GPU: Metal acceleration enabled ({hw_info.ram_gb:.0f}GB unified memory)")
    print(f"  API Endpoint: {hw_info.dmr_api_endpoint}")
    print()
    print(f"  Models Configured: {len(model_list)}")
    for model in model_list:
        roles_str = ", ".join(model.roles)
        print(f"    • {model.name} ({roles_str}) - ~{model.ram_gb}GB")
    print()
    print(f"  Config: {config_path}")
    print()
    
    print(ui.colorize("Next Steps:", ui.Colors.YELLOW + ui.Colors.BOLD))
    print()
    
    step = 1
    
    if "vscode" in target_ide:
        print(f"  {step}. Install Continue.dev extension in VS Code:")
        vscode_available = shutil.which("code") is not None
        
        if vscode_available:
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
        print(f"  {step}. Install Continue plugin in IntelliJ IDEA:")
        intellij_available = detect_intellij_cli() is not None
        
        if intellij_available:
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
    
    if hw_info.docker_model_runner_available:
        print(f"  {step}. Verify Docker Model Runner is running:")
        print(ui.colorize("     docker model list", ui.Colors.CYAN))
        print()
        step += 1
    
    if "vscode" in target_ide:
        print(f"  {step}. Restart VS Code:")
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
                        ui.print_warning("    Failed to restart automatically. Please restart manually.")
                else:
                    ui.print_info("    Skipping automatic restart.")
            else:
                ui.print_info("    Please restart VS Code manually when ready.")
        else:
            ui.print_info("    VS Code is not running. Open VS Code when ready.")
        print()
        step += 1
    
    if "intellij" in target_ide:
        print(f"  {step}. Restart IntelliJ IDEA:")
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
                        ui.print_warning("    Failed to restart automatically. Please restart manually.")
                else:
                    ui.print_info("    Skipping automatic restart.")
            else:
                ui.print_info("    Please restart IntelliJ IDEA manually when ready.")
        else:
            ui.print_info("    IntelliJ IDEA is not running. Open IntelliJ IDEA when ready.")
        print()
        step += 1
    
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
    
    print()
    
    print(ui.colorize("Useful Commands:", ui.Colors.BLUE + ui.Colors.BOLD))
    print()
    print("  Check installed models:")
    print(ui.colorize("     docker model list", ui.Colors.CYAN))
    print()
    print("  View config:")
    print(ui.colorize(f"     cat {config_path}", ui.Colors.CYAN))
    print()
