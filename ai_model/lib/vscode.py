"""
VS Code integration functionality.

Provides functions to install extensions, restart VS Code, and display next steps.
"""

import platform
import shutil
import ssl
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import List, Optional

from . import hardware
from . import models
from . import ui
from . import utils

# SSL context that skips certificate verification (equivalent to curl -k)
# Needed for work machines with corporate proxies/interception
try:
    _UNVERIFIED_SSL_CONTEXT = ssl._create_unverified_context()
except Exception:
    # Fallback: create a default context and disable verification
    _UNVERIFIED_SSL_CONTEXT = ssl.create_default_context()
    _UNVERIFIED_SSL_CONTEXT.check_hostname = False
    _UNVERIFIED_SSL_CONTEXT.verify_mode = ssl.CERT_NONE


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


def start_model_server(model_name: str) -> Optional[subprocess.Popen]:
    """Start the Docker Model Runner API server in the background."""
    try:
        process = subprocess.Popen(
            ["docker", "model", "run", model_name],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        # Give it a moment to start
        time.sleep(2)
        # Check if it's still running (didn't immediately fail)
        if process.poll() is None:
            return process
        else:
            return None
    except Exception:
        return None


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


def show_next_steps(config_path: Path, model_list: List[models.ModelInfo], hw_info: hardware.HardwareInfo) -> None:
    """Display next steps after setup."""
    ui.print_header("✅ Setup Complete!")
    
    print(ui.colorize("Installation Summary:", ui.Colors.GREEN + ui.Colors.BOLD))
    print()
    print(f"  Hardware: {hw_info.apple_chip_model or hw_info.cpu_brand}")
    print(f"  Tier: {hw_info.get_tier_label()}")
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
    
    print(ui.colorize("━" * 60, ui.Colors.DIM))
    print(ui.colorize("Next Steps:", ui.Colors.YELLOW + ui.Colors.BOLD))
    print()
    
    step = 1
    
    # Step 1: Install Continue.dev (automated if possible)
    print(f"  {step}. Install Continue.dev extension in VS Code:")
    
    # Check if VS Code CLI is available
    vscode_available = shutil.which("code") is not None
    
    if vscode_available:
        # Check if already installed
        code, stdout, _ = utils.run_command(["code", "--list-extensions"], timeout=10)
        already_installed = code == 0 and "Continue.continue" in stdout
        
        if already_installed:
            ui.print_success("Continue.dev extension is already installed")
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
    
    # Step 2: Docker Model Runner setup
    if hw_info.docker_model_runner_available:
        print(f"  {step}. Verify Docker Model Runner is running:")
        print(ui.colorize("     docker model list", ui.Colors.CYAN))
        print()
        step += 1
        
        # Run a model if needed
        chat_models = [m for m in model_list if "chat" in m.roles]
        if chat_models:
            print(f"  {step}. Start the model server (if not already running):")
            
            # Convert model name for Docker Hub format
            model_to_run = chat_models[0].docker_name
            if model_to_run.startswith("ai.docker.com/"):
                remaining = model_to_run[len("ai.docker.com/"):]
                parts = remaining.split("/")
                if len(parts) > 1:
                    model_part = parts[1]
                else:
                    model_part = parts[0]
                if ":" in model_part:
                    model_part = model_part.split(":")[0]
                model_to_run = f"ai/{model_part}"
            
            # Check if API is already running
            api_running = False
            try:
                req = urllib.request.Request(f"{hw_info.dmr_api_endpoint}/models", method="GET")
                with urllib.request.urlopen(req, timeout=2, context=_UNVERIFIED_SSL_CONTEXT) as response:
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
                        print(ui.colorize(f"       docker model run {model_to_run}", ui.Colors.CYAN))
                else:
                    ui.print_info("    Start manually with:")
                    print(ui.colorize(f"       docker model run {model_to_run}", ui.Colors.CYAN))
            print()
            step += 1
    else:
        print(f"  {step}. Enable Docker Model Runner:")
        if hw_info.os_name == "Darwin":
            print(ui.colorize("     Option A - Via Docker Desktop:", ui.Colors.DIM))
            print(ui.colorize("       • Open Docker Desktop", ui.Colors.DIM))
            print(ui.colorize("       • Settings → Features in development", ui.Colors.DIM))
            print(ui.colorize("       • Enable 'Docker Model Runner' or 'Enable Docker AI'", ui.Colors.DIM))
            print(ui.colorize("       • Click 'Apply & restart'", ui.Colors.DIM))
            print()
            print(ui.colorize("     Option B - Via terminal:", ui.Colors.DIM))
            print(ui.colorize("       docker desktop enable model-runner --tcp 12434", ui.Colors.CYAN))
        else:
            print(ui.colorize("     • Open Docker Desktop → Settings", ui.Colors.DIM))
            print(ui.colorize("     • Features in development → Enable Docker Model Runner", ui.Colors.DIM))
            print(ui.colorize("     • Apply & restart", ui.Colors.DIM))
        print()
        step += 1
        
        print(f"  {step}. Pull the models:")
        for model in model_list:
            print(ui.colorize(f"     docker model pull {model.docker_name}", ui.Colors.CYAN))
        print()
        step += 1
    
    # Step: Restart VS Code (automated if possible)
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
    
    # Step: Start using
    print(f"  {step}. Start coding with AI:")
    if hw_info.os_name == "Darwin":
        print(ui.colorize("     • Cmd+L - Open Continue.dev chat", ui.Colors.DIM))
        print(ui.colorize("     • Cmd+K - Inline code edits", ui.Colors.DIM))
        print(ui.colorize("     • Cmd+I - Quick actions", ui.Colors.DIM))
    else:
        print(ui.colorize("     • Ctrl+L - Open Continue.dev chat", ui.Colors.DIM))
        print(ui.colorize("     • Ctrl+K - Inline code edits", ui.Colors.DIM))
        print(ui.colorize("     • Ctrl+I - Quick actions", ui.Colors.DIM))
    print(ui.colorize("     • @Codebase - Semantic code search", ui.Colors.DIM))
    print(ui.colorize("     • @file - Reference specific files", ui.Colors.DIM))
    print()
    
    print(ui.colorize("━" * 60, ui.Colors.DIM))
    print(ui.colorize("Useful Commands:", ui.Colors.BLUE + ui.Colors.BOLD))
    print()
    print("  Check installed models:")
    print(ui.colorize("     docker model list", ui.Colors.CYAN))
    print()
    print("  Run a model interactively:")
    if model_list:
        print(ui.colorize(f"     docker model run {model_list[0].docker_name}", ui.Colors.CYAN))
    else:
        print(ui.colorize("     docker model run <model-name>", ui.Colors.CYAN))
    print()
    print("  Remove a model:")
    print(ui.colorize("     docker model rm <model-name>", ui.Colors.CYAN))
    print()
    print("  View config:")
    print(ui.colorize(f"     cat {config_path}", ui.Colors.CYAN))
    print()
    
    print(ui.colorize("━" * 60, ui.Colors.DIM))
    print(ui.colorize("Documentation:", ui.Colors.BLUE + ui.Colors.BOLD))
    print()
    print("  • Continue.dev: https://docs.continue.dev")
    print("  • Docker Model Runner: https://docs.docker.com/desktop/features/ai/")
    if hw_info.has_apple_silicon:
        print("  • Apple Silicon optimization: Metal acceleration is automatic")
    print()
