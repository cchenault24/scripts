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
    tiers: List[hardware.HardwareTier]  # Which tiers can run this model
    recommended_for: List[str] = field(default_factory=list)
    base_model_name: Optional[str] = None  # Base model name for variant discovery (e.g., "llama3.3")
    selected_variant: Optional[str] = None  # Selected variant tag (e.g., "70B-Q4_K_M")


# Model catalog for Docker Model Runner (DMR)
# Docker Model Runner uses the namespace: ai/ for Docker Hub models
# Models are optimized for Apple Silicon with Metal acceleration
# Format: ai/<model-name> or ai/<model-name>:<tag>
# Note: Legacy ai.docker.com/ format models have been removed as they don't exist in ai/ namespace
MODEL_CATALOG: List[ModelInfo] = [
    # =========================================================================
    # Chat/Edit Models - Large (Tier S: 49GB+ RAM)
    # =========================================================================
    ModelInfo(
        name="Llama 3.3",
        docker_name="ai/llama3.3",
        description="Highest quality for complex refactoring - variant auto-selected based on hardware",
        ram_gb=35.0,  # Will be updated based on selected variant
        context_length=131072,
        roles=["chat", "edit", "agent"],
        tiers=[hardware.HardwareTier.S],
        recommended_for=["Tier S primary model", "Complex refactoring"],
        base_model_name="llama3.3"
    ),
    ModelInfo(
        name="Llama 3.1",
        docker_name="ai/llama3.1",
        description="Excellent for architecture and complex tasks - variant auto-selected based on hardware",
        ram_gb=35.0,  # Will be updated based on selected variant
        context_length=131072,
        roles=["chat", "edit", "agent"],
        tiers=[hardware.HardwareTier.S],
        recommended_for=["Tier S alternative"],
        base_model_name="llama3.1"
    ),
    # =========================================================================
    # Chat/Edit Models - Medium-Large (Tier A: 33-48GB RAM)
    # =========================================================================
    ModelInfo(
        name="Granite 4.0 H-Small",
        docker_name="ai/granite-4.0-h-small",
        description="IBM's Granite 4.0 coding model (small variant) - State-of-the-art code generation",
        ram_gb=18.0,
        context_length=131072,
        roles=["chat", "edit", "autocomplete"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A],
        recommended_for=["Best coding quality", "Tier A primary"]
    ),
    ModelInfo(
        name="Codestral",
        docker_name="ai/codestral",
        description="Mistral's Codestral code generation model - Excellent for code generation",
        ram_gb=12.0,
        context_length=32768,
        roles=["chat", "edit", "autocomplete"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A],
        recommended_for=["Excellent code generation", "Mistral coding model"]
    ),
    ModelInfo(
        name="Devstral Small",
        docker_name="ai/devstral-small",
        description="Mistral's Devstral coding model (small variant) - Fast and capable",
        ram_gb=9.0,
        context_length=32768,
        roles=["chat", "edit", "autocomplete"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A],
        recommended_for=["Good balance of speed and quality"]
    ),
    # =========================================================================
    # Chat/Edit Models - Medium (Tier B: >24-32GB RAM)
    # =========================================================================
    ModelInfo(
        name="Phi-4",
        docker_name="ai/phi4",
        description="Microsoft's state-of-the-art reasoning model - variant auto-selected based on hardware",
        ram_gb=8.0,  # Will be updated based on selected variant
        context_length=16384,
        roles=["chat", "edit", "agent"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B],
        recommended_for=["Excellent reasoning", "Tier B primary"],
        base_model_name="phi4"
    ),
    ModelInfo(
        name="Granite 4.0 H-Micro",
        docker_name="ai/granite-4.0-h-micro",
        description="IBM's Granite 4.0 coding model (micro variant) - Strong coding with good performance",
        ram_gb=8.0,
        context_length=131072,
        roles=["chat", "edit", "autocomplete"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B],
        recommended_for=["Good balance of quality and speed"]
    ),
    # =========================================================================
    # Chat/Edit Models - Small (All Tiers, optimized for Tier C: 16-24GB RAM)
    # =========================================================================
    # Note: Llama 3.2 8B is NOT available in Docker Model Runner
    # Docker Model Runner only provides ai/llama3.2 which is the 3B variant
    # Keeping this commented out to prevent confusion
    # ModelInfo(
    #     name="Llama 3.2 8B",
    #     docker_name="ai.docker.com/meta/llama3.2:8b-instruct",
    #     description="8B - Fast general-purpose assistant",
    #     ram_gb=5.0,
    #     context_length=131072,
    #     roles=["chat", "edit", "autocomplete"],
    #     tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
    #     recommended_for=["All tiers", "Fast responses"]
    # ),
    ModelInfo(
        name="Granite 4.0 H-Nano",
        docker_name="ai/granite-4.0-h-nano",
        description="IBM's Granite 4.0 coding model (nano variant) - Efficient coding model",
        ram_gb=4.0,
        context_length=131072,
        roles=["chat", "edit", "autocomplete"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
        recommended_for=["Tier C primary", "Fast autocomplete"]
    ),
    # =========================================================================
    # Autocomplete Models - Ultra-fast (All Tiers)
    # =========================================================================
    ModelInfo(
        name="Llama 3.2",
        docker_name="ai/llama3.2",
        description="Small and efficient general model - variant auto-selected based on hardware",
        ram_gb=1.8,  # Will be updated based on selected variant
        context_length=131072,
        roles=["chat", "edit", "autocomplete"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
        recommended_for=["All tiers", "Quick edits", "Low memory", "Fast responses"],
        base_model_name="llama3.2"
    ),
    ModelInfo(
        name="Granite 4.0 H-Tiny",
        docker_name="ai/granite-4.0-h-tiny",
        description="IBM's Granite 4.0 coding model (tiny variant) - Smallest coding model, very fast",
        ram_gb=1.0,
        context_length=131072,
        roles=["autocomplete"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
        recommended_for=["Minimal memory usage", "Ultra-fast autocomplete"]
    ),
    # =========================================================================
    # Embedding Models (All Tiers)
    # =========================================================================
    ModelInfo(
        name="Nomic Embed Text v1.5",
        docker_name="ai/nomic-embed-text-v1.5",
        description="Best open embedding model for code indexing (8192 tokens)",
        ram_gb=0.3,
        context_length=8192,
        roles=["embed"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
        recommended_for=["Code indexing", "Semantic search"],
        base_model_name="nomic-embed-text-v1.5"
    ),
    ModelInfo(
        name="Granite Embedding Multilingual",
        docker_name="ai/granite-embedding-multilingual",
        description="IBM's Granite multilingual embedding model - Multi-lingual code and text embeddings",
        ram_gb=0.5,
        context_length=8192,
        roles=["embed"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
        recommended_for=["Multi-lingual codebases"]
    ),
    ModelInfo(
        name="MXBAI Embed Large",
        docker_name="ai/mxbai-embed-large",
        description="Mixedbread AI's large embedding model - High-quality embeddings for code",
        ram_gb=0.8,
        context_length=8192,
        roles=["embed"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
        recommended_for=["High-quality code embeddings"]
    ),
    ModelInfo(
        name="All-MiniLM-L6-v2 (vLLM)",
        docker_name="ai/all-minilm-l6-v2-vllm",
        description="Lightweight embedding model optimized with vLLM - Minimal memory usage",
        ram_gb=0.1,
        context_length=512,
        roles=["embed"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
        recommended_for=["Minimal memory", "Simple search", "Fast embeddings"]
    ),
]


def discover_model_variants(base_model_name: str, hw_info: Optional[hardware.HardwareInfo] = None) -> List[str]:
    """
    Discover available variants of a model using docker search.
    
    For example, searching for 'ai/phi4' might reveal that 'ai/phi4' exists,
    which helps verify our catalog models match what's actually available.
    
    Returns a list of found model names in 'ai/namespace' format.
    """
    variants = []
    try:
        # Extract just the model name part (e.g., 'phi4' from 'ai/phi4' or 'ai.docker.com/microsoft/phi4:14b')
        search_query = base_model_name
        if base_model_name.startswith("ai.docker.com/"):
            # Extract model name from ai.docker.com format
            remaining = base_model_name[len("ai.docker.com/"):]
            parts = remaining.split("/")
            if len(parts) > 1:
                model_part = parts[1]
            else:
                model_part = parts[0]
            if ":" in model_part:
                model_part = model_part.split(":")[0]
            search_query = f"ai/{model_part}"
        elif not base_model_name.startswith("ai/"):
            # If it's just a model name, add ai/ prefix
            search_query = f"ai/{base_model_name}"
        
        # Use docker search to find variants
        code, stdout, _ = utils.run_command(["docker", "search", search_query, "--limit", "25"], timeout=15)
        if code == 0:
            lines = stdout.strip().split("\n")
            for line in lines[1:]:  # Skip header
                if line.strip():
                    parts = line.split()
                    if parts:
                        found_name = parts[0]
                        # Only include models in ai/ namespace that match our base
                        if found_name.startswith("ai/") and search_query.replace("ai/", "").lower() in found_name.lower():
                            variants.append(found_name)
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError, ValueError):
        # Silently fail - this is just for discovery
        pass
    
    return variants


def discover_docker_hub_models(query: str = "ai/", limit: int = 50) -> List[Dict[str, Any]]:
    """Discover models from Docker Hub."""
    models = []
    try:
        ui.print_info(f"Searching Docker Hub for '{query}'...")
        code, stdout, _ = utils.run_command(["docker", "search", query, "--limit", str(limit)], timeout=30)
        if code == 0:
            lines = stdout.strip().split("\n")
            if len(lines) > 1:  # Has results (first line is header)
                for line in lines[1:]:
                    if line.strip():
                        parts = line.split()
                        if parts:
                            model_name = parts[0]
                            description = " ".join(parts[1:]) if len(parts) > 1 else "No description"
                            # Only include models in ai/ namespace
                            if model_name.startswith("ai/"):
                                models.append({
                                    "name": model_name,
                                    "description": description[:100],  # Limit description length
                                    "source": "docker_hub",
                                    "stars": parts[1] if len(parts) > 1 and parts[1].isdigit() else "0"
                                })
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError, ValueError) as e:
        ui.print_warning(f"Could not search Docker Hub: {e}")
    
    return models


def fetch_available_models_from_docker_hub(page_size: int = 100) -> List[str]:
    """
    Fetch list of available models from Docker Hub API.
    
    Uses the Docker Hub v2 API to get all repositories in the 'ai' namespace.
    Handles pagination to fetch all available models.
    Returns a list of model names in format 'ai/model-name'.
    """
    available_models = []
    page = 1
    
    # Fetch all pages
    while True:
        try:
            url = f"https://hub.docker.com/v2/repositories/ai/?page={page}&page_size={page_size}"
            
            data = fetch_with_retry(url, max_retries=3, timeout=15)
            
            if data is None:
                # If first page fails, return empty list
                if page == 1:
                    ui.print_warning("Could not fetch models from Docker Hub API")
                    return []
                # If later page fails, return what we have
                break
            
            if "results" in data:
                page_models = data["results"]
                if not page_models:
                    # No more results
                    break
                
                for repo in page_models:
                    repo_name = repo.get("name", "")
                    if repo_name:
                        available_models.append(f"ai/{repo_name}")
                
                # Check if there are more pages
                if "next" not in data or data.get("next") is None:
                    break
                
                page += 1
            else:
                # No results field - stop
                break
                
        except Exception as e:
            ui.print_warning(f"Error fetching models from Docker Hub (page {page}): {e}")
            if page == 1:
                return []
            break
    
    return available_models


def fetch_with_retry(
    url: str, 
    max_retries: int = 3, 
    backoff_base: float = 2.0,
    timeout: int = 10
) -> Optional[Dict[str, Any]]:
    """
    Fetch URL with exponential backoff retry logic.
    
    Handles:
    - 429 (rate limit): retry with exponential backoff
    - 404: return None (caller should try alternatives)
    - Network timeouts: retry with exponential backoff
    - Other errors: retry with exponential backoff
    
    Args:
        url: URL to fetch
        max_retries: Maximum number of retry attempts
        backoff_base: Base for exponential backoff (seconds)
        timeout: Request timeout in seconds
    
    Returns:
        Parsed JSON response as dict, or None if all retries failed
    """
    for attempt in range(max_retries):
        try:
            req = urllib.request.Request(url)
            req.add_header("User-Agent", "Docker-Model-Runner-Setup/1.0")
            
            with urllib.request.urlopen(req, timeout=timeout, context=get_unverified_ssl_context()) as response:
                if response.status == 200:
                    data = json.loads(response.read().decode('utf-8'))
                    return data
                elif response.status == 429:
                    # Rate limited - wait and retry
                    if attempt < max_retries - 1:
                        wait_time = backoff_base ** attempt
                        ui.print_warning(f"Rate limited, retrying in {wait_time:.1f}s...")
                        time.sleep(wait_time)
                        continue
                    else:
                        ui.print_error("Rate limit exceeded after retries")
                        return None
                elif response.status == 404:
                    # Not found - don't retry
                    return None
                else:
                    # Other HTTP error - retry
                    if attempt < max_retries - 1:
                        wait_time = backoff_base ** attempt
                        ui.print_warning(f"HTTP {response.status}, retrying in {wait_time:.1f}s...")
                        time.sleep(wait_time)
                        continue
                    else:
                        ui.print_error(f"HTTP {response.status} after retries")
                        return None
                        
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None  # Don't retry 404s
            elif e.code == 429:
                if attempt < max_retries - 1:
                    wait_time = backoff_base ** attempt
                    ui.print_warning(f"Rate limited (HTTP 429), retrying in {wait_time:.1f}s...")
                    time.sleep(wait_time)
                    continue
                else:
                    ui.print_error("Rate limit exceeded after retries")
                    return None
            else:
                if attempt < max_retries - 1:
                    wait_time = backoff_base ** attempt
                    ui.print_warning(f"HTTP {e.code}, retrying in {wait_time:.1f}s...")
                    time.sleep(wait_time)
                    continue
                else:
                    ui.print_error(f"HTTP {e.code} after retries")
                    return None
                    
        except (urllib.error.URLError, OSError) as e:
            # Network error - retry
            if attempt < max_retries - 1:
                wait_time = backoff_base ** attempt
                ui.print_warning(f"Network error: {e}, retrying in {wait_time:.1f}s...")
                time.sleep(wait_time)
                continue
            else:
                ui.print_warning(f"Network error after retries: {e}")
                return None
                
        except json.JSONDecodeError as e:
            ui.print_error(f"Invalid JSON response: {e}")
            return None
            
        except Exception as e:
            ui.print_error(f"Unexpected error: {e}")
            return None
    
    return None


def score_variant(
    tag_info: Dict[str, Any], 
    hw_info: hardware.HardwareInfo,
    target_size: Optional[float] = None
) -> float:
    """
    Score a model variant based on hardware fit, quality, and performance.
    
    Scoring factors:
    - Hardware fit: RAM budget compliance (higher score if fits well)
    - Quality: F16 > Q8 > Q5 > Q4 > Q3 > Q2 (higher quantization = better quality)
    - Performance: Prefer vLLM variants (faster inference)
    
    When target_size is specified, weights are adjusted to prioritize size match:
    - Quality weight is reduced (from 60% to 30%)
    - Fit weight is increased (from 30% to 50%)
    - Prefers quantized models (Q4/Q5) over F16 when targeting specific sizes
    
    Args:
        tag_info: Parsed tag dictionary from parse_tag_info()
        hw_info: Hardware information for RAM constraints
        target_size: Optional target model size in billions (adjusts scoring weights)
    
    Returns:
        Score (higher is better), or -1 if variant doesn't fit in RAM
    """
    if not tag_info.get("size"):
        return -1.0
    
    ram_needed = tag_info.get("estimated_ram_gb", 0)
    usable_ram = hw_info.get_estimated_model_memory()
    
    # Hardware fit score: negative if doesn't fit, positive if fits (closer to budget = better)
    if ram_needed > usable_ram:
        return -1.0  # Doesn't fit
    
    # Fit score: how well it uses available RAM
    # When target_size specified, don't penalize larger models that fit
    ram_usage_ratio = ram_needed / usable_ram if usable_ram > 0 else 0
    if target_size is not None:
        # Prefer models that fit well, but don't penalize larger models
        fit_score = min(1.0, ram_usage_ratio)  # Linear up to 100% usage
    else:
        # Original behavior: prefer ~70% usage
        fit_score = 1.0 - abs(ram_usage_ratio - 0.7)
    fit_score = max(0.0, min(1.0, fit_score))  # Clamp to [0, 1]
    
    # Quality score based on quantization
    quantization = (tag_info.get("quantization") or "").upper()
    is_full_precision = tag_info.get("is_full_precision", False)
    
    quality_scores = {
        "F32": 10.0,
        "F16": 9.0,
        "Q8": 7.0,
        "Q8_0": 7.0,
        "Q5": 6.0,
        "Q4": 5.0,
        "Q4_K_M": 5.5,  # Slightly better than Q4
        "Q4_0": 5.0,
        "Q3": 3.0,
        "Q2": 2.0,
    }
    
    if is_full_precision and not quantization:
        quality_score = 9.0  # Default to F16 quality
    else:
        quality_score = quality_scores.get(quantization, 5.0)
    
    # When targeting specific sizes, strongly prefer quantized models (Q4/Q5) over F16
    # Quantized models are more likely to match target sizes, F16 models are often smaller variants
    if target_size is not None:
        size = tag_info.get("size", 0)
        if size > 0:
            size_ratio = size / target_size if target_size > 0 else 1.0
            
            # Strongly boost quantized models when they're close to target size
            if quantization in ["Q4", "Q4_K_M", "Q4_0", "Q5"]:
                # Large boost for quantized models when targeting sizes (they fit better)
                if 0.8 <= size_ratio <= 1.2:  # Within 20% of target
                    quality_score += 3.0  # Significant boost
                else:
                    quality_score += 1.5  # Still boost, but less
            elif quantization in ["Q8", "Q8_0"]:
                # Moderate boost for Q8 (good quality, still quantized)
                if 0.8 <= size_ratio <= 1.2:
                    quality_score += 2.0
            elif quantization == "F16":
                # Penalize F16 when targeting sizes - F16 models are often smaller variants
                # Only keep F16 if it's very close to target (within 10%)
                if size_ratio < 0.9:
                    quality_score -= 3.0  # Strong penalty for F16 that's too small
                elif size_ratio > 1.1:
                    quality_score -= 1.0  # Small penalty for F16 that's too large
    
    # Performance score: prefer vLLM variants (check tag name)
    tag_name = tag_info.get("tag_name", "").lower()
    performance_score = 1.5 if "vllm" in tag_name else 1.0
    
    # Combined score: weighted sum
    # Adjust weights based on whether target_size is specified
    if target_size is not None:
        # When targeting size: prioritize fit, reduce quality weight
        # Fit: 50%, Quality: 30%, Performance: 20%
        total_score = (fit_score * 0.5) + (quality_score * 0.3) + (performance_score * 0.2)
    else:
        # Original weights: Fit: 30%, Quality: 60%, Performance: 10%
        total_score = (fit_score * 0.3) + (quality_score * 0.6) + (performance_score * 0.1)
    
    return total_score


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


def discover_model_tags(
    model_name: str, 
    hw_info: Optional[hardware.HardwareInfo] = None,
    use_cache: bool = True,
    silent: bool = False
) -> List[Dict[str, Any]]:
    """
    Discover available tags/variants for a model from Docker Hub API.
    
    Features:
    - Pagination support (fetches all pages)
    - Exponential backoff retry logic
    - Caching with 1hr TTL
    
    Args:
        model_name: Base model name (e.g., "llama3.3" or "ai/llama3.3")
        hw_info: Optional HardwareInfo for caching
        use_cache: Whether to use cached results (default: True)
    
    Returns:
        List of tag dictionaries with parsed metadata
    """
    # Normalize model name (remove ai/ prefix if present)
    base_name = model_name.replace("ai/", "").strip()
    
    # Check cache first (with TTL check)
    if use_cache and hw_info:
        if hasattr(hw_info, 'discovered_model_tags'):
            # Check if we have cached data with timestamp
            cache_key = f"{base_name}_cache"
            if cache_key in hw_info.discovered_model_tags:
                cached_data = hw_info.discovered_model_tags[cache_key]
                if isinstance(cached_data, dict) and "tags" in cached_data and "timestamp" in cached_data:
                    try:
                        cache_age = datetime.now() - cached_data["timestamp"]
                        # Use shorter TTL for empty results (failed requests) - 15 minutes
                        # Longer TTL for successful results - 1 hour
                        is_empty_result = len(cached_data.get("tags", [])) == 0
                        ttl = timedelta(minutes=15) if is_empty_result else timedelta(hours=1)
                        
                        if cache_age < ttl:
                            # Cache is still valid (including empty results for models that don't exist)
                            return cached_data["tags"]
                    except (TypeError, ValueError, AttributeError):
                        # Cache corruption - invalidate this entry
                        del hw_info.discovered_model_tags[cache_key]
    
    tags = []
    page = 1
    page_size = 100
    
    # Fetch all pages
    while True:
        url = f"https://hub.docker.com/v2/repositories/ai/{base_name}/tags/?page={page}&page_size={page_size}"
        
        data = fetch_with_retry(url, max_retries=3, timeout=15)
        
        if data is None:
            # If first page fails, return empty list
            if page == 1:
                if not silent:
                    ui.print_warning(f"Could not fetch tags for {base_name}")
                # Cache the failure to avoid repeated attempts (shorter TTL - 15 minutes)
                if hw_info:
                    if not hasattr(hw_info, 'discovered_model_tags'):
                        hw_info.discovered_model_tags = {}
                    cache_key = f"{base_name}_cache"
                    hw_info.discovered_model_tags[cache_key] = {
                        "tags": [],
                        "timestamp": datetime.now(),
                        "is_failure": True  # Mark as failure for shorter TTL
                    }
                return []
            # If later page fails, return what we have
            break
        
        # Process results
        if "results" in data:
            page_tags = data["results"]
            if not page_tags:
                # No more results
                break
            
            for tag_result in page_tags:
                tag_name = tag_result.get("name", "")
                if tag_name:
                    # Parse tag info
                    tag_info = parse_tag_info(tag_name)
                    tags.append(tag_info)
            
            # Check if there are more pages
            if "next" not in data or data.get("next") is None:
                break
            
            page += 1
        else:
            # No results field - stop
            break
    
    # Cache results with timestamp
    if hw_info:
        if not hasattr(hw_info, 'discovered_model_tags'):
            hw_info.discovered_model_tags = {}
        cache_key = f"{base_name}_cache"
        hw_info.discovered_model_tags[cache_key] = {
            "tags": tags,
            "timestamp": datetime.now(),
            "is_failure": False  # Mark as successful for longer TTL
        }
        # Also store directly for backward compatibility
        hw_info.discovered_model_tags[base_name] = tags
    
    return tags


def get_model_family_alternatives(model_family: str) -> List[str]:
    """
    Get alternative model families from the same category.
    
    Categories:
    - Reasoning: phi4, gpt-oss, seed-oss
    - Coding: granite-4.0, codestral, devstral, codellama, phi4
    - General: llama3, mistral, granite-4.0
    - Multimodal: gemma3n, moondream, smolvlm
    - Embedding: nomic-embed, mxbai, all-minilm
    
    Args:
        model_family: Base model name (e.g., "llama3.3")
    
    Returns:
        List of alternative model family names
    """
    family_lower = model_family.lower()
    
    # Reasoning models
    if any(x in family_lower for x in ["phi4", "gpt-oss", "seed-oss"]):
        return ["phi4", "gpt-oss", "seed-oss"]
    
    # Coding models
    if any(x in family_lower for x in ["granite", "codestral", "devstral", "codellama"]):
        return ["granite-4.0-h-small", "granite-4.0-h-micro", "codestral", "devstral", "codellama"]
    
    # General chat models
    if any(x in family_lower for x in ["llama3", "llama3.1", "llama3.2", "llama3.3"]):
        return ["llama3.3", "llama3.1", "llama3.2", "mistral"]
    
    # Multimodal models
    if any(x in family_lower for x in ["gemma3n", "moondream", "smolvlm"]):
        return ["gemma3n", "moondream", "smolvlm"]
    
    # Embedding models
    if any(x in family_lower for x in ["nomic-embed", "mxbai", "all-minilm", "embed"]):
        return ["nomic-embed-text-v1.5", "mxbai-embed-large", "granite-embedding-multilingual"]
    
    # Default: return empty list
    return []


def select_best_model_with_fallback(
    model_family: str,
    ram_budget: float,
    hw_info: hardware.HardwareInfo
) -> Optional[Tuple[str, str]]:
    """
    Select best model variant with cascading fallbacks.
    
    Strategy:
    1. Try primary model family
    2. If no suitable variant, try alternatives from same category
    3. Return None only if all alternatives exhausted
    
    Args:
        model_family: Primary model family name (e.g., "llama3.3")
        ram_budget: Available RAM budget in GB
        hw_info: Hardware information
    
    Returns:
        Tuple of (model_name, variant_tag) or None if no suitable model found
    """
    # Try primary model family first
    tags = discover_model_tags(model_family, hw_info)
    if tags:
        # Score all variants
        scored_variants = []
        for tag in tags:
            score = score_variant(tag, hw_info)
            if score > 0 and tag.get("estimated_ram_gb", 0) <= ram_budget:
                scored_variants.append((tag, score))
        
        if scored_variants:
            # Sort by score (highest first)
            scored_variants.sort(key=lambda x: x[1], reverse=True)
            best_tag = scored_variants[0][0]
            return (model_family, best_tag.get("tag_name"))
    
    # Try alternatives from same category
    alternatives = get_model_family_alternatives(model_family)
    for alt_family in alternatives:
        if alt_family == model_family:
            continue  # Skip primary (already tried)
        
        alt_tags = discover_model_tags(alt_family, hw_info)
        if alt_tags:
            scored_variants = []
            for tag in alt_tags:
                score = score_variant(tag, hw_info)
                if score > 0 and tag.get("estimated_ram_gb", 0) <= ram_budget:
                    scored_variants.append((tag, score))
            
            if scored_variants:
                scored_variants.sort(key=lambda x: x[1], reverse=True)
                best_tag = scored_variants[0][0]
                return (alt_family, best_tag.get("tag_name"))
    
    # All alternatives exhausted
    return None


def get_display_name_from_model(model_name: str, category: str = "", variant: Optional[str] = None) -> str:
    """
    Generate a human-readable display name from a model name.
    
    Args:
        model_name: Model name (e.g., "llama3.2", "mistral", "granite-4.0-h-small")
        category: Optional category hint (e.g., "general", "coding", "reasoning", "multimodal")
        variant: Optional variant tag (e.g., "7B-Q4_K_M") - size will be extracted and included
    
    Returns:
        Human-readable display name (e.g., "Llama 3.2", "Mistral:7B", "Granite 4.0 H-Small")
    """
    model_lower = model_name.lower()
    
    # Llama models
    if "llama3.3" in model_lower:
        base_name = "Llama 3.3"
    elif "llama3.2" in model_lower:
        base_name = "Llama 3.2"
    elif "llama3.1" in model_lower:
        base_name = "Llama 3.1"
    elif "llama" in model_lower:
        base_name = "Llama"
    # Granite models
    elif "granite-4.0-h-small" in model_lower or "granite4.0hsmall" in model_lower:
        base_name = "Granite 4.0 H-Small"
    elif "granite-4.0-h-micro" in model_lower or "granite4.0hmicro" in model_lower:
        base_name = "Granite 4.0 H-Micro"
    elif "granite-4.0-h-nano" in model_lower or "granite4.0hnano" in model_lower:
        base_name = "Granite 4.0 H-Nano"
    elif "granite-4.0-h-tiny" in model_lower or "granite4.0htiny" in model_lower:
        base_name = "Granite 4.0 H-Tiny"
    elif "granite" in model_lower:
        base_name = "Granite"
    # Mistral models
    elif "mistral" in model_lower:
        base_name = "Mistral"
    # Codestral/Devstral
    elif "codestral" in model_lower:
        base_name = "Codestral"
    elif "devstral" in model_lower:
        base_name = "Devstral"
    # Phi models
    elif "phi4" in model_lower or "phi-4" in model_lower:
        base_name = "Phi-4"
    elif "phi" in model_lower:
        base_name = "Phi"
    # Embedding models
    elif "nomic-embed" in model_lower or "nomicembed" in model_lower:
        base_name = "Nomic Embed"
    elif "granite-embedding" in model_lower or "graniteembedding" in model_lower:
        base_name = "Granite Embedding"
    elif "mxbai-embed" in model_lower or "mxbaiembed" in model_lower:
        base_name = "MxBai Embed"
    # Other models
    elif "gemma" in model_lower:
        base_name = "Gemma"
    elif "moondream" in model_lower:
        base_name = "Moondream"
    elif "smolvlm" in model_lower:
        base_name = "SmolVLM"
    elif "tinyllama" in model_lower or "tiny-llama" in model_lower:
        base_name = "TinyLlama"
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
    
    # Add category suffix if provided
    if category:
        category_lower = category.lower()
        if category_lower == "general":
            return f"{base_name}{size_suffix} (General)"
        elif category_lower == "coding":
            return f"{base_name}{size_suffix} (Coding)"
        elif category_lower == "reasoning":
            return f"{base_name}{size_suffix} (Reasoning)"
        elif category_lower == "multimodal":
            return f"{base_name}{size_suffix} (Multimodal)"
        elif category_lower == "utility":
            return f"{base_name}{size_suffix} (Utility)"
        elif category_lower == "embedding":
            return f"{base_name}{size_suffix} (Embeddings)"
    
    # If variant size but no category, still include size
    if size_suffix:
        return f"{base_name}{size_suffix}"
    
    return base_name


def discover_best_model_by_criteria(
    target_size: Optional[float],
    category: str,
    ram_budget: float,
    hw_info: hardware.HardwareInfo
) -> Optional[Tuple[str, str]]:
    """
    Discover the best model based on criteria rather than hardcoding model names.
    
    Args:
        target_size: Target model size in billions (e.g., 70.0, 34.0, 13.0, 7.0, 3.0, 1.0)
                     If None, finds the largest model that fits the budget
        category: Model category - "reasoning", "coding", "general", "multimodal", "embedding"
        ram_budget: Available RAM budget in GB
        hw_info: Hardware information
    
    Returns:
        Tuple of (model_name, variant_tag) or None if no suitable model found
    """
    # Define model families by category (prioritized order)
    category_families = {
        "reasoning": ["llama3.3", "llama3.1", "llama3.2", "phi4", "gpt-oss", "seed-oss", "mistral"],
        "coding": ["granite-4.0-h-small", "granite-4.0-h-micro", "granite-4.0-h-nano", 
                  "codestral", "devstral", "codellama", "phi4"],
        "general": ["llama3.3", "llama3.2", "llama3.1", "mistral", "granite-4.0-h-small"],
        "multimodal": ["gemma3n", "moondream", "smolvlm", "llama3.2", "llama3.1"],
        "embedding": ["nomic-embed-text-v1.5", "mxbai-embed-large", "granite-embedding-multilingual"]
    }
    
    families = category_families.get(category.lower(), [])
    if not families:
        return None
    
    best_result = None
    best_score = -1
    best_size_match = None
    best_size = 0  # Track actual size of best model
    
    # Try each family in priority order
    for family in families:
        # Use silent=True to suppress warnings for models that may not exist
        tags = discover_model_tags(family, hw_info, use_cache=True, silent=True)
        if not tags:
            continue
        
        # Score all variants
        for tag in tags:
            size = tag.get("size", 0)
            ram_needed = tag.get("estimated_ram_gb", 0)
            
            # Must fit in budget
            if ram_needed > ram_budget:
                continue
            
            # If target_size specified, enforce minimum size constraint (within 50% of target)
            # Reject models that are too small - they're likely wrong choices
            if target_size is not None and size is not None and size > 0:
                min_acceptable_size = target_size * 0.5  # Must be at least 50% of target
                if size < min_acceptable_size:
                    continue  # Skip models that are too small
            
            # Score based on size match and quality (pass target_size to adjust weights)
            score = score_variant(tag, hw_info, target_size)
            if score <= 0:
                continue
            
            # If target_size specified, prioritize exact match, then closest
            # Heavily penalize models that are much smaller than target
            # Size match scores are multiplied by 100x to dominate over quality scores
            size_match_score = 0
            if target_size is not None:
                size_diff = abs(size - target_size)
                if size_diff == 0:
                    size_match_score = 1000000  # Exact match bonus (100x increase)
                elif size_diff <= 1.0:
                    size_match_score = 500000 - (size_diff * 50000)  # Close match (100x increase)
                elif size < target_size:
                    # Heavily penalize models that are much smaller than target
                    # Prefer models closer to target, but allow smaller if nothing else fits
                    if size_diff <= 3.0:
                        size_match_score = 200000 - (size_diff * 20000)  # Somewhat close (100x)
                    elif size_diff <= 6.0:
                        size_match_score = 50000 - (size_diff * 5000)  # Far but acceptable (100x)
                    else:
                        size_match_score = 1000 - size_diff  # Too small, heavy penalty
                else:
                    # Slightly larger is okay, but not ideal
                    if size_diff <= 2.0:
                        size_match_score = 300000 - (size_diff * 20000)  # Slightly larger (100x)
                    else:
                        size_match_score = 100000 - (size_diff * 5000)  # Much larger (100x)
            else:
                # No target size - prefer larger models that fit
                size_match_score = size * 10
            
            total_score = score + size_match_score
            
            # Prefer exact size match, then closest, then best quality
            # But strongly prefer models that are at or above target size
            should_update = False
            if best_result is None:
                should_update = True
            elif target_size is not None:
                # Models at or above target size get priority over smaller models
                current_at_or_above = best_size >= target_size
                candidate_at_or_above = size >= target_size
                
                # If candidate is at/above target and current is not, prefer candidate
                if candidate_at_or_above and not current_at_or_above:
                    should_update = True
                # If both are at/above target, prefer closer to target
                elif candidate_at_or_above and current_at_or_above:
                    current_diff = abs(best_size - target_size)
                    candidate_diff = abs(size - target_size)
                    if candidate_diff < current_diff:
                        should_update = True
                    elif candidate_diff == current_diff and total_score > best_score:
                        should_update = True
                # If both are below target, prefer larger (closer to target)
                elif not candidate_at_or_above and not current_at_or_above:
                    if size > best_size:
                        should_update = True
                    elif size == best_size and total_score > best_score:
                        should_update = True
                # If current is at/above but candidate is not, keep current (don't update)
            else:
                # No target size: prioritize total score (quality + size)
                if total_score > best_score:
                    should_update = True
            
            if should_update:
                best_result = (family, tag.get("tag_name"))
                best_score = total_score
                best_size_match = size_match_score
                best_size = size
    
    return best_result


def select_best_variant(
    available_tags: List[Dict[str, Any]], 
    hw_info: hardware.HardwareInfo,
    preferred_size: Optional[str] = None
) -> Optional[str]:
    """
    Select best model variant tag based on hardware capabilities.
    
    Args:
        available_tags: List of parsed tag dictionaries from discover_model_tags()
        hw_info: Hardware information for tier and RAM constraints
        preferred_size: Optional preferred size (e.g., "70B", "14B") to prioritize
    
    Returns:
        Selected tag name (e.g., "70B-Q4_K_M") or None if no suitable variant
    """
    if not available_tags:
        return None
    
    # Filter out "latest" and invalid tags
    valid_tags = [t for t in available_tags if t.get("size") is not None]
    if not valid_tags:
        # If no valid tags, return None (will fall back to base model)
        return None
    
    # Use calculated usable RAM from hardware info (already accounts for OS overhead)
    usable_ram = hw_info.get_estimated_model_memory()
    
    # Filter tags by tier compatibility (rough size-based tier matching)
    tier_appropriate_tags = []
    for tag in valid_tags:
        size = tag.get("size", 0)
        ram_needed = tag.get("estimated_ram_gb", 0)
        
        # Check if this size is appropriate for the tier
        if hw_info.tier == hardware.HardwareTier.S:
            # Tier S can handle 70B, 34B, 22B
            if size >= 20 or ram_needed <= usable_ram:
                tier_appropriate_tags.append(tag)
        elif hw_info.tier == hardware.HardwareTier.A:
            # Tier A can handle 70B, 34B, 13B (upgraded from 34B, 13B, 7B)
            if size <= 70 or ram_needed <= usable_ram:
                tier_appropriate_tags.append(tag)
        elif hw_info.tier == hardware.HardwareTier.B:
            # Tier B (>24-32GB) can handle 34B, 13B, 7B
            if size <= 40 or ram_needed <= usable_ram:
                tier_appropriate_tags.append(tag)
        elif hw_info.tier == hardware.HardwareTier.C:
            # Tier C (16-24GB) can handle 13B, 7B, 3B
            if size <= 15 or ram_needed <= usable_ram:
                tier_appropriate_tags.append(tag)
        else:  # Tier D (should not occur - minimum 16GB required)
            # Tier D (<16GB) is unsupported - this should never be reached
            if size <= 8 or ram_needed <= usable_ram:
                tier_appropriate_tags.append(tag)
    
    if not tier_appropriate_tags:
        tier_appropriate_tags = valid_tags  # Fallback to all valid tags
    
    # Filter by preferred size if specified
    if preferred_size:
        preferred_size_num = None
        try:
            # Extract number from preferred_size (e.g., "70B" -> 70)
            match = re.search(r'(\d+(?:\.\d+)?)', preferred_size.upper())
            if match:
                preferred_size_num = float(match.group(1))
        except (ValueError, AttributeError):
            pass
        
        if preferred_size_num:
            preferred_tags = [t for t in tier_appropriate_tags if t.get("size") == preferred_size_num]
            if preferred_tags:
                tier_appropriate_tags = preferred_tags
    
    # Filter tags that fit in available RAM
    fitting_tags = [t for t in tier_appropriate_tags if t.get("estimated_ram_gb", 0) <= usable_ram]
    if not fitting_tags:
        # If nothing fits, use the smallest tag
        fitting_tags = sorted(tier_appropriate_tags, key=lambda t: t.get("estimated_ram_gb", float('inf')))
        if fitting_tags:
            fitting_tags = [fitting_tags[0]]  # Just the smallest one
    
    # Calculate RAM headroom for quantization decision
    if fitting_tags:
        largest_tag = max(fitting_tags, key=lambda t: t.get("estimated_ram_gb", 0))
        ram_needed = largest_tag.get("estimated_ram_gb", 0)
        ram_headroom = usable_ram - ram_needed
    else:
        ram_headroom = 0
    
    # Sort tags by priority:
    # 1. Size (largest first, but must fit in RAM)
    # 2. Quantization preference based on RAM headroom
    def tag_priority(tag):
        size = tag.get("size", 0)
        is_full = tag.get("is_full_precision", False)
        quant = tag.get("quantization", "")
        ram = tag.get("estimated_ram_gb", 0)
        
        # Size priority (larger is better, but must fit)
        size_score = size if ram <= usable_ram else -1
        
        # Quantization priority based on RAM headroom
        if ram_headroom > 10:
            # Plenty of RAM - prefer full precision
            quant_score = 3 if is_full else (2 if quant == "Q4_K_M" else 1)
        elif ram_headroom > 5:
            # Moderate RAM - prefer Q4_K_M or full precision
            quant_score = 3 if (is_full or quant == "Q4_K_M") else 1
        else:
            # Tight RAM - prefer quantized
            quant_score = 2 if quant == "Q4_K_M" else (1 if quant else 0)
        
        return (size_score, quant_score)
    
    fitting_tags.sort(key=tag_priority, reverse=True)
    
    if fitting_tags:
        return fitting_tags[0].get("tag_name")
    
    return None


def discover_huggingface_models(query: str = "llama", limit: int = 30) -> List[Dict[str, Any]]:
    """Discover models from Hugging Face (GGUF format)."""
    # Input validation
    if not query or not isinstance(query, str):
        query = "llama"
    if limit < 1 or limit > 100:
        limit = 30
    
    models = []
    try:
        ui.print_info(f"Searching Hugging Face for '{query}'...")
        url = f"https://huggingface.co/api/models?search={query}&filter=gguf&limit={limit}"
        req = urllib.request.Request(url)
        req.add_header("User-Agent", "Docker-Model-Runner-Setup/1.0")
        
        with urllib.request.urlopen(req, timeout=10, context=get_unverified_ssl_context()) as response:
            data = json.loads(response.read())
            if isinstance(data, list):
                for model in data[:limit]:
                    model_id = model.get("id", "")
                    if model_id:
                        models.append({
                            "name": f"hf.co/{model_id}",
                            "description": model.get("pipeline_tag", "GGUF model"),
                            "source": "huggingface",
                            "downloads": model.get("downloads", 0)
                        })
    except urllib.error.URLError as e:
        ui.print_warning(f"Could not search Hugging Face: {e}")
    except (json.JSONDecodeError, ValueError, OSError) as e:
        ui.print_warning(f"Error searching Hugging Face: {e}")
    
    return models


def convert_discovered_to_modelinfo(discovered: Dict[str, Any], tier: hardware.HardwareTier) -> ModelInfo:
    """Convert a discovered model to ModelInfo format."""
    model_name = discovered["name"]
    # Extract a friendly name
    friendly_name = model_name.split("/")[-1].replace("-", " ").replace("_", " ").title()
    
    # Estimate RAM based on model name patterns
    ram_gb = 8.0  # Default
    if "70b" in model_name.lower() or "70B" in model_name.lower():
        ram_gb = 35.0
    elif "32b" in model_name.lower() or "32B" in model_name.lower():
        ram_gb = 18.0
    elif "22b" in model_name.lower() or "22B" in model_name.lower():
        ram_gb = 12.0
    elif "14b" in model_name.lower() or "14B" in model_name.lower():
        ram_gb = 8.0
    elif "8b" in model_name.lower() or "8B" in model_name.lower():
        ram_gb = 5.0
    elif "7b" in model_name.lower() or "7B" in model_name.lower():
        ram_gb = 4.0
    elif "3b" in model_name.lower() or "3B" in model_name.lower():
        ram_gb = 2.0
    elif "1.5b" in model_name.lower() or "1.5B" in model_name.lower():
        ram_gb = 1.0
    
    # Determine roles based on name
    roles = ["chat", "edit"]
    if "embed" in model_name.lower():
        roles = ["embed"]
    elif "coder" in model_name.lower() or "code" in model_name.lower():
        roles = ["chat", "edit", "autocomplete"]
    
    # Determine tier
    tiers = [hardware.HardwareTier.C]
    if ram_gb >= 35:
        tiers = [hardware.HardwareTier.S]
    elif ram_gb >= 18:
        tiers = [hardware.HardwareTier.S, hardware.HardwareTier.A]
    elif ram_gb >= 12:
        tiers = [hardware.HardwareTier.A, hardware.HardwareTier.S]
    elif ram_gb >= 8:
        tiers = [hardware.HardwareTier.B, hardware.HardwareTier.A, hardware.HardwareTier.S]
    else:
        tiers = [hardware.HardwareTier.C, hardware.HardwareTier.B, hardware.HardwareTier.A, hardware.HardwareTier.S]
    
    return ModelInfo(
        name=friendly_name,
        docker_name=model_name,
        description=discovered.get("description", "Discovered model"),
        ram_gb=ram_gb,
        context_length=32768,  # Default
        roles=roles,
        tiers=tiers,
        recommended_for=[]
    )


def discover_and_select_models(hw_info: hardware.HardwareInfo) -> List[ModelInfo]:
    """Discover available models and let user select interactively."""
    ui.print_header("🔍 Model Discovery & Selection")
    
    selected_models: List[ModelInfo] = []
    all_discovered: List[Dict[str, Any]] = []
    
    # Ask which source to search
    ui.print_info("Where would you like to search for models?")
    source_choice = ui.prompt_choice(
        "Select source:",
        ["Docker Hub (ai/ namespace)", "Hugging Face (hf.co/)", "Both"],
        default=0
    )
    
    # Search Docker Hub
    if source_choice in [0, 2]:
        print()
        search_query = input("Enter search query for Docker Hub (default: 'ai/'): ").strip() or "ai/"
        docker_models = discover_docker_hub_models(search_query)
        all_discovered.extend(docker_models)
        if docker_models:
            ui.print_success(f"Found {len(docker_models)} models on Docker Hub")
    
    # Search Hugging Face
    if source_choice in [1, 2]:
        print()
        search_query = input("Enter search query for Hugging Face (default: 'llama'): ").strip() or "llama"
        hf_models = discover_huggingface_models(search_query)
        all_discovered.extend(hf_models)
        if hf_models:
            ui.print_success(f"Found {len(hf_models)} models on Hugging Face")
    
    if not all_discovered:
        ui.print_warning("No models found. Try a different search query.")
        return []
    
    # Convert to ModelInfo and display
    print()
    ui.print_subheader("Discovered Models")
    model_infos = [convert_discovered_to_modelinfo(m, hw_info.tier) for m in all_discovered]
    
    # Filter by hardware tier
    available_models = [m for m in model_infos if hw_info.tier in m.tiers]
    
    if not available_models:
        ui.print_warning(f"No models found compatible with your hardware tier ({hw_info.tier.value})")
        ui.print_info("Showing all models anyway...")
        available_models = model_infos
    
    # Group by role
    chat_models = [m for m in available_models if "chat" in m.roles or "edit" in m.roles]
    auto_models = [m for m in available_models if "autocomplete" in m.roles]
    embed_models = [m for m in available_models if "embed" in m.roles]
    
    # Select chat/edit models
    if chat_models:
        print()
        ui.print_subheader("Chat/Edit Models")
        choices = [(m.name, f"{m.description} (~{m.ram_gb}GB) - {m.docker_name}", False) for m in chat_models]
        indices = ui.prompt_multi_choice("Select chat/edit model(s):", choices, min_selections=1)
        for i in indices:
            selected_models.append(chat_models[i])
    
    # Select autocomplete models
    if auto_models:
        print()
        if ui.prompt_yes_no("Add a dedicated autocomplete model?", default=False):
            ui.print_subheader("Autocomplete Models")
            choices = [(m.name, f"{m.description} (~{m.ram_gb}GB) - {m.docker_name}", False) for m in auto_models]
            indices = ui.prompt_multi_choice("Select autocomplete model:", choices, min_selections=1)
            for i in indices:
                if auto_models[i] not in selected_models:
                    selected_models.append(auto_models[i])
    
    # Select embedding models
    if embed_models:
        print()
        if ui.prompt_yes_no("Add an embedding model for code indexing?", default=False):
            ui.print_subheader("Embedding Models")
            choices = [(m.name, f"{m.description} (~{m.ram_gb}GB) - {m.docker_name}", False) for m in embed_models]
            indices = ui.prompt_multi_choice("Select embedding model:", choices, min_selections=1)
            for i in indices:
                if embed_models[i] not in selected_models:
                    selected_models.append(embed_models[i])
    
    return selected_models


def get_models_for_tier(tier: hardware.HardwareTier) -> List[ModelInfo]:
    """Get models available for a specific hardware tier."""
    return [m for m in MODEL_CATALOG if tier in m.tiers]


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
    unavailable_models = [
        "starcoder2",  # Not in ai/ namespace (401 error confirmed)
        "codegemma",  # Not in ai/ namespace (only in other namespaces)
        "codellama",  # Not in ai/ namespace
    ]
    
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
        "ai/llama3.2": ["3b"],
        "ai/llama3.3": ["70b"],
        "ai/llama3.1": ["70b"],
        "ai/nomic-embed-text-v1.5": [None],
        "ai/granite-4.0-h-nano": ["nano"],
        "ai/phi4": ["14b"],
    }
    
    for known_base, available_sizes in known_models.items():
        if base_name_lower == known_base.lower():
            if None in available_sizes:
                return True
            requested_size = _extract_model_size(model_lower)
            if requested_size:
                return requested_size in [s.lower() if s else None for s in available_sizes]
            return len(available_sizes) > 0
    
    # Fetch from Docker Hub API if not cached
    if not hasattr(hw_info, 'available_docker_hub_models') or not hw_info.available_docker_hub_models:
        docker_hub_models = fetch_available_models_from_docker_hub()
        if any(base_name_lower == m.lower() for m in docker_hub_models):
            return True
    
    # Last resort: Docker search
    search_base = base_name.replace("ai/", "").split(":")[0].split("/")[-1]
    variants = discover_model_variants(f"ai/{search_base}", hw_info)
    if variants:
        return any(base_name_lower == v.lower() or search_base in v.lower().replace("ai/", "")
                   for v in variants)
    
    return False


def get_curated_top_models(tier: hardware.HardwareTier, limit: int = 10, hw_info: Optional[hardware.HardwareInfo] = None) -> List[ModelInfo]:
    """Get curated top models for a hardware tier, prioritizing quality and variety.
    Excludes models from restricted countries (China, Russia) due to political conflicts.
    Only includes models that are verified to exist in Docker Model Runner.
    If not enough models for the tier, includes models from higher tiers to reach the limit."""
    # Start with models for this tier
    tier_models = get_models_for_tier(tier)
    
    # Filter out restricted models (Chinese/Russian) and models not available in Docker Hub
    tier_models = [m for m in tier_models if not is_restricted_model(m) and not is_docker_hub_unavailable(m)]
    
    # Verify models actually exist in Docker Model Runner (if hardware info provided)
    if hw_info and hw_info.docker_model_runner_available:
        ui.print_info("Verifying model availability in Docker Model Runner...")
        verified_models = []
        for model in tier_models:
            if verify_model_available(model, hw_info):
                verified_models.append(model)
            else:
                ui.print_warning(f"Skipping {model.name} - not available in Docker Model Runner")
        tier_models = verified_models
        if tier_models:
            ui.print_success(f"Found {len(tier_models)} verified models for your tier")
    
    # If we don't have enough models, include models from all tiers (filtered)
    if len(tier_models) < limit:
        all_models = [m for m in MODEL_CATALOG if not is_restricted_model(m) and not is_docker_hub_unavailable(m)]
        # Prioritize tier-compatible models, then add others
        available = tier_models.copy()
        seen_names = {m.docker_name for m in available}
        
        # Add models from other tiers that aren't already included
        for m in all_models:
            if m.docker_name not in seen_names and len(available) < limit:
                available.append(m)
                seen_names.add(m.docker_name)
    else:
        available = tier_models
    
    if not available:
        return []
    
    # Prioritize models by:
    # 1. Tier-compatible models first
    # 2. Chat/Edit models (sorted by quality/RAM descending)
    # 3. Coding-specific models (coder, code-focused)
    # 4. Autocomplete models (for speed)
    # 5. Embedding models
    
    curated = []
    seen_names = set()
    
    # Separate tier-compatible from others
    tier_compatible = [m for m in available if tier in m.tiers]
    other_models = [m for m in available if tier not in m.tiers]
    
    # 1. Top chat/edit models from tier-compatible (best quality first)
    chat_models = [m for m in tier_compatible if ("chat" in m.roles or "edit" in m.roles) and "embed" not in m.roles]
    chat_models.sort(key=lambda m: m.ram_gb, reverse=True)
    for m in chat_models[:6]:
        if m.docker_name not in seen_names:
            curated.append(m)
            seen_names.add(m.docker_name)
    
    # 2. Coding-specific models from tier-compatible
    coder_models = [m for m in tier_compatible if ("coder" in m.name.lower() or "code" in m.name.lower()) and m.docker_name not in seen_names]
    coder_models.sort(key=lambda m: m.ram_gb, reverse=True)
    for m in coder_models:
        if len(curated) < limit:
            curated.append(m)
            seen_names.add(m.docker_name)
    
    # 3. Fast autocomplete models from tier-compatible
    auto_models = [m for m in tier_compatible if "autocomplete" in m.roles and m.docker_name not in seen_names]
    auto_models.sort(key=lambda m: m.ram_gb)  # Smallest first
    for m in auto_models[:3]:
        if len(curated) < limit:
            curated.append(m)
            seen_names.add(m.docker_name)
    
    # 4. Embedding models from tier-compatible
    embed_models = [m for m in tier_compatible if "embed" in m.roles and m.docker_name not in seen_names]
    for m in embed_models[:2]:
        if len(curated) < limit:
            curated.append(m)
            seen_names.add(m.docker_name)
    
    # 5. Fill remaining slots with other tier-compatible models
    remaining_tier = [m for m in tier_compatible if m.docker_name not in seen_names]
    remaining_tier.sort(key=lambda m: m.ram_gb, reverse=True)
    for m in remaining_tier:
        if len(curated) >= limit:
            break
        curated.append(m)
        seen_names.add(m.docker_name)
    
    # 6. If still not enough, add models from other tiers (prioritize smaller ones)
    if len(curated) < limit:
        other_chat = [m for m in other_models if ("chat" in m.roles or "edit" in m.roles) and "embed" not in m.roles and m.docker_name not in seen_names]
        other_chat.sort(key=lambda m: m.ram_gb)  # Smaller first (more likely to work)
        for m in other_chat:
            if len(curated) >= limit:
                break
            curated.append(m)
            seen_names.add(m.docker_name)
    
    # 7. Fill any remaining slots
    remaining_all = [m for m in other_models if m.docker_name not in seen_names]
    remaining_all.sort(key=lambda m: m.ram_gb)  # Smaller first
    for m in remaining_all:
        if len(curated) >= limit:
            break
        curated.append(m)
        seen_names.add(m.docker_name)
    
    return curated[:limit]


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


def find_modelinfo_by_docker_hub_name(docker_hub_name: str) -> Optional[ModelInfo]:
    """Find ModelInfo object from catalog that matches a Docker Hub model name."""
    hub_name_lower = docker_hub_name.lower()
    # Extract base name (e.g., "phi4" from "ai/phi4")
    base_name = hub_name_lower.replace("ai/", "").split(":")[0]
    
    for model in MODEL_CATALOG:
        catalog_hub_name = get_docker_hub_model_name(model.docker_name).lower()
        catalog_base = catalog_hub_name.replace("ai/", "").split(":")[0]
        
        # Try exact match first
        if hub_name_lower == catalog_hub_name:
            return model
        
        # Try base name match (e.g., "phi4" matches "phi4")
        if base_name == catalog_base:
            return model
        
        # Try partial match (e.g., "phi4" in "phi4:14b")
        if base_name in catalog_base or catalog_base in base_name:
            return model
    
    return None


def get_recommended_models_by_category(hw_info: Optional[hardware.HardwareInfo] = None) -> Dict[str, List[Dict[str, Any]]]:
    """
    Get recommended models organized by category, with role information and tier filtering.
    
    Returns a dictionary mapping category names to lists of model dicts with:
    - name: Docker Hub model name (ai/model-name)
    - roles: List of roles this model supports
    - model_info: ModelInfo object if found in catalog (None if not in catalog)
    
    Limits to top 10 models per category and filters by hardware tier.
    """
    # Fetch all available models from Docker Hub
    docker_hub_models = []
    if hw_info and hasattr(hw_info, 'available_docker_hub_models') and hw_info.available_docker_hub_models:
        docker_hub_models = hw_info.available_docker_hub_models
    else:
        docker_hub_models = fetch_available_models_from_docker_hub()
    
    # Define category mappings based on model name patterns
    categories: Dict[str, List[Dict[str, Any]]] = {
        "Reasoning & Agent Models": [],
        "Coding Models": [],
        "Small/Efficient Models": [],
        "Multimodal Models": [],
        "General Chat/Instruction Models": [],
        "Embedding Models": [],
        "Safety Models": []
    }
    
    # Map models to categories based on Docker Hub names
    # Order matters - check more specific categories first
    seen_models = set()
    tier = hw_info.tier if hw_info else hardware.HardwareTier.C
    
    for model_name in docker_hub_models:
        if model_name in seen_models:
            continue
        
        # Skip restricted (Chinese/Russian) models
        if is_restricted_model_name(model_name):
            continue
        
        model_lower = model_name.lower()
        
        # Find ModelInfo from catalog to get roles and tier info
        model_info = find_modelinfo_by_docker_hub_name(model_name)
        roles = model_info.roles if model_info else []
        
        # Skip if model_info indicates it's restricted
        if model_info and is_restricted_model(model_info):
            continue
        
        # Allow models from higher tiers (they can run on lower tier hardware, just slower)
        # Only skip if model requires a tier higher than what we have
        if model_info and model_info.tiers:
            # Check if any of the model's tiers are compatible (same or lower)
            tier_order = [hardware.HardwareTier.D, hardware.HardwareTier.C, hardware.HardwareTier.B, hardware.HardwareTier.A, hardware.HardwareTier.S]
            current_tier_index = tier_order.index(tier) if tier in tier_order else 0
            model_tier_indices = [tier_order.index(t) for t in model_info.tiers if t in tier_order]
            if model_tier_indices and min(model_tier_indices) > current_tier_index + 1:
                # Model requires tier more than 1 level above current - skip
                continue
        
        # Safety Models (check first - most specific)
        if "safeguard" in model_lower:
            categories["Safety Models"].append({
                "name": model_name,
                "roles": roles,
                "model_info": model_info
            })
            seen_models.add(model_name)
        
        # Embedding Models (check before general models)
        elif any(x in model_lower for x in ["embed", "mxbai", "nomic-embed", "embeddinggemma", "all-minilm", "arctic-embed"]):
            categories["Embedding Models"].append({
                "name": model_name,
                "roles": roles,
                "model_info": model_info
            })
            seen_models.add(model_name)
        
        # Multimodal Models
        elif any(x in model_lower for x in ["gemma3n", "moondream", "smolvlm", "granite-docling", "llava", "vision", "multimodal", "vl", "visual"]):
            categories["Multimodal Models"].append({
                "name": model_name,
                "roles": roles,
                "model_info": model_info
            })
            seen_models.add(model_name)
        
        # Reasoning & Agent Models
        elif any(x in model_lower for x in ["gpt-oss", "seed-oss", "phi4", "phi-4", "phi3", "phi-3", "gemma", "gemini", "claude", "o1", "reasoning", "agent", "function", "tool", "assistant"]):
            if "safeguard" not in model_lower and "embed" not in model_lower:  # Exclude safeguard and embedding variants
                categories["Reasoning & Agent Models"].append({
                    "name": model_name,
                    "roles": roles,
                    "model_info": model_info
                })
                seen_models.add(model_name)
        
        # Coding Models
        elif any(x in model_lower for x in ["devstral", "codestral", "granite-4.0", "codellama", "codegemma", "starcoder", "code", "coder", "wizardcoder", "magicoder", "octocoder"]):
            if "embed" not in model_lower:  # Exclude embedding models
                categories["Coding Models"].append({
                    "name": model_name,
                    "roles": roles,
                    "model_info": model_info
                })
                seen_models.add(model_name)
        
        # Small/Efficient Models
        elif any(x in model_lower for x in ["smollm", "granite-4.0-h-micro", "functiongemma", "granite-4.0-nano", "granite-4.0-h-nano", "granite-4.0-h-tiny", "tiny", "nano", "micro", "small", "1b", "1.5b", "3b", "smol"]):
            if "embed" not in model_lower:  # Exclude embedding models
                categories["Small/Efficient Models"].append({
                    "name": model_name,
                    "roles": roles,
                    "model_info": model_info
                })
                seen_models.add(model_name)
        
        # General Chat/Instruction Models (catch-all for remaining chat models)
        elif any(x in model_lower for x in ["llama3", "llama2", "mistral", "granite-4.0", "gemma", "neural-chat", "vicuna", "alpaca", "chat", "instruct", "zephyr"]):
            if "embed" not in model_lower and "coder" not in model_lower and "code" not in model_lower and "vl" not in model_lower and "visual" not in model_lower:
                categories["General Chat/Instruction Models"].append({
                    "name": model_name,
                    "roles": roles,
                    "model_info": model_info
                })
                seen_models.add(model_name)
    
    # Sort and limit to top 10 models per category
    # Prioritize models with ModelInfo (from catalog) and sort by RAM if available
    for category in categories:
        models = categories[category]
        # Sort: models with ModelInfo first, then tier-compatible models, then by RAM (descending), then alphabetically
        models.sort(key=lambda m: (
            m["model_info"] is None,  # False (catalog models) first
            # Prefer tier-compatible models
            0 if (m["model_info"] and tier in m["model_info"].tiers) else 1,
            -m["model_info"].ram_gb if m["model_info"] else 0,  # Higher RAM first
            m["name"].lower()  # Alphabetical
        ))
        # Limit to top 10 models (or all if less than 10)
        categories[category] = models[:10]
    
    # Remove empty categories
    return {k: v for k, v in categories.items() if v}


def display_recommended_models_by_category(hw_info: Optional[hardware.HardwareInfo] = None):
    """Display recommended models organized by category with role indicators."""
    categories = get_recommended_models_by_category(hw_info)
    
    if not categories:
        ui.print_warning("No recommended models found")
        return
    
    print(ui.colorize("Recommended Models by Category:", ui.Colors.GREEN + ui.Colors.BOLD))
    print()
    
    for category_name, models in categories.items():
        print(category_name)
        for model_dict in models:
            model_name = model_dict["name"]
            roles = model_dict["roles"]
            if roles:
                roles_str = ", ".join(roles)
                print(f"-{model_name} (roles: {roles_str})")
            else:
                print(f"-{model_name}")
        print()


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
    - Model diversity (max 1 per family)
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
    
    # Check: Model diversity
    families = {}
    for model in models:
        docker_name = model.docker_name.replace("ai/", "").replace("ai.docker.com/", "")
        base_family = docker_name.split("/")[-1].split(":")[0].split("-")[0]
        
        # Normalize family
        if "llama" in base_family.lower():
            family_key = "llama"
        elif "granite" in base_family.lower():
            family_key = "granite"
        else:
            family_key = base_family.lower()
        
        if family_key in families:
            warnings.append(
                f"Multiple models from {family_key} family detected. "
                f"Consider diversifying for better capability coverage."
            )
        else:
            families[family_key] = model
    
    # Check: Always include embedding model
    has_embed = any("embed" in m.roles for m in models)
    if not has_embed:
        warnings.append("No embedding model selected. Code indexing (@Codebase) will not work.")
    
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
    
    # Fetch uncached models concurrently
    ui.print_info(f"Fetching tags for {len(uncached_models)} model(s) concurrently...")
    
    def fetch_single_model(model_name: str) -> Tuple[str, List[Dict[str, Any]]]:
        """Fetch tags for a single model."""
        try:
            tags = discover_model_tags(model_name, hw_info, use_cache=False)
            return (model_name, tags)
        except Exception as e:
            ui.print_warning(f"Error fetching tags for {model_name}: {e}")
            return (model_name, [])
    
    # Use ThreadPoolExecutor for concurrent fetching
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        # Submit all tasks
        future_to_model = {
            executor.submit(fetch_single_model, model_name): model_name
            for model_name in uncached_models
        }
        
        # Collect results as they complete
        completed = 0
        for future in as_completed(future_to_model):
            completed += 1
            model_name, tags = future.result()
            results[model_name] = tags
            
            # Show progress
            if len(uncached_models) > 3:
                ui.print_info(f"  Progress: {completed}/{len(uncached_models)} models fetched")
    
    return results


def select_preset(hw_info: hardware.HardwareInfo) -> Optional[str]:
    """
    Select a quick start preset for model configuration.
    
    Presets:
    - Balanced: General + coding + embeddings (default portfolio)
    - Coding Focus: Emphasize coding models
    - Minimal: Fastest, smallest models
    - Custom: Manual selection
    
    Args:
        hw_info: Hardware information
    
    Returns:
        Preset name or None for custom
    """
    ui.print_subheader("Quick Start Presets")
    print()
    ui.print_info("Select a preset configuration, or choose Custom for manual selection:")
    print()
    
    presets = [
        ("Balanced", "General chat + coding + embeddings (recommended)"),
        ("Coding Focus", "Emphasize coding models for development"),
        ("Minimal", "Fastest, smallest models for quick responses"),
        ("Custom", "Manual selection with full control")
    ]
    
    for i, (name, desc) in enumerate(presets):
        marker = ui.colorize("●", ui.Colors.GREEN) if i == 0 else ui.colorize("○", ui.Colors.DIM)
        print(f"  {marker} [{i + 1}] {ui.colorize(name, ui.Colors.BOLD)}")
        print(f"      {ui.colorize(desc, ui.Colors.DIM)}")
    
    print()
    
    while True:
        response = input(f"  Enter choice (1-{len(presets)}) [1]: ").strip()
        if not response:
            return "Balanced"
        try:
            idx = int(response) - 1
            if 0 <= idx < len(presets):
                preset_name = presets[idx][0]
                if preset_name == "Custom":
                    return None
                return preset_name
        except ValueError:
            pass
        ui.print_warning(f"Please enter a number between 1 and {len(presets)}")


def ensure_model_diversity(selected_models: List[ModelInfo]) -> List[ModelInfo]:
    """
    Ensure model diversity: max 1 per family, balance capabilities, always include embed.
    
    Args:
        selected_models: List of selected models
    
    Returns:
        Filtered list with diversity rules applied
    """
    if not selected_models:
        return []
    
    # Group models by family (extract base name)
    families_seen = {}
    diverse_models = []
    has_embed = False
    
    for model in selected_models:
        # Extract family name (e.g., "llama" from "llama3.3")
        docker_name = model.docker_name.replace("ai/", "").replace("ai.docker.com/", "")
        base_family = docker_name.split("/")[-1].split(":")[0].split("-")[0]
        
        # Normalize family names
        if "llama" in base_family.lower():
            family_key = "llama"
        elif "granite" in base_family.lower():
            family_key = "granite"
        elif "phi" in base_family.lower():
            family_key = "phi"
        elif "codestral" in base_family.lower() or "devstral" in base_family.lower():
            family_key = "mistral_code"
        elif "embed" in base_family.lower() or "nomic" in base_family.lower():
            family_key = "embed"
            has_embed = True
        else:
            family_key = base_family.lower()
        
        # Check if we already have a model from this family
        if family_key not in families_seen:
            families_seen[family_key] = model
            diverse_models.append(model)
        else:
            # Keep the one with higher RAM (better quality)
            existing = families_seen[family_key]
            if model.ram_gb > existing.ram_gb:
                diverse_models.remove(existing)
                diverse_models.append(model)
                families_seen[family_key] = model
    
    # Ensure we have at least one embedding model
    if not has_embed:
        # Find an embedding model from catalog
        embed_models = [m for m in MODEL_CATALOG if "embed" in m.roles]
        if embed_models:
            # Pick smallest embedding model that fits
            embed_models.sort(key=lambda m: m.ram_gb)
            for embed_model in embed_models:
                if embed_model not in diverse_models:
                    diverse_models.append(embed_model)
                    break
    
    return diverse_models


def generate_portfolio_recommendation(hw_info: hardware.HardwareInfo) -> List[ModelInfo]:
    """
    Generate portfolio-based model recommendations for hardware tier.
    
    Portfolio allocation (CONSERVATIVE for proper headroom):
    - Primary model: 50% RAM budget (main workhorse - conservative allocation for stability)
    - Specialized: 30% RAM budget (coding, reasoning, vision - increased for balance)
    - Utility: 3% RAM budget (embeddings, small helpers - minimal, embeddings are small)
    - Reserve: 17% free RAM (generous reserve for OS, multiple models, browser, and other apps)
    
    Tier-specific portfolios (DOWNGRADED - one size smaller for stability):
    - Tier S (>64GB): 34B reasoning (Q4) + 22B coding (Q5) + 13B multimodal (Q5) + embed
    - Tier A (32-64GB): 34B reasoning (Q4) + 13B coding (Q5) + 7B multimodal (Q4) + embed
    - Tier B (>24-32GB): 13B general (Q4) + 7B coding (Q4) + 3B multimodal (Q4) + embed
    - Tier C (16-24GB): 7B general (Q4) + 3B coding (Q4) + 1B utility (Q4) + embed
    - Tier D (<16GB): Unsupported - minimum 16GB RAM required
    
    Args:
        hw_info: Hardware information
    
    Returns:
        List of recommended ModelInfo objects with selected variants
    """
    usable_ram = hw_info.get_estimated_model_memory()
    
    # Calculate RAM budgets (conservative for proper headroom)
    primary_budget = usable_ram * 0.50  # Reduced to 50% for stability and headroom
    specialized_budget = usable_ram * 0.30  # Increased to 30% for balance
    utility_budget = usable_ram * 0.03  # Kept at 3% (embeddings are small)
    
    recommended = []
    
    # Tier-specific model selection
    if hw_info.tier == hardware.HardwareTier.S:
        # Tier S: 34B reasoning (Q4) + 22B coding (Q5) + 13B multimodal (Q5) + embed
        # Primary: 34B reasoning model
        primary_result = discover_best_model_by_criteria(34.0, "reasoning", primary_budget, hw_info)
        if primary_result:
            model_name, variant = primary_result
            model_info = ModelInfo(
                name=get_display_name_from_model(model_name, "reasoning", variant),
                docker_name=f"ai/{model_name}",
                description="34B reasoning model",
                ram_gb=calculate_model_ram(34.0, "Q4"),
                context_length=131072,
                roles=["chat", "edit", "agent"],
                tiers=[hardware.HardwareTier.S],
                base_model_name=model_name,
                selected_variant=variant
            )
            recommended.append(model_info)
        
        # Specialized: 22B coding
        coding_result = discover_best_model_by_criteria(22.0, "coding", specialized_budget, hw_info)
        if coding_result:
            model_name, variant = coding_result
            model_info = ModelInfo(
                name=get_display_name_from_model(model_name, "coding", variant),
                docker_name=f"ai/{model_name}",
                description="22B coding model",
                ram_gb=calculate_model_ram(22.0, "Q5"),
                context_length=131072,
                roles=["chat", "edit", "autocomplete"],
                tiers=[hardware.HardwareTier.S],
                base_model_name=model_name,
                selected_variant=variant
            )
            recommended.append(model_info)
        
        # Multimodal: 13B
        multimodal_result = discover_best_model_by_criteria(13.0, "multimodal", specialized_budget, hw_info)
        if multimodal_result:
            model_name, variant = multimodal_result
            model_info = ModelInfo(
                name=get_display_name_from_model(model_name, "multimodal", variant),
                docker_name=f"ai/{model_name}",
                description="13B multimodal model",
                ram_gb=calculate_model_ram(13.0, "Q5"),
                context_length=131072,
                roles=["chat", "edit"],
                tiers=[hardware.HardwareTier.S],
                base_model_name=model_name,
                selected_variant=variant
            )
            recommended.append(model_info)
    
    elif hw_info.tier == hardware.HardwareTier.A:
        # Tier A: 34B reasoning (Q4) + 13B coding (Q5) + 7B multimodal (Q4) + embed
        primary_result = discover_best_model_by_criteria(34.0, "reasoning", primary_budget, hw_info)
        if primary_result:
            model_name, variant = primary_result
            model_info = ModelInfo(
                name=get_display_name_from_model(model_name, "reasoning", variant),
                docker_name=f"ai/{model_name}",
                description="34B reasoning model",
                ram_gb=calculate_model_ram(34.0, "Q4"),
                context_length=131072,
                roles=["chat", "edit", "agent"],
                tiers=[hardware.HardwareTier.A],
                base_model_name=model_name,
                selected_variant=variant
            )
            recommended.append(model_info)
        
        coding_result = discover_best_model_by_criteria(13.0, "coding", specialized_budget, hw_info)
        if coding_result:
            model_name, variant = coding_result
            model_info = ModelInfo(
                name=get_display_name_from_model(model_name, "coding", variant),
                docker_name=f"ai/{model_name}",
                description="13B coding model",
                ram_gb=calculate_model_ram(13.0, "Q5"),
                context_length=131072,
                roles=["chat", "edit", "autocomplete"],
                tiers=[hardware.HardwareTier.A],
                base_model_name=model_name,
                selected_variant=variant
            )
            recommended.append(model_info)
        
        multimodal_result = discover_best_model_by_criteria(7.0, "multimodal", specialized_budget, hw_info)
        if multimodal_result:
            model_name, variant = multimodal_result
            model_info = ModelInfo(
                name=get_display_name_from_model(model_name, "multimodal", variant),
                docker_name=f"ai/{model_name}",
                description="7B multimodal model",
                ram_gb=calculate_model_ram(7.0, "Q4"),
                context_length=16384,
                roles=["chat", "edit"],
                tiers=[hardware.HardwareTier.A],
                base_model_name=model_name,
                selected_variant=variant
            )
            recommended.append(model_info)
    
    elif hw_info.tier == hardware.HardwareTier.B:
        # Tier B: 13B general (Q4) + 7B coding (Q4) + 3B multimodal (Q4) + embed
        primary_result = discover_best_model_by_criteria(13.0, "general", primary_budget, hw_info)
        if primary_result:
            model_name, variant = primary_result
            model_info = ModelInfo(
                name=get_display_name_from_model(model_name, "general", variant),
                docker_name=f"ai/{model_name}",
                description="13B general model",
                ram_gb=calculate_model_ram(13.0, "Q4"),
                context_length=131072,
                roles=["chat", "edit"],
                tiers=[hardware.HardwareTier.B],
                base_model_name=model_name,
                selected_variant=variant
            )
            recommended.append(model_info)
        
        coding_result = discover_best_model_by_criteria(7.0, "coding", specialized_budget, hw_info)
        if coding_result:
            model_name, variant = coding_result
            model_info = ModelInfo(
                name=get_display_name_from_model(model_name, "coding", variant),
                docker_name=f"ai/{model_name}",
                description="7B coding model",
                ram_gb=calculate_model_ram(7.0, "Q4"),
                context_length=16384,
                roles=["chat", "edit", "autocomplete"],
                tiers=[hardware.HardwareTier.B],
                base_model_name=model_name,
                selected_variant=variant
            )
            recommended.append(model_info)
        
        multimodal_result = discover_best_model_by_criteria(3.0, "multimodal", specialized_budget, hw_info)
        if multimodal_result:
            model_name, variant = multimodal_result
            model_info = ModelInfo(
                name=get_display_name_from_model(model_name, "multimodal", variant),
                docker_name=f"ai/{model_name}",
                description="3B multimodal model",
                ram_gb=calculate_model_ram(3.0, "Q4"),
                context_length=32768,
                roles=["chat", "edit"],
                tiers=[hardware.HardwareTier.B],
                base_model_name=model_name,
                selected_variant=variant
            )
            recommended.append(model_info)
    
    elif hw_info.tier == hardware.HardwareTier.C:
        # Tier C: 7B general (Q4) + 3B coding (Q4) + 1B utility (Q4) + embed
        primary_result = discover_best_model_by_criteria(7.0, "general", primary_budget, hw_info)
        if primary_result:
            model_name, variant = primary_result
            model_info = ModelInfo(
                name=get_display_name_from_model(model_name, "general", variant),
                docker_name=f"ai/{model_name}",
                description="7B general model",
                ram_gb=calculate_model_ram(7.0, "Q4"),
                context_length=131072,
                roles=["chat", "edit"],
                tiers=[hardware.HardwareTier.C],
                base_model_name=model_name,
                selected_variant=variant
            )
            recommended.append(model_info)
        
        coding_result = discover_best_model_by_criteria(3.0, "coding", specialized_budget, hw_info)
        if coding_result:
            model_name, variant = coding_result
            model_info = ModelInfo(
                name=get_display_name_from_model(model_name, "coding", variant),
                docker_name=f"ai/{model_name}",
                description="3B coding model",
                ram_gb=calculate_model_ram(3.0, "Q4"),
                context_length=32768,
                roles=["chat", "edit", "autocomplete"],
                tiers=[hardware.HardwareTier.C],
                base_model_name=model_name,
                selected_variant=variant
            )
            recommended.append(model_info)
        
        utility_result = discover_best_model_by_criteria(1.0, "coding", utility_budget, hw_info)
        if utility_result:
            model_name, variant = utility_result
            model_info = ModelInfo(
                name=get_display_name_from_model(model_name, "utility", variant),
                docker_name=f"ai/{model_name}",
                description="1B utility model",
                ram_gb=calculate_model_ram(1.0, "Q4"),
                context_length=2048,
                roles=["chat", "edit"],
                tiers=[hardware.HardwareTier.C],
                base_model_name=model_name,
                selected_variant=variant
            )
            recommended.append(model_info)
    
    else:  # Tier D - should never be reached (minimum 16GB required)
        # Tier D (<16GB) is unsupported - hardware detection should have raised an error
        ui.print_error("Tier D hardware detected - this should not be possible")
        ui.print_error("Minimum 16GB RAM is required. Please upgrade your hardware.")
        raise ValueError("Tier D hardware is unsupported - minimum 16GB RAM required")
    
    # Always add embedding model
    # Embedding models typically don't have variants, so use catalog models directly
    embed_models = [m for m in MODEL_CATALOG if "embed" in m.roles]
    
    # Try to find a suitable embedding model that fits in utility budget
    embed_model = None
    for model in embed_models:
        if model.ram_gb <= utility_budget and hw_info.tier in model.tiers:
            embed_model = model
            break
    
    # If no catalog model fits, try variant discovery as fallback
    if not embed_model:
        embed_result = discover_best_model_by_criteria(None, "embedding", utility_budget, hw_info)
        if embed_result:
            model_name, variant = embed_result
            embed_model = ModelInfo(
                name=get_display_name_from_model(model_name, "embedding", variant),
                docker_name=f"ai/{model_name}",
                description="Embedding model",
                ram_gb=calculate_model_ram(0.3, "Q4"),  # Small embedding model
                context_length=8192,
                roles=["embed"],
                tiers=[hw_info.tier],
                base_model_name=model_name,
                selected_variant=variant
            )
    
    if embed_model:
        # Create a copy to avoid modifying the catalog
        embed_info = ModelInfo(
            name=embed_model.name,
            docker_name=embed_model.docker_name,
            description=embed_model.description,
            ram_gb=embed_model.ram_gb,
            context_length=embed_model.context_length,
            roles=embed_model.roles,
            tiers=embed_model.tiers,
            base_model_name=embed_model.base_model_name,
            selected_variant=embed_model.selected_variant
        )
        recommended.append(embed_info)
    
    # Apply diversity rules
    recommended = ensure_model_diversity(recommended)
    
    # Update RAM estimates based on actual selected variants
    for model in recommended:
        if model.selected_variant and model.base_model_name:
            tags = discover_model_tags(model.base_model_name, hw_info, use_cache=True)
            for tag in tags:
                if tag.get("tag_name") == model.selected_variant:
                    model.ram_gb = tag.get("estimated_ram_gb", model.ram_gb)
                    break
    
    return recommended


def get_tier_optimized_recommendation(hw_info: hardware.HardwareInfo) -> Dict[str, str]:
    """
    Get tier-optimized recommendation - best model from each relevant category.
    
    Returns a dictionary mapping category names to Docker Hub model names (ai/model-name).
    Selects one model from each relevant category based on hardware tier and RAM constraints.
    """
    categories = get_recommended_models_by_category(hw_info)
    recommendation: Dict[str, str] = {}
    
    if not categories:
        return recommendation
    
    # Priority order for categories (most important first)
    category_priority = [
        "Coding Models",
        "Embedding Models",
        "General Chat/Instruction Models",
        "Reasoning & Agent Models",
        "Small/Efficient Models",
        "Multimodal Models",
        "Safety Models"
    ]
    
    total_ram_used = 0.0
    available_ram = hw_info.ram_gb
    
    # Select best model from each category, considering RAM constraints
    for category in category_priority:
        if category not in categories:
            continue
        
        models = categories[category]
        if not models:
            continue
        
        # Find best model that fits in remaining RAM
        best_model = None
        for model_dict in models:
            model_info = model_dict.get("model_info")
            if model_info:
                model_ram = model_info.ram_gb
                # Check if this model fits
                if total_ram_used + model_ram <= available_ram * 0.9:  # Leave 10% buffer
                    if best_model is None or model_ram > best_model[1]:
                        best_model = (model_dict["name"], model_ram, model_info)
            else:
                # Model not in catalog, estimate RAM based on category
                estimated_ram = 4.0  # Default estimate
                if "embed" in category.lower():
                    estimated_ram = 0.5
                elif "small" in category.lower() or "efficient" in category.lower():
                    estimated_ram = 2.0
                
                if total_ram_used + estimated_ram <= available_ram * 0.9:
                    if best_model is None:
                        best_model = (model_dict["name"], estimated_ram, None)
        
        if best_model:
            recommendation[category] = best_model[0]
            total_ram_used += best_model[1]
    
    return recommendation


def _generate_model_description(model_name: str, roles: List[str], category: str) -> str:
    """Generate a descriptive text for a model based on its name and category."""
    name_lower = model_name.lower()
    base_name = model_name.replace("ai/", "").replace("-", " ").replace("_", " ").title()
    
    # Try to infer model characteristics from name
    desc_parts = []
    model_type = ""
    
    # Model type indicators (most specific first)
    if "gpt-oss" in name_lower:
        model_type = "OpenAI's open-weight reasoning model"
    elif "seed-oss" in name_lower:
        model_type = "Seed AI's reasoning model"
    elif "granite" in name_lower:
        model_type = "IBM's Granite coding model"
    elif "devstral" in name_lower or "codestral" in name_lower:
        model_type = "Mistral's coding model"
    elif "phi" in name_lower:
        model_type = "Microsoft's reasoning model"
    elif "llama" in name_lower:
        model_type = "Meta's Llama model"
    elif "mistral" in name_lower:
        model_type = "Mistral AI model"
    elif "gemma" in name_lower and "function" in name_lower:
        model_type = "Google's function-calling model"
    elif "gemma" in name_lower:
        model_type = "Google's Gemma model"
    elif "granite" in name_lower:
        model_type = "IBM's Granite model"
    elif "smollm" in name_lower or "smol" in name_lower:
        model_type = "Lightweight efficient model"
    elif "functiongemma" in name_lower:
        model_type = "Function-calling model"
    elif "embed" in name_lower or "nomic-embed" in name_lower:
        model_type = "Embedding model"
    elif "safeguard" in name_lower:
        model_type = "Safety reasoning model"
    elif "moondream" in name_lower:
        model_type = "Vision-language model"
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
    
    # Category-specific use case (only if not redundant)
    category_lower = category.lower()
    if "reasoning" in category_lower or "agent" in category_lower:
        if "reasoning" not in model_type.lower() and "agent" not in model_type.lower():
            desc_parts.append("for reasoning and agent tasks")
    elif "coding" in category_lower:
        if "coding" not in model_type.lower() and "code" not in model_type.lower():
            desc_parts.append("for code generation")
    elif "multimodal" in category_lower:
        if "vision" not in model_type.lower() and "multimodal" not in model_type.lower():
            desc_parts.append("supports text, image, and video")
    
    # RAM estimate based on category and size
    ram_estimate = 4.0
    if "embed" in category_lower or "embed" in name_lower:
        ram_estimate = 0.5
    elif "small" in category_lower or "efficient" in category_lower or "smol" in name_lower:
        ram_estimate = 2.0
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


def customize_from_categories(hw_info: hardware.HardwareInfo) -> List[ModelInfo]:
    """
    Let user customize model selection by picking from category lists.
    
    Returns a list of ModelInfo objects for selected models.
    """
    categories = get_recommended_models_by_category(hw_info)
    
    if not categories:
        ui.print_warning("No models available for customization")
        return []
    
    ui.print_subheader("Customize Model Selection")
    ui.print_info("Select models from each category (press Enter to skip a category):")
    print()
    
    selected_models: List[ModelInfo] = []
    seen_names = set()
    
    for category_name, models in categories.items():
        if not models:
            continue
        
        print(ui.colorize(f"{category_name}:", ui.Colors.CYAN + ui.Colors.BOLD))
        
        # Prepare choices
        choices = []
        for i, model_dict in enumerate(models, 1):
            model_name = model_dict["name"]
            roles = model_dict.get("roles", [])
            model_info = model_dict.get("model_info")
            
            if model_info:
                # Use catalog description
                desc = f"{model_info.description} | ~{model_info.ram_gb:.1f}GB RAM"
                if roles:
                    desc += f" | roles: {', '.join(roles)}"
            else:
                # Generate description from model name
                desc = _generate_model_description(model_name, roles, category_name)
            
            choices.append((model_name, desc, False))
        
        # Add "Skip" option
        choices.append(("Skip", "Skip this category", False))
        
        # Let user select
        indices = ui.prompt_multi_choice(
            f"Select models from {category_name} (or 's' to skip):",
            choices,
            min_selections=0
        )
        
        # Process selections
        for idx in indices:
            if idx < len(models):  # Not the "Skip" option
                model_dict = models[idx]
                model_name = model_dict["name"]
                model_info = model_dict.get("model_info")
                
                # If we have ModelInfo, use it; otherwise create a basic one
                if model_info:
                    # Check if this is a base model that needs variant selection
                    base_name = model_info.base_model_name or get_docker_hub_model_name(model_info.docker_name).replace("ai/", "")
                    if not model_info.selected_variant and base_name:
                        # Discover and select best variant
                        tags = discover_model_tags(base_name, hw_info)
                        if tags:
                            selected_tag = select_best_variant(tags, hw_info)
                            if selected_tag:
                                model_info.selected_variant = selected_tag
                                model_info.base_model_name = base_name
                                # Update RAM estimate based on selected variant
                                for tag in tags:
                                    if tag.get("tag_name") == selected_tag:
                                        model_info.ram_gb = tag.get("estimated_ram_gb", model_info.ram_gb)
                                        break
                    
                    if model_info.docker_name not in seen_names:
                        selected_models.append(model_info)
                        seen_names.add(model_info.docker_name)
                else:
                    # Create a basic ModelInfo for models not in catalog
                    hub_name = get_docker_hub_model_name(model_name)
                    base_name = hub_name.replace("ai/", "")
                    
                    # Discover and select best variant
                    tags = discover_model_tags(base_name, hw_info)
                    selected_tag = None
                    estimated_ram = 4.0
                    if tags:
                        selected_tag = select_best_variant(tags, hw_info)
                        if selected_tag:
                            for tag in tags:
                                if tag.get("tag_name") == selected_tag:
                                    estimated_ram = tag.get("estimated_ram_gb", 4.0)
                                    break
                    
                    basic_model = ModelInfo(
                        name=model_name.replace("ai/", "").replace("-", " ").title(),
                        docker_name=hub_name,
                        description=f"Docker Hub model: {model_name}",
                        ram_gb=estimated_ram,
                        context_length=8192,
                        roles=model_dict.get("roles", ["chat"]),
                        tiers=[hw_info.tier],
                        base_model_name=base_name,
                        selected_variant=selected_tag
                    )
                    if basic_model.docker_name not in seen_names:
                        selected_models.append(basic_model)
                        seen_names.add(basic_model.docker_name)
        
        print()
    
    return selected_models


def get_top_models_by_role(tier: hardware.HardwareTier, hw_info: Optional[hardware.HardwareInfo] = None) -> Dict[str, List[ModelInfo]]:
    """
    Get top models for each role, automatically selecting variants based on hardware tier.
    
    Returns a dictionary mapping role names to lists of models, sorted by quality within each role.
    Automatically picks the best size variant (3B, 8B, 14B, 70B, etc.) for the tier.
    
    Uses docker search to discover available variants and verify models exist.
    """
    # Get all models for this tier
    available = get_models_for_tier(tier)
    
    # Filter out restricted models and unavailable models
    available = [m for m in available if not is_restricted_model(m) and not is_docker_hub_unavailable(m)]
    
    # Verify models exist using multiple methods (Docker Hub API, docker search, etc.)
    if hw_info:
        verified_available = []
        ui.print_info("Verifying model availability and discovering variants...")
        for model in available:
            if verify_model_available(model, hw_info):
                verified_available.append(model)
            else:
                # Try variant discovery as a fallback
                variants = discover_model_variants(model.docker_name, hw_info)
                if variants:
                    # Model exists in some form, keep it
                    verified_available.append(model)
        available = verified_available
        if available:
            ui.print_success(f"Verified {len(available)} model(s) available for your tier")
    
    # Group models by role
    models_by_role: Dict[str, List[ModelInfo]] = {
        "chat": [],
        "edit": [],
        "autocomplete": [],
        "embed": [],
        "agent": []
    }
    
    # Categorize models by their roles
    for model in available:
        for role in model.roles:
            if role in models_by_role:
                models_by_role[role].append(model)
    
    # For each role, sort by quality (RAM descending) to get best models first
    # This automatically selects the best variant for the tier
    for role in models_by_role:
        models_by_role[role].sort(key=lambda m: m.ram_gb, reverse=True)
    
    return models_by_role


def get_recommended_models(tier: hardware.HardwareTier, hw_info: Optional[hardware.HardwareInfo] = None) -> Dict[str, ModelInfo]:
    """Get recommended models for each role based on tier and chip capabilities.
    Excludes models from restricted countries (China, Russia) due to political conflicts.
    Only includes models verified to exist in Docker Model Runner.
    Enhanced to consider chip performance for better recommendations."""
    recommendations: Dict[str, ModelInfo] = {}
    
    available = get_models_for_tier(tier)
    
    # Filter out restricted models (Chinese/Russian) and models not available in Docker Hub
    available = [m for m in available if not is_restricted_model(m) and not is_docker_hub_unavailable(m)]
    
    # Verify models actually exist in Docker Model Runner (if hardware info provided)
    if hw_info and hw_info.docker_model_runner_available:
        verified_available = []
        for model in available:
            if verify_model_available(model, hw_info):
                verified_available.append(model)
        available = verified_available
    
    # Determine if this is a high-end chip that can handle larger models
    is_high_end_chip = False
    if hw_info and hw_info.has_apple_silicon and hw_info.apple_chip_model:
        high_end_patterns = ["M3 Pro", "M3 Max", "M3 Ultra", "M4 Pro", "M4 Max", "M4 Ultra"]
        is_high_end_chip = any(pattern in hw_info.apple_chip_model for pattern in high_end_patterns)
    
    # Chat/Edit model (primary) - prioritize best quality models
    chat_models = [m for m in available if "chat" in m.roles or "edit" in m.roles]
    if chat_models:
        # For high-end chips, prefer larger models even if at tier boundary
        # Sort by RAM (descending) to get best quality within tier
        chat_models.sort(key=lambda m: m.ram_gb, reverse=True)
        
        # For Tier A with high-end chips and 40GB+ RAM, prefer larger models
        if tier == hardware.HardwareTier.A and is_high_end_chip and hw_info and hw_info.ram_gb >= 40:
            # Prefer models that are close to Tier S quality
            # Look for models that are 20GB+ (like devstral:27b, codestral:22b)
            large_models = [m for m in chat_models if m.ram_gb >= 20]
            if large_models:
                recommendations["chat"] = large_models[0]
            else:
                recommendations["chat"] = chat_models[0]
        else:
            recommendations["chat"] = chat_models[0]
    
    # Autocomplete model (fast) - balance speed and quality
    auto_models = [m for m in available if "autocomplete" in m.roles]
    if auto_models:
        # For high-end chips, we can use slightly larger autocomplete models for better quality
        if is_high_end_chip and tier in (hardware.HardwareTier.S, hardware.HardwareTier.A):
            # Prefer medium-sized autocomplete models (5-15GB) for better quality
            medium_auto = [m for m in auto_models if 5 <= m.ram_gb <= 15]
            if medium_auto:
                medium_auto.sort(key=lambda m: m.ram_gb, reverse=True)  # Best quality first
                recommendations["autocomplete"] = medium_auto[0]
            else:
                # Fallback to smallest for speed
                auto_models.sort(key=lambda m: m.ram_gb)
                recommendations["autocomplete"] = auto_models[0]
        else:
            # For other systems, prioritize speed (smallest)
            auto_models.sort(key=lambda m: m.ram_gb)
            recommendations["autocomplete"] = auto_models[0]
    
    # Embedding model (excluding restricted ones)
    embed_models = [m for m in available if "embed" in m.roles]
    if embed_models:
        recommendations["embed"] = embed_models[0]
    
    return recommendations


def select_models(hw_info: hardware.HardwareInfo) -> List[ModelInfo]:
    """
    Interactive model selection with new UX flow:
    1. Show categories with top models
    2. Show tier-optimized recommendation
    3. User confirms or customizes
    """
    # Input validation
    if not hw_info:
        raise ValueError("hw_info is required")
    
    ui.print_header("🤖 Model Selection")
    
    ui.print_info(f"Hardware Tier: {ui.colorize(hw_info.tier.value, ui.Colors.GREEN + ui.Colors.BOLD)}")
    ui.print_info(f"Available RAM: ~{hw_info.ram_gb:.1f}GB")
    print()
    
    # Step 1: Get portfolio recommendation
    recommended_models = generate_portfolio_recommendation(hw_info)
    
    if not recommended_models:
        ui.print_warning("Could not generate recommendations for your hardware tier.")
        ui.print_info("You can try the model discovery feature to search for available models.")
        if ui.prompt_yes_no("Would you like to search for available models?", default=False):
            return discover_and_select_models(hw_info)
        return []
    
    # Step 2: Display recommended selection
    ui.print_subheader("Recommended Selection (Auto-selected for your tier)")
    print()
    
    # Display recommended models
    total_ram = sum(m.ram_gb for m in recommended_models)
    if recommended_models:
        for model in recommended_models:
            roles_str = ", ".join(model.roles) if model.roles else "general"
            variant_info = ""
            if model.selected_variant:
                variant_info = f" ({model.selected_variant})"
            print(f"  • {model.name}{variant_info} ({roles_str}) - ~{model.ram_gb:.1f}GB RAM")
        print(f"  Total RAM: ~{total_ram:.1f}GB")
        print()
    
    # Step 4: User confirms, customizes, or cancels
    choice = ui.prompt_choice(
        "What would you like to do?",
        ["Use recommended selection", "Customize selection", "Cancel setup"],
        default=0
    )
    
    if choice == 0:
        return recommended_models
    elif choice == 1:
        return customize_from_categories(hw_info)
    else:
        ui.print_info("Setup cancelled.")
        return []


def pull_models_docker(model_list: List[ModelInfo], hw_info: hardware.HardwareInfo) -> List[ModelInfo]:
    """Pull selected models using Docker Model Runner."""
    # Input validation
    if not model_list:
        ui.print_warning("No models provided to pull")
        return []
    if not hw_info:
        raise ValueError("hw_info is required")
    
    ui.print_header("📥 Downloading Models via Docker Model Runner")
    
    if not hw_info.docker_model_runner_available:
        ui.print_warning("Docker Model Runner not available. Skipping model download.")
        ui.print_info("Models will be downloaded when you first use them in Continue.dev.")
        print()
        ui.print_info("To manually pull models later, run:")
        for model in model_list:
            print(ui.colorize(f"    docker model pull {model.docker_name}", ui.Colors.CYAN))
        return model_list
    
    successfully_pulled: List[ModelInfo] = []
    
    # Estimate total download size
    total_download_gb = sum(m.ram_gb * 0.5 for m in model_list)  # Rough estimate: model size is ~50% of RAM needed
    ui.print_info(f"Estimated total download: ~{total_download_gb:.1f}GB")
    ui.print_info(f"Models will use Metal GPU acceleration on Apple Silicon")
    print()
    
    for i, model in enumerate(model_list, 1):
        ui.print_step(i, len(model_list), f"Pulling {model.name}...")
        ui.print_info(f"Model: {model.docker_name}")
        ui.print_info(f"Estimated download: ~{model.ram_gb * 0.5:.1f}GB")
        ui.print_info(f"Memory required: ~{model.ram_gb:.1f}GB")
        print()
        
        # Determine model name format and handle legacy ai.docker.com format
        # Docker Model Runner supports:
        # - Docker Hub: ai/model-name (e.g., ai/llama3.2)
        # - Hugging Face: hf.co/username/model-name
        # Legacy format: ai.docker.com/org/model:tag (convert directly to ai/model-name)
        model_name_to_pull = model.docker_name
        
        # Check if we have a selected variant that needs to be applied
        base_model_name = None
        if model.selected_variant:
            # We have a selected variant, use it
            base_model_name = model.base_model_name or get_docker_hub_model_name(model.docker_name).replace("ai/", "").split(":")[0]
            if base_model_name:
                model_name_to_pull = f"ai/{base_model_name}:{model.selected_variant}"
        elif model.base_model_name:
            # We have a base model name but no variant selected yet - discover and select
            base_model_name = model.base_model_name
            ui.print_info(f"Discovering variants for {model.name}...")
            tags = discover_model_tags(base_model_name, hw_info)
            if tags:
                selected_tag = select_best_variant(tags, hw_info)
                if selected_tag:
                    model.selected_variant = selected_tag
                    model_name_to_pull = f"ai/{base_model_name}:{selected_tag}"
                    ui.print_success(f"Auto-selected variant: {selected_tag} (best for your hardware)")
                    # Update RAM estimate
                    for tag in tags:
                        if tag.get("tag_name") == selected_tag:
                            model.ram_gb = tag.get("estimated_ram_gb", model.ram_gb)
                            break
                else:
                    ui.print_warning(f"Could not select variant for {model.name}, using base model")
                    model_name_to_pull = f"ai/{base_model_name}"
            else:
                ui.print_warning(f"Could not discover variants for {model.name}, using base model")
                model_name_to_pull = f"ai/{base_model_name}"
        else:
            # Try to extract base name from docker_name if it's in ai/ format
            if model.docker_name.startswith("ai/"):
                base_model_name = model.docker_name.replace("ai/", "").split(":")[0]
                # Only try variant discovery if it looks like a base model (no size variant in name)
                if not re.search(r'[0-9]+\s*b', base_model_name, re.IGNORECASE):
                    ui.print_info(f"Discovering variants for {model.name}...")
                    tags = discover_model_tags(base_model_name, hw_info)
                    if tags:
                        selected_tag = select_best_variant(tags, hw_info)
                        if selected_tag:
                            model.selected_variant = selected_tag
                            model.base_model_name = base_model_name
                            model_name_to_pull = f"ai/{base_model_name}:{selected_tag}"
                            ui.print_success(f"Auto-selected variant: {selected_tag} (best for your hardware)")
                            # Update RAM estimate
                            for tag in tags:
                                if tag.get("tag_name") == selected_tag:
                                    model.ram_gb = tag.get("estimated_ram_gb", model.ram_gb)
                                    break
        
        # Convert legacy ai.docker.com format directly to Docker Hub format
        # No DNS check needed - ai.docker.com doesn't exist, always convert
        if model_name_to_pull.startswith("ai.docker.com/"):
            # Convert to Docker Hub format
            # ai.docker.com/org/model:tag -> ai/model-name
            # Remove ai.docker.com/ prefix
            remaining = model_name_to_pull[len("ai.docker.com/"):]
            
            # Remove organization prefix (meta/, mistral/, microsoft/, etc.)
            parts = remaining.split("/")
            if len(parts) > 1:
                # Has org prefix, remove it
                model_part = parts[1]
            else:
                model_part = parts[0]
            
            # Special handling for nomic-embed-text: version is part of model name, not a tag
            # ai.docker.com/nomic/nomic-embed-text:v1.5 -> ai/nomic-embed-text-v1.5
            if "nomic-embed-text" in model_part.lower():
                # Extract version from tag and append to model name
                if ":" in model_part:
                    model_base, version = model_part.split(":", 1)
                    # Convert v1.5 -> v1.5, or just use as-is
                    model_part = f"{model_base}-{version}"
                model_name_to_pull = f"ai/{model_part}"
            else:
                # For other models, remove tag (everything after :)
                if ":" in model_part:
                    model_part = model_part.split(":")[0]
                
                # Convert to Docker Hub format: ai/modelname
                model_name_to_pull = f"ai/{model_part}"
        
        # Log the actual command being executed
        variant_info = ""
        if model.selected_variant:
            variant_info = f" ({model.selected_variant} variant)"
        ui.print_info(f"Command: {ui.colorize(f'docker model pull {model_name_to_pull}', ui.Colors.CYAN)}")
        if variant_info:
            ui.print_info(f"Selected variant{variant_info} based on your hardware ({hw_info.ram_gb:.1f}GB RAM)")
        print()
        
        # Run docker model pull
        # We don't capture output so user can see download progress
        
        # Initialize full_output for error handling
        full_output = []
        code = -1
        process = None
        
        try:
            process = subprocess.Popen(
                ["docker", "model", "pull", model_name_to_pull],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )
            
            # Stream output in real-time and capture for analysis
            if process.stdout:
                # Try to parse progress and display with rich if available
                if _ensure_rich_available():
                    from rich.progress import Progress, SpinnerColumn, BarColumn, TextColumn, TimeRemainingColumn, DownloadColumn, TransferSpeedColumn
                    from rich.console import Console
                    console = Console()
                    progress_bar = None
                    task_id = None
                    
                    # Parse Docker output for progress information
                    for line in process.stdout:
                        line = line.strip()
                        if line:
                            full_output.append(line)
                            
                            # Try to extract progress from Docker output
                            # Format: "Downloaded X of Y" or "Downloaded X/Y"
                            progress_match = re.search(r'Downloaded\s+([\d.]+)\s*(kB|MB|GB|B)?\s*(?:of|/)\s*([\d.]+)\s*(kB|MB|GB|B)?', line, re.IGNORECASE)
                            if progress_match:
                                downloaded_val = float(progress_match.group(1))
                                downloaded_unit = (progress_match.group(2) or progress_match.group(4) or "B").upper()
                                total_val = float(progress_match.group(3))
                                total_unit = (progress_match.group(4) or "B").upper()
                                
                                # Convert to bytes for consistent calculation
                                unit_multipliers = {"B": 1, "KB": 1024, "MB": 1024**2, "GB": 1024**3}
                                downloaded_bytes = downloaded_val * unit_multipliers.get(downloaded_unit, 1)
                                total_bytes = total_val * unit_multipliers.get(total_unit, 1)
                                
                                if total_bytes > 0 and progress_bar is None:
                                    # Initialize progress bar on first progress update
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
                                        f"[cyan]Downloading {model.name}...",
                                        total=total_bytes
                                    )
                                
                                if progress_bar and task_id is not None:
                                    progress_bar.update(task_id, completed=downloaded_bytes)
                            elif "complete" in line.lower() or "done" in line.lower() or "pulled" in line.lower():
                                if progress_bar:
                                    progress_bar.stop()
                                    console.print(f"[green]✓ {line}[/green]")
                                else:
                                    console.print(f"[green]✓ {line}[/green]")
                            elif "error" in line.lower() or "failed" in line.lower():
                                if progress_bar:
                                    progress_bar.stop()
                                console.print(f"[red]✗ {line}[/red]")
                    
                    # Clean up progress bar if still running
                    if progress_bar:
                        progress_bar.stop()
                else:
                    # Fallback to simple line-by-line output with carriage return for updates
                    last_line = ""
                    for line in process.stdout:
                        line = line.strip()
                        if line:
                            full_output.append(line)
                            # Show progress lines with carriage return to update in place
                            if "pulling" in line.lower() or "download" in line.lower() or "%" in line:
                                # Use carriage return to overwrite previous line
                                if "Downloaded" in line:
                                    sys.stdout.write(f"\r    {line}")
                                    sys.stdout.flush()
                                    last_line = line
                                else:
                                    if last_line:
                                        print()  # New line for non-download messages
                                        last_line = ""
                                    print(f"    {line}")
                            elif "complete" in line.lower() or "done" in line.lower():
                                if last_line:
                                    print()  # New line before completion message
                                print(ui.colorize(f"    {line}", ui.Colors.GREEN))
                                last_line = ""
                    
                    if last_line:
                        print()  # Final newline
            
            process.wait(timeout=3600)  # 1 hour timeout
            code = process.returncode
            
        except subprocess.TimeoutExpired:
            if process is not None:
                process.kill()
            ui.print_error("Download timed out after 1 hour")
            code = -1
        except Exception as e:
            ui.print_error(f"Error: {e}")
            code = -1
        finally:
            # Ensure process is always cleaned up, even if exception occurs during output streaming
            if process is not None:
                try:
                    # Check if process is still running
                    if process.poll() is None:
                        # Process is still running, terminate it
                        process.terminate()
                        try:
                            # Wait up to 5 seconds for graceful termination
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            # Force kill if it doesn't terminate gracefully
                            process.kill()
                            process.wait()
                except Exception:
                    # Ignore errors during cleanup - process may already be terminated
                    pass
        
        if code == 0:
            # Verify the model was actually downloaded and check its parameters
            verify_code, verify_out, _ = utils.run_command(["docker", "model", "list"])
            model_found = False
            actual_params = None
            
            if verify_code == 0:
                # Check if the model appears in the list (by name or converted name)
                model_name_simple = model_name_to_pull.split("/")[-1].split(":")[0]
                for line in verify_out.split("\n"):
                    if model_name_simple in line.lower() or "llama3.2" in line.lower():
                        model_found = True
                        # Extract parameters from the line
                        param_match = re.search(r'(\d+\.?\d*)\s*B', line)
                        if param_match:
                            actual_params = float(param_match.group(1))
                        break
                
                # Also try to inspect the model to get exact parameters
                if model_found:
                    inspect_code, inspect_out, _ = utils.run_command(["docker", "model", "inspect", model_name_simple], timeout=10)
                    if inspect_code == 0:
                        try:
                            inspect_data = json.loads(inspect_out)
                            actual_params_str = inspect_data.get("config", {}).get("parameters", "")
                            if actual_params_str:
                                param_match = re.search(r'(\d+\.?\d*)', actual_params_str)
                                if param_match:
                                    actual_params = float(param_match.group(1))
                        except (json.JSONDecodeError, KeyError, ValueError):
                            pass
            
            if model_found:
                # Report success with parameter count if available
                # Note: We don't validate parameter count against RAM size because they are different metrics
                # (parameter count vs memory usage). The model was successfully downloaded, which is what matters.
                if actual_params:
                    ui.print_success(f"{model.name} downloaded successfully ({actual_params}B parameters)")
                else:
                    ui.print_success(f"{model.name} downloaded successfully")
                successfully_pulled.append(model)
                ui.print_info("Model verified in Docker Model Runner")
            else:
                ui.print_warning(f"Download completed but model '{model.name}' not found in Docker Model Runner list")
                ui.print_info("The model may have been downloaded with a different name")
        else:
            ui.print_error(f"Failed to pull {model.name}")
            
            # Check if it was a 401 Unauthorized error
            is_unauthorized = False
            if 'full_output' in locals() and isinstance(full_output, list):
                is_unauthorized = any("401" in line or "unauthorized" in line.lower() for line in full_output)
            
            if is_unauthorized:
                ui.print_warning("Model not found in Docker Hub (401 Unauthorized)")
                ui.print_info("This model may not be available in the 'ai/' namespace.")
                ui.print_info("You can try:")
                ui.print_info("  1. Check if the model exists: docker search ai/<model-name>")
                ui.print_info("  2. Search for alternatives: docker search <model-name>")
            else:
                ui.print_info("You can try pulling manually later with:")
                if model_name_to_pull != model.docker_name:
                    print(ui.colorize(f"    docker model pull {model_name_to_pull}", ui.Colors.CYAN))
                    ui.print_info(f"    (Original format: {model.docker_name})")
                else:
                    print(ui.colorize(f"    docker model pull {model.docker_name}", ui.Colors.CYAN))
            
            if len(model_list) > i and ui.prompt_yes_no("Continue with remaining models?", default=True):
                continue
            elif len(model_list) > i:
                break
        
        print()
    
    # Summary
    if successfully_pulled:
        ui.print_success(f"Successfully downloaded {len(successfully_pulled)}/{len(model_list)} models")
    
    return successfully_pulled if successfully_pulled else model_list


def get_model_id_for_continue(model: Any, hw_info: Optional[hardware.HardwareInfo] = None) -> str:
    """
    Convert Docker Model Runner model name to Continue.dev compatible format.
    
    Docker Model Runner API returns models as: ai/llama3.2:latest
    The model catalog uses: ai.docker.com/meta/llama3.2:3b-instruct
    
    This function converts to the actual API model ID format.
    Preserves variant tags if selected.
    """
    # Input validation - accept either ModelInfo or string for backward compatibility
    if isinstance(model, str):
        docker_name = model
        selected_variant = None
        base_model_name = None
    elif isinstance(model, ModelInfo):
        docker_name = model.docker_name
        selected_variant = model.selected_variant
        base_model_name = model.base_model_name
    else:
        raise ValueError("model must be ModelInfo or string")
    
    # If we have a selected variant, use it
    if selected_variant and base_model_name:
        # Format: ai/base_model_name:variant_tag
        return f"ai/{base_model_name}:{selected_variant}"
    
    # First, check if we can get the actual model ID from the API
    if hw_info and hasattr(hw_info, 'available_api_models') and hw_info.available_api_models:
        # Try to match the model name to an API model ID
        model_lower = docker_name.lower()
        
        # Check for llama3.2 variants
        if "llama3.2" in model_lower or "llama3.2" in docker_name.lower():
            for api_model_id in hw_info.available_api_models:
                if "llama3.2" in api_model_id.lower():
                    return api_model_id  # Return the actual API model ID
        
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
            # Has org prefix (meta/, mistral/, etc.), remove it
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
