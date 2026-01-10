"""
Model catalog and legacy support.

DEPRECATED: This module is kept for backward compatibility only.
New code should use:
- lib.model_selector for model recommendations
- lib.validator for model pulling and verification

This module provides:
- ModelInfo: Dataclass for model metadata (used by config.py normalization)
- MODEL_CATALOG: Static list of known models (for reference only)
"""

from dataclasses import dataclass, field
from typing import List, Optional

from . import hardware


@dataclass
class ModelInfo:
    """
    Information about an LLM model.
    
    DEPRECATED: New code should use model_selector.RecommendedModel instead.
    This class is kept for backward compatibility with config.py normalization.
    """
    name: str
    ollama_name: str  # Name used in Ollama
    description: str
    ram_gb: float
    context_length: int
    roles: List[str]  # chat, autocomplete, embed, etc.
    tiers: List[hardware.HardwareTier]  # Which tiers can run this model
    recommended_for: List[str] = field(default_factory=list)
    base_model_name: Optional[str] = None  # Base model name for variant discovery
    selected_variant: Optional[str] = None  # Selected variant tag


# Model catalog for Ollama - kept for backward compatibility
# New code should use model_selector.PRIMARY_MODELS, AUTOCOMPLETE_MODELS, etc.
MODEL_CATALOG: List[ModelInfo] = [
    # =========================================================================
    # Chat/Edit Models - Large (Tier S/A)
    # =========================================================================
    ModelInfo(
        name="Codestral 22B",
        ollama_name="codestral:22b",
        description="Mistral's Codestral 22B - Excellent code generation",
        ram_gb=13.0,
        context_length=32768,
        roles=["chat", "edit", "autocomplete"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A],
        recommended_for=["Best coding quality for Tier S/A"],
        base_model_name="codestral"
    ),
    ModelInfo(
        name="Qwen2.5 Coder 14B",
        ollama_name="qwen2.5-coder:14b",
        description="Alibaba's Qwen2.5 Coder 14B - Excellent code generation",
        ram_gb=9.0,
        context_length=32768,
        roles=["chat", "edit", "autocomplete"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A],
        recommended_for=["Tier A primary", "Excellent code generation"],
        base_model_name="qwen2.5-coder"
    ),
    
    # =========================================================================
    # Chat/Edit Models - Medium (Tier B/C)
    # =========================================================================
    ModelInfo(
        name="Qwen2.5 Coder 7B",
        ollama_name="qwen2.5-coder:7b",
        description="Alibaba's Qwen2.5 Coder 7B - Fast and capable",
        ram_gb=5.0,
        context_length=32768,
        roles=["chat", "edit", "autocomplete"],
        tiers=[hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
        recommended_for=["Tier B primary", "Fast coding"],
        base_model_name="qwen2.5-coder"
    ),
    ModelInfo(
        name="Granite Code 8B",
        ollama_name="granite-code:8b",
        description="IBM's Granite Code 8B - Balanced coding model",
        ram_gb=5.0,
        context_length=131072,
        roles=["chat", "edit", "autocomplete"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
        recommended_for=["Tier C primary", "Good balance"],
        base_model_name="granite-code"
    ),
    
    # =========================================================================
    # Autocomplete Models - Fast (All Tiers)
    # =========================================================================
    ModelInfo(
        name="Granite Code 3B",
        ollama_name="granite-code:3b",
        description="IBM's Granite Code 3B - Fast autocomplete",
        ram_gb=2.0,
        context_length=131072,
        roles=["autocomplete", "chat", "edit"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
        recommended_for=["Fast autocomplete", "All tiers"],
        base_model_name="granite-code"
    ),
    
    # =========================================================================
    # Embedding Models (All Tiers)
    # =========================================================================
    ModelInfo(
        name="Nomic Embed Text",
        ollama_name="nomic-embed-text:latest",
        description="Best open embedding model for code indexing (8192 tokens)",
        ram_gb=0.3,
        context_length=8192,
        roles=["embed"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
        recommended_for=["Code indexing", "Semantic search", "@codebase"],
        base_model_name="nomic-embed-text"
    ),
    
    # =========================================================================
    # Optional Reasoning Models (Tier S/A)
    # =========================================================================
    ModelInfo(
        name="Phi-4",
        ollama_name="phi4:latest",
        description="Microsoft's Phi-4 - Excellent reasoning",
        ram_gb=9.0,
        context_length=16384,
        roles=["chat", "edit"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A],
        recommended_for=["Reasoning", "Architecture discussions"],
        base_model_name="phi4"
    ),
]


def get_models_for_tier(tier: hardware.HardwareTier) -> List[ModelInfo]:
    """
    Get models available for a specific hardware tier.
    
    DEPRECATED: Use model_selector.PRIMARY_MODELS[tier] instead.
    """
    return [m for m in MODEL_CATALOG if tier in m.tiers]


def find_modelinfo_by_ollama_name(ollama_name: str) -> Optional[ModelInfo]:
    """
    Find a ModelInfo by its Ollama name.
    
    DEPRECATED: Use model_selector catalogs instead.
    """
    for model in MODEL_CATALOG:
        if model.ollama_name == ollama_name:
            return model
        # Check base name match
        if ollama_name.split(":")[0] == model.ollama_name.split(":")[0]:
            return model
    return None
