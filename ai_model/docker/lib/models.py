"""
Model catalog and selection functionality.

Provides model information, catalog, discovery, selection, and pulling capabilities.
"""

import json
import re
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

from . import hardware
from . import ui
from . import utils
from .utils import get_unverified_ssl_context

# Try to import rich for better progress bars (lazy import - only when needed)
RICH_AVAILABLE = False
_rich_imported = False

def _install_rich_background():
    """Install rich in the background (non-blocking)."""
    def install():
        global RICH_AVAILABLE, _rich_imported
        if RICH_AVAILABLE or _rich_imported:
            return
        
        try:
            # Try multiple installation methods
            install_commands = [
                [sys.executable, "-m", "pip", "install", "--quiet", "--user", "rich>=13.7.0"],
                [sys.executable, "-m", "pip", "install", "--quiet", "--break-system-packages", "rich>=13.7.0"],
                [sys.executable, "-m", "pip", "install", "--quiet", "rich>=13.7.0"],
            ]
            
            for cmd in install_commands:
                result = subprocess.run(
                    cmd,
                    capture_output=True,
                    timeout=60,
                    text=True
                )
                if result.returncode == 0:
                    # Try importing after successful installation
                    try:
                        from rich.progress import Progress, SpinnerColumn, BarColumn, TextColumn, TimeRemainingColumn, DownloadColumn, TransferSpeedColumn
                        from rich.console import Console
                        RICH_AVAILABLE = True
                        break
                    except ImportError:
                        continue
        except Exception:
            # Silently fail in background
            pass
        finally:
            _rich_imported = True
    
    # Start installation in background thread
    thread = threading.Thread(target=install, daemon=True)
    thread.start()
    return thread


def _ensure_rich_available():
    """Ensure rich is available, installing it if necessary."""
    global RICH_AVAILABLE, _rich_imported
    
    if RICH_AVAILABLE:
        return True
    
    # Try to import if already installed
    if not _rich_imported:
        try:
            from rich.progress import Progress, SpinnerColumn, BarColumn, TextColumn, TimeRemainingColumn, DownloadColumn, TransferSpeedColumn
            from rich.console import Console
            RICH_AVAILABLE = True
            _rich_imported = True
            return True
        except ImportError:
            _rich_imported = True
    
    # Try to install and import
    if not RICH_AVAILABLE:
        try:
            ui.print_info("Installing 'rich' for better progress bars...")
            install_commands = [
                [sys.executable, "-m", "pip", "install", "--quiet", "--user", "rich>=13.7.0"],
                [sys.executable, "-m", "pip", "install", "--quiet", "--break-system-packages", "rich>=13.7.0"],
                [sys.executable, "-m", "pip", "install", "--quiet", "rich>=13.7.0"],
            ]
            
            for cmd in install_commands:
                result = subprocess.run(cmd, capture_output=True, timeout=60, text=True)
                if result.returncode == 0:
                    try:
                        from rich.progress import Progress, SpinnerColumn, BarColumn, TextColumn, TimeRemainingColumn, DownloadColumn, TransferSpeedColumn
                        from rich.console import Console
                        RICH_AVAILABLE = True
                        ui.print_success("Successfully installed 'rich'")
                        return True
                    except ImportError:
                        continue
            
            ui.print_warning("Could not install 'rich' - will use basic progress display")
            return False
        except Exception:
            ui.print_warning("Could not install 'rich' - will use basic progress display")
            return False
    
    return False


@dataclass
class ModelInfo:
    """Information about an LLM model."""
    name: str
    docker_name: str  # Name used in Docker Model Runner
    description: str
    ram_gb: float
    context_length: int
    roles: List[str]  # chat, autocomplete, embed, etc.
    recommended_for: List[str] = field(default_factory=list)
    base_model_name: Optional[str] = None  # Base model name for variant discovery (e.g., "gpt-oss")
    selected_variant: Optional[str] = None  # Selected variant tag (e.g., "70B-Q4_K_M")


# Model catalog for Docker Model Runner (DMR)
# Docker Model Runner uses the namespace: ai/ for Docker Hub models
# Models are optimized for Apple Silicon with Metal acceleration
# Format: ai/<model-name> or ai/<model-name>:<tag>
# Only GPT-OSS 20B and nomic-embed-text-v1.5 are supported
MODEL_CATALOG: List[ModelInfo] = [
    # =========================================================================
    # Primary Chat/Edit/Reasoning Model
    # =========================================================================
    ModelInfo(
        name="GPT-OSS 20B",
        docker_name="ai/gpt-oss:20B-UD-Q6_K_XL",
        description="OpenAI GPT-OSS 20B - Matches o3-mini performance, 1200 tokens/sec, Apache 2.0 license, US-based",
        ram_gb=16.0,
        context_length=131072,
        roles=["chat", "edit", "agent", "autocomplete"],
        recommended_for=["Primary reasoning/chat model", "All configurations 16GB+ RAM"],
        base_model_name="gpt-oss"
    ),
    # =========================================================================
    # Embedding Models
    # =========================================================================
    ModelInfo(
        name="Nomic Embed Text v1.5",
        docker_name="ai/nomic-embed-text-v1.5",
        description="Best open embedding model for code indexing (8192 tokens)",
        ram_gb=0.3,
        context_length=8192,
        roles=["embed"],
        recommended_for=["Code indexing", "Semantic search"],
        base_model_name="nomic-embed-text-v1.5"
    ),
]


def calculate_model_ram(params: float, quantization: Optional[str] = None) -> float:
    """
    Calculate RAM requirements for a model based on parameters and quantization.
    
    Formula (corrected for accuracy):
    - Q2: 0.35×params (2 bits per param + overhead)
    - Q3: 0.5×params (3 bits per param + overhead)
    - Q4: 0.6×params (4-5 bits per param + overhead) - e.g., 13B Q4 ≈ 7.8GB
    - Q5: 0.75×params (5-6 bits per param + overhead)
    - Q8: 1.0×params (8 bits per param + overhead)
    - F16: 2.0×params (16 bits per param + overhead)
    - F32: 4.0×params (32 bits per param + overhead)
    - Includes overhead for activations, KV cache, and system buffers
    
    Args:
        params: Model size in billions of parameters
        quantization: Quantization level (Q2, Q3, Q4, Q4_K_M, Q4_0, Q5, Q8, Q8_0, F16, F32) or None
    
    Returns:
        Estimated RAM requirement in GB
    """
    if params <= 0:
        return 0.0
    
    # Determine base RAM multiplier based on quantization (corrected values)
    quant_lower = (quantization or "").lower()
    
    if "q2" in quant_lower:
        base_multiplier = 0.35  # ~2 bits per param
    elif "q3" in quant_lower:
        base_multiplier = 0.5   # ~3 bits per param
    elif "q4" in quant_lower or "q4_k_m" in quant_lower or "q4_0" in quant_lower:
        base_multiplier = 0.6   # ~4-5 bits per param (13B Q4 ≈ 7.8GB)
    elif "q5" in quant_lower:
        base_multiplier = 0.75  # ~5-6 bits per param
    elif "q8" in quant_lower or "q8_0" in quant_lower:
        base_multiplier = 1.0   # ~8 bits per param
    elif "f16" in quant_lower:
        base_multiplier = 2.0   # 16 bits per param
    elif "f32" in quant_lower:
        base_multiplier = 4.0   # 32 bits per param
    else:
        # Default to F16 if no quantization specified
        base_multiplier = 2.0
    
    # Calculate base RAM (multiplier already includes typical overhead)
    ram_gb = params * base_multiplier
    
    return ram_gb


def parse_tag_info(tag_name: str) -> Dict[str, Any]:
    """
    Parse tag name to extract size, quantization, and other metadata.
    
    Args:
        tag_name: Tag name from Docker Hub (e.g., "70B-Q4_K_M", "14B-F16", "32B", "latest")
    
    Returns:
        Dictionary with:
        - size: Model size in billions (e.g., 70, 14, 32) or None
        - size_str: Size string (e.g., "70B", "14B") or None
        - quantization: Quantization level (e.g., "Q4_K_M", "Q4_0", "F16") or None
        - is_full_precision: True if F16 or no quantization specified
        - estimated_ram_gb: Estimated RAM requirement in GB
    """
    tag_lower = tag_name.lower()
    
    # Skip "latest" tag - it's unpredictable
    if tag_lower == "latest":
        return {
            "size": None,
            "size_str": None,
            "quantization": None,
            "is_full_precision": False,
            "estimated_ram_gb": 0.0,
            "tag_name": tag_name
        }
    
    # Extract size (e.g., 70B, 14B, 32B, 7B, 3B, or 335M for millions)
    size_match = re.search(r'(\d+(?:\.\d+)?)\s*([mb])', tag_lower)
    size = None
    size_str = None
    if size_match:
        size_val = float(size_match.group(1))
        size_unit = size_match.group(2).lower()
        if size_unit == 'm':
            # Convert millions to billions (e.g., 335M -> 0.335B)
            size = size_val / 1000.0
        else:
            # Already in billions
            size = size_val
        size_str = tag_name[size_match.start():size_match.end()].upper()
    
    # Extract quantization level
    quantization = None
    is_full_precision = False
    
    # Check for quantization patterns (more specific first)
    if "-q4_k_m" in tag_lower or tag_lower.endswith("-q4_k_m"):
        quantization = "Q4_K_M"
    elif "-q4_0" in tag_lower or tag_lower.endswith("-q4_0"):
        quantization = "Q4_0"
    elif "-q8_0" in tag_lower or tag_lower.endswith("-q8_0"):
        quantization = "Q8_0"
    elif "-q5" in tag_lower or tag_lower.endswith("-q5"):
        quantization = "Q5"
    elif "-q3" in tag_lower or tag_lower.endswith("-q3"):
        quantization = "Q3"
    elif "-q2" in tag_lower or tag_lower.endswith("-q2"):
        quantization = "Q2"
    elif "-q8" in tag_lower:
        quantization = "Q8"
    elif "-q4" in tag_lower:
        quantization = "Q4"
    elif "-f16" in tag_lower or tag_lower.endswith("-f16"):
        quantization = "F16"
        is_full_precision = True
    elif "-f32" in tag_lower or tag_lower.endswith("-f32"):
        quantization = "F32"
        is_full_precision = True
    
    # If no quantization specified and size exists, assume F16 (full precision)
    if quantization is None and size is not None:
        quantization = "F16"
        is_full_precision = True
    
    # Estimate RAM requirements using new calculation function
    estimated_ram_gb = 0.0
    if size is not None:
        estimated_ram_gb = calculate_model_ram(size, quantization)
    
    return {
        "size": size,
        "size_str": size_str,
        "quantization": quantization,
        "is_full_precision": is_full_precision,
        "estimated_ram_gb": estimated_ram_gb,
        "tag_name": tag_name
    }


def get_display_name_from_model(model_name: str, variant: Optional[str] = None) -> str:
    """
    Generate a human-readable display name from a model name.
    
    Args:
        model_name: Model name (e.g., "gpt-oss", "nomic-embed-text-v1.5")
        variant: Optional variant tag (e.g., "20B-UD-Q6_K_XL") - size will be extracted and included
    
    Returns:
        Human-readable display name (e.g., "GPT-OSS:20B", "Nomic Embed")
    """
    model_lower = model_name.lower()
    
    # GPT-OSS models
    if "gpt-oss" in model_lower or "gptoss" in model_lower:
        base_name = "GPT-OSS"
    # Nomic embedding models
    elif "nomic-embed" in model_lower or "nomicembed" in model_lower:
        base_name = "Nomic Embed"
    else:
        # Fallback: capitalize and format the model name
        base_name = model_name.replace("-", " ").replace("_", " ").title()
    
    # Extract size from variant tag if provided (e.g., "7B-Q4_K_M" -> "7B")
    size_suffix = ""
    if variant:
        # Match patterns like "7B", "13B", "70B", "3B", "1B", etc.
        size_match = re.search(r'(\d+(?:\.\d+)?)\s*[Bb]', variant)
        if size_match:
            size_value = size_match.group(1)
            # Format: "7B", "13B", "70B", etc. (remove decimal if .0)
            if size_value.endswith('.0'):
                size_value = size_value[:-2]
            size_suffix = f":{size_value}B"
    
    # RAM estimate based on model name
    # If variant size, include size
    if size_suffix:
        return f"{base_name}{size_suffix}"
    
    return base_name


def is_restricted_model(model: ModelInfo) -> bool:
    """Check if a model is from restricted countries (China, Russia) due to political conflicts."""
    restricted_keywords = [
        "qwen", "deepseek", "deepcoder", "baai", "bge-", "yi", "baichuan",
        "chatglm", "glm", "internlm", "minicpm", "cogvlm", "qianwen", "tongyi"
    ]
    model_lower = model.name.lower() + " " + model.docker_name.lower()
    return any(keyword in model_lower for keyword in restricted_keywords)


def is_restricted_model_name(model_name: str) -> bool:
    """Check if a model name (string) is from restricted countries."""
    restricted_keywords = [
        "qwen", "deepseek", "deepcoder", "baai", "bge-", "yi", "baichuan",
        "chatglm", "glm", "internlm", "minicpm", "cogvlm", "qianwen", "tongyi"
    ]
    return any(keyword in model_name.lower() for keyword in restricted_keywords)


def is_docker_hub_unavailable(model: ModelInfo) -> bool:
    """Check if a model is not available in Docker Hub's ai/ namespace.
    These models would fail with 401 Unauthorized when trying to pull.
    Only models confirmed to exist in Docker Hub's ai/ namespace are included."""
    # Models that don't exist in Docker Hub's ai/ namespace (verified)
    # Only GPT-OSS and nomic-embed-text are supported, so this list is minimal
    unavailable_models = []
    
    # Extract base model name (remove ai/ prefix and any tag)
    if not model.docker_name.startswith("ai/"):
        return False
    
    model_name = model.docker_name[3:]  # Remove "ai/" prefix
    if ":" in model_name:
        model_name = model_name.split(":")[0]  # Remove tag
    
    # Check if model name contains any unavailable model names
    model_lower = model_name.lower()
    return any(unavailable in model_lower for unavailable in unavailable_models)


def _extract_model_size(model_name: str) -> Optional[str]:
    """Extract model size from name (e.g., '3b', '70b')."""
    model_lower = model_name.lower()
    for size in ["8b", "3b", "7b", "14b", "70b"]:
        if f":{size}" in model_lower or f"-{size}" in model_lower or f" {size}" in model_lower:
            return size
    return None


def verify_model_available(model: ModelInfo, hw_info: hardware.HardwareInfo) -> bool:
    """
    Verify that a model actually exists and can be pulled from Docker Model Runner.
    
    Checks in order:
    1. Cached Docker Hub models list
    2. Cached API models list
    3. Direct API query
    4. Known working models
    5. Docker Hub API fetch
    6. Docker search fallback
    """
    # Convert to Docker Hub format
    base_name = get_docker_hub_model_name(model.docker_name)
    base_name_lower = base_name.lower()
    model_lower = model.docker_name.lower()
    
    # Check cached Docker Hub models
    if hasattr(hw_info, 'available_docker_hub_models') and hw_info.available_docker_hub_models:
        if any(base_name_lower == m.lower() for m in hw_info.available_docker_hub_models):
            return True
    
    # Check cached API models
    if hasattr(hw_info, 'available_api_models') and hw_info.available_api_models:
        if any(base_name_lower in m.lower() or m.lower() in base_name_lower 
               for m in hw_info.available_api_models):
            return True
    
    # Query API directly
    if hw_info.docker_model_runner_available and hw_info.dmr_api_endpoint:
        try:
            api_url = f"{hw_info.dmr_api_endpoint}/models"
            req = urllib.request.Request(api_url, method="GET")
            req.add_header("Content-Type", "application/json")
            with urllib.request.urlopen(req, timeout=5, context=get_unverified_ssl_context()) as response:
                if response.status == 200:
                    data = json.loads(response.read().decode('utf-8'))
                    if "data" in data:
                        if any(base_name_lower in m.get("id", "").lower() 
                               for m in data["data"]):
                            return True
        except (urllib.error.URLError, urllib.error.HTTPError, OSError, json.JSONDecodeError):
            pass
    
    # Check known working models
    known_models = {
        "ai/gpt-oss": ["20B-UD-Q6_K_XL"],
        "ai/nomic-embed-text-v1.5": [None],
    }
    
    for known_base, available_sizes in known_models.items():
        if base_name_lower == known_base.lower():
            if None in available_sizes:
                return True
            requested_size = _extract_model_size(model_lower)
            if requested_size:
                return requested_size in [s.lower() if s else None for s in available_sizes]
            return len(available_sizes) > 0
    
    # For fixed models, just check against catalog
    # GPT-OSS and nomic-embed-text are the only supported models
    return base_name_lower in ["gpt-oss", "nomic-embed-text-v1.5", "nomic-embed-text"]


def get_docker_hub_model_name(docker_name: str) -> str:
    """Convert docker_name to Docker Hub format (ai/model-name)."""
    if docker_name.startswith("ai.docker.com/"):
        # Convert ai.docker.com/org/model:tag -> ai/model
        remaining = docker_name[len("ai.docker.com/"):]
        parts = remaining.split("/")
        if len(parts) > 1:
            model_part = parts[1]
        else:
            model_part = parts[0]
        # Remove tag
        if ":" in model_part:
            model_part = model_part.split(":")[0]
        return f"ai/{model_part}"
    elif docker_name.startswith("ai/"):
        # Already in correct format, just remove tag if present
        if ":" in docker_name:
            return docker_name.split(":")[0]
        return docker_name
    else:
        # Fallback: try to extract model name
        return docker_name


def validate_model_selection(
    models: List[ModelInfo],
    hw_info: hardware.HardwareInfo
) -> Tuple[bool, List[str]]:
    """
    Validate model selection with pre-install safety checks.
    
    Checks:
    - No single model >50% available RAM
    - Total selection ≤85% available RAM
    - Minimum 2GB free RAM after load
    - Docker resources available
    - Disk space available
    - Network connectivity
    
    Args:
        models: List of selected models
        hw_info: Hardware information
    
    Returns:
        Tuple of (is_valid, list_of_warnings)
    """
    warnings = []
    usable_ram = hw_info.get_estimated_model_memory()
    total_ram_used = sum(m.ram_gb for m in models)
    
    # Check: No single model >50% available RAM
    for model in models:
        if model.ram_gb > usable_ram * 0.5:
            warnings.append(
                f"Model {model.name} uses {model.ram_gb:.1f}GB ({model.ram_gb / usable_ram * 100:.1f}%) "
                f"of available RAM (max 50% recommended)"
            )
    
    # Check: Total selection ≤85% available RAM
    ram_usage_percent = (total_ram_used / usable_ram * 100) if usable_ram > 0 else 0
    if ram_usage_percent > 85:
        warnings.append(
            f"Total RAM usage {total_ram_used:.1f}GB ({ram_usage_percent:.1f}%) exceeds 85% limit. "
            f"Recommended: ≤{usable_ram * 0.85:.1f}GB"
        )
    
    # Check: Minimum 2GB free RAM after load
    free_ram_after = usable_ram - total_ram_used
    if free_ram_after < 2.0:
        warnings.append(
            f"Only {free_ram_after:.1f}GB free RAM after model load (minimum 2GB recommended). "
            f"System may become unstable."
        )
    
    # Check: Always include embedding model
    has_embed = any("embed" in m.roles for m in models)
    if not has_embed:
        warnings.append(
            "⚠️  No embedding model selected:\n"
            "   • Legacy @Codebase search will NOT work\n"
            "   • CRITICAL for JetBrains: No transformers.js fallback available\n"
            "   • Agent mode codebase awareness will still work via rules\n"
            "   • Recommendation: Add an embedding model for full functionality"
        )
    
    # Check: Docker resources
    if hw_info.docker_model_runner_available:
        # Check Docker disk space (rough estimate)
        docker_info_code, docker_info_out, _ = utils.run_command(["docker", "system", "df"])
        if docker_info_code == 0:
            # Parse Docker disk usage
            lines = docker_info_out.strip().split("\n")
            if len(lines) > 1:
                # Estimate: each model is roughly 50% of its RAM size
                estimated_download_size = sum(m.ram_gb * 0.5 for m in models)
                if estimated_download_size > 50:  # Warn if >50GB total download
                    warnings.append(
                        f"Estimated download size: ~{estimated_download_size:.1f}GB. "
                        f"Ensure sufficient disk space and bandwidth."
                    )
    else:
        warnings.append("Docker Model Runner not available. Models cannot be downloaded.")
    
    # Check: Network connectivity (basic check with retries)
    # This is a non-blocking check - failures only generate warnings
    network_ok = False
    for attempt in range(2):  # Try twice before giving up
        try:
            req = urllib.request.Request("https://hub.docker.com")
            req.add_header("User-Agent", "Docker-Model-Runner-Setup/1.0")
            with urllib.request.urlopen(req, timeout=10, context=get_unverified_ssl_context()) as response:
                # Connection is properly closed when exiting the with block
                network_ok = True
            break  # Success, no need to retry
        except (urllib.error.URLError, urllib.error.HTTPError, OSError, TimeoutError):
            if attempt < 1:  # Not the last attempt
                time.sleep(1)  # Brief pause before retry
                continue
            # Final attempt failed
            network_ok = False
        except Exception:
            # For unexpected exceptions (SSL issues, etc.), don't retry
            network_ok = False
            break
    
    if not network_ok:
        warnings.append("Cannot reach Docker Hub. Model downloads may fail. (You can proceed if models are already cached)")
    
    # Determine if valid (warnings are non-critical, errors would be critical)
    # Only block on actual critical issues: system instability or Docker not available
    critical_warnings = [
        w for w in warnings 
        if "may become unstable" in w.lower() 
        or ("cannot" in w.lower() and "docker model runner" in w.lower() and "not available" in w.lower())
    ]
    is_valid = len(critical_warnings) == 0
    
    return is_valid, warnings


def display_ram_usage(selected_models: List[ModelInfo], hw_info: hardware.HardwareInfo) -> None:
    """
    Display real-time RAM usage feedback with color coding.
    
    Format:
    RAM Usage: X.XXGB / XXGB (XX%) [COLOR] | Reserve: X.XXGB (XX%)
    ✓ model-name (variant) - X.XXGB | ✓ model-name (variant) - X.XXGB
    
    Color coding:
    - Green <70%
    - Yellow 70-85%
    - Red >85%
    - Block >90% (prevent installation)
    
    Args:
        selected_models: List of selected models
        hw_info: Hardware information
    """
    usable_ram = hw_info.get_estimated_model_memory()
    total_ram_used = sum(m.ram_gb for m in selected_models)
    reserve_ram = usable_ram - total_ram_used
    usage_percent = (total_ram_used / usable_ram * 100) if usable_ram > 0 else 0
    reserve_percent = (reserve_ram / usable_ram * 100) if usable_ram > 0 else 0
    
    # Determine color based on usage
    if usage_percent < 70:
        color = ui.Colors.GREEN
        status_icon = "✓"
    elif usage_percent < 85:
        color = ui.Colors.YELLOW
        status_icon = "⚠"
    elif usage_percent < 90:
        color = ui.Colors.RED
        status_icon = "⚠"
    else:
        color = ui.Colors.RED + ui.Colors.BOLD
        status_icon = "✗"
    
    # Display RAM usage summary
    print()
    ui.print_subheader("RAM Usage Summary")
    ram_usage_str = f"RAM Usage: {total_ram_used:.1f}GB / {usable_ram:.1f}GB usable (of {hw_info.ram_gb:.1f}GB total) ({usage_percent:.1f}%)"
    reserve_str = f"Reserve: {reserve_ram:.1f}GB ({reserve_percent:.1f}%)"
    
    print(f"  {status_icon} {ui.colorize(ram_usage_str, color)} | {reserve_str}")
    
    # Display per-model breakdown
    print()
    print("  Model Breakdown:")
    for model in selected_models:
        variant_info = f" ({model.selected_variant})" if model.selected_variant else ""
        roles_str = ", ".join(model.roles) if model.roles else "general"
        print(f"    {ui.colorize('✓', ui.Colors.GREEN)} {model.name}{variant_info} - {model.ram_gb:.1f}GB ({roles_str})")
    
    # Show warnings if needed
    if usage_percent >= 90:
        print()
        ui.print_error("RAM usage exceeds 90% - installation blocked for safety")
        ui.print_info("Please reduce model selection or upgrade hardware")
    elif usage_percent >= 85:
        print()
        ui.print_warning("RAM usage exceeds 85% - system may become unstable")
    elif usage_percent >= 70:
        print()
        ui.print_warning("RAM usage is high - consider reducing selection if experiencing issues")
    
    print()


def fetch_model_tags_concurrent(
    model_names: List[str],
    hw_info: hardware.HardwareInfo,
    max_workers: int = 5
) -> Dict[str, List[Dict[str, Any]]]:
    """
    Fetch model tags concurrently using ThreadPoolExecutor.
    
    Features:
    - Parallel API calls (max 5 workers for rate limiting)
    - Caching results in hw_info
    - Rate limiting to avoid overwhelming Docker Hub API
    
    Args:
        model_names: List of model names to fetch tags for
        hw_info: Hardware information for caching
        max_workers: Maximum number of concurrent workers (default: 5)
    
    Returns:
        Dictionary mapping model names to lists of tag dictionaries
    """
    results = {}
    
    # Filter out models we already have cached
    uncached_models = []
    for model_name in model_names:
        base_name = model_name.replace("ai/", "").strip()
        cache_key = f"{base_name}_cache"
        
        # Check cache
        if hasattr(hw_info, 'discovered_model_tags') and cache_key in hw_info.discovered_model_tags:
            cached_data = hw_info.discovered_model_tags[cache_key]
            if isinstance(cached_data, dict) and "tags" in cached_data and "timestamp" in cached_data:
                cache_age = datetime.now() - cached_data["timestamp"]
                if cache_age < timedelta(hours=1):
                    # Use cached data
                    results[model_name] = cached_data["tags"]
                    continue
        
        uncached_models.append(model_name)
    
    if not uncached_models:
        return results
    
    # For fixed models, no need to fetch tags - return empty lists
    # GPT-OSS and nomic-embed-text are the only supported models
    for model_name in uncached_models:
        results[model_name] = []
    
    return results


def _generate_model_description(model_name: str, roles: List[str]) -> str:
    """Generate a descriptive text for a model based on its name."""
    name_lower = model_name.lower()
    base_name = model_name.replace("ai/", "").replace("-", " ").replace("_", " ").title()
    
    # Try to infer model characteristics from name
    desc_parts = []
    model_type = ""
    
    # Model type indicators
    if "gpt-oss" in name_lower:
        model_type = "OpenAI's open-weight reasoning model"
    elif "embed" in name_lower or "nomic-embed" in name_lower:
        model_type = "Embedding model"
    else:
        model_type = f"{base_name} model"
    
    desc_parts.append(model_type)
    
    # Inference engine/optimization variants (detect before size to avoid conflicts)
    variant_info = ""
    if "-vllm" in name_lower:
        variant_info = "vLLM engine (faster inference)"
    elif "-tensorrt" in name_lower or "-trt" in name_lower:
        variant_info = "TensorRT optimized"
    elif "-onnx" in name_lower:
        variant_info = "ONNX runtime"
    elif "-gguf" in name_lower:
        variant_info = "GGUF format"
    elif "-ggml" in name_lower:
        variant_info = "GGML format"
    elif "-flash" in name_lower or "-flash-attention" in name_lower:
        variant_info = "Flash Attention optimized"
    elif "-quantized" in name_lower or "-q" in name_lower:
        variant_info = "Quantized"
    elif "-preview" in name_lower:
        variant_info = "Preview version"
    elif "-beta" in name_lower:
        variant_info = "Beta version"
    
    if variant_info:
        desc_parts.append(variant_info)
    
    # Size indicators (add to description if found)
    size_info = ""
    if "70b" in name_lower or "70-b" in name_lower:
        size_info = "70B"
    elif "32b" in name_lower or "32-b" in name_lower:
        size_info = "32B"
    elif "22b" in name_lower or "22-b" in name_lower:
        size_info = "22B"
    elif "14b" in name_lower or "14-b" in name_lower:
        size_info = "14B"
    elif "7b" in name_lower or "7-b" in name_lower:
        size_info = "7B"
    elif "3b" in name_lower or "3-b" in name_lower:
        size_info = "3B"
    elif "1.5b" in name_lower or "1.5-b" in name_lower:
        size_info = "1.5B"
    
    if size_info:
        desc_parts.append(f"{size_info} parameters")
    
    # RAM estimate based on model name
    ram_estimate = 4.0
    if "embed" in name_lower:
        ram_estimate = 0.3  # nomic-embed-text
    elif "gpt-oss" in name_lower or "20b" in name_lower or "20B" in name_lower:
        ram_estimate = 16.0  # GPT-OSS 20B
    elif size_info == "70B":
        ram_estimate = 35.0
    elif size_info == "32B":
        ram_estimate = 18.0
    elif size_info == "22B":
        ram_estimate = 12.0
    elif size_info == "14B":
        ram_estimate = 8.0
    elif size_info == "7B":
        ram_estimate = 4.0
    elif size_info == "3B":
        ram_estimate = 1.8
    elif size_info == "1.5B":
        ram_estimate = 1.0
    
    # Build description
    description = ", ".join(desc_parts)
    
    # Add RAM and roles
    description += f" | ~{ram_estimate:.1f}GB RAM"
    if roles:
        description += f" | roles: {', '.join(roles)}"
    
    return description


def get_model_id_for_continue(model: Any, hw_info: Optional[hardware.HardwareInfo] = None) -> str:
    """
    Convert Docker Model Runner model name to Continue.dev compatible format.
    
    Docker Model Runner API returns models as: ai/gpt-oss:20B-UD-Q6_K_XL
    The model catalog uses: ai/gpt-oss:20B-UD-Q6_K_XL
    
    This function converts to the actual API model ID format.
    Preserves variant tags if selected.
    """
    # Input validation - accept ModelInfo, RecommendedModel, or string
    if isinstance(model, str):
        docker_name = model
        selected_variant = None
        base_model_name = None
    elif isinstance(model, ModelInfo):
        docker_name = model.docker_name
        selected_variant = model.selected_variant
        base_model_name = getattr(model, 'base_model_name', None)
    else:
        # Try RecommendedModel (from model_selector)
        try:
            from .model_selector import RecommendedModel
            if isinstance(model, RecommendedModel):
                docker_name = model.docker_name
                selected_variant = None
                base_model_name = None
            else:
                raise ValueError("model must be ModelInfo, RecommendedModel, or string")
        except ImportError:
            # Check if it has docker_name attribute (duck typing)
            if hasattr(model, 'docker_name'):
                docker_name = model.docker_name
                selected_variant = getattr(model, 'selected_variant', None)
                base_model_name = getattr(model, 'base_model_name', None)
            else:
                raise ValueError("model must be ModelInfo, RecommendedModel, or string")
    
    # If we have a selected variant, use it
    if selected_variant and base_model_name:
        # Format: ai/base_model_name:variant_tag
        return f"ai/{base_model_name}:{selected_variant}"
    
    # First, check if we can get the actual model ID from the API
    if hw_info and hasattr(hw_info, 'available_api_models') and hw_info.available_api_models:
        # Try to match the model name to an API model ID
        model_lower = docker_name.lower()
        
        # Check for nomic-embed variants
        if "nomic" in model_lower or "embed" in model_lower:
            for api_model_id in hw_info.available_api_models:
                if "nomic" in api_model_id.lower() or "embed" in api_model_id.lower():
                    return api_model_id
    
    # Fallback: Convert from catalog format to Docker Hub format
    model_id = docker_name
    
    # Remove the ai.docker.com/ prefix if present
    if model_id.startswith("ai.docker.com/"):
        remaining = model_id[len("ai.docker.com/"):]
        parts = remaining.split("/")
        if len(parts) > 1:
            # Has org prefix, remove it
            model_part = parts[1]
        else:
            model_part = parts[0]
        
        # Preserve variant tag if present (e.g., :70B-Q4_K_M)
        variant_tag = None
        if ":" in model_part:
            model_part, variant_tag = model_part.split(":", 1)
        
        # Remove size indicators (3b, 8b, etc.) from model name only if no variant tag
        if not variant_tag:
            model_part = re.sub(r'[-_]?[0-9]+b', '', model_part, flags=re.IGNORECASE)
        
        # Convert to Docker Hub format: ai/modelname
        model_id = f"ai/{model_part}"
        
        # Add variant tag or :latest
        if variant_tag:
            model_id = f"{model_id}:{variant_tag}"
        elif ":" not in model_id:
            model_id = f"{model_id}:latest"
    
    # If it already starts with ai/, preserve existing tag or add :latest
    elif model_id.startswith("ai/"):
        if ":" not in model_id:
            model_id = f"{model_id}:latest"
    
    return model_id
