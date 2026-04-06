"""
Unified model catalog with backend abstraction.

Provides a common interface for model selection across different backends
(Ollama, llama.cpp, etc.) while allowing backend-specific implementations.
"""

from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, List, Optional, Tuple
from abc import ABC, abstractmethod

from . import hardware


class Backend(Enum):
    """Supported backend types."""
    OLLAMA = "ollama"
    LLAMACPP = "llamacpp"


class ModelSize(Enum):
    """Model size categories."""
    SMALL = "2b"      # 2-4B parameters
    MEDIUM = "4b"     # 4-8B parameters
    LARGE = "26b"     # 20-30B parameters
    XLARGE = "31b"    # 30B+ parameters


@dataclass
class ContextOption:
    """Context window configuration option."""
    size: int  # Context size in tokens
    description: str  # Human-readable description (e.g., "32K context (~17GB RAM)")
    ram_gb: float  # Estimated RAM usage with this context


@dataclass
class BaseModel(ABC):
    """
    Abstract base class for model definitions across backends.

    All backend-specific models should inherit from this and implement
    the abstract methods.
    """
    # Core metadata
    name: str  # Display name (e.g., "Gemma 4 26B (High Quality)")
    size: ModelSize  # Model size category
    description: str  # Human-readable description

    # Hardware requirements
    ram_gb: float  # Base RAM usage (GB)
    min_ram: int  # Minimum system RAM (GB)
    max_ram: int  # Maximum recommended RAM (GB)

    # Context options
    contexts: List[ContextOption] = field(default_factory=list)

    # Selection metadata
    recommended: bool = False  # Whether this is the default recommendation
    performance_tier: str = "balanced"  # "fast", "balanced", "quality"

    @abstractmethod
    def get_identifier(self) -> str:
        """
        Get backend-specific model identifier.

        Returns:
            Model identifier string (e.g., "gemma4:26b" for Ollama,
            "ggml-org/gemma-4-26B-A4B-it-GGUF:Q4_K_M" for llama.cpp)
        """
        pass

    @abstractmethod
    def get_backend(self) -> Backend:
        """Get the backend type for this model."""
        pass

    def supports_ram(self, ram_gb: float) -> bool:
        """Check if model is suitable for given RAM."""
        return self.min_ram <= ram_gb <= self.max_ram

    def get_default_context(self) -> ContextOption:
        """Get default context option (first one, or create default)."""
        if self.contexts:
            return self.contexts[0]
        # Fallback: 32K context
        return ContextOption(
            size=32768,
            description=f"32K context (~{self.ram_gb:.0f}GB RAM)",
            ram_gb=self.ram_gb
        )


@dataclass
class OllamaModel(BaseModel):
    """Ollama backend model definition."""
    ollama_name: str = ""  # Ollama model name (e.g., "gemma4:26b")

    def get_identifier(self) -> str:
        """Return Ollama model name."""
        return self.ollama_name

    def get_backend(self) -> Backend:
        """Return Ollama backend type."""
        return Backend.OLLAMA


@dataclass
class LlamaCppModel(BaseModel):
    """llama.cpp backend model definition."""
    hf_repo: str = ""  # HuggingFace repo:file (e.g., "ggml-org/gemma-4-26B-A4B-it-GGUF:Q4_K_M")

    def get_identifier(self) -> str:
        """Return HuggingFace repo identifier."""
        return self.hf_repo

    def get_backend(self) -> Backend:
        """Return llama.cpp backend type."""
        return Backend.LLAMACPP

    def get_repo_and_file(self) -> Tuple[str, str]:
        """
        Split HuggingFace repo into (repo_id, filename).

        Returns:
            Tuple of (repo_id, filename) where filename has .gguf extension

        Raises:
            ValueError: If hf_repo format is invalid
        """
        if ':' not in self.hf_repo:
            raise ValueError(f"Invalid hf_repo format: {self.hf_repo} (expected 'repo:file')")

        repo_id, filename = self.hf_repo.rsplit(':', 1)

        # Ensure .gguf extension
        if not filename.endswith('.gguf'):
            filename = f"{filename}.gguf"

        return repo_id, filename


# =============================================================================
# LLAMA.CPP MODEL CATALOG
# =============================================================================

LLAMACPP_MODELS: Dict[str, LlamaCppModel] = {
    "2b": LlamaCppModel(
        name="Gemma 4 2B (Efficient)",
        size=ModelSize.SMALL,
        hf_repo="ggml-org/gemma-4-E2B-it-GGUF:Q8_0",
        ram_gb=2.5,
        min_ram=4,
        max_ram=12,
        description="Fast, efficient model for basic coding tasks.",
        contexts=[
            ContextOption(32768, "32K context (~3GB RAM)", 3.0)
        ],
        performance_tier="fast"
    ),
    "4b": LlamaCppModel(
        name="Gemma 4 4B (Balanced)",
        size=ModelSize.MEDIUM,
        hf_repo="ggml-org/gemma-4-E4B-it-GGUF:Q4_K_M",
        ram_gb=4.5,
        min_ram=8,
        max_ram=16,
        description="Balanced performance and quality.",
        contexts=[
            ContextOption(32768, "32K context (~5GB RAM)", 5.0)
        ],
        performance_tier="balanced"
    ),
    "26b": LlamaCppModel(
        name="Gemma 4 26B (High Quality)",
        size=ModelSize.LARGE,
        hf_repo="ggml-org/gemma-4-26B-A4B-it-GGUF:gemma-4-26B-A4B-it-Q4_K_M.gguf",
        ram_gb=16.0,
        min_ram=16,
        max_ram=32,
        description="High quality 26B model, excellent balance.",
        contexts=[
            ContextOption(32768, "32K context (~17GB RAM)", 17.0),
            ContextOption(65536, "64K context (~20GB RAM)", 20.0),
            ContextOption(131072, "128K context (~25GB RAM)", 25.0),
        ],
        performance_tier="quality",
        recommended=True
    ),
    "31b": LlamaCppModel(
        name="Gemma 4 31B (Maximum Quality)",
        size=ModelSize.XLARGE,
        hf_repo="ggml-org/gemma-4-31B-it-GGUF:gemma-4-31B-it-Q4_K_M.gguf",
        ram_gb=20.0,
        min_ram=24,
        max_ram=64,
        description="Largest model, best quality for high-RAM systems.",
        contexts=[
            ContextOption(32768, "32K context (~21GB RAM)", 21.0),
            ContextOption(65536, "64K context (~24GB RAM)", 24.0),
            ContextOption(131072, "128K context (~28GB RAM)", 28.0),
        ],
        performance_tier="quality"
    ),
}


# =============================================================================
# OLLAMA MODEL CATALOG
# =============================================================================

OLLAMA_MODELS: Dict[str, OllamaModel] = {
    "2b": OllamaModel(
        name="Gemma4 2B (Efficient)",
        size=ModelSize.SMALL,
        ollama_name="gemma4:e2b",
        ram_gb=2.5,
        min_ram=4,
        max_ram=12,
        description="Fast, efficient model for basic coding tasks.",
        performance_tier="fast"
    ),
    "4b": OllamaModel(
        name="Gemma4 4B (Balanced)",
        size=ModelSize.MEDIUM,
        ollama_name="gemma4:e4b",
        ram_gb=4.5,
        min_ram=8,
        max_ram=16,
        description="Balanced performance and quality.",
        performance_tier="balanced"
    ),
    "26b-optimized": OllamaModel(
        name="Gemma4 26B (Optimized for 16GB VRAM)",
        size=ModelSize.LARGE,
        ollama_name="VladimirGav/gemma4-26b-16GB-VRAM:latest",
        ram_gb=16.0,
        min_ram=16,
        max_ram=32,
        description="Optimized 26B model for Mac Silicon with 16GB+ RAM.",
        performance_tier="quality",
        recommended=True
    ),
    "26b": OllamaModel(
        name="Gemma4 26B (Standard)",
        size=ModelSize.LARGE,
        ollama_name="gemma4:26b",
        ram_gb=16.0,
        min_ram=16,
        max_ram=32,
        description="Standard 26B model, high quality code generation.",
        performance_tier="quality"
    ),
    "31b": OllamaModel(
        name="Gemma4 31B (Maximum Quality)",
        size=ModelSize.XLARGE,
        ollama_name="gemma4:31b",
        ram_gb=20.0,
        min_ram=24,
        max_ram=64,
        description="Largest model, best quality for high-RAM systems.",
        performance_tier="quality"
    ),
}


def get_model_catalog(backend: Backend) -> Dict[str, BaseModel]:
    """
    Get model catalog for specified backend.

    Args:
        backend: Backend type

    Returns:
        Dictionary mapping model keys to model objects
    """
    if backend == Backend.LLAMACPP:
        return LLAMACPP_MODELS
    elif backend == Backend.OLLAMA:
        return OLLAMA_MODELS
    else:
        raise ValueError(f"Unknown backend: {backend}")


def get_recommended_model(
    backend: Backend,
    hw_info: hardware.HardwareInfo
) -> Optional[BaseModel]:
    """
    Get recommended model for hardware and backend.

    Args:
        backend: Backend type
        hw_info: Hardware information

    Returns:
        Recommended model, or None if no suitable model found
    """
    catalog = get_model_catalog(backend)

    # Filter by RAM
    suitable = [m for m in catalog.values() if m.supports_ram(hw_info.ram_gb)]

    if not suitable:
        return None

    # First try to find a model marked as recommended
    for model in suitable:
        if model.recommended and model.supports_ram(hw_info.ram_gb):
            return model

    # Otherwise, pick the largest model that fits RAM constraints
    return max(suitable, key=lambda m: m.ram_gb)


def filter_models_by_ram(
    catalog: Dict[str, BaseModel],
    ram_gb: float
) -> Dict[str, BaseModel]:
    """
    Filter model catalog by available RAM.

    Args:
        catalog: Model catalog dictionary
        ram_gb: Available RAM in GB

    Returns:
        Filtered dictionary of suitable models
    """
    return {
        key: model
        for key, model in catalog.items()
        if model.supports_ram(ram_gb)
    }
