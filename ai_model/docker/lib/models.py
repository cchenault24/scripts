"""
Model utilities for Docker Model Runner.

Minimal module providing only essential model information and conversion utilities.
"""

from dataclasses import dataclass
from typing import Any, Optional

from . import hardware


@dataclass
class ModelInfo:
    """Minimal model info for config generation."""
    name: str
    docker_name: str
    ram_gb: float
    context_length: int
    roles: list[str]


def get_model_id_for_continue(model: Any, hw_info: Optional[hardware.HardwareInfo] = None) -> str:
    """
    Convert Docker Model Runner model name to Continue.dev compatible format.
    
    Args:
        model: ModelInfo, RecommendedModel, or string
        hw_info: Optional hardware info for API model matching
    
    Returns:
        Continue.dev compatible model ID
    """
    # Extract docker_name from various model types
    if isinstance(model, str):
        docker_name = model
    elif hasattr(model, 'docker_name'):
        docker_name = model.docker_name
    else:
        raise ValueError("model must be ModelInfo, RecommendedModel, or string")
    
    # If it already starts with ai/, preserve existing tag or add :latest
    if docker_name.startswith("ai/"):
        if ":" not in docker_name:
            docker_name = f"{docker_name}:latest"
        return docker_name
    
    # Fallback: assume it needs ai/ prefix
    if ":" not in docker_name:
        return f"ai/{docker_name}:latest"
    return f"ai/{docker_name}"
