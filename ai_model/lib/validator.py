"""
Model Validator.

Handles:
- Immediate verification after each model pull
- Fallback to hardcoded catalog when Ollama API is unreachable
- Partial setup tracking when some models fail
- Graceful degradation with actionable next steps
"""

import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

from . import hardware
from . import ui
from . import utils
from .utils import get_unverified_ssl_context
from .model_selector import ModelRole, GemmaModel


# Ollama API configuration
OLLAMA_API_BASE = "http://localhost:11434"
OLLAMA_REGISTRY = "https://registry.ollama.ai"

# Restricted model keywords (Chinese-based LLMs are not allowed)
RESTRICTED_MODEL_KEYWORDS = [
    "qwen", "deepseek", "deepcoder", "baai", "bge-", "yi", "baichuan",
    "chatglm", "glm", "internlm", "minicpm", "cogvlm", "qianwen", "tongyi"
]


def is_restricted_model_name(model_name: str) -> bool:
    """
    Check if a model name is from restricted countries (China-based LLMs).
    
    Args:
        model_name: The model name to check (e.g., "qwen2.5-coder:14b")
        
    Returns:
        True if the model is restricted, False otherwise
    """
    model_lower = model_name.lower()
    return any(keyword in model_lower for keyword in RESTRICTED_MODEL_KEYWORDS)


# Timeout and delay constants (in seconds)
API_TIMEOUT = 5  # Timeout for API health checks
API_TIMEOUT_LONG = 10  # Timeout for longer API operations
OLLAMA_LIST_TIMEOUT = 10  # Timeout for 'ollama list' command
MODEL_PULL_TIMEOUT = 3600  # Timeout for model pull (1 hour)
PROCESS_KILL_TIMEOUT = 5  # Timeout for process termination
VERIFICATION_DELAY = 1  # Delay before verifying model after pull

# Retry configuration
MAX_PULL_RETRIES = 3
RETRY_BASE_DELAY = 2  # Base delay for exponential backoff (seconds)

# Pre-flight test model (very small, ~400MB)
# Using a non-Chinese model for preflight testing
PREFLIGHT_TEST_MODEL = "all-minilm"


class PullErrorType:
    """Classification of pull errors for targeted troubleshooting."""
    SSH_KEY = "ssh_key"  # "ssh: no key found" error
    NETWORK = "network"  # Connection refused, timeout, DNS issues
    AUTH = "auth"  # Authentication/authorization errors
    SERVICE = "service"  # Ollama service not running
    REGISTRY = "registry"  # Registry unreachable
    DISK = "disk"  # Disk full or permission issues
    MODEL_NOT_FOUND = "model_not_found"  # Model doesn't exist
    UNKNOWN = "unknown"


def is_restricted_model_name(model_name: str) -> bool:
    """
    Check if a model name is from restricted countries (China-based LLMs).
    
    Args:
        model_name: The model name to check (e.g., "qwen2.5-coder:14b")
        
    Returns:
        True if the model is restricted, False otherwise
    """
    model_lower = model_name.lower()
    return any(keyword in model_lower for keyword in RESTRICTED_MODEL_KEYWORDS)


def classify_pull_error(error_msg: str) -> str:
    """
    Classify the type of pull error for targeted troubleshooting.
    
    Args:
        error_msg: The error message from a failed pull
        
    Returns:
        PullErrorType constant indicating the error category
    """
    error_lower = error_msg.lower()
    
    # SSH-related errors
    if "ssh:" in error_lower or "no key found" in error_lower or "ssh_auth" in error_lower:
        return PullErrorType.SSH_KEY
    
    # Network errors
    if any(x in error_lower for x in [
        "connection refused", "connection reset", "timeout",
        "network unreachable", "no route to host", "dns",
        "could not resolve", "failed to connect"
    ]):
        return PullErrorType.NETWORK
    
    # Authentication errors
    if any(x in error_lower for x in [
        "unauthorized", "403", "401", "forbidden", "authentication"
    ]):
        return PullErrorType.AUTH
    
    # Service not running (Ollama or Docker)
    if any(x in error_lower for x in [
        "is ollama running", "ollama not running", "ollama service",
        "is docker running", "docker not running", "docker daemon"
    ]):
        return PullErrorType.SERVICE
    if any(x in error_lower for x in [
        "is ollama running", "service unavailable", "connection refused localhost"
    ]):
        return PullErrorType.SERVICE
    
    # Registry issues
    if any(x in error_lower for x in [
        "registry", "manifest unknown", "pull access denied"
    ]):
        return PullErrorType.REGISTRY
    
    # Disk issues
    if any(x in error_lower for x in [
        "no space left", "disk full", "permission denied", "read-only"
    ]):
        return PullErrorType.DISK
    
    # Model not found
    if any(x in error_lower for x in [
        "not found", "does not exist", "unknown model"
    ]):
        return PullErrorType.MODEL_NOT_FOUND
    
    return PullErrorType.UNKNOWN


def get_troubleshooting_steps(error_type: str) -> List[str]:
    """
    Get specific troubleshooting steps based on error type.
    
    Args:
        error_type: PullErrorType constant
        
    Returns:
        List of troubleshooting steps
    """
    steps = {
        PullErrorType.SSH_KEY: [
            "SSH-related error detected. Try:",
            "  1. Restart Ollama: pkill ollama && ollama serve &",
            "  2. Retry the pull: ollama pull <model>",
            "  3. If issue persists, check Ollama installation: ollama --version",
        ],
        PullErrorType.NETWORK: [
            "Network connectivity issue detected. Try:",
            "  1. Check internet connection: curl -k https://ollama.com",
            "  2. Disable VPN if active",
            "  3. Check proxy settings: echo $HTTP_PROXY $HTTPS_PROXY",
            "  4. Test registry: curl -k https://registry.ollama.ai/v2/",
        ],
        PullErrorType.AUTH: [
            "Authentication error. This is unusual for public models:",
            "  1. Clear Ollama cache: rm -rf ~/.ollama/models/*",
            "  2. Restart Ollama: pkill ollama && ollama serve &",
            "  3. If on corporate network, check proxy/firewall settings",
        ],
        PullErrorType.SERVICE: [
            "Ollama service is not running. Try:",
            "  1. Start Ollama: ollama serve (or open Ollama app)",
            "  2. Check status: ollama list",
            "  3. Check logs: tail -f ~/.ollama/logs/server.log",
        ],
        PullErrorType.REGISTRY: [
            "Cannot reach Ollama registry. Try:",
            "  1. Check registry status: curl -k https://registry.ollama.ai/v2/",
            "  2. Wait and retry (registry may be temporarily down)",
            "  3. Check if model name is correct: ollama search <model>",
        ],
        PullErrorType.DISK: [
            "Disk space or permission issue. Try:",
            "  1. Check disk space: df -h ~/.ollama",
            "  2. Clear old models: ollama rm <old-model>",
            "  3. Check permissions: ls -la ~/.ollama",
        ],
        PullErrorType.MODEL_NOT_FOUND: [
            "Model not found in registry. Try:",
            "  1. Search for model: ollama search <model-name>",
            "  2. Check model name spelling and tag",
            "  3. Try without tag: ollama pull <model-name>",
        ],
        PullErrorType.UNKNOWN: [
            "Unknown error. Try these general steps:",
            "  1. Restart Ollama: pkill ollama && ollama serve &",
            "  2. Clear cache: rm -rf ~/.ollama/models/*",
            "  3. Reinstall Ollama from ollama.com",
            "  4. Check Ollama GitHub issues for similar problems",
        ],
    }
    return steps.get(error_type, steps[PullErrorType.UNKNOWN])


@dataclass
class PullResult:
    """Result of a model pull attempt."""
    model: GemmaModel
    success: bool
    verified: bool = False
    error_message: str = ""


@dataclass
class SetupResult:
    """Result of the complete model setup."""
    successful_models: List[GemmaModel] = field(default_factory=list)
    failed_models: List[Tuple[GemmaModel, str]] = field(default_factory=list)
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


def is_ollama_api_available() -> bool:
    """Check if Ollama API is reachable."""
    try:
        req = urllib.request.Request(f"{OLLAMA_API_BASE}/api/tags", method="GET")
        with urllib.request.urlopen(req, timeout=API_TIMEOUT, context=get_unverified_ssl_context()) as response:
            return response.status == 200
    except (urllib.error.URLError, urllib.error.HTTPError, OSError):
        return False


def get_installed_models() -> List[str]:
    """Get list of currently installed Ollama models."""
    try:
        req = urllib.request.Request(f"{OLLAMA_API_BASE}/api/tags", method="GET")
        with urllib.request.urlopen(req, timeout=API_TIMEOUT, context=get_unverified_ssl_context()) as response:
            if response.status == 200:
                data = json.loads(response.read().decode('utf-8'))
                return [m.get("name", "") for m in data.get("models", [])]
    except (urllib.error.URLError, urllib.error.HTTPError, OSError, json.JSONDecodeError):
        pass
    
    # Fallback to ollama list command
    code, stdout, _ = utils.run_command(["ollama", "list"], timeout=OLLAMA_LIST_TIMEOUT, clean_env=True)
    if code == 0:
        models = []
        lines = stdout.strip().split("\n")
        for line in lines[1:]:  # Skip header
            if line.strip():
                parts = line.split()
                if parts:
                    models.append(parts[0])
        return models
    
    return []


def verify_model_exists(model_name: str) -> bool:
    """
    Verify that a model exists in Ollama after pulling.
    
    Checks both full name (codestral:22b) and base name (codestral).
    """
    installed = get_installed_models()
    
    # Normalize model name
    model_lower = model_name.lower()
    base_name = model_lower.split(":")[0]
    
    for installed_model in installed:
        installed_lower = installed_model.lower()
        installed_base = installed_lower.split(":")[0]
        
        # Check exact match
        if model_lower == installed_lower:
            return True
        
        # Check base name match (e.g., "codestral" matches "codestral:22b-v0.1-q4_K_M")
        if base_name == installed_base:
            return True
        
        # Check if requested model is a prefix of installed
        if installed_lower.startswith(model_lower):
            return True
    
    return False


def pull_model_with_verification(
    model_name: str,
    show_progress: bool = True
) -> Tuple[bool, str]:
    """
    Pull a model with immediate verification (simplified for OpenCode setup).

    Args:
        model_name: Ollama model name (e.g., "gemma4:31b", "nomic-embed-text")
        show_progress: Whether to show progress output

    Returns:
        Tuple of (success, error_message)
    """
    # Check if model is restricted (Chinese-based)
    if is_restricted_model_name(model_name):
        error_msg = f"Model {model_name} is from a restricted country and cannot be downloaded"
        if show_progress:
            ui.print_error(f"✗ Blocked: {model_name}")
            ui.print_error(f"  Reason: Chinese-based LLMs are not allowed")
        return False, error_msg

    if show_progress:
        ui.print_info(f"Pulling {model_name}...")

    # Try to pull the model
    success, error_msg = _pull_model(model_name, show_progress)

    if success:
        # Verify the model exists
        time.sleep(VERIFICATION_DELAY)  # Brief pause for Ollama to update
        if verify_model_exists(model_name):
            if show_progress:
                ui.print_success(f"✓ {model_name} downloaded and verified")
            return True, ""
        else:
            if show_progress:
                ui.print_warning(f"⚠ {model_name} pull succeeded but verification failed")
            return False, "Pull appeared to succeed but model not found in Ollama"
    else:
        if show_progress:
            ui.print_error(f"✗ Failed to pull {model_name}")
            if error_msg:
                # Show truncated error for readability
                display_error = error_msg[:300] if len(error_msg) > 300 else error_msg
                ui.print_error(f"  Error: {display_error}")
        return False, error_msg or "Model pull failed"


def run_preflight_check(show_progress: bool = True) -> Tuple[bool, str, Optional[str]]:
    """
    Run a pre-flight check by pulling a tiny test model.
    
    This helps identify issues before attempting larger downloads.
    
    Returns:
        Tuple of (success, message, error_type):
        - success: True if pre-flight check passed
        - message: Status or error message
        - error_type: PullErrorType if failed, None if successful
    """
    if show_progress:
        ui.print_info(f"Running pre-flight check with {PREFLIGHT_TEST_MODEL}...")
    
    # First check if Ollama API is responding
    if not is_ollama_api_available():
        return False, "Ollama API not responding. Is Ollama running?", PullErrorType.SERVICE
    
    # Try pulling the tiny test model
    success, error_msg = _pull_model_single_attempt(PREFLIGHT_TEST_MODEL, show_progress=False)
    
    if success:
        # Clean up test model to save space
        utils.run_command(["ollama", "rm", PREFLIGHT_TEST_MODEL], timeout=30, clean_env=True)
        if show_progress:
            ui.print_success("Pre-flight check passed!")
        return True, "Pre-flight check passed", None
    
    # Classify the error
    error_type = classify_pull_error(error_msg)
    
    if show_progress:
        ui.print_error(f"Pre-flight check failed: {error_msg[:150]}")
        ui.print_warning(f"Error type: {error_type}")
        print()
        for step in get_troubleshooting_steps(error_type):
            print(f"  {step}")
    
    return False, error_msg, error_type


def _pull_model_via_api(model_name: str, show_progress: bool = True) -> Tuple[bool, str]:
    """
    Pull a model using Ollama API with streaming JSON progress.
    
    This is the preferred method as it provides clean JSON progress data
    instead of parsing ANSI-formatted CLI output.
    
    Returns:
        Tuple of (success, error_message)
    """
    import json as json_module
    
    try:
        # Try to use rich progress bar
        try:
            from rich.progress import Progress, SpinnerColumn, BarColumn, TextColumn, DownloadColumn, TransferSpeedColumn, TimeRemainingColumn
            from rich.console import Console
            use_rich = True
        except ImportError:
            use_rich = False
        
        # Prepare API request
        import urllib.request
        import urllib.parse
        
        url = f"{OLLAMA_API_BASE}/api/pull"
        data = json_module.dumps({"name": model_name}).encode('utf-8')
        req = urllib.request.Request(
            url,
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        
        if use_rich:
            console = Console()
            with Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
                BarColumn(),
                TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
                DownloadColumn(),
                TransferSpeedColumn(),
                TimeRemainingColumn(),
                console=console,
                transient=False,
                refresh_per_second=10
            ) as progress:
                # Track multiple layers (Ollama pulls multiple blobs)
                tasks: Dict[str, Any] = {}  # digest -> task_id
                total_bytes_all_layers = 0
                completed_bytes_all_layers = 0
                
                try:
                    with urllib.request.urlopen(req, timeout=MODEL_PULL_TIMEOUT, context=get_unverified_ssl_context()) as response:
                        for line_bytes in response:
                            try:
                                line = line_bytes.decode('utf-8').strip()
                                if not line:
                                    continue
                                
                                # Parse JSON response
                                data = json_module.loads(line)
                                status = data.get("status", "")
                                
                                if status == "pulling manifest":
                                    # Skip manifest - we'll show progress for actual layer downloads
                                    # No need to create a progress bar for manifest
                                    continue
                                
                                elif status.startswith("pulling ") and data.get("digest"):
                                    # Layer download progress
                                    digest = data.get("digest", "")
                                    total = data.get("total")
                                    completed = data.get("completed", 0)
                                    
                                    if digest and total:
                                        # Create task for this layer if it doesn't exist
                                        if digest not in tasks:
                                            tasks[digest] = progress.add_task(
                                                f"Pulling {model_name}",
                                                total=total
                                            )
                                        
                                        # Update progress for this layer
                                        # Note: TransferSpeedColumn may show "?" for very small files
                                        # that complete too quickly (< 1 second) - this is expected behavior
                                        progress.update(
                                            tasks[digest],
                                            completed=completed,
                                            total=total,
                                            description=f"Pulling {model_name}"
                                        )
                                
                                elif status == "verifying sha256 digest":
                                    # Verification phase - update all layer tasks
                                    for task_id in tasks.values():
                                        progress.update(task_id, description=f"Pulling {model_name} (verifying)")
                                
                                elif status == "success":
                                    # Complete all tasks
                                    for task_id in tasks.values():
                                        progress.update(task_id, completed=progress.tasks[task_id].total or 100, total=progress.tasks[task_id].total or 100)
                                    print()
                                    ui.print_success(f"Downloaded {model_name}")
                                    return True, ""
                                
                                elif "error" in status.lower():
                                    error_msg = data.get("error", status)
                                    print()
                                    ui.print_error(f"Error: {error_msg}")
                                    return False, error_msg
                            
                            except json_module.JSONDecodeError:
                                # Skip malformed JSON lines
                                continue
                            except Exception as e:
                                # Log but continue
                                continue
                
                except urllib.error.HTTPError as e:
                    error_body = e.read().decode('utf-8') if e.fp else ""
                    try:
                        error_data = json_module.loads(error_body)
                        error_msg = error_data.get("error", error_body)
                    except:
                        error_msg = error_body or str(e)
                    return False, error_msg
                except Exception as e:
                    return False, str(e)
        
        else:
            # Fallback: simple progress without rich
            try:
                with urllib.request.urlopen(req, timeout=MODEL_PULL_TIMEOUT, context=get_unverified_ssl_context()) as response:
                    last_percent = 0
                    for line_bytes in response:
                        try:
                            line = line_bytes.decode('utf-8').strip()
                            if not line:
                                continue
                            
                            data = json_module.loads(line)
                            status = data.get("status", "")
                            total = data.get("total")
                            completed = data.get("completed", 0)
                            
                            if status.startswith("pulling ") and total and completed:
                                percent = int((completed / total) * 100) if total > 0 else 0
                                if percent != last_percent:
                                    downloaded_mb = completed / (1024 * 1024)
                                    total_mb = total / (1024 * 1024)
                                    print(f"\r    {percent:3d}% ({downloaded_mb:.1f} MB / {total_mb:.1f} MB)", end="", flush=True)
                                    last_percent = percent
                            elif status == "success":
                                print()
                                ui.print_success(f"Downloaded {model_name}")
                                return True, ""
                            elif "error" in status.lower():
                                error_msg = data.get("error", status)
                                print()
                                ui.print_error(f"Error: {error_msg}")
                                return False, error_msg
                        
                        except json_module.JSONDecodeError:
                            continue
                        except Exception:
                            continue
            
            except Exception as e:
                return False, str(e)
        
        return False, "Unexpected end of stream"

    except Exception as e:
        return False, f"API error: {type(e).__name__}: {e}"


# =============================================================================
# Phase 1: Helper Functions (Pure Functions)
# =============================================================================

@dataclass
class ProgressInfo:
    """Parsed progress information from Ollama output."""
    percent: Optional[int] = None
    downloaded_bytes: Optional[int] = None
    total_bytes: Optional[int] = None
    status: str = "pulling"  # "pulling", "manifest", "complete", "error"
    message: str = ""


def _remove_ansi_codes(line: str) -> str:
    """
    Remove ANSI escape sequences from terminal output.

    Args:
        line: Raw terminal output line with ANSI codes

    Returns:
        Cleaned string with ANSI codes removed
    """
    # Remove ANSI control sequences (including cursor positioning with ?)
    clean = re.sub(r'\x1b\[[0-9;?]*[a-zA-Z]', '', line)
    # Remove OSC sequences
    clean = re.sub(r'\x1b\][0-9;]*', '', clean)
    return clean.strip()


def _parse_ollama_progress(line: str) -> Optional[ProgressInfo]:
    """
    Parse Ollama progress line into structured data.

    Format examples:
    - "pulling manifest"
    - "pulling abc123:  45% ▕██...▏ 2.5 GB/5.5 GB"
    - "success"

    Args:
        line: Cleaned terminal output line (ANSI removed)

    Returns:
        ProgressInfo if line contains progress, None otherwise
    """
    line_lower = line.lower()

    # Check for completion
    if any(word in line_lower for word in ["success", "done", "complete"]):
        return ProgressInfo(percent=100, status="complete", message=line)

    # Check for errors
    if "error" in line_lower or "ssh:" in line_lower:
        return ProgressInfo(status="error", message=line)

    # Check for pulling with percentage
    if "pulling" in line_lower and "%" in line:
        # Extract percentage first
        percent_match = re.search(r'(\d+)%', line)
        if percent_match:
            percent = int(percent_match.group(1))

            # Extract size info if available: "X MB/Y GB"
            size_match = re.search(
                r'(\d+(?:\.\d+)?)\s*(MB|GB)\s*/\s*(\d+(?:\.\d+)?)\s*(MB|GB)',
                line
            )

            if size_match:
                downloaded = float(size_match.group(1))
                downloaded_unit = size_match.group(2)
                total = float(size_match.group(3))
                total_unit = size_match.group(4)

                # Convert to bytes
                downloaded_bytes = int(downloaded * (1024**3 if downloaded_unit == "GB" else 1024**2))
                total_bytes = int(total * (1024**3 if total_unit == "GB" else 1024**2))

                return ProgressInfo(
                    percent=percent,
                    downloaded_bytes=downloaded_bytes,
                    total_bytes=total_bytes,
                    status="pulling"
                )
            else:
                # Just percentage, no size info
                return ProgressInfo(percent=percent, status="pulling")

    # Check for manifest pulling (without percentage)
    if "pulling manifest" in line_lower:
        return ProgressInfo(status="manifest", message="Pulling manifest")

    return None


def _create_rich_progress_bar() -> 'Progress':
    """
    Create pre-configured rich Progress bar for model downloading.

    Returns:
        Configured Progress instance with columns for downloading
    """
    from rich.progress import (
        Progress, SpinnerColumn, BarColumn, TextColumn,
        DownloadColumn, TransferSpeedColumn, TimeRemainingColumn
    )
    from rich.console import Console

    return Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        BarColumn(),
        TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
        DownloadColumn(),
        TransferSpeedColumn(),
        TimeRemainingColumn(),
        console=Console(),
        transient=False,
        refresh_per_second=2  # Reduced from 10 (performance optimization)
    )


# =============================================================================
# Phase 2: Progress Handlers
# =============================================================================

def _monitor_rich_progress(
    process: subprocess.Popen,
    model_name: str,
    progress: 'Progress',
    task: 'TaskID'
) -> List[str]:
    """
    Monitor subprocess stderr and update rich progress bar.

    Args:
        process: Running subprocess (ollama pull)
        model_name: Model being pulled
        progress: Rich Progress instance
        task: Progress task ID

    Returns:
        List of output lines for error reporting
    """
    output_lines = []
    total_bytes = None

    if not process.stderr:
        return output_lines

    for line in process.stderr:
        # Clean ANSI codes
        clean_line = _remove_ansi_codes(line)

        # Handle edge case: "pulling manifest" appended to progress line
        if "pulling manifest" in clean_line.lower() and "%" in clean_line:
            clean_line = clean_line.split("pulling manifest")[0].strip()

        if not clean_line and "%" not in line:
            continue

        if clean_line:
            output_lines.append(clean_line)

        # Parse progress
        progress_info = _parse_ollama_progress(clean_line)
        if not progress_info:
            continue

        # Update progress bar based on parsed info
        if progress_info.status == "pulling" and progress_info.percent is not None:
            if progress_info.total_bytes:
                # Update with actual bytes
                total_bytes = progress_info.total_bytes
                progress.update(
                    task,
                    completed=progress_info.downloaded_bytes,
                    total=progress_info.total_bytes,
                    description=f"Pulling {model_name}"
                )
            else:
                # Update with percentage only
                if total_bytes is None:
                    progress.update(task, total=100, completed=progress_info.percent)
                else:
                    completed_bytes = int((progress_info.percent / 100) * total_bytes)
                    progress.update(task, completed=completed_bytes, total=total_bytes)

        elif progress_info.status == "manifest":
            progress.update(task, description=f"Pulling {model_name} (manifest)", total=None)

        elif progress_info.status == "complete":
            if total_bytes:
                progress.update(task, completed=total_bytes, total=total_bytes)
            else:
                progress.update(task, completed=100, total=100)
            print()
            ui.print_success(f"Downloaded {model_name}")

        elif progress_info.status == "error":
            print()
            ui.print_error(f"    {progress_info.message}")

    return output_lines


def _monitor_simple_progress(process: subprocess.Popen, model_name: str) -> List[str]:
    """
    Monitor subprocess stderr with simple text output (no rich).

    Args:
        process: Running subprocess (ollama pull)
        model_name: Model being pulled

    Returns:
        List of output lines for error reporting
    """
    output_lines = []

    if not process.stderr:
        return output_lines

    for line in process.stderr:
        clean_line = _remove_ansi_codes(line)
        if not clean_line:
            continue

        output_lines.append(clean_line)

        # Simple progress output
        line_lower = clean_line.lower()
        if "pulling" in line_lower or "%" in clean_line:
            print(f"    {clean_line}", end="\r", flush=True)
        elif any(word in line_lower for word in ["success", "done"]):
            print()
            ui.print_success(f"    {clean_line}")
        elif "error" in line_lower or "ssh:" in line_lower:
            print()
            ui.print_error(f"    {clean_line}")

    return output_lines


# =============================================================================
# Phase 3: Transport Methods
# =============================================================================

def _pull_via_cli_with_progress(model_name: str) -> Tuple[bool, str]:
    """
    Pull model via Ollama CLI with progress display.

    Uses rich progress bar if available, falls back to simple output.

    Args:
        model_name: Model to pull (e.g., "gpt-oss:20b")

    Returns:
        Tuple of (success, error_message)
    """
    # Check if rich is available
    try:
        from rich.progress import Progress
        use_rich = True
    except ImportError:
        use_rich = False

    # Create clean environment (remove SSH_AUTH_SOCK for VPN resilience)
    clean_env = {k: v for k, v in os.environ.items() if k != 'SSH_AUTH_SOCK'}

    # Start subprocess
    process = subprocess.Popen(
        ["ollama", "pull", model_name],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
        env=clean_env
    )

    try:
        # Monitor progress based on available UI
        if use_rich:
            with _create_rich_progress_bar() as progress:
                task = progress.add_task(f"Pulling {model_name}", total=100)
                output_lines = _monitor_rich_progress(process, model_name, progress, task)
        else:
            output_lines = _monitor_simple_progress(process, model_name)

        # Wait for completion
        if process.poll() is None:
            process.wait(timeout=MODEL_PULL_TIMEOUT)

        # Check result
        if process.returncode == 0:
            return True, ""
        else:
            # Find error in output
            error_msg = ""
            for line in output_lines:
                if any(word in line.lower() for word in ["error", "failed", "ssh:"]):
                    error_msg = line
                    break
            return False, error_msg or "Unknown error during pull"

    except subprocess.TimeoutExpired:
        process.kill()
        try:
            process.wait(timeout=PROCESS_KILL_TIMEOUT)
        except subprocess.TimeoutExpired:
            pass
        return False, f"Timeout after {MODEL_PULL_TIMEOUT}s"

    finally:
        # Cleanup
        if process.poll() is None:
            process.kill()
            try:
                process.wait(timeout=PROCESS_KILL_TIMEOUT)
            except subprocess.TimeoutExpired:
                pass


def _pull_via_cli_silent(model_name: str) -> Tuple[bool, str]:
    """
    Pull model via Ollama CLI without progress display.

    Args:
        model_name: Model to pull

    Returns:
        Tuple of (success, error_message)
    """
    code, stdout, stderr = utils.run_command(
        ["ollama", "pull", model_name],
        timeout=MODEL_PULL_TIMEOUT,
        clean_env=True
    )

    if code == 0:
        return True, ""
    else:
        error_msg = stderr.strip() if stderr else stdout.strip()
        return False, error_msg or "Unknown error during pull"


# =============================================================================
# Phase 4: Simplified Main Function
# =============================================================================

def _pull_model_single_attempt(model_name: str, show_progress: bool = True, use_api: bool = True) -> Tuple[bool, str]:
    """
    Execute a single Ollama pull attempt without retries.

    Strategy:
    1. Try API method first (clean JSON progress)
    2. Fall back to CLI with progress display
    3. Or use silent CLI if progress disabled

    Args:
        model_name: Model to pull (e.g., "gpt-oss:20b")
        show_progress: Whether to display progress
        use_api: Whether to try API method first

    Returns:
        Tuple of (success, error_message):
        - success: True if pull succeeded
        - error_message: Error details if failed, empty if successful
    """
    # Try API first (preferred: clean JSON progress)
    if use_api:
        try:
            return _pull_model_via_api(model_name, show_progress)
        except Exception as e:
            if show_progress:
                ui.print_warning(f"API pull failed, falling back to CLI: {e}")

    # Fall back to CLI method
    try:
        if show_progress:
            return _pull_via_cli_with_progress(model_name)
        else:
            return _pull_via_cli_silent(model_name)

    except FileNotFoundError:
        return False, "Ollama command not found - is Ollama installed?"
    except (OSError, IOError, subprocess.SubprocessError) as e:
        return False, f"Process error: {type(e).__name__}: {e}"

def _pull_model(model_name: str, show_progress: bool = True) -> Tuple[bool, str]:
    """
    Execute ollama pull command with retry logic and exponential backoff.
    
    Returns:
        Tuple of (success, error_message):
        - success: True if the command succeeded
        - error_message: Error details if failed, empty string if successful
    
    Implements:
    - Up to MAX_PULL_RETRIES attempts
    - Exponential backoff between retries
    - Proper process cleanup on timeout or error
    """
    last_error = ""
    
    for attempt in range(MAX_PULL_RETRIES):
        if attempt > 0:
            # Exponential backoff
            delay = RETRY_BASE_DELAY * (2 ** (attempt - 1))
            if show_progress:
                ui.print_info(f"Retrying in {delay}s... (attempt {attempt + 1}/{MAX_PULL_RETRIES})")
            time.sleep(delay)
        
        success, error_msg = _pull_model_single_attempt(model_name, show_progress)
        
        if success:
            return True, ""
        
        last_error = error_msg
        error_type = classify_pull_error(error_msg)
        
        # Don't retry certain errors
        if error_type in [PullErrorType.MODEL_NOT_FOUND, PullErrorType.DISK]:
            if show_progress:
                ui.print_warning(f"Not retrying - error type: {error_type}")
            break
        
        if show_progress and attempt < MAX_PULL_RETRIES - 1:
            ui.print_warning(f"Attempt {attempt + 1} failed: {error_msg[:100]}")
    
    return False, last_error




def pull_models_with_tracking(
    models: List[GemmaModel],
    hw_info: hardware.HardwareInfo,
    show_progress: bool = True
) -> SetupResult:
    """
    Pull multiple models with verification and tracking.
    
    Implements the reliable pulling strategy:
    1. Pull each model
    2. Verify after each pull
    3. Continue with remaining models on failure
    4. Report partial setup status
    """
    result = SetupResult()
    
    if show_progress:
        ui.print_header("📥 Downloading Models")
        total_gb = sum(m.ram_gb for m in models) * 0.5  # Rough download estimate
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
    """
    Display the setup result with actionable next steps.
    
    Format:
    Setup Complete (with warnings)
    
    ✓ codestral:22b - Ready to use
    ✓ granite-code:3b - Ready to use  
    ✗ nomic-embed-text - Failed to download
    
    You can code and get autocomplete now.
    Codebase search (@codebase) won't work until embeddings model is installed.
    
    To retry failed models:
      ollama pull nomic-embed-text
    
    [Continue to IDE Setup] [Retry Failed Models] [Exit]
    """
    print()
    
    if result.complete_success:
        ui.print_header("✅ Setup Complete!")
    elif result.partial_success:
        ui.print_header("⚠️ Setup Complete (with warnings)")
    else:
        ui.print_header("❌ Setup Failed")
    
    print()
    
    # Show successful models
    for model in result.successful_models:
        ui.print_success(f"{model.ollama_name} - Ready to use")
    
    # Show failed models with error details
    for model, error in result.failed_models:
        ui.print_error(f"{model.ollama_name} - Failed to download")
        if error:
            # Show truncated error for readability
            display_error = error[:150] if len(error) > 150 else error
            print(ui.colorize(f"    └─ {display_error}", ui.Colors.DIM))
    
    print()
    
    # Show warnings
    if result.warnings:
        for warning in result.warnings:
            ui.print_warning(warning)
        print()
    
    # Actionable guidance based on what's working
    if result.partial_success:
        # Determine what's working and what's not
        has_primary = any(m.role == ModelRole.CHAT for m in result.successful_models)
        has_autocomplete = any(m.role == ModelRole.AUTOCOMPLETE for m in result.successful_models)
        has_embed = any(m.role == ModelRole.EMBED for m in result.successful_models)
        
        working = []
        not_working = []
        
        if has_primary:
            working.append("chat and code editing")
        else:
            not_working.append("Primary coding features won't work")
        
        if has_autocomplete:
            working.append("autocomplete")
        else:
            not_working.append("Autocomplete won't work")
        
        if has_embed:
            working.append("codebase search (@codebase)")
        else:
            not_working.append("Codebase search (@codebase) won't work")
        
        if working:
            print(ui.colorize(f"Working now: {', '.join(working)}", ui.Colors.GREEN))
        
        if not_working:
            for issue in not_working:
                print(ui.colorize(f"⚠ {issue} until missing model is installed.", ui.Colors.YELLOW))
        
        print()
    
    # If complete failure, provide diagnostic guidance based on error type
    if result.complete_failure:
        # Try to classify the most common error
        most_common_error = ""
        if result.failed_models:
            _, first_error = result.failed_models[0]
            most_common_error = first_error
        
        error_type = classify_pull_error(most_common_error)
        
        print(ui.colorize(f"Error Type: {error_type}", ui.Colors.YELLOW + ui.Colors.BOLD))
        print()
        
        steps = get_troubleshooting_steps(error_type)
        for step in steps:
            print(f"  {step}")
        print()
        
        # Additional SSH-specific guidance if relevant
        if error_type == PullErrorType.SSH_KEY:
            print(ui.colorize("Quick Fix for SSH errors:", ui.Colors.CYAN + ui.Colors.BOLD))
            print("  Run these commands in order:")
            print("    pkill ollama")
            print("    ollama serve &")
            print("    ollama pull <model-name>")
            print()
    
    # Show retry commands for failed models
    if result.failed_models:
        print("To retry failed models:")
        for model, _ in result.failed_models:
            print(ui.colorize(f"  ollama pull {model.ollama_name}", ui.Colors.CYAN))
        print()


def prompt_setup_action(result: SetupResult) -> str:
    """
    Prompt user for next action after setup.
    
    Returns: "continue", "retry", or "exit"
    """
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
    else:
        return "exit"


def retry_failed_models(
    result: SetupResult,
    hw_info: hardware.HardwareInfo
) -> SetupResult:
    """
    Retry pulling failed models.
    
    Returns updated SetupResult with retry results merged.
    """
    if not result.failed_models:
        return result
    
    models_to_retry = [model for model, _ in result.failed_models]
    retry_result = pull_models_with_tracking(models_to_retry, hw_info)
    
    # Merge results
    new_result = SetupResult()
    new_result.successful_models = result.successful_models + retry_result.successful_models
    new_result.warnings = result.warnings + retry_result.warnings
    
    # Keep only models that still failed
    still_failed_names = {model.ollama_name for model, _ in retry_result.failed_models}
    new_result.failed_models = [
        (model, error) for model, error in result.failed_models
        if model.ollama_name in still_failed_names
    ]
    
    return new_result


def test_ollama_connectivity() -> Tuple[bool, str, Dict[str, Any]]:
    """
    Comprehensive connectivity test for Ollama model pulling.
    
    Tests:
    1. Local Ollama API is running
    2. Can reach ollama.com (model registry)
    3. Can perform a model search (validates registry access)
    
    Returns:
        Tuple of (success, message, details):
        - success: True if all tests pass
        - message: Human-readable status message
        - details: Dict with individual test results
    """
    details: Dict[str, Any] = {
        "ollama_api": False,
        "registry_reachable": False,
        "search_works": False,
        "errors": []
    }
    
    ui.print_info("Testing connectivity...")
    
    # Test 1: Local Ollama API
    try:
        req = urllib.request.Request(f"{OLLAMA_API_BASE}/api/tags", method="GET")
        with urllib.request.urlopen(req, timeout=API_TIMEOUT, context=get_unverified_ssl_context()) as response:
            if response.status == 200:
                details["ollama_api"] = True
                ui.print_success("  Local Ollama API is running")
    except (urllib.error.URLError, urllib.error.HTTPError, OSError) as e:
        details["errors"].append(f"Ollama API: {type(e).__name__}: {e}")
        ui.print_error("  Local Ollama API is not available")
        return False, "Ollama is not running. Start Ollama and try again.", details
    
    # Test 2: Can reach ollama.com
    try:
        req = urllib.request.Request("https://ollama.com")
        req.add_header("User-Agent", "Ollama-LLM-Setup/2.0")
        with urllib.request.urlopen(req, timeout=API_TIMEOUT_LONG, context=get_unverified_ssl_context()) as response:
            if response.status == 200:
                details["registry_reachable"] = True
                ui.print_success("  Ollama registry (ollama.com) is reachable")
    except (urllib.error.URLError, urllib.error.HTTPError, OSError) as e:
        details["errors"].append(f"Registry: {type(e).__name__}: {e}")
        ui.print_warning("  Cannot reach ollama.com - may be SSL/proxy issue")
    
    # Test 3: Try ollama search command
    code, stdout, stderr = utils.run_command(["ollama", "search", "granite"], timeout=15, clean_env=True)
    if code == 0 and stdout:
        details["search_works"] = True
        ui.print_success("  Ollama search is working")
    else:
        # Try an alternative test - list existing models
        code2, stdout2, stderr2 = utils.run_command(["ollama", "list"], timeout=10, clean_env=True)
        if code2 == 0:
            ui.print_info("  Ollama list works (search may not be available)")
        else:
            details["errors"].append(f"Search: exit={code}, stderr={stderr[:100] if stderr else 'none'}")
            ui.print_warning("  Ollama search/list not working properly")
    
    # Determine overall status
    if not details["registry_reachable"] and not details["search_works"]:
        return False, "Cannot reach Ollama registry. Check network/proxy settings.", details
    
    return True, "Connectivity OK", details


def validate_pre_install(
    models: List[GemmaModel],
    hw_info: hardware.HardwareInfo,
    run_preflight: bool = False
) -> Tuple[bool, List[str]]:
    """
    Pre-installation validation.
    
    Checks:
    - Models are not restricted (Chinese-based LLMs are not allowed)
    - Ollama is installed and running
    - Models fit in available RAM
    - Network connectivity (with detailed diagnostics)
    - Optional: Pre-flight pull test with tiny model
    
    Args:
        models: List of models to validate
        hw_info: Hardware information
        run_preflight: If True, runs a pre-flight test by pulling a tiny model
    
    Returns: (is_valid, list_of_warnings)
    """
    warnings = []
    
    # Check for restricted models (Chinese-based LLMs)
    restricted_models = [m for m in models if is_restricted_model_name(m.ollama_name)]
    if restricted_models:
        for model in restricted_models:
            warnings.append(
                f"Model {model.ollama_name} ({model.name}) is from a restricted country and cannot be downloaded. "
                f"Chinese-based LLMs are not allowed."
            )
        # This is a hard failure - cannot proceed with restricted models
        return False, warnings
    
    # Check Ollama API
    if not is_ollama_api_available():
        warnings.append("Ollama API is not available. Please ensure Ollama is running.")
        # Can't continue validation if API is down
        return False, warnings
    
    # Check RAM
    usable_ram = hw_info.ram_gb  # Use total RAM for validation
    total_ram_needed = sum(m.ram_gb for m in models)
    
    if total_ram_needed > usable_ram:
        warnings.append(
            f"Selected models ({total_ram_needed:.1f}GB) exceed available RAM ({usable_ram:.1f}GB). "
            f"Some models may not load simultaneously."
        )
    elif total_ram_needed > usable_ram * 0.90:
        warnings.append(
            f"Selected models use {total_ram_needed:.1f}GB of {usable_ram:.1f}GB available RAM. "
            f"System may be slow. Consider reducing model count."
        )
    
    # Comprehensive network connectivity test
    conn_ok, conn_msg, conn_details = test_ollama_connectivity()
    
    if not conn_ok:
        warnings.append(f"Network issue: {conn_msg}")
        if conn_details.get("errors"):
            for err in conn_details["errors"][:3]:  # Show up to 3 errors
                warnings.append(f"  - {err}")
    elif not conn_details.get("registry_reachable"):
        warnings.append(
            "Cannot reach ollama.com directly. Model downloads may work via Ollama CLI. "
            "Proceed if models are already cached or behind proxy."
        )
    
    # Optional pre-flight check
    if run_preflight:
        preflight_ok, preflight_msg, error_type = run_preflight_check(show_progress=True)
        if not preflight_ok:
            warnings.append(f"Pre-flight check failed: {preflight_msg[:100]}")
            if error_type:
                warnings.append(f"Error type: {error_type}")
                # Add troubleshooting steps
                steps = get_troubleshooting_steps(error_type)
                for step in steps[:3]:  # Show first 3 steps
                    warnings.append(step)
            return False, warnings
    
    is_valid = not any("API is not available" in w for w in warnings)
    
    return is_valid, warnings


def run_diagnostics(verbose: bool = True) -> Dict[str, Any]:
    """
    Run comprehensive diagnostics to identify pull issues.
    
    This function checks:
    - Ollama installation and version
    - Ollama service status
    - Network connectivity
    - Registry access
    - SSH agent status
    - Environment variables
    
    Args:
        verbose: If True, print diagnostic output
        
    Returns:
        Dict with diagnostic results
    """
    import os
    
    results: Dict[str, Any] = {
        "ollama_installed": False,
        "ollama_version": "",
        "ollama_service_running": False,
        "api_accessible": False,
        "registry_reachable": False,
        "ssh_agent_active": False,
        "proxy_configured": False,
        "issues_found": [],
        "recommendations": [],
    }
    
    if verbose:
        ui.print_header("🔍 Ollama Diagnostics")
        print()
    
    # Check 1: Ollama installation
    code, stdout, _ = utils.run_command(["ollama", "--version"], timeout=5, clean_env=True)
    if code == 0:
        results["ollama_installed"] = True
        results["ollama_version"] = stdout.strip()
        if verbose:
            ui.print_success(f"Ollama installed: {stdout.strip()}")
    else:
        results["issues_found"].append("Ollama not installed")
        results["recommendations"].append("Install Ollama from https://ollama.com")
        if verbose:
            ui.print_error("Ollama not installed")
            return results
    
    # Check 2: Ollama service
    if is_ollama_api_available():
        results["ollama_service_running"] = True
        results["api_accessible"] = True
        if verbose:
            ui.print_success("Ollama service is running")
    else:
        results["issues_found"].append("Ollama service not running")
        results["recommendations"].append("Start Ollama: ollama serve (or open Ollama app)")
        if verbose:
            ui.print_error("Ollama service not running")
    
    # Check 3: List models
    code, stdout, stderr = utils.run_command(["ollama", "list"], timeout=10, clean_env=True)
    if code == 0:
        if verbose:
            model_count = len(stdout.strip().split("\n")) - 1  # Subtract header
            ui.print_success(f"Ollama list works ({max(0, model_count)} models installed)")
    else:
        results["issues_found"].append(f"ollama list failed: {stderr[:100]}")
        if verbose:
            ui.print_error(f"ollama list failed: {stderr[:100]}")
    
    # Check 4: Registry access
    try:
        req = urllib.request.Request("https://registry.ollama.ai/v2/")
        with urllib.request.urlopen(req, timeout=10, context=get_unverified_ssl_context()) as response:
            # 401 is expected (no auth), 200 or 404 are also fine
            results["registry_reachable"] = True
            if verbose:
                ui.print_success(f"Registry reachable (HTTP {response.status})")
    except urllib.error.HTTPError as e:
        if e.code in [401, 404]:  # These are expected
            results["registry_reachable"] = True
            if verbose:
                ui.print_success(f"Registry reachable (HTTP {e.code} - expected)")
        else:
            results["issues_found"].append(f"Registry returned HTTP {e.code}")
            if verbose:
                ui.print_warning(f"Registry returned HTTP {e.code}")
    except Exception as e:
        results["issues_found"].append(f"Cannot reach registry: {e}")
        results["recommendations"].append("Check network/firewall settings")
        if verbose:
            ui.print_error(f"Cannot reach registry: {e}")
    
    # Check 5: SSH agent (informational only - script handles this automatically)
    ssh_sock = os.environ.get("SSH_AUTH_SOCK", "")
    if ssh_sock:
        results["ssh_agent_active"] = True
        if verbose:
            ui.print_info("SSH agent detected (script will handle automatically)")
    else:
        if verbose:
            ui.print_success("No SSH agent detected")
    
    # Check 6: Proxy configuration
    proxy_vars = ["HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy", "ALL_PROXY"]
    active_proxies = {k: v for k, v in os.environ.items() if k in proxy_vars and v}
    if active_proxies:
        results["proxy_configured"] = True
        if verbose:
            ui.print_warning(f"Proxy configured: {list(active_proxies.keys())}")
            ui.print_info("  This may affect model downloads")
    else:
        if verbose:
            ui.print_success("No proxy configured")
    
    # Check 7: Try a test pull (only if everything else looks OK)
    if results["ollama_service_running"] and results["registry_reachable"]:
        if verbose:
            print()
            ui.print_info("Testing model pull capability...")
        
        # Try to pull a very small model
        success, error = _pull_model_single_attempt("all-minilm", show_progress=False)
        if success:
            if verbose:
                ui.print_success("Test pull successful!")
            # Clean up
            utils.run_command(["ollama", "rm", "all-minilm"], timeout=30, clean_env=True)
        else:
            error_type = classify_pull_error(error)
            results["issues_found"].append(f"Test pull failed: {error[:100]}")
            results["recommendations"].extend(get_troubleshooting_steps(error_type)[:3])
            if verbose:
                ui.print_error(f"Test pull failed: {error[:100]}")
                ui.print_info(f"Error type: {error_type}")
    
    # Summary
    if verbose:
        print()
        if not results["issues_found"]:
            ui.print_header("✅ All diagnostics passed!")
        else:
            ui.print_header(f"⚠️ Found {len(results['issues_found'])} issue(s)")
            print()
            for issue in results["issues_found"]:
                ui.print_error(f"  • {issue}")
            print()
            if results["recommendations"]:
                ui.print_info("Recommendations:")
                for rec in results["recommendations"][:5]:
                    print(f"  • {rec}")
    
    return results
