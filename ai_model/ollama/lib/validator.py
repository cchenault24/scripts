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
        # Embedding fallbacks - using widely available models
        fallbacks = [
            ("all-minilm", 0.1),  # Very small and widely available
            ("mxbai-embed-large", 0.7),
        ]
        for name, ram in fallbacks:
            if name != model.ollama_name and name not in model.ollama_name:
                return RecommendedModel(
                    name="Fallback Embedding",
                    ollama_name=name,
                    ram_gb=ram,
                    role=ModelRole.EMBED,
                    roles=["embed"],
                    description="Alternative embedding model"
                )
    
    elif role == ModelRole.AUTOCOMPLETE:
        # Autocomplete fallbacks - using reliable models
        fallbacks = [
            ("codegemma:2b", 1.5),  # Very reliable Google model
            ("starcoder2:3b", 2.0),
        ]
        for name, ram in fallbacks:
            if name != model.ollama_name and name not in model.ollama_name:
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
        
        # If no tier-specific fallback, try general fallbacks (reliable models)
        fallbacks = [
            ("codellama:7b", 4.0),  # Meta's CodeLlama - very reliable
            ("qwen2.5-coder:3b", 2.0),  # Smaller Qwen coder
            ("codegemma:7b", 4.5),  # Google's CodeGemma
        ]
        for name, ram in fallbacks:
            if name != model.ollama_name and name not in model.ollama_name:
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
    success, error_msg = _pull_model(model.ollama_name, show_progress)
    
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
            error_msg = "Pull appeared to succeed but model not found in Ollama"
    else:
        if show_progress:
            ui.print_error(f"Failed to pull {model.name}")
            if error_msg:
                # Show truncated error for readability
                display_error = error_msg[:300] if len(error_msg) > 300 else error_msg
                ui.print_error(f"  Error: {display_error}")
    
    # Store the error for reporting
    primary_error = error_msg
    
    # Try fallback
    fallback = get_fallback_model(model, tier)
    if fallback:
        if show_progress:
            ui.print_info(f"Trying fallback: {fallback.ollama_name}")
        
        fallback_success, fallback_error = _pull_model(fallback.ollama_name, show_progress)
        
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
            else:
                if show_progress:
                    ui.print_warning(f"Fallback {fallback.name} pull succeeded but verification failed")
        else:
            if show_progress:
                ui.print_error(f"Fallback {fallback.ollama_name} also failed")
                if fallback_error:
                    ui.print_error(f"  Error: {fallback_error[:200]}")
    
    # All attempts failed - include detailed error
    result.error_message = primary_error or "Model pull and fallback both failed"
    return result


def _pull_model(model_name: str, show_progress: bool = True) -> Tuple[bool, str]:
    """
    Execute ollama pull command.
    
    Returns:
        Tuple of (success, error_message):
        - success: True if the command succeeded
        - error_message: Error details if failed, empty string if successful
    
    Ensures proper process cleanup on timeout or error.
    """
    process = None
    output_lines: List[str] = []
    
    try:
        if show_progress:
            # Show live progress with separate stdout/stderr for better error capture
            process = subprocess.Popen(
                ["ollama", "pull", model_name],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1
            )
            
            # Read stdout for progress
            if process.stdout:
                for line in process.stdout:
                    line = line.strip()
                    if line:
                        output_lines.append(line)
                        # Show progress updates
                        if "pulling" in line.lower() or "%" in line:
                            print(f"    {line}", end="\r")
                        elif "success" in line.lower() or "done" in line.lower():
                            print()
                            ui.print_success(f"    {line}")
                        elif "error" in line.lower():
                            print()
                            ui.print_error(f"    {line}")
            
            # Read stderr for errors
            stderr_output = ""
            if process.stderr:
                stderr_output = process.stderr.read()
                if stderr_output:
                    output_lines.append(stderr_output)
            
            process.wait(timeout=MODEL_PULL_TIMEOUT)
            
            if process.returncode == 0:
                return True, ""
            else:
                # Collect error info
                error_msg = stderr_output.strip() if stderr_output else ""
                if not error_msg and output_lines:
                    # Look for error in output
                    for line in output_lines:
                        if "error" in line.lower() or "failed" in line.lower():
                            error_msg = line
                            break
                return False, error_msg or "Unknown error during pull"
        else:
            # Silent pull - capture output
            code, stdout, stderr = utils.run_command(
                ["ollama", "pull", model_name],
                timeout=MODEL_PULL_TIMEOUT
            )
            if code == 0:
                return True, ""
            else:
                error_msg = stderr.strip() if stderr else stdout.strip()
                return False, error_msg or "Unknown error during pull"
    
    except subprocess.TimeoutExpired:
        # Clean up the process on timeout
        if process:
            process.kill()
            try:
                process.wait(timeout=PROCESS_KILL_TIMEOUT)
            except subprocess.TimeoutExpired:
                pass
        return False, f"Timeout after {MODEL_PULL_TIMEOUT}s - model download may be stuck"
    except FileNotFoundError:
        return False, "Ollama command not found - is Ollama installed?"
    except (OSError, IOError, subprocess.SubprocessError) as e:
        return False, f"Process error: {type(e).__name__}: {e}"
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
    
    # If complete failure, provide diagnostic guidance
    if result.complete_failure:
        print(ui.colorize("Troubleshooting:", ui.Colors.YELLOW + ui.Colors.BOLD))
        print("  1. Check if Ollama is running: ollama list")
        print("  2. Test network: ollama search granite")
        print("  3. Try pulling manually: ollama pull <model-name>")
        print("  4. If on corporate network, check proxy/SSL settings")
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
    code, stdout, stderr = utils.run_command(["ollama", "search", "granite"], timeout=15)
    if code == 0 and stdout:
        details["search_works"] = True
        ui.print_success("  Ollama search is working")
    else:
        # Try an alternative test - list existing models
        code2, stdout2, stderr2 = utils.run_command(["ollama", "list"], timeout=10)
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
    models: List[RecommendedModel],
    hw_info: hardware.HardwareInfo
) -> Tuple[bool, List[str]]:
    """
    Pre-installation validation.
    
    Checks:
    - Ollama is installed and running
    - Models fit in available RAM
    - Network connectivity (with detailed diagnostics)
    
    Returns: (is_valid, list_of_warnings)
    """
    warnings = []
    
    # Check Ollama API
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
    
    is_valid = not any("API is not available" in w for w in warnings)
    
    return is_valid, warnings
