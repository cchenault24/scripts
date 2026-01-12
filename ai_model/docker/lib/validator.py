"""
Model Validator and Fallback Handler for Docker Model Runner.

Handles:
- Immediate verification after each model pull
- Fallback to hardcoded catalog when Docker API is unreachable
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
from .model_selector import RecommendedModel, ModelRole, EMBED_MODEL, AUTOCOMPLETE_MODELS, PRIMARY_MODELS


# Docker Model Runner API configuration
DMR_API_BASE = "http://localhost:12434/v1"

# Restricted model keywords (Chinese-based LLMs are not allowed)
RESTRICTED_MODEL_KEYWORDS = [
    "qwen", "deepseek", "deepcoder", "baai", "bge-", "yi", "baichuan",
    "chatglm", "glm", "internlm", "minicpm", "cogvlm", "qianwen", "tongyi"
]

# Timeout and delay constants (in seconds)
API_TIMEOUT = 5
API_TIMEOUT_LONG = 10
MODEL_LIST_TIMEOUT = 10
MODEL_PULL_TIMEOUT = 3600  # 1 hour for large model downloads
PROCESS_KILL_TIMEOUT = 5
VERIFICATION_DELAY = 2

# Retry configuration
MAX_PULL_RETRIES = 3
RETRY_BASE_DELAY = 2


class PullErrorType:
    """Classification of pull errors for targeted troubleshooting."""
    NETWORK = "network"
    AUTH = "auth"
    SERVICE = "service"
    REGISTRY = "registry"
    DISK = "disk"
    MODEL_NOT_FOUND = "model_not_found"
    DOCKER_NOT_RUNNING = "docker_not_running"
    DMR_NOT_ENABLED = "dmr_not_enabled"
    UNKNOWN = "unknown"


def is_restricted_model_name(model_name: str) -> bool:
    """
    Check if a model name is from restricted countries (China-based LLMs).
    """
    model_lower = model_name.lower()
    return any(keyword in model_lower for keyword in RESTRICTED_MODEL_KEYWORDS)


def classify_pull_error(error_msg: str) -> str:
    """Classify the type of pull error for targeted troubleshooting."""
    error_lower = error_msg.lower()
    
    # Docker not running
    if any(x in error_lower for x in [
        "docker daemon", "cannot connect to docker", "is docker running",
        "docker desktop"
    ]):
        return PullErrorType.DOCKER_NOT_RUNNING
    
    # DMR not enabled
    if any(x in error_lower for x in [
        "unknown command", "docker model", "model runner", "not enabled"
    ]):
        return PullErrorType.DMR_NOT_ENABLED
    
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
    
    # Service not running
    if any(x in error_lower for x in [
        "service unavailable", "connection refused localhost"
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
    """Get specific troubleshooting steps based on error type."""
    steps = {
        PullErrorType.DOCKER_NOT_RUNNING: [
            "Docker is not running. Try:",
            "  1. Start Docker Desktop",
            "  2. Wait for Docker to fully start",
            "  3. Run this script again",
        ],
        PullErrorType.DMR_NOT_ENABLED: [
            "Docker Model Runner is not enabled. Try:",
            "  1. Open Docker Desktop",
            "  2. Go to Settings → Features in development",
            "  3. Enable 'Docker Model Runner' or 'Enable Docker AI'",
            "  4. Click 'Apply & restart'",
            "  Or run: docker desktop enable model-runner --tcp 12434",
        ],
        PullErrorType.NETWORK: [
            "Network connectivity issue detected. Try:",
            "  1. Check internet connection",
            "  2. Disable VPN if active",
            "  3. Check proxy settings",
            "  4. Restart Docker Desktop",
        ],
        PullErrorType.AUTH: [
            "Authentication error. Try:",
            "  1. Run: docker logout",
            "  2. Run: docker login",
            "  3. Verify your Docker Hub account",
        ],
        PullErrorType.SERVICE: [
            "Service not running. Try:",
            "  1. Restart Docker Desktop",
            "  2. Verify Docker Model Runner is enabled",
            "  3. Check Docker Desktop logs",
        ],
        PullErrorType.REGISTRY: [
            "Cannot reach Docker Hub registry. Try:",
            "  1. Check internet connection",
            "  2. Wait and retry (registry may be temporarily down)",
            "  3. Check if model name is correct",
        ],
        PullErrorType.DISK: [
            "Disk space or permission issue. Try:",
            "  1. Check disk space: docker system df",
            "  2. Prune unused images: docker system prune",
            "  3. Check Docker Desktop settings for disk usage",
        ],
        PullErrorType.MODEL_NOT_FOUND: [
            "Model not found in registry. Try:",
            "  1. Verify model name is correct",
            "  2. Check Docker Hub for available models",
            "  3. Run: docker search ai/<model-name>",
        ],
        PullErrorType.UNKNOWN: [
            "Unknown error. Try these general steps:",
            "  1. Restart Docker Desktop",
            "  2. Check Docker logs",
            "  3. Verify Docker Model Runner is enabled",
            "  4. Check Docker Desktop for updates",
        ],
    }
    return steps.get(error_type, steps[PullErrorType.UNKNOWN])


@dataclass
class PullResult:
    """Result of a model pull attempt."""
    model: RecommendedModel
    success: bool
    verified: bool = False
    error_message: str = ""
    used_fallback: bool = False
    fallback_model: Optional[RecommendedModel] = None


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


def is_dmr_api_available() -> bool:
    """Check if Docker Model Runner API is reachable."""
    try:
        req = urllib.request.Request(f"{DMR_API_BASE}/models", method="GET")
        with urllib.request.urlopen(req, timeout=API_TIMEOUT, context=get_unverified_ssl_context()) as response:
            return response.status == 200
    except (urllib.error.URLError, urllib.error.HTTPError, OSError):
        return False


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
    
    model_lower = model_name.lower()
    base_name = model_lower.split(":")[0]
    
    for installed_model in installed:
        installed_lower = installed_model.lower()
        installed_base = installed_lower.split(":")[0]
        
        if model_lower == installed_lower:
            return True
        if base_name == installed_base:
            return True
        if installed_lower.startswith(model_lower):
            return True
    
    return False


def get_fallback_model(model: RecommendedModel, tier: hardware.HardwareTier) -> Optional[RecommendedModel]:
    """Get a fallback model for a failed pull."""
    role = model.role
    
    if model.fallback_name:
        if not is_restricted_model_name(model.fallback_name):
            return RecommendedModel(
                name=f"{model.name} (fallback)",
                docker_name=model.fallback_name,
                ram_gb=model.ram_gb,
                role=model.role,
                roles=model.roles,
                context_length=model.context_length,
                description=f"Fallback for {model.name}"
            )
    
    if role == ModelRole.EMBED:
        fallbacks = [("ai/all-minilm-l6-v2-vllm", 0.1), ("ai/mxbai-embed-large", 0.8)]
        for name, ram in fallbacks:
            if name != model.docker_name:
                return RecommendedModel(
                    name="Fallback Embedding", docker_name=name, ram_gb=ram,
                    role=ModelRole.EMBED, roles=["embed"], context_length=8192,
                    description="Alternative embedding model"
                )
    
    elif role == ModelRole.AUTOCOMPLETE:
        fallbacks = [("ai/llama3.2", 1.8), ("ai/granite-4.0-h-tiny", 1.0)]
        for name, ram in fallbacks:
            if name != model.docker_name:
                return RecommendedModel(
                    name="Fallback Autocomplete", docker_name=name, ram_gb=ram,
                    role=ModelRole.AUTOCOMPLETE, roles=["autocomplete"], context_length=131072,
                    description="Alternative autocomplete model"
                )
    
    elif role == ModelRole.CHAT:
        primary_options = PRIMARY_MODELS.get(tier, [])
        for option in primary_options:
            if option.docker_name != model.docker_name:
                return option
        fallbacks = [("ai/granite-4.0-h-nano", 4.0), ("ai/llama3.2", 1.8)]
        for name, ram in fallbacks:
            if name != model.docker_name:
                return RecommendedModel(
                    name="Fallback Coding Model", docker_name=name, ram_gb=ram,
                    role=ModelRole.CHAT, roles=["chat", "edit"], context_length=131072,
                    description="Alternative coding model"
                )
    
    return None


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
                        elif "pulling" in clean_line.lower():
                            print(f"\r    Pulling...", end="", flush=True)
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
        error_type = classify_pull_error(error_msg)
        
        if error_type in [PullErrorType.MODEL_NOT_FOUND, PullErrorType.DISK,
                          PullErrorType.DMR_NOT_ENABLED, PullErrorType.DOCKER_NOT_RUNNING]:
            if show_progress:
                ui.print_warning(f"Not retrying - error type: {error_type}")
            break
        
        if show_progress and attempt < MAX_PULL_RETRIES - 1:
            ui.print_warning(f"Attempt {attempt + 1} failed: {error_msg[:100]}")
    
    return False, last_error


def pull_model_with_verification(
    model: RecommendedModel, tier: hardware.HardwareTier, show_progress: bool = True
) -> PullResult:
    """Pull a model with immediate verification and fallback."""
    result = PullResult(model=model, success=False)
    
    if is_restricted_model_name(model.docker_name):
        result.error_message = f"Model {model.docker_name} is restricted"
        if show_progress:
            ui.print_error(f"Blocked: {model.name} ({model.docker_name})")
            ui.print_error("  Reason: Chinese-based LLMs are not allowed")
        return result
    
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
    
    primary_error = error_msg
    
    fallback = get_fallback_model(model, tier)
    if fallback:
        if is_restricted_model_name(fallback.docker_name):
            if show_progress:
                ui.print_warning(f"Fallback {fallback.docker_name} is also restricted")
            result.error_message = "Primary and fallback both restricted"
            return result
        
        if show_progress:
            ui.print_info(f"Trying fallback: {fallback.docker_name}")
        
        fallback_success, _ = _pull_model(fallback.docker_name, show_progress)
        
        if fallback_success:
            time.sleep(VERIFICATION_DELAY)
            if verify_model_exists(fallback.docker_name):
                result.success = True
                result.verified = True
                result.used_fallback = True
                result.fallback_model = fallback
                if show_progress:
                    ui.print_success(f"Fallback {fallback.name} downloaded and verified")
                return result
    
    result.error_message = primary_error or "Model pull and fallback both failed"
    return result


def pull_models_with_tracking(
    models: List[RecommendedModel], hw_info: hardware.HardwareInfo, show_progress: bool = True
) -> SetupResult:
    """Pull multiple models with verification and tracking."""
    result = SetupResult()
    tier = hw_info.tier
    
    if show_progress:
        ui.print_header("📥 Downloading Models")
        total_gb = sum(m.ram_gb for m in models) * 0.5
        ui.print_info(f"Estimated total download: ~{total_gb:.1f}GB")
        print()
    
    for i, model in enumerate(models, 1):
        if show_progress:
            ui.print_step(i, len(models), f"Pulling {model.name}")
            print()
        
        pull_result = pull_model_with_verification(model, tier, show_progress)
        
        if pull_result.success:
            if pull_result.used_fallback and pull_result.fallback_model:
                result.successful_models.append(pull_result.fallback_model)
                result.warnings.append(f"Used fallback for {model.name}: {pull_result.fallback_model.docker_name}")
            else:
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
    
    if result.complete_failure:
        most_common_error = ""
        if result.failed_models:
            _, first_error = result.failed_models[0]
            most_common_error = first_error
        
        error_type = classify_pull_error(most_common_error)
        print(ui.colorize(f"Error Type: {error_type}", ui.Colors.YELLOW + ui.Colors.BOLD))
        print()
        
        for step in get_troubleshooting_steps(error_type):
            print(f"  {step}")
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
    
    # Check for restricted models
    restricted_models = [m for m in models if is_restricted_model_name(m.docker_name)]
    if restricted_models:
        for model in restricted_models:
            warnings.append(f"Model {model.docker_name} is from a restricted country")
        return False, warnings
    
    # Check Docker Model Runner
    code, _, stderr = utils.run_command(["docker", "model", "list"], timeout=10, clean_env=True)
    if code != 0:
        error_type = classify_pull_error(stderr)
        if error_type == PullErrorType.DMR_NOT_ENABLED:
            warnings.append("Docker Model Runner is not enabled")
        elif error_type == PullErrorType.DOCKER_NOT_RUNNING:
            warnings.append("Docker is not running")
        else:
            warnings.append("Docker Model Runner is not available")
        return False, warnings
    
    # Check RAM
    from .model_selector import get_usable_ram
    usable_ram = get_usable_ram(hw_info)
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
