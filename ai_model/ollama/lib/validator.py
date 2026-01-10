"""
Model Validator and Fallback Handler.

Handles:
- Immediate verification after each model pull
- Fallback to hardcoded catalog when Ollama API is unreachable
- Partial setup tracking when some models fail
- Graceful degradation with actionable next steps
"""

import json
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


# Ollama API configuration
OLLAMA_API_BASE = "http://localhost:11434"

# Timeout and delay constants (in seconds)
API_TIMEOUT = 5  # Timeout for API health checks
API_TIMEOUT_LONG = 10  # Timeout for longer API operations
OLLAMA_LIST_TIMEOUT = 10  # Timeout for 'ollama list' command
MODEL_PULL_TIMEOUT = 3600  # Timeout for model pull (1 hour)
PROCESS_KILL_TIMEOUT = 5  # Timeout for process termination
VERIFICATION_DELAY = 1  # Delay before verifying model after pull


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
    code, stdout, _ = utils.run_command(["ollama", "list"], timeout=OLLAMA_LIST_TIMEOUT)
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


def get_fallback_model(model: RecommendedModel, tier: hardware.HardwareTier) -> Optional[RecommendedModel]:
    """
    Get a fallback model for a failed pull.
    
    Uses the hardcoded catalog to find alternatives based on role and tier.
    """
    role = model.role
    
    # Try the model's built-in fallback first
    if model.fallback_name:
        return RecommendedModel(
            name=f"{model.name} (fallback)",
            ollama_name=model.fallback_name,
            ram_gb=model.ram_gb,
            role=model.role,
            roles=model.roles,
            description=f"Fallback for {model.name}"
        )
    
    # Find alternative from catalog
    if role == ModelRole.EMBED:
        # Embedding fallbacks
        fallbacks = [
            ("mxbai-embed-large:latest", 0.7),
            ("all-minilm:latest", 0.1),
        ]
        for name, ram in fallbacks:
            if name != model.ollama_name:
                return RecommendedModel(
                    name="Fallback Embedding",
                    ollama_name=name,
                    ram_gb=ram,
                    role=ModelRole.EMBED,
                    roles=["embed"],
                    description="Alternative embedding model"
                )
    
    elif role == ModelRole.AUTOCOMPLETE:
        # Autocomplete fallbacks
        fallbacks = [
            ("starcoder2:3b", 2.0),
            ("codegemma:2b", 1.5),
        ]
        for name, ram in fallbacks:
            if name != model.ollama_name:
                return RecommendedModel(
                    name="Fallback Autocomplete",
                    ollama_name=name,
                    ram_gb=ram,
                    role=ModelRole.AUTOCOMPLETE,
                    roles=["autocomplete"],
                    description="Alternative autocomplete model"
                )
    
    elif role == ModelRole.CHAT:
        # Primary model fallbacks - try smaller models
        primary_options = PRIMARY_MODELS.get(tier, [])
        for option in primary_options:
            if option.ollama_name != model.ollama_name:
                return option
        
        # If no tier-specific fallback, try general fallbacks
        fallbacks = [
            ("granite-code:8b", 5.0),
            ("granite-code:3b", 2.0),
            ("codellama:7b", 4.0),
        ]
        for name, ram in fallbacks:
            if name != model.ollama_name:
                return RecommendedModel(
                    name="Fallback Coding Model",
                    ollama_name=name,
                    ram_gb=ram,
                    role=ModelRole.CHAT,
                    roles=["chat", "edit"],
                    description="Alternative coding model"
                )
    
    return None


def pull_model_with_verification(
    model: RecommendedModel,
    tier: hardware.HardwareTier,
    show_progress: bool = True
) -> PullResult:
    """
    Pull a model with immediate verification and fallback.
    
    Strategy:
    1. Try to pull the model
    2. Verify it exists in Ollama
    3. If verification fails, try the fallback
    4. Track success/failure for reporting
    """
    result = PullResult(model=model, success=False)
    
    if show_progress:
        ui.print_info(f"Pulling {model.name} ({model.ollama_name})...")
    
    # Try to pull the model
    success = _pull_model(model.ollama_name, show_progress)
    
    if success:
        # Verify the model exists
        time.sleep(VERIFICATION_DELAY)  # Brief pause for Ollama to update
        if verify_model_exists(model.ollama_name):
            result.success = True
            result.verified = True
            if show_progress:
                ui.print_success(f"{model.name} downloaded and verified")
            return result
        else:
            if show_progress:
                ui.print_warning(f"{model.name} pull succeeded but verification failed")
    else:
        if show_progress:
            ui.print_warning(f"Failed to pull {model.name}")
    
    # Try fallback
    fallback = get_fallback_model(model, tier)
    if fallback:
        if show_progress:
            ui.print_info(f"Trying fallback: {fallback.ollama_name}")
        
        fallback_success = _pull_model(fallback.ollama_name, show_progress)
        
        if fallback_success:
            time.sleep(VERIFICATION_DELAY)
            if verify_model_exists(fallback.ollama_name):
                result.success = True
                result.verified = True
                result.used_fallback = True
                result.fallback_model = fallback
                if show_progress:
                    ui.print_success(f"Fallback {fallback.name} downloaded and verified")
                return result
    
    # All attempts failed
    result.error_message = "Model pull and fallback both failed"
    return result


def _pull_model(model_name: str, show_progress: bool = True) -> bool:
    """
    Execute ollama pull command.
    
    Returns True if the command succeeded.
    Ensures proper process cleanup on timeout or error.
    """
    process = None
    try:
        if show_progress:
            # Show live progress
            process = subprocess.Popen(
                ["ollama", "pull", model_name],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )
            
            if process.stdout:
                for line in process.stdout:
                    line = line.strip()
                    if line:
                        # Show progress updates
                        if "pulling" in line.lower() or "%" in line:
                            print(f"    {line}", end="\r")
                        elif "success" in line.lower() or "done" in line.lower():
                            print()
                            ui.print_success(f"    {line}")
            
            process.wait(timeout=MODEL_PULL_TIMEOUT)
            return process.returncode == 0
        else:
            # Silent pull
            code, _, _ = utils.run_command(
                ["ollama", "pull", model_name],
                timeout=MODEL_PULL_TIMEOUT
            )
            return code == 0
    
    except subprocess.TimeoutExpired:
        # Clean up the process on timeout
        if process:
            process.kill()
            try:
                process.wait(timeout=PROCESS_KILL_TIMEOUT)
            except subprocess.TimeoutExpired:
                pass
        return False
    except (OSError, IOError, FileNotFoundError, subprocess.SubprocessError):
        # Process creation or execution failed
        return False
    finally:
        # Ensure process is cleaned up
        if process and process.poll() is None:
            process.kill()
            try:
                process.wait(timeout=PROCESS_KILL_TIMEOUT)
            except subprocess.TimeoutExpired:
                pass


def pull_models_with_tracking(
    models: List[RecommendedModel],
    hw_info: hardware.HardwareInfo,
    show_progress: bool = True
) -> SetupResult:
    """
    Pull multiple models with verification and tracking.
    
    Implements the reliable pulling strategy:
    1. Pull each model
    2. Verify after each pull
    3. Try fallback if verification fails
    4. Continue with remaining models on failure
    5. Report partial setup status
    """
    result = SetupResult()
    tier = hw_info.tier
    
    if show_progress:
        ui.print_header("📥 Downloading Models")
        total_gb = sum(m.ram_gb for m in models) * 0.5  # Rough download estimate
        ui.print_info(f"Estimated total download: ~{total_gb:.1f}GB")
        print()
    
    for i, model in enumerate(models, 1):
        if show_progress:
            ui.print_step(i, len(models), f"Pulling {model.name}")
            print()
        
        pull_result = pull_model_with_verification(model, tier, show_progress)
        
        if pull_result.success:
            # Add the actually installed model (might be fallback)
            if pull_result.used_fallback and pull_result.fallback_model:
                result.successful_models.append(pull_result.fallback_model)
                result.warnings.append(
                    f"Used fallback for {model.name}: {pull_result.fallback_model.ollama_name}"
                )
            else:
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
    
    # Show failed models
    for model, error in result.failed_models:
        ui.print_error(f"{model.ollama_name} - Failed to download")
    
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


def validate_pre_install(
    models: List[RecommendedModel],
    hw_info: hardware.HardwareInfo
) -> Tuple[bool, List[str]]:
    """
    Pre-installation validation.
    
    Checks:
    - Ollama is installed and running
    - Models fit in available RAM
    - Network connectivity
    
    Returns: (is_valid, list_of_warnings)
    """
    warnings = []
    
    # Check Ollama
    if not is_ollama_api_available():
        warnings.append("Ollama API is not available. Please ensure Ollama is running.")
    
    # Check RAM
    from .model_selector import get_usable_ram
    usable_ram = get_usable_ram(hw_info)
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
    
    # Check network
    try:
        req = urllib.request.Request("https://ollama.com")
        req.add_header("User-Agent", "Ollama-LLM-Setup/1.0")
        with urllib.request.urlopen(req, timeout=API_TIMEOUT_LONG, context=get_unverified_ssl_context()) as response:
            pass  # Just checking connectivity
    except (urllib.error.URLError, urllib.error.HTTPError, OSError):
        warnings.append(
            "Cannot reach ollama.com. Model downloads may fail. "
            "Proceed if models are already cached."
        )
    
    is_valid = not any("API is not available" in w for w in warnings)
    
    return is_valid, warnings
