"""
Model Selector for Continue.dev + Ollama Setup.

Installs the same two models for all users:
- GPT-OSS 20B: Primary coding model
- Nomic Embed Text: Embedding model for code indexing
"""

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple
from enum import Enum

from . import hardware
from . import ui


class ModelRole(Enum):
    """Model roles for Continue.dev."""
    CHAT = "chat"
    EDIT = "edit"
    AUTOCOMPLETE = "autocomplete"
    EMBED = "embed"
    APPLY = "apply"
    RERANK = "rerank"


@dataclass
class RecommendedModel:
    """A model in the recommended portfolio."""
    name: str  # Display name (e.g., "Codestral 22B")
    ollama_name: str  # Full Ollama name with tag (e.g., "codestral:22b-v0.1-q4_K_M")
    ram_gb: float  # Estimated RAM usage
    role: ModelRole  # Primary role
    roles: List[str]  # All supported roles
    context_length: int = 131072  # Default context length
    description: str = ""
    min_perf_score: float = 1.0  # Minimum CPU performance score needed
    requires_fp16: bool = False  # Whether FP16 quantization is required (M3 Pro+ or M4+)
    recommended_for: List[str] = field(default_factory=list)  # Chip generations/tiers optimized for


# =============================================================================
# MODEL CATALOG - Fixed Models for All Users
# =============================================================================

# Embedding model - universal for all users
# Note: nomic-embed-text is widely available and reliable
EMBED_MODEL = RecommendedModel(
    name="Nomic Embed Text",
    ollama_name="nomic-embed-text",
    ram_gb=0.3,
    role=ModelRole.EMBED,
    roles=["embed"],
    context_length=8192,
    description="Best open embedding model for code indexing (8192 tokens)",
    min_perf_score=1.0,
    requires_fp16=False,
    recommended_for=["all"]
)


# Primary model - GPT-OSS 20B
PRIMARY_MODEL = RecommendedModel(
    name="GPT-OSS 20B",
    ollama_name="gpt-oss:20b",
    ram_gb=16.0,
    role=ModelRole.CHAT,
    roles=["chat", "edit", "autocomplete"],
    context_length=131072,
    description="OpenAI GPT-OSS 20B - Matches o3-mini performance, 1200 tokens/sec, Apache 2.0 license",
    min_perf_score=1.0,
    requires_fp16=False,
    recommended_for=["M1", "M2", "M3", "M4", "M1 Ultra", "M2 Ultra", "M3 Max", "M4 Pro", "M4 Max"]
)


def select_models(hw_info: hardware.HardwareInfo, installed_ides: Optional[List[str]] = None) -> List[RecommendedModel]:
    """
    Select models to install.
    
    Returns the same two models for all users:
    - GPT-OSS 20B: Primary coding model
    - Nomic Embed Text: Embedding model
    
    Args:
        hw_info: Hardware information
        installed_ides: List of installed IDEs (auto-detected if None, unused)
    
    Returns:
        List of RecommendedModel objects to install
    """
    ui.print_header("📦 Model Selection")
    
    # Validate Apple Silicon support
    is_supported, error_msg = hardware.validate_apple_silicon_support(hw_info)
    if not is_supported:
        ui.print_error(error_msg or "This setup only supports Apple Silicon Macs")
        raise SystemExit("Hardware requirements not met: Apple Silicon required")
    
    # Display hardware info
    print()
    chip_model = hw_info.apple_chip_model or hw_info.cpu_brand
    ui.print_success(f"Detected: {chip_model} {hw_info.ram_gb:.0f}GB")
    
    if installed_ides:
        ide_str = ", ".join(installed_ides)
        ui.print_success(f"Scanned: {ide_str} installed")
    
    print()
    print(f"  System RAM:           {hw_info.ram_gb:.0f}GB")
    
    # Always install the same two models
    models_to_install = [PRIMARY_MODEL, EMBED_MODEL]
    
    print()
    ui.print_success("Models to install:")
    total_ram = 0.0
    for model in models_to_install:
        print(f"  • {ui.colorize(model.ollama_name, ui.Colors.CYAN)} - {model.ram_gb:.1f}GB")
        total_ram += model.ram_gb
    
    print()
    print(f"Total model RAM: {total_ram:.1f}GB")
    
    return models_to_install
