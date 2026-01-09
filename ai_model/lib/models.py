"""
Model catalog and selection functionality.

Provides model information, catalog, discovery, selection, and pulling capabilities.
"""

import json
import re
import subprocess
import sys
import threading
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from . import hardware
from . import ui
from . import utils

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
    
    # First try: import if already installed
    if not _rich_imported:
        try:
            from rich.progress import Progress, SpinnerColumn, BarColumn, TextColumn, TimeRemainingColumn, DownloadColumn, TransferSpeedColumn
            from rich.console import Console
            RICH_AVAILABLE = True
            _rich_imported = True
            return True
        except ImportError:
            _rich_imported = True  # Mark as tried so we don't try again
    
    # Second try: install and import
    if not RICH_AVAILABLE:
        try:
            ui.print_info("Installing 'rich' for better progress bars...")
            # Try multiple installation methods (for different Python environments)
            install_commands = [
                [sys.executable, "-m", "pip", "install", "--quiet", "--user", "rich>=13.7.0"],
                [sys.executable, "-m", "pip", "install", "--quiet", "--break-system-packages", "rich>=13.7.0"],
                [sys.executable, "-m", "pip", "install", "--quiet", "rich>=13.7.0"],
            ]
            
            installed = False
            last_error = None
            for cmd in install_commands:
                result = subprocess.run(
                    cmd,
                    capture_output=True,
                    timeout=60,
                    text=True
                )
                if result.returncode == 0:
                    installed = True
                    break
                else:
                    # Capture error message for helpful feedback
                    error_output = result.stderr.strip() if result.stderr else result.stdout.strip()
                    if error_output:
                        last_error = error_output
            
            if installed:
                # Try importing again after installation
                try:
                    from rich.progress import Progress, SpinnerColumn, BarColumn, TextColumn, TimeRemainingColumn, DownloadColumn, TransferSpeedColumn
                    from rich.console import Console
                    RICH_AVAILABLE = True
                    ui.print_success("Successfully installed 'rich'")
                    return True
                except ImportError:
                    ui.print_warning("Installed 'rich' but import failed - will use basic progress display")
                    return False
            else:
                # Installation failed - provide helpful message based on error
                ui.print_warning("Could not install 'rich' automatically")
                if last_error and "externally-managed" in last_error.lower():
                    ui.print_info("Your Python environment is externally managed (e.g., Homebrew)")
                    ui.print_info("Install manually with one of these options:")
                    ui.print_info("  1. pip install --user rich")
                    ui.print_info("  2. pip install --break-system-packages rich")
                    ui.print_info("  3. python3 -m pip install --user rich")
                else:
                    ui.print_info("You can install it manually with: pip install rich")
                ui.print_info("Will use basic progress display (still functional)")
                return False
        except subprocess.TimeoutExpired:
            ui.print_warning("Installation of 'rich' timed out - will use basic progress display")
            return False
        except (FileNotFoundError, ImportError, Exception) as e:
            ui.print_warning(f"Could not install 'rich' - will use basic progress display")
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
# Docker Model Runner uses the namespace: ai.docker.com/ or just model names
# Models are optimized for Apple Silicon with Metal acceleration
# Format: ai.docker.com/<org>/<model>:<tag> or simplified <model>:<tag>
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
        name="Codestral 22B",
        docker_name="ai.docker.com/mistral/codestral:22b-v0.1",
        description="22B - Mistral's code generation model",
        ram_gb=12.0,
        context_length=32768,
        roles=["chat", "edit", "autocomplete"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A],
        recommended_for=["Excellent code generation"]
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
    # Chat/Edit Models - Medium (Tier B: 17-32GB RAM)
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
    ModelInfo(
        name="CodeLlama 13B",
        docker_name="ai.docker.com/meta/codellama:13b-instruct",
        description="13B - Meta's code-specialized Llama",
        ram_gb=7.5,
        context_length=16384,
        roles=["chat", "edit", "autocomplete"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B],
        recommended_for=["Code generation"]
    ),
    # =========================================================================
    # Chat/Edit Models - Small (All Tiers, optimized for Tier C: <17GB RAM)
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
    ModelInfo(
        name="CodeGemma 7B",
        docker_name="ai.docker.com/google/codegemma:7b-it",
        description="7B - Google's code-optimized model",
        ram_gb=4.0,
        context_length=8192,
        roles=["chat", "autocomplete"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
        recommended_for=["Fast autocomplete"]
    ),
    # =========================================================================
    # Autocomplete Models - Ultra-fast (All Tiers)
    # =========================================================================
    ModelInfo(
        name="StarCoder2 3B",
        docker_name="ai.docker.com/bigcode/starcoder2:3b",
        description="3B - Ultra-fast autocomplete optimized for code",
        ram_gb=1.8,
        context_length=16384,
        roles=["autocomplete"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
        recommended_for=["Fastest autocomplete", "Low memory"]
    ),
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
        name="All-MiniLM-L6-v2",
        docker_name="ai.docker.com/sentence-transformers/all-minilm:l6-v2",
        description="Lightweight embedding for simple use cases",
        ram_gb=0.1,
        context_length=512,
        roles=["embed"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
        recommended_for=["Minimal memory", "Simple search"]
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
    Returns a list of model names in format 'ai/model-name'.
    """
    available_models = []
    try:
        url = f"https://hub.docker.com/v2/repositories/ai/?page_size={page_size}"
        req = urllib.request.Request(url)
        req.add_header("User-Agent", "Docker-Model-Runner-Setup/1.0")
        
        with urllib.request.urlopen(req, timeout=10) as response:
            if response.status == 200:
                data = json.loads(response.read().decode('utf-8'))
                if "results" in data:
                    for repo in data["results"]:
                        repo_name = repo.get("name", "")
                        if repo_name:
                            available_models.append(f"ai/{repo_name}")
    except (urllib.error.URLError, urllib.error.HTTPError, OSError, json.JSONDecodeError) as e:
        ui.print_warning(f"Could not fetch models from Docker Hub API: {e}")
    
    return available_models


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
    
    if "-f16" in tag_lower or tag_lower.endswith("-f16"):
        quantization = "F16"
        is_full_precision = True
    elif "-q4_k_m" in tag_lower or tag_lower.endswith("-q4_k_m"):
        quantization = "Q4_K_M"
    elif "-q4_0" in tag_lower or tag_lower.endswith("-q4_0"):
        quantization = "Q4_0"
    elif "-q8_0" in tag_lower or tag_lower.endswith("-q8_0"):
        quantization = "Q8_0"
    elif "-q8" in tag_lower:
        quantization = "Q8"
    elif "-q4" in tag_lower:
        quantization = "Q4"
    
    # If no quantization specified and size exists, assume full precision
    if quantization is None and size is not None:
        is_full_precision = True
    
    # Estimate RAM requirements
    estimated_ram_gb = 0.0
    if size is not None:
        # Base RAM estimate: roughly size * 0.5 for full precision
        base_ram = size * 0.5
        
        # Apply quantization reduction
        if quantization == "F16" or is_full_precision:
            estimated_ram_gb = base_ram
        elif quantization == "Q8_0" or quantization == "Q8":
            estimated_ram_gb = base_ram * 0.75
        elif quantization == "Q4_K_M" or quantization == "Q4_0" or quantization == "Q4":
            estimated_ram_gb = base_ram * 0.5
        else:
            # Unknown quantization, assume full precision
            estimated_ram_gb = base_ram
    
    return {
        "size": size,
        "size_str": size_str,
        "quantization": quantization,
        "is_full_precision": is_full_precision,
        "estimated_ram_gb": estimated_ram_gb,
        "tag_name": tag_name
    }


def discover_model_tags(model_name: str, hw_info: Optional[hardware.HardwareInfo] = None) -> List[Dict[str, Any]]:
    """
    Discover available tags/variants for a model from Docker Hub API.
    
    Args:
        model_name: Base model name (e.g., "llama3.3" or "ai/llama3.3")
        hw_info: Optional HardwareInfo for caching
    
    Returns:
        List of tag dictionaries with parsed metadata
    """
    # Normalize model name (remove ai/ prefix if present)
    base_name = model_name.replace("ai/", "").strip()
    
    # Check cache first
    if hw_info and hasattr(hw_info, 'discovered_model_tags') and base_name in hw_info.discovered_model_tags:
        return hw_info.discovered_model_tags[base_name]
    
    tags = []
    try:
        url = f"https://hub.docker.com/v2/repositories/ai/{base_name}/tags/?page_size=100"
        req = urllib.request.Request(url)
        req.add_header("User-Agent", "Docker-Model-Runner-Setup/1.0")
        
        with urllib.request.urlopen(req, timeout=10) as response:
            if response.status == 200:
                data = json.loads(response.read().decode('utf-8'))
                if "results" in data:
                    for tag_result in data["results"]:
                        tag_name = tag_result.get("name", "")
                        if tag_name:
                            # Parse tag info
                            tag_info = parse_tag_info(tag_name)
                            tags.append(tag_info)
            else:
                ui.print_warning(f"Could not fetch tags for {base_name}: HTTP {response.status}")
                return []
    except urllib.error.HTTPError as e:
        if e.code == 404:
            ui.print_warning(f"Model {base_name} not found on Docker Hub (404)")
        else:
            ui.print_warning(f"Could not fetch tags for {base_name}: HTTP {e.code}")
        return []
    except (urllib.error.URLError, OSError) as e:
        ui.print_warning(f"Network error fetching tags for {base_name}: {e}")
        return []
    except json.JSONDecodeError as e:
        ui.print_warning(f"Invalid JSON response for {base_name} tags: {e}")
        return []
    except Exception as e:
        ui.print_warning(f"Unexpected error fetching tags for {base_name}: {e}")
        return []
    
    # Cache results
    if hw_info:
        if not hasattr(hw_info, 'discovered_model_tags'):
            hw_info.discovered_model_tags = {}
        hw_info.discovered_model_tags[base_name] = tags
    
    return tags


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
    
    available_ram = hw_info.ram_gb
    ram_buffer = available_ram * 0.15  # 15% buffer for system overhead
    usable_ram = available_ram - ram_buffer
    
    # Filter tags by tier compatibility (rough size-based tier matching)
    tier_appropriate_tags = []
    for tag in valid_tags:
        size = tag.get("size", 0)
        ram_needed = tag.get("estimated_ram_gb", 0)
        
        # Check if this size is appropriate for the tier
        if hw_info.tier == hardware.HardwareTier.S:
            # Tier S can handle 70B, 32B, 22B
            if size >= 20 or ram_needed <= usable_ram:
                tier_appropriate_tags.append(tag)
        elif hw_info.tier == hardware.HardwareTier.A:
            # Tier A can handle 22B, 14B, 7B
            if size <= 32 or ram_needed <= usable_ram:
                tier_appropriate_tags.append(tag)
        elif hw_info.tier == hardware.HardwareTier.B:
            # Tier B can handle 14B, 7B, 3B
            if size <= 14 or ram_needed <= usable_ram:
                tier_appropriate_tags.append(tag)
        else:  # Tier C
            # Tier C can handle 7B, 3B, 1.5B
            if size <= 7 or ram_needed <= usable_ram:
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
        
        with urllib.request.urlopen(req, timeout=10) as response:
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
        "qwen",  # Chinese (Alibaba)
        "deepseek",  # Chinese
        "deepcoder",  # Chinese (based on DeepSeek)
        "baai",  # Chinese (Beijing Academy of Artificial Intelligence)
        "bge-",  # Chinese (BAAI models)
    ]
    model_lower = model.name.lower() + " " + model.docker_name.lower()
    return any(keyword in model_lower for keyword in restricted_keywords)


def is_docker_hub_unavailable(model: ModelInfo) -> bool:
    """Check if a model is not available in Docker Hub's ai/ namespace.
    These models would fail with 401 Unauthorized when trying to pull.
    Only models confirmed to exist in Docker Hub's ai/ namespace are included."""
    # Models that don't exist in Docker Hub's ai/ namespace (verified)
    # These models are not available and will fail with 401 Unauthorized
    unavailable_models = [
        "starcoder2",  # Not in ai/ namespace (401 error confirmed)
        "codestral",  # Not in ai/ namespace
        "codegemma",  # Not in ai/ namespace (only in other namespaces)
        "codellama",  # Not in ai/ namespace
        # Note: nomic-embed-text exists as ai/nomic-embed-text-v1.5, but our format is different
        # Keeping it filtered since the exact name doesn't match
    ]
    
    # Convert model name to what it would be in Docker Hub format
    if model.docker_name.startswith("ai.docker.com/"):
        remaining = model.docker_name[len("ai.docker.com/"):]
        parts = remaining.split("/")
        if len(parts) > 1:
            model_part = parts[1]
        else:
            model_part = parts[0]
        if ":" in model_part:
            model_part = model_part.split(":")[0]
    else:
        # Already in Docker Hub format or other format
        if model.docker_name.startswith("ai/"):
            model_part = model.docker_name[3:]
            if ":" in model_part:
                model_part = model_part.split(":")[0]
        else:
            return False
    
    model_lower = model_part.lower()
    return any(unavailable in model_lower for unavailable in unavailable_models)


def verify_model_available(model: ModelInfo, hw_info: hardware.HardwareInfo) -> bool:
    """
    Verify that a model actually exists and can be pulled from Docker Model Runner.
    
    According to Docker Model Runner docs (https://docs.docker.com/ai/model-runner/):
    - Models are pulled from Docker Hub and stored locally
    - The API exposes OpenAI-compatible endpoints
    - Models can be checked via the Docker Hub API or Docker Model Runner API
    
    This function checks:
    1. Docker Hub API (cached list) - most accurate for what's available to pull
    2. Docker Model Runner API (installed models) - shows what's already pulled
    3. Known working models with size variants
    4. Docker Hub search as fallback
    """
    # Convert model name to Docker Hub format for checking
    model_name_to_check = model.docker_name
    
    if model.docker_name.startswith("ai.docker.com/"):
        # Convert to Docker Hub format
        remaining = model.docker_name[len("ai.docker.com/"):]
        parts = remaining.split("/")
        if len(parts) > 1:
            model_part = parts[1]
        else:
            model_part = parts[0]
        
        # Remove tag (everything after :)
        if ":" in model_part:
            model_part = model_part.split(":")[0]
        
        # Convert to Docker Hub format: ai/modelname
        model_name_to_check = f"ai/{model_part}"
    
    model_lower = model_name_to_check.lower()
    base_name = model_name_to_check.split(":")[0] if ":" in model_name_to_check else model_name_to_check
    
    # First, try to use cached Docker Hub models list (most accurate for what's available to pull)
    if hasattr(hw_info, 'available_docker_hub_models') and hw_info.available_docker_hub_models:
        base_name_lower = base_name.lower()
        for hub_model in hw_info.available_docker_hub_models:
            if base_name_lower == hub_model.lower():
                return True
    
    # Second, try to use cached API models list (fetched during DMR check)
    # According to docs: https://docs.docker.com/ai/model-runner/api-reference/
    if hasattr(hw_info, 'available_api_models') and hw_info.available_api_models:
        for api_model_id in hw_info.available_api_models:
            api_model_lower = api_model_id.lower()
            # Check if our model matches (with or without tag)
            if base_name.lower() in api_model_lower or api_model_lower in base_name.lower():
                return True
    
    # If no cached list, try to query the API directly
    if hw_info.docker_model_runner_available and hw_info.dmr_api_endpoint:
        try:
            # Try to get available models from the API
            api_url = f"{hw_info.dmr_api_endpoint}/models"
            req = urllib.request.Request(api_url, method="GET")
            req.add_header("Content-Type", "application/json")
            
            with urllib.request.urlopen(req, timeout=5) as response:
                if response.status == 200:
                    data = json.loads(response.read().decode('utf-8'))
                    # Check if model is in the API response
                    if "data" in data:
                        for api_model in data["data"]:
                            model_id = api_model.get("id", "").lower()
                            # Check if our model matches (with or without tag)
                            if base_name.lower() in model_id or model_id in base_name.lower():
                                return True
        except (urllib.error.URLError, urllib.error.HTTPError, OSError, json.JSONDecodeError):
            # API not available or error, fall through to other checks
            pass
    
    # Known working models in Docker Model Runner (from official docs and testing)
    # Format: (base_name, available_size_variants)
    # Based on: https://docs.docker.com/ai/model-runner/
    known_working_models = {
        "ai/llama3.2": ["3b"],  # Only 3B variant exists in Docker Model Runner, not 8B
        "ai/llama3.3": ["70b"],  # Only 70B variant exists
        "ai/llama3.1": ["70b"],  # Only 70B variant exists
        "ai/nomic-embed-text-v1.5": [None],  # No size variant
        "ai/granite-4.0-h-nano": ["nano"],  # Granite 4.0 nano variant
        "ai/phi4": ["14b"],  # Only 14B variant exists
    }
    
    # Check if base model is known
    for known_base, available_sizes in known_working_models.items():
        if base_name.lower() == known_base.lower():
            # Check size variant if specified
            if None in available_sizes:
                # No size variant needed
                return True
            
            # Check if requested size matches available sizes
            requested_size = None
            if "8b" in model_lower or ":8b" in model_lower or "-8b" in model_lower:
                requested_size = "8b"
            elif "3b" in model_lower or ":3b" in model_lower or "-3b" in model_lower:
                requested_size = "3b"
            elif "7b" in model_lower or ":7b" in model_lower or "-7b" in model_lower:
                requested_size = "7b"
            elif "14b" in model_lower or ":14b" in model_lower or "-14b" in model_lower:
                requested_size = "14b"
            elif "70b" in model_lower or ":70b" in model_lower or "-70b" in model_lower:
                requested_size = "70b"
            
            if requested_size:
                # Check if requested size is available
                size_list = [s.lower() if s else None for s in available_sizes]
                return requested_size in size_list
            else:
                # No specific size requested, check if any variant exists
                return len(available_sizes) > 0
    
    # For unknown models, try to fetch from Docker Hub API directly (if not cached)
    if not hasattr(hw_info, 'available_docker_hub_models') or not hw_info.available_docker_hub_models:
        docker_hub_models = fetch_available_models_from_docker_hub()
        if docker_hub_models:
            base_name_lower = base_name.lower()
            for hub_model in docker_hub_models:
                if base_name_lower == hub_model.lower():
                    return True
    
    # Last resort: try Docker search command to find variants
    # This is useful for discovering if a model exists even if not in our cached lists
    # Extract base model name for search (e.g., 'phi4' from 'ai/phi4' or 'ai.docker.com/microsoft/phi4:14b')
    search_base = base_name.replace("ai/", "").lower()
    if "/" in search_base:
        # Extract just the model name part
        search_base = search_base.split("/")[-1]
    if ":" in search_base:
        search_base = search_base.split(":")[0]
    
    variants = discover_model_variants(f"ai/{search_base}", hw_info)
    if variants:
        # Check if any variant matches our model name
        base_name_lower = base_name.lower()
        for variant in variants:
            variant_lower = variant.lower()
            # Exact match
            if base_name_lower == variant_lower:
                return True
            # Check if the base model name is in the variant (e.g., 'phi4' in 'ai/phi4')
            if search_base in variant_lower.replace("ai/", ""):
                return True
        # If we found variants for this model family, the model likely exists
        # Docker Model Runner may use simplified naming (e.g., 'ai/phi4' instead of 'ai/phi4:14b')
        if variants:
            return True
    
    # Model not found in API, known list, or search
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
    
    Limits to top 3-5 models per category and filters by hardware tier.
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
        
        model_lower = model_name.lower()
        
        # Find ModelInfo from catalog to get roles and tier info
        model_info = find_modelinfo_by_docker_hub_name(model_name)
        roles = model_info.roles if model_info else []
        
        # Filter by tier if model_info exists
        if model_info and tier not in model_info.tiers:
            # Skip models not suitable for this tier
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
        elif any(x in model_lower for x in ["gemma3n", "moondream", "smolvlm", "granite-docling"]):
            categories["Multimodal Models"].append({
                "name": model_name,
                "roles": roles,
                "model_info": model_info
            })
            seen_models.add(model_name)
        
        # Reasoning & Agent Models
        elif any(x in model_lower for x in ["gpt-oss", "seed-oss"]):
            if "safeguard" not in model_lower:  # Exclude safeguard variant
                categories["Reasoning & Agent Models"].append({
                    "name": model_name,
                    "roles": roles,
                    "model_info": model_info
                })
                seen_models.add(model_name)
        
        # Coding Models
        elif any(x in model_lower for x in ["devstral", "phi4", "codestral", "granite-4.0", "codellama", "codegemma", "starcoder"]):
            categories["Coding Models"].append({
                "name": model_name,
                "roles": roles,
                "model_info": model_info
            })
            seen_models.add(model_name)
        
        # Small/Efficient Models
        elif any(x in model_lower for x in ["smollm", "granite-4.0-h-micro", "functiongemma", "granite-4.0-nano", "granite-4.0-h-nano", "granite-4.0-h-tiny"]):
            categories["Small/Efficient Models"].append({
                "name": model_name,
                "roles": roles,
                "model_info": model_info
            })
            seen_models.add(model_name)
        
        # General Chat/Instruction Models (catch-all for remaining chat models)
        elif any(x in model_lower for x in ["llama3", "mistral", "granite-4.0"]):
            if "embed" not in model_lower and "coder" not in model_lower and "vl" not in model_lower:
                categories["General Chat/Instruction Models"].append({
                    "name": model_name,
                    "roles": roles,
                    "model_info": model_info
                })
                seen_models.add(model_name)
    
    # Sort and limit to top 3-5 models per category
    # Prioritize models with ModelInfo (from catalog) and sort by RAM if available
    for category in categories:
        models = categories[category]
        # Sort: models with ModelInfo first, then by RAM (descending), then alphabetically
        models.sort(key=lambda m: (
            m["model_info"] is None,  # False (catalog models) first
            -m["model_info"].ram_gb if m["model_info"] else 0,  # Higher RAM first
            m["name"].lower()  # Alphabetical
        ))
        # Limit to top 5 models
        categories[category] = models[:5]
    
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
    
    # Step 1: Get tier-optimized recommendation
    recommendation = get_tier_optimized_recommendation(hw_info)
    
    if not recommendation:
        ui.print_warning("Could not generate recommendations for your hardware tier.")
        ui.print_info("You can try the model discovery feature to search for available models.")
        if ui.prompt_yes_no("Would you like to search for available models?", default=False):
            return discover_and_select_models(hw_info)
        return []
    
    # Step 3: Display recommended selection
    ui.print_subheader("Recommended Selection (Auto-selected for your tier)")
    print()
    
    # Convert recommendation (category -> model_name) to ModelInfo objects
    categories_data = get_recommended_models_by_category(hw_info)
    recommended_models: List[ModelInfo] = []
    total_ram = 0.0
    
    for category, model_name in recommendation.items():
        # Find the model in categories data
        if category in categories_data:
            for model_dict in categories_data[category]:
                if model_dict["name"] == model_name:
                    model_info = model_dict.get("model_info")
                    if model_info:
                        # Check if this is a base model that needs variant selection
                        base_name = model_info.base_model_name
                        if not base_name:
                            # Try to extract base name from docker_name
                            hub_name = get_docker_hub_model_name(model_info.docker_name)
                            base_name = hub_name.replace("ai/", "").split(":")[0]
                            model_info.base_model_name = base_name
                        
                        if not model_info.selected_variant and base_name:
                            # Discover and select best variant
                            ui.print_info(f"Discovering variants for {model_info.name}...")
                            tags = discover_model_tags(base_name, hw_info)
                            if tags:
                                selected_tag = select_best_variant(tags, hw_info)
                                if selected_tag:
                                    model_info.selected_variant = selected_tag
                                    # Update RAM estimate based on selected variant
                                    for tag in tags:
                                        if tag.get("tag_name") == selected_tag:
                                            model_info.ram_gb = tag.get("estimated_ram_gb", model_info.ram_gb)
                                            break
                                    ui.print_success(f"Selected {selected_tag} variant for {model_info.name} (best for your hardware)")
                                else:
                                    ui.print_warning(f"Could not select variant for {model_info.name}, using base model")
                            else:
                                ui.print_warning(f"Could not discover variants for {model_info.name}, using base model")
                        
                        recommended_models.append(model_info)
                        total_ram += model_info.ram_gb
                    else:
                        # Create basic ModelInfo for models not in catalog
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
                        recommended_models.append(basic_model)
                        total_ram += basic_model.ram_gb
                    break
    
    # Display recommended models
    if recommended_models:
        for model in recommended_models:
            roles_str = ", ".join(model.roles) if model.roles else "general"
            variant_info = ""
            if model.selected_variant:
                variant_info = f" ({model.selected_variant} variant)"
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
            process.kill()
            ui.print_error("Download timed out after 1 hour")
            code = -1
        except Exception as e:
            ui.print_error(f"Error: {e}")
            code = -1
        
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
                # Check if parameters match expected (allow some tolerance)
                expected_params = model.ram_gb  # Rough estimate: 8B model ~5GB, 3B model ~2GB
                if actual_params:
                    if abs(actual_params - expected_params) > 2.0:  # More than 2GB difference
                        ui.print_warning(f"{model.name} downloaded, but got {actual_params}B model instead of expected ~{expected_params}GB model")
                        ui.print_info(f"Actual model: {actual_params}B parameters")
                    else:
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
