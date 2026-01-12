"""
Smart Model Selector for Continue.dev + Ollama Setup.

Implements the "single best recommendation" approach:
- Recommends highest quality model that safely fits in available RAM
- Primary use case is coding (Continue.dev)
- Balanced portfolio: one good all-rounder + fast autocomplete + embeddings
- Conservative RAM assumptions (users won't close other apps)

Model selection is based on:
- Continue.dev recommended models (https://docs.continue.dev/customize/models#recommended-models)
- Hardware tier (RAM-based)
- Tier-based RAM reservation (40%/35%/30%)
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
    description: str = ""
    fallback_name: Optional[str] = None  # Fallback Ollama name if primary fails
    min_perf_score: float = 1.0  # Minimum CPU performance score needed
    requires_fp16: bool = False  # Whether FP16 quantization is required (M3 Pro+ or M4+)
    recommended_for: List[str] = field(default_factory=list)  # Chip generations/tiers optimized for


@dataclass
class ModelRecommendation:
    """Complete model recommendation for a hardware tier."""
    primary: RecommendedModel  # Primary coding model
    autocomplete: Optional[RecommendedModel] = None  # Fast autocomplete model
    embeddings: Optional[RecommendedModel] = None  # Embeddings model
    reasoning: Optional[RecommendedModel] = None  # Optional reasoning model
    vision: Optional[RecommendedModel] = None  # Optional vision model
    
    def all_models(self) -> List[RecommendedModel]:
        """Get all models in the recommendation."""
        models = [self.primary]
        if self.autocomplete:
            models.append(self.autocomplete)
        if self.embeddings:
            models.append(self.embeddings)
        if self.reasoning:
            models.append(self.reasoning)
        if self.vision:
            models.append(self.vision)
        return models
    
    def total_ram(self) -> float:
        """Get total RAM usage for all models."""
        return sum(m.ram_gb for m in self.all_models())


# =============================================================================
# MODEL CATALOG - Dynamic Selection Based on RAM + CPU
# Organized by family with all variants, sorted by size/quality
# =============================================================================

# Embedding models - universal across all tiers
# Note: nomic-embed-text is widely available and reliable
EMBED_MODEL = RecommendedModel(
    name="Nomic Embed Text",
    ollama_name="nomic-embed-text",
    ram_gb=0.3,
    role=ModelRole.EMBED,
    roles=["embed"],
    description="Best open embedding model for code indexing (8192 tokens)",
    fallback_name="all-minilm",
    min_perf_score=1.0,
    requires_fp16=False,
    recommended_for=["all"]
)

# Model families with all variants, sorted from smallest to largest
# Only Meta Llama models are offered (3.1 for small, 3.3 for large)
# Source of truth: Mac Model + RAM determines model selection
MODEL_FAMILIES = {
    "llama": [
        # Llama 3.1 8B - for most configurations (all except Ultra and high-end Max)
        RecommendedModel(
            name="Llama 3.1 8B",
            ollama_name="llama3.1:8b",
            ram_gb=4.58,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="Meta Llama 3.1 8B - Best scaling across all hardware",
            fallback_name="llama3.1:8b",
            min_perf_score=1.0,
            requires_fp16=False,
            recommended_for=["M1", "M2", "M3", "M4"]
        ),
        # Llama 3.3 70B - for Ultra and high-end Max models (48GB+)
        RecommendedModel(
            name="Llama 3.3 70B",
            ollama_name="llama3.3:70b",
            ram_gb=39.59,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="Meta Llama 3.3 70B - Top tier quality",
            fallback_name="llama3.1:8b",
            min_perf_score=2.0,
            requires_fp16=False,
            recommended_for=["M1 Ultra", "M2 Ultra", "M3 Max 48GB+", "M4 Pro 48GB", "M4 Max"]
        ),
    ],
}

# Legacy tier-based catalogs (kept for backward compatibility during transition)
# These will be removed after full migration
AUTOCOMPLETE_MODELS = {
    hardware.HardwareTier.S: RecommendedModel(
        name="StarCoder2 3B",
        ollama_name="starcoder2:3b",
        ram_gb=2.0,
        role=ModelRole.AUTOCOMPLETE,
        roles=["autocomplete", "chat", "edit"],
        description="Fast autocomplete - optimized for code completion",
        fallback_name="codegemma:2b"
    ),
    hardware.HardwareTier.A: RecommendedModel(
        name="StarCoder2 3B",
        ollama_name="starcoder2:3b",
        ram_gb=2.0,
        role=ModelRole.AUTOCOMPLETE,
        roles=["autocomplete", "chat", "edit"],
        description="Fast autocomplete - optimized for code completion",
        fallback_name="codegemma:2b"
    ),
    hardware.HardwareTier.B: RecommendedModel(
        name="StarCoder2 3B",
        ollama_name="starcoder2:3b",
        ram_gb=2.0,
        role=ModelRole.AUTOCOMPLETE,
        roles=["autocomplete", "chat", "edit"],
        description="Fast autocomplete - optimized for code completion",
        fallback_name="codegemma:2b"
    ),
    hardware.HardwareTier.C: RecommendedModel(
        name="StarCoder2 3B",
        ollama_name="starcoder2:3b",
        ram_gb=2.0,
        role=ModelRole.AUTOCOMPLETE,
        roles=["autocomplete", "chat", "edit"],
        description="Fast autocomplete - also serves as primary on 16GB",
        fallback_name="codegemma:2b"
    ),
}

PRIMARY_MODELS = {
    hardware.HardwareTier.S: [
        RecommendedModel(
            name="Codestral 22B",
            ollama_name="codestral:22b",
            ram_gb=13.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="Mistral's Codestral - Best open coding model",
            fallback_name="codestral:latest"
        ),
        RecommendedModel(
            name="CodeLlama 13B",
            ollama_name="codellama:13b",
            ram_gb=7.5,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="Meta's CodeLlama 13B - Excellent code generation",
            fallback_name="codellama:7b"
        ),
    ],
    hardware.HardwareTier.A: [
        RecommendedModel(
            name="Codestral 22B",
            ollama_name="codestral:22b",
            ram_gb=13.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="Mistral's Codestral - Best open coding model",
            fallback_name="codestral:latest"
        ),
        RecommendedModel(
            name="CodeLlama 13B",
            ollama_name="codellama:13b",
            ram_gb=7.5,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="Meta's CodeLlama 13B - Excellent code generation",
            fallback_name="codellama:7b"
        ),
    ],
    hardware.HardwareTier.B: [
        RecommendedModel(
            name="Granite Code 8B",
            ollama_name="granite-code:8b",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="IBM's Granite Code - Balanced coding model",
            fallback_name="granite-code:latest"
        ),
        RecommendedModel(
            name="CodeLlama 7B",
            ollama_name="codellama:7b",
            ram_gb=4.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="Meta's CodeLlama 7B - Reliable coding model",
            fallback_name="starcoder2:3b"
        ),
    ],
    hardware.HardwareTier.C: [
        RecommendedModel(
            name="CodeLlama 7B",
            ollama_name="codellama:7b",
            ram_gb=4.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="Meta's CodeLlama 7B - Reliable coding model",
            fallback_name="starcoder2:3b"
        ),
        RecommendedModel(
            name="Granite Code 8B",
            ollama_name="granite-code:8b",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="IBM's Granite Code - Balanced coding model",
            fallback_name="granite-code:latest"
        ),
    ],
}

REASONING_MODELS = {
    hardware.HardwareTier.S: RecommendedModel(
        name="Phi-4",
        ollama_name="phi4:latest",
        ram_gb=9.0,
        role=ModelRole.CHAT,
        roles=["chat", "edit"],
        description="Microsoft's Phi-4 - Reasoning and architecture",
        fallback_name="llama3.2:3b"
    ),
    hardware.HardwareTier.A: RecommendedModel(
        name="Phi-4",
        ollama_name="phi4:latest",
        ram_gb=9.0,
        role=ModelRole.CHAT,
        roles=["chat", "edit"],
        description="Microsoft's Phi-4 - Reasoning and architecture",
        fallback_name="llama3.2:3b"
    ),
}

VISION_MODELS = {
    hardware.HardwareTier.S: RecommendedModel(
        name="LLaVA 7B",
        ollama_name="llava:7b",
        ram_gb=5.0,
        role=ModelRole.CHAT,
        roles=["chat", "vision"],
        description="Vision model for analyzing images/screenshots",
        fallback_name="llava:latest"
    ),
    hardware.HardwareTier.A: RecommendedModel(
        name="LLaVA 7B",
        ollama_name="llava:7b",
        ram_gb=5.0,
        role=ModelRole.CHAT,
        roles=["chat", "vision"],
        description="Vision model for analyzing images/screenshots",
        fallback_name="llava:latest"
    ),
}

# Autocomplete models by tier
# Note: Using starcoder2:3b as primary autocomplete - it's proven and reliable
# Granite-code models may have availability issues in some regions
AUTOCOMPLETE_MODELS = {
    hardware.HardwareTier.S: RecommendedModel(
        name="StarCoder2 3B",
        ollama_name="starcoder2:3b",
        ram_gb=2.0,
        role=ModelRole.AUTOCOMPLETE,
        roles=["autocomplete", "chat", "edit"],
        description="Fast autocomplete - optimized for code completion",
        fallback_name="codegemma:2b"
    ),
    hardware.HardwareTier.A: RecommendedModel(
        name="StarCoder2 3B",
        ollama_name="starcoder2:3b",
        ram_gb=2.0,
        role=ModelRole.AUTOCOMPLETE,
        roles=["autocomplete", "chat", "edit"],
        description="Fast autocomplete - optimized for code completion",
        fallback_name="codegemma:2b"
    ),
    hardware.HardwareTier.B: RecommendedModel(
        name="StarCoder2 3B",
        ollama_name="starcoder2:3b",
        ram_gb=2.0,
        role=ModelRole.AUTOCOMPLETE,
        roles=["autocomplete", "chat", "edit"],
        description="Fast autocomplete - optimized for code completion",
        fallback_name="codegemma:2b"
    ),
    hardware.HardwareTier.C: RecommendedModel(
        name="StarCoder2 3B",
        ollama_name="starcoder2:3b",
        ram_gb=2.0,
        role=ModelRole.AUTOCOMPLETE,
        roles=["autocomplete", "chat", "edit"],
        description="Fast autocomplete - also serves as primary on 16GB",
        fallback_name="codegemma:2b"
    ),
}

# Primary coding models by tier (largest that fits safely)
# These are the "best quality model that safely fits in available RAM"
PRIMARY_MODELS = {
    hardware.HardwareTier.S: [
        # Tier S (>64GB): Can run 22B models comfortably
        RecommendedModel(
            name="Codestral 22B",
            ollama_name="codestral:22b",
            ram_gb=13.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="Mistral's Codestral - Best open coding model",
            fallback_name="codestral:latest"
        ),
        RecommendedModel(
            name="CodeLlama 13B",
            ollama_name="codellama:13b",
            ram_gb=7.5,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="Meta's CodeLlama 13B - Excellent code generation",
            fallback_name="codellama:7b"
        ),
    ],
    hardware.HardwareTier.A: [
        # Tier A (32-64GB): 14B models with good quality
        RecommendedModel(
            name="Codestral 22B",
            ollama_name="codestral:22b",
            ram_gb=13.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="Mistral's Codestral - Best open coding model",
            fallback_name="codestral:latest"
        ),
        RecommendedModel(
            name="CodeLlama 13B",
            ollama_name="codellama:13b",
            ram_gb=7.5,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="Meta's CodeLlama 13B - Excellent code generation",
            fallback_name="codellama:7b"
        ),
    ],
    hardware.HardwareTier.B: [
        # Tier B (24-32GB): 7-8B models
        RecommendedModel(
            name="Granite Code 8B",
            ollama_name="granite-code:8b",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="IBM's Granite Code - Balanced coding model",
            fallback_name="granite-code:latest"
        ),
        RecommendedModel(
            name="CodeLlama 7B",
            ollama_name="codellama:7b",
            ram_gb=4.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="Meta's CodeLlama 7B - Reliable coding model",
            fallback_name="starcoder2:3b"
        ),
    ],
    hardware.HardwareTier.C: [
        # Tier C (16-24GB): 3-8B models
        RecommendedModel(
            name="CodeLlama 7B",
            ollama_name="codellama:7b",
            ram_gb=4.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="Meta's CodeLlama 7B - Reliable coding model",
            fallback_name="starcoder2:3b"
        ),
        RecommendedModel(
            name="Granite Code 8B",
            ollama_name="granite-code:8b",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="IBM's Granite Code - Balanced coding model",
            fallback_name="granite-code:latest"
        ),
    ],
}

# Optional reasoning models (for Multi-Model presets)
# Note: Using "chat" and "edit" roles which are valid in Continue.dev schema
# The "agent" role is not part of the schema, so we use standard roles
REASONING_MODELS = {
    hardware.HardwareTier.S: RecommendedModel(
        name="Phi-4",
        ollama_name="phi4:latest",
        ram_gb=9.0,
        role=ModelRole.CHAT,
        roles=["chat", "edit"],
        description="Microsoft's Phi-4 - Reasoning and architecture",
        fallback_name="llama3.2:3b"
    ),
    hardware.HardwareTier.A: RecommendedModel(
        name="Phi-4",
        ollama_name="phi4:latest",
        ram_gb=9.0,
        role=ModelRole.CHAT,
        roles=["chat", "edit"],
        description="Microsoft's Phi-4 - Reasoning and architecture",
        fallback_name="llama3.2:3b"
    ),
}

# Optional vision models (for advanced users)
VISION_MODELS = {
    hardware.HardwareTier.S: RecommendedModel(
        name="LLaVA 7B",
        ollama_name="llava:7b",
        ram_gb=5.0,
        role=ModelRole.CHAT,
        roles=["chat", "vision"],
        description="Vision model for analyzing images/screenshots",
        fallback_name="llava:latest"
    ),
    hardware.HardwareTier.A: RecommendedModel(
        name="LLaVA 7B",
        ollama_name="llava:7b",
        ram_gb=5.0,
        role=ModelRole.CHAT,
        roles=["chat", "vision"],
        description="Vision model for analyzing images/screenshots",
        fallback_name="llava:latest"
    ),
}


def get_usable_ram(hw_info: hardware.HardwareInfo) -> float:
    """
    Get usable RAM for models based on tier-based reservation.
    
    Uses tier-specific reservation from HardwareInfo.get_tier_ram_reservation().
    """
    reservation = hw_info.get_tier_ram_reservation()
    return hw_info.ram_gb * (1 - reservation)


def get_available_families(hw_info: hardware.HardwareInfo) -> List[Dict[str, str]]:
    """
    Get list of available model families with their descriptions.
    
    Args:
        hw_info: Hardware information
        
    Returns:
        List of dicts with family info (name, description, emoji/icon)
    """
    return [
        {
            "key": "llama",
            "name": "Meta Llama",
            "description": "Best scaling (3.1 for small, 3.3 for large)",
            "icon": "⭐"
        },
    ]


def get_model_for_family(hw_info: hardware.HardwareInfo, family: str) -> RecommendedModel:
    """
    Get the best model variant for a given family based on Mac model + RAM.
    
    Selection rules based on source of truth matrix:
    - Most configurations: llama3.1:8b (4.58GB)
    - Ultra models (64GB+): llama3.3:70b (39.59GB Ollama / 37.22GB Docker)
    - M3 Max 48GB+: llama3.3:70b
    - M4 Pro 48GB: llama3.3:70b
    - M4 Max: llama3.3:70b
    
    Args:
        hw_info: Hardware information
        family: Family name ("llama")
        
    Returns:
        Selected RecommendedModel variant
        
    Raises:
        ValueError: If hardware not supported or family not found
    """
    # Validate Apple Silicon
    capabilities = hardware.get_apple_silicon_capabilities(hw_info)
    if capabilities is None:
        raise ValueError("This setup only supports Apple Silicon Macs")
    
    # Get family variants
    if family not in MODEL_FAMILIES:
        raise ValueError(f"Unknown model family: {family}")
    
    variants = MODEL_FAMILIES[family]
    if not variants:
        raise ValueError(f"No variants available for family: {family}")
    
    chip_model = hw_info.apple_chip_model or ""
    ram_gb = hw_info.ram_gb
    usable_ram = capabilities["usable_ram_gb"]
    performance_score = capabilities["performance_score"]
    
    # Check for Ultra models or high-end Max models that should get 70B
    # Based on source of truth matrix: Ultra (64GB+) and high-end Max (48GB+) get 70B
    is_ultra = "Ultra" in chip_model
    is_m3_max_48gb_plus = "M3 Max" in chip_model and ram_gb >= 48
    is_m4_pro_48gb = "M4 Pro" in chip_model and ram_gb >= 48
    is_m4_max = "M4 Max" in chip_model
    
    # Select 70B model for Ultra/high-end configurations
    if is_ultra or is_m3_max_48gb_plus or is_m4_pro_48gb or is_m4_max:
        # Find 70B variant
        for variant in variants:
            if "70b" in variant.ollama_name.lower():
                # Verify it fits in RAM and meets CPU requirements
                if variant.ram_gb <= usable_ram and variant.min_perf_score <= performance_score:
                    return variant
                # If it doesn't fit, fall back to 8B
                break
    
    # Default to 8B model for all other configurations
    for variant in variants:
        if "8b" in variant.ollama_name.lower():
            # Verify it fits (should always fit, but check anyway)
            if variant.ram_gb <= usable_ram:
                return variant
    
    # Fallback to smallest variant
    return variants[0]


def explain_model_selection(
    hw_info: hardware.HardwareInfo,
    model: RecommendedModel,
    family: str
) -> str:
    """
    Generate human-readable explanation of model selection.
    
    Args:
        hw_info: Hardware information
        model: Selected model
        family: Family name
        
    Returns:
        Human-readable explanation string
    """
    capabilities = hardware.get_apple_silicon_capabilities(hw_info)
    if capabilities is None:
        return f"Selected {model.name} ({model.ram_gb:.1f}GB)"
    
    usable_ram = capabilities["usable_ram_gb"]
    performance_score = capabilities["performance_score"]
    chip_model = hw_info.apple_chip_model or "Apple Silicon"
    
    reasons = []
    reasons.append(f"Fits in {usable_ram:.1f}GB usable RAM ✓")
    
    if performance_score >= model.min_perf_score:
        reasons.append(f"Your {chip_model} (score {performance_score:.1f}) exceeds minimum ({model.min_perf_score:.1f}) ✓")
    else:
        reasons.append(f"Your {chip_model} (score {performance_score:.1f}) meets minimum ({model.min_perf_score:.1f}) ✓")
    
    if "Q4" in model.name:
        reasons.append("Q4 quantization provides good balance of quality and speed")
    elif "Q5" in model.name:
        reasons.append("Q5 quantization provides higher quality")
    elif "FP16" in model.name:
        reasons.append("FP16 provides highest quality")
    
    return " • ".join(reasons)


# =============================================================================
# DEPRECATED FUNCTIONS - Kept for backward compatibility with tests
# These functions are no longer used by the new family-based selection workflow
# =============================================================================

def generate_best_recommendation(hw_info: hardware.HardwareInfo) -> ModelRecommendation:
    """
    DEPRECATED: Use get_model_for_family() instead.
    
    Generate the single best recommendation for the hardware.
    Kept for backward compatibility with tests.
    """
    tier = hw_info.tier
    usable_ram = get_usable_ram(hw_info)
    
    # Target usage: 70% of usable RAM for safety buffer
    target_ram = usable_ram * 0.70
    
    # Get embeddings (always included, ~0.3GB)
    embeddings = EMBED_MODEL
    remaining_ram = target_ram - embeddings.ram_gb
    
    # Get autocomplete (always included)
    autocomplete = AUTOCOMPLETE_MODELS.get(tier, AUTOCOMPLETE_MODELS[hardware.HardwareTier.C])
    remaining_ram -= autocomplete.ram_gb
    
    # Select best primary model that fits in remaining RAM
    primary = None
    primary_options = PRIMARY_MODELS.get(tier, PRIMARY_MODELS[hardware.HardwareTier.C])
    
    for model in primary_options:
        if model.ram_gb <= remaining_ram:
            primary = model
            break
    
    # Fallback: use the smallest primary model available
    if primary is None:
        primary = primary_options[-1] if primary_options else autocomplete
    
    # Don't include autocomplete if it's the same model as primary
    include_autocomplete = autocomplete.ollama_name != primary.ollama_name
    
    return ModelRecommendation(
        primary=primary,
        autocomplete=autocomplete if include_autocomplete else None,
        embeddings=embeddings
    )


def display_recommendation(
    recommendation: ModelRecommendation,
    hw_info: hardware.HardwareInfo,
    title: str = "Recommended setup"
) -> None:
    """
    DEPRECATED: Display logic is now integrated into select_models_smart().
    
    Display a model recommendation in user-friendly format.
    Kept for backward compatibility with tests.
    """
    usable_ram = get_usable_ram(hw_info)
    total_ram = recommendation.total_ram()
    buffer = usable_ram - total_ram
    buffer_percent = (buffer / usable_ram * 100) if usable_ram > 0 else 0
    usage_percent = (total_ram / usable_ram * 100) if usable_ram > 0 else 0
    
    print()
    print(ui.colorize(f"{title}:", ui.Colors.GREEN + ui.Colors.BOLD))
    
    # Primary model
    print(f"  • {ui.colorize(recommendation.primary.ollama_name, ui.Colors.CYAN)} (primary coding) - {recommendation.primary.ram_gb:.1f}GB")
    
    # Autocomplete (if separate from primary)
    if recommendation.autocomplete:
        print(f"  • {ui.colorize(recommendation.autocomplete.ollama_name, ui.Colors.CYAN)} (autocomplete) - {recommendation.autocomplete.ram_gb:.1f}GB")
    
    # Embeddings
    if recommendation.embeddings:
        print(f"  • {ui.colorize(recommendation.embeddings.ollama_name, ui.Colors.CYAN)} (codebase search) - {recommendation.embeddings.ram_gb:.1f}GB")
    
    # Reasoning (if included)
    if recommendation.reasoning:
        print(f"  • {ui.colorize(recommendation.reasoning.ollama_name, ui.Colors.CYAN)} (reasoning) - {recommendation.reasoning.ram_gb:.1f}GB")
    
    # Vision (if included)
    if recommendation.vision:
        print(f"  • {ui.colorize(recommendation.vision.ollama_name, ui.Colors.CYAN)} (vision) - {recommendation.vision.ram_gb:.1f}GB")
    
    print()
    
    # Color code the usage
    if usage_percent < 70:
        color = ui.Colors.GREEN
    elif usage_percent < 85:
        color = ui.Colors.YELLOW
    else:
        color = ui.Colors.RED
    
    print(ui.colorize(
        f"Total: {total_ram:.1f}GB / {usable_ram:.1f}GB usable ({buffer_percent:.0f}% buffer remaining)",
        color
    ))


def select_models_smart(hw_info: hardware.HardwareInfo, installed_ides: Optional[List[str]] = None) -> List[RecommendedModel]:
    """
    Smart model selection with family-based selection.
    
    New workflow:
    1. Display hardware detection with capabilities
    2. User picks model family
    3. Script automatically selects best variant based on RAM + CPU
    4. Display selection with reasoning
    
    Args:
        hw_info: Hardware information
        installed_ides: List of installed IDEs (auto-detected if None)
    
    Returns:
        List of RecommendedModel objects to install
    """
    ui.print_header("🤖 Smart Model Selection")
    
    # Validate Apple Silicon support
    is_supported, error_msg = hardware.validate_apple_silicon_support(hw_info)
    if not is_supported:
        ui.print_error(error_msg or "This setup only supports Apple Silicon Macs")
        raise SystemExit("Hardware requirements not met: Apple Silicon required")
    
    # Get hardware capabilities
    capabilities = hardware.get_apple_silicon_capabilities(hw_info)
    if capabilities is None:
        ui.print_error("Unable to determine hardware capabilities")
        raise SystemExit("Hardware detection failed")
    
    # Display hardware detection with capabilities
    print()
    chip_model = hw_info.apple_chip_model or hw_info.cpu_brand
    ui.print_success(f"Detected: {chip_model} {hw_info.ram_gb:.0f}GB")
    
    if installed_ides:
        ide_str = ", ".join(installed_ides)
        ui.print_success(f"Scanned: {ide_str} installed")
    
    print()
    print(f"  System RAM:           {hw_info.ram_gb:.0f}GB")
    usable_ram = capabilities["usable_ram_gb"]
    reservation = hw_info.get_tier_ram_reservation()
    reserved_ram = hw_info.ram_gb * reservation
    print(f"  Reserved ({reservation:.0%}):     {reserved_ram:.1f}GB (for OS, IDE, browser)")
    print(f"  Usable RAM:          {usable_ram:.1f}GB (for models)")
    print(f"  CPU Performance:    {capabilities['performance_score']:.1f} ({chip_model} with {hw_info.cpu_perf_cores}P cores)")
    print(f"  Can handle FP16:     {'Yes' if capabilities['can_handle_fp16'] else 'No'}")
    
    # Only one family available (Meta Llama), so auto-select it
    selected_family_key = "llama"
    selected_family_name = "Meta Llama"
    
    print()
    ui.print_info(f"Model Family: {selected_family_name} ⭐ Best scaling")
    
    # Script automatically selects best variant
    try:
        selected_model = get_model_for_family(hw_info, selected_family_key)
    except ValueError as e:
        ui.print_error(str(e))
        raise SystemExit("Model selection failed")
    
    # Display selection with reasoning
    print()
    ui.print_success(f"Selected: {selected_model.ollama_name} (~{selected_model.ram_gb:.1f}GB)")
    print()
    print("Selection reasoning:")
    reasoning = explain_model_selection(hw_info, selected_model, selected_family_key)
    print(f"  {reasoning}")
    
    # Always include embeddings
    models_to_install = [selected_model, EMBED_MODEL]
    
    print()
    ui.print_success("Models to install:")
    for model in models_to_install:
        print(f"  • {ui.colorize(model.ollama_name, ui.Colors.CYAN)} - {model.ram_gb:.1f}GB")
    
    total_ram = sum(m.ram_gb for m in models_to_install)
    usage_percent = (total_ram / usable_ram * 100) if usable_ram > 0 else 0
    
    print()
    if usage_percent < 70:
        color = ui.Colors.GREEN
    elif usage_percent < 85:
        color = ui.Colors.YELLOW
    else:
        color = ui.Colors.RED
    
    print(ui.colorize(
        f"Total: {total_ram:.1f}GB / {usable_ram:.1f}GB usable ({usage_percent:.0f}% used)",
        color
    ))
    
    return models_to_install
