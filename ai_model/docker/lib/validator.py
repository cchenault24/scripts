"""
Model Validator for Docker Model Runner.

Handles model pulling, verification, and setup tracking.
"""

import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field
from typing import List, Optional, Tuple

from . import hardware
from . import ui
from . import utils
from .model_selector import RecommendedModel, ModelRole

# Docker Model Runner API configuration
DMR_API_BASE = "http://127.0.0.1:12434/v1"

# Timeout and delay constants
API_TIMEOUT = 5
MODEL_LIST_TIMEOUT = 10
MODEL_PULL_TIMEOUT = 3600  # 1 hour
PROCESS_KILL_TIMEOUT = 5
VERIFICATION_DELAY = 2

# Retry configuration
MAX_PULL_RETRIES = 3
RETRY_BASE_DELAY = 2


@dataclass
class PullResult:
    """Result of a model pull attempt."""
    model: RecommendedModel
    success: bool
    verified: bool = False
    error_message: str = ""


@dataclass
class SetupResult:
    """Result of the complete model setup."""
    successful_models: List[RecommendedModel] = field(default_factory=list)
    failed_models: List[Tuple[RecommendedModel, str]] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    
    @property
    def partial_success(self) -> bool:
        """True if some but not all models were installed."""
        return len(self.successful_models) > 0 and len(self.failed_models) > 0
    
    @property
    def complete_success(self) -> bool:
        """True if all models were installed successfully."""
        return len(self.failed_models) == 0 and len(self.successful_models) > 0
    
    @property
    def complete_failure(self) -> bool:
        """True if no models were installed but some were attempted."""
        return len(self.successful_models) == 0 and len(self.failed_models) > 0


def get_installed_models() -> List[str]:
    """Get list of currently installed Docker Model Runner models."""
    code, stdout, _ = utils.run_command(["docker", "model", "list"], timeout=MODEL_LIST_TIMEOUT, clean_env=True)
    if code != 0:
        return []
    
    models = []
    lines = stdout.strip().split("\n")
    if len(lines) > 1:
        for line in lines[1:]:  # Skip header
            if line.strip():
                parts = line.split()
                if parts:
                    models.append(parts[0])
    return models


def verify_model_exists(model_name: str) -> bool:
    """Verify that a model exists in Docker Model Runner after pulling."""
    installed = get_installed_models()
    
    # Normalize model name
    model_normalized = model_name.lower()
    if model_normalized.startswith("ai/"):
        model_normalized = model_normalized[3:]
    base_name = model_normalized.split(":")[0]
    
    for installed_model in installed:
        installed_lower = installed_model.lower()
        installed_base = installed_lower.split(":")[0]
        
        if model_normalized == installed_lower:
            return True
        if base_name == installed_base:
            return True
        if installed_lower.startswith(model_normalized):
            return True
        if model_normalized.startswith(installed_lower):
            return True
    
    return False


def _ensure_rich_available() -> bool:
    """Ensure rich library is available for progress bars."""
    try:
        from rich.progress import Progress, SpinnerColumn, BarColumn, TextColumn, TimeRemainingColumn, DownloadColumn, TransferSpeedColumn
        from rich.console import Console
        return True
    except ImportError:
        return False


def _pull_model_single_attempt(model_name: str, show_progress: bool = True) -> Tuple[bool, str]:
    """Execute a single docker model pull attempt without retries."""
    process = None
    output_lines: List[str] = []
    
    try:
        clean_env = {k: v for k, v in os.environ.items() if k != 'SSH_AUTH_SOCK'}
        
        if show_progress:
            process = subprocess.Popen(
                ["docker", "model", "pull", model_name],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, bufsize=1, env=clean_env
            )
            
            # Try rich progress bars
            rich_used = False
            if _ensure_rich_available():
                try:
                    from rich.progress import Progress, SpinnerColumn, BarColumn, TextColumn, TimeRemainingColumn, DownloadColumn, TransferSpeedColumn
                    from rich.console import Console
                    console = Console()
                    progress_bar = None
                    task_id = None
                    rich_used = True
                    
                    if process.stdout:
                        for line in process.stdout:
                            clean_line = line.strip()
                            if clean_line:
                                output_lines.append(clean_line)
                                
                                progress_match = re.search(r'Downloaded\s+([\d.]+)\s*(kB|MB|GB|B)?\s*(?:of|/)\s*([\d.]+)\s*(kB|MB|GB|B)?', clean_line, re.IGNORECASE)
                                percent_match = re.search(r'(\d+)%', clean_line)
                                
                                if progress_match:
                                    downloaded_val = float(progress_match.group(1))
                                    downloaded_unit = (progress_match.group(2) or progress_match.group(4) or "B").upper()
                                    total_val = float(progress_match.group(3))
                                    total_unit = (progress_match.group(4) or "B").upper()
                                    
                                    unit_multipliers = {"B": 1, "KB": 1024, "MB": 1024**2, "GB": 1024**3}
                                    downloaded_bytes = downloaded_val * unit_multipliers.get(downloaded_unit, 1)
                                    total_bytes = total_val * unit_multipliers.get(total_unit, 1)
                                    
                                    if total_bytes > 0 and progress_bar is None:
                                        progress_bar = Progress(
                                            SpinnerColumn(),
                                            TextColumn("[progress.description]{task.description}"),
                                            BarColumn(),
                                            TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
                                            DownloadColumn(),
                                            TransferSpeedColumn(),
                                            TimeRemainingColumn(),
                                            console=console
                                        )
                                        progress_bar.start()
                                        task_id = progress_bar.add_task(
                                            f"[cyan]Downloading {model_name}...",
                                            total=total_bytes
                                        )
                                    
                                    if progress_bar and task_id is not None:
                                        progress_bar.update(task_id, completed=downloaded_bytes)
                                elif percent_match:
                                    percent = int(percent_match.group(1))
                                    if progress_bar is None:
                                        progress_bar = Progress(
                                            SpinnerColumn(),
                                            TextColumn("[progress.description]{task.description}"),
                                            BarColumn(),
                                            TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
                                            console=console
                                        )
                                        progress_bar.start()
                                        task_id = progress_bar.add_task(
                                            f"[cyan]Downloading {model_name}...",
                                            total=100
                                        )
                                    if progress_bar and task_id is not None:
                                        progress_bar.update(task_id, completed=percent)
                                elif "complete" in clean_line.lower() or "success" in clean_line.lower() or "pulled" in clean_line.lower():
                                    if progress_bar:
                                        if task_id is not None and progress_bar.tasks:
                                            total = progress_bar.tasks[task_id].total or 100
                                            progress_bar.update(task_id, completed=total)
                                        progress_bar.stop()
                                    console.print(f"[green]✓ {clean_line}[/green]")
                                elif "error" in clean_line.lower() or "failed" in clean_line.lower():
                                    if progress_bar:
                                        progress_bar.stop()
                                    console.print(f"[red]✗ {clean_line}[/red]")
                    
                    if progress_bar:
                        progress_bar.stop()
                except Exception:
                    rich_used = False
            
            # Fallback to basic progress
            if not rich_used:
                last_percent = 0
                if process.stdout:
                    for line in process.stdout:
                        clean_line = line.strip()
                        if clean_line:
                            output_lines.append(clean_line)
                            if "%" in clean_line:
                                percent_match = re.search(r'(\d+)%', clean_line)
                                if percent_match:
                                    percent = int(percent_match.group(1))
                                    if percent != last_percent:
                                        print(f"\r    {percent:3d}% complete", end="", flush=True)
                                        last_percent = percent
                            elif "complete" in clean_line.lower() or "success" in clean_line.lower():
                                print()
                            elif "error" in clean_line.lower():
                                print()
                                ui.print_error(f"    {clean_line}")
            
            stderr_output = process.stderr.read() if process.stderr else ""
            process.wait(timeout=MODEL_PULL_TIMEOUT)
            
            if process.returncode == 0:
                return True, ""
            else:
                error_msg = stderr_output.strip() if stderr_output else ""
                if not error_msg and output_lines:
                    for line in output_lines:
                        if "error" in line.lower() or "failed" in line.lower():
                            error_msg = line
                            break
                return False, error_msg or "Unknown error during pull"
        else:
            code, stdout, stderr = utils.run_command(
                ["docker", "model", "pull", model_name],
                timeout=MODEL_PULL_TIMEOUT, clean_env=True
            )
            if code == 0:
                return True, ""
            return False, stderr.strip() if stderr else stdout.strip() or "Unknown error"
    
    except subprocess.TimeoutExpired:
        if process:
            process.kill()
            try:
                process.wait(timeout=PROCESS_KILL_TIMEOUT)
            except subprocess.TimeoutExpired:
                pass
        return False, f"Timeout after {MODEL_PULL_TIMEOUT}s"
    except FileNotFoundError:
        return False, "Docker command not found - is Docker installed?"
    except (OSError, IOError, subprocess.SubprocessError) as e:
        return False, f"Process error: {type(e).__name__}: {e}"
    finally:
        if process and process.poll() is None:
            process.kill()
            try:
                process.wait(timeout=PROCESS_KILL_TIMEOUT)
            except subprocess.TimeoutExpired:
                pass


def _pull_model(model_name: str, show_progress: bool = True) -> Tuple[bool, str]:
    """Execute docker model pull command with retry logic."""
    last_error = ""
    
    for attempt in range(MAX_PULL_RETRIES):
        if attempt > 0:
            delay = RETRY_BASE_DELAY * (2 ** (attempt - 1))
            if show_progress:
                ui.print_info(f"Retrying in {delay}s... (attempt {attempt + 1}/{MAX_PULL_RETRIES})")
            time.sleep(delay)
        
        success, error_msg = _pull_model_single_attempt(model_name, show_progress)
        
        if success:
            return True, ""
        
        last_error = error_msg
        
        # Don't retry on certain errors
        error_lower = error_msg.lower()
        if any(x in error_lower for x in [
            "not found", "does not exist", "unknown model",
            "no space left", "disk full",
            "unknown command", "docker model", "not enabled",
            "docker daemon", "cannot connect to docker", "is docker running"
        ]):
            if show_progress:
                ui.print_warning(f"Not retrying - fatal error: {error_msg[:100]}")
            break
        
        if show_progress and attempt < MAX_PULL_RETRIES - 1:
            ui.print_warning(f"Attempt {attempt + 1} failed: {error_msg[:100]}")
    
    return False, last_error


def pull_model_with_verification(
    model: RecommendedModel, show_progress: bool = True
) -> PullResult:
    """Pull a model with immediate verification."""
    result = PullResult(model=model, success=False)
    
    if show_progress:
        ui.print_info(f"Pulling {model.name} ({model.docker_name})...")
    
    success, error_msg = _pull_model(model.docker_name, show_progress)
    
    if success:
        time.sleep(VERIFICATION_DELAY)
        if verify_model_exists(model.docker_name):
            result.success = True
            result.verified = True
            if show_progress:
                ui.print_success(f"{model.name} downloaded and verified")
            return result
        else:
            if show_progress:
                ui.print_warning(f"{model.name} pull succeeded but verification failed")
            error_msg = "Pull appeared to succeed but model not found"
    else:
        if show_progress:
            ui.print_error(f"Failed to pull {model.name}")
            if error_msg:
                ui.print_error(f"  Error: {error_msg[:300]}")
    
    result.error_message = error_msg or "Model pull failed"
    return result


def pull_models_with_tracking(
    models: List[RecommendedModel], hw_info: hardware.HardwareInfo, show_progress: bool = True
) -> SetupResult:
    """Pull multiple models with verification and tracking."""
    result = SetupResult()
    
    if show_progress:
        ui.print_header("📥 Downloading Models")
        total_gb = sum(m.ram_gb for m in models) * 0.5
        ui.print_info(f"Estimated total download: ~{total_gb:.1f}GB")
        print()
    
    for i, model in enumerate(models, 1):
        if show_progress:
            ui.print_step(i, len(models), f"Pulling {model.name}")
            print()
        
        pull_result = pull_model_with_verification(model, show_progress)
        
        if pull_result.success:
            result.successful_models.append(model)
        else:
            result.failed_models.append((model, pull_result.error_message))
        
        if show_progress:
            print()
    
    return result


def display_setup_result(result: SetupResult) -> None:
    """Display the setup result with actionable next steps."""
    print()
    
    if result.complete_success:
        ui.print_header("✅ Setup Complete!")
    elif result.partial_success:
        ui.print_header("⚠️ Setup Complete (with warnings)")
    else:
        ui.print_header("❌ Setup Failed")
    
    print()
    
    for model in result.successful_models:
        ui.print_success(f"{model.docker_name} - Ready to use")
    
    for model, error in result.failed_models:
        ui.print_error(f"{model.docker_name} - Failed to download")
        if error:
            display_error = error[:150] if len(error) > 150 else error
            print(ui.colorize(f"    └─ {display_error}", ui.Colors.DIM))
    
    print()
    
    if result.warnings:
        for warning in result.warnings:
            ui.print_warning(warning)
        print()
    
    if result.partial_success:
        has_primary = any(m.role == ModelRole.CHAT for m in result.successful_models)
        has_embed = any(m.role == ModelRole.EMBED for m in result.successful_models)
        
        working = []
        not_working = []
        
        if has_primary:
            working.append("chat and code editing")
        else:
            not_working.append("Primary coding features won't work")
        if has_embed:
            working.append("codebase search")
        else:
            not_working.append("Codebase search won't work")
        
        if working:
            print(ui.colorize(f"Working now: {', '.join(working)}", ui.Colors.GREEN))
        if not_working:
            for issue in not_working:
                print(ui.colorize(f"⚠ {issue} until missing model is installed.", ui.Colors.YELLOW))
        print()
    
    if result.complete_failure:
        ui.print_error("No models were installed. Please check:")
        ui.print_info("  • Docker Desktop is running")
        ui.print_info("  • Docker Model Runner is enabled")
        ui.print_info("  • Internet connection is working")
        print()
    
    if result.failed_models:
        print("To retry failed models:")
        for model, _ in result.failed_models:
            print(ui.colorize(f"  docker model pull {model.docker_name}", ui.Colors.CYAN))
        print()


def prompt_setup_action(result: SetupResult) -> str:
    """Prompt user for next action after setup."""
    if result.complete_success:
        return "continue"
    
    choices = []
    if result.partial_success:
        choices.append("Continue to IDE Setup")
    if result.failed_models:
        choices.append("Retry Failed Models")
    choices.append("Exit")
    
    choice = ui.prompt_choice("What would you like to do?", choices, default=0)
    
    if choices[choice] == "Continue to IDE Setup":
        return "continue"
    elif choices[choice] == "Retry Failed Models":
        return "retry"
    return "exit"


def retry_failed_models(result: SetupResult, hw_info: hardware.HardwareInfo) -> SetupResult:
    """Retry pulling failed models."""
    if not result.failed_models:
        return result
    
    models_to_retry = [model for model, _ in result.failed_models]
    retry_result = pull_models_with_tracking(models_to_retry, hw_info)
    
    new_result = SetupResult()
    new_result.successful_models = result.successful_models + retry_result.successful_models
    new_result.warnings = result.warnings + retry_result.warnings
    
    still_failed_names = {model.docker_name for model, _ in retry_result.failed_models}
    new_result.failed_models = [
        (model, error) for model, error in result.failed_models
        if model.docker_name in still_failed_names
    ]
    
    return new_result


def validate_pre_install(
    models: List[RecommendedModel], hw_info: hardware.HardwareInfo
) -> Tuple[bool, List[str]]:
    """Pre-installation validation."""
    warnings = []
    
    # Check Docker Model Runner
    code, _, stderr = utils.run_command(["docker", "model", "list"], timeout=10, clean_env=True)
    if code != 0:
        error_lower = stderr.lower()
        if "unknown command" in error_lower or "docker model" in error_lower:
            warnings.append("Docker Model Runner is not enabled")
        elif "docker daemon" in error_lower or "cannot connect" in error_lower:
            warnings.append("Docker is not running")
        else:
            warnings.append("Docker Model Runner is not available")
        return False, warnings
    
    # Check RAM
    usable_ram = hw_info.ram_gb
    total_ram_needed = sum(m.ram_gb for m in models)
    
    if total_ram_needed > usable_ram:
        warnings.append(
            f"Selected models ({total_ram_needed:.1f}GB) exceed available RAM ({usable_ram:.1f}GB)"
        )
    elif total_ram_needed > usable_ram * 0.90:
        warnings.append(
            f"Selected models use {total_ram_needed:.1f}GB of {usable_ram:.1f}GB available RAM"
        )
    
    is_valid = not any("not enabled" in w.lower() or "not running" in w.lower() for w in warnings)
    return is_valid, warnings
