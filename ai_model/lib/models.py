"""
Model catalog and legacy support.

DEPRECATED: This module is kept for backward compatibility only.
New code should use:
- lib.model_selector for model recommendations
- lib.validator for model pulling and verification

This module provides:
- ModelInfo: Dataclass for model metadata (used by config.py normalization)
- MODEL_CATALOG: Static list of known models (GPT-OSS 20B and nomic-embed-text only)
"""

from dataclasses import dataclass, field
from typing import List, Optional


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
    recommended_for: List[str] = field(default_factory=list)
    base_model_name: Optional[str] = None  # Base model name for variant discovery
    selected_variant: Optional[str] = None  # Selected variant tag


# Model catalog for Ollama - kept for backward compatibility
# New code should use model_selector for recommendations
# Only GPT-OSS 20B and nomic-embed-text are supported
MODEL_CATALOG: List[ModelInfo] = [
    # =========================================================================
    # Primary Chat/Edit/Reasoning Model
    # =========================================================================
    ModelInfo(
        name="GPT-OSS 20B",
        ollama_name="gpt-oss:20b",
        description="OpenAI's GPT-OSS 20B - Matches o3-mini performance, 1200 tokens/sec, only 16GB RAM",
        ram_gb=16.0,
        context_length=131072,
        roles=["chat", "edit", "agent", "autocomplete"],
        recommended_for=["Primary reasoning/chat model"],
        base_model_name="gpt-oss"
    ),
    
    # =========================================================================
    # Embedding Models
    # =========================================================================
    ModelInfo(
        name="Nomic Embed Text",
        ollama_name="nomic-embed-text:latest",
        description="Best open embedding model for code indexing (8192 tokens)",
        ram_gb=0.3,
        context_length=8192,
        roles=["embed"],
        recommended_for=["Code indexing", "Semantic search", "@codebase"],
        base_model_name="nomic-embed-text"
    ),
]
