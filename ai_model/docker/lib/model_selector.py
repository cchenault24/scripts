"""
Smart Model Selector for Continue.dev + Docker Model Runner Setup.

Implements the "single best recommendation" approach:
- Recommends highest quality model that safely fits in available RAM
- Primary use case is coding (Continue.dev)
- Balanced portfolio: one good all-rounder + fast autocomplete + embeddings
- Conservative RAM assumptions (users won't close other apps)

Model selection is based on:
- Docker Hub ai/ namespace available models
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
    name: str  # Display name (e.g., "Codestral")
    docker_name: str  # Full Docker name (e.g., "ai/codestral")
    ram_gb: float  # Estimated RAM usage
    role: ModelRole  # Primary role
    roles: List[str]  # All supported roles
    context_length: int = 32768  # Default context length
    description: str = ""
    fallback_name: Optional[str] = None  # Fallback Docker name if primary fails


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
# HARDCODED MODEL CATALOG
# Primary source: Docker Hub ai/ namespace
# Filtered to only Docker Model Runner compatible models
# =============================================================================

# Embedding models - universal across all tiers
EMBED_MODEL = RecommendedModel(
    name="Nomic Embed Text v1.5",
    docker_name="ai/nomic-embed-text-v1.5",
    ram_gb=0.3,
    role=ModelRole.EMBED,
    roles=["embed"],
    context_length=8192,
    description="Best open embedding model for code indexing (8192 tokens)",
    fallback_name="ai/all-minilm-l6-v2-vllm"
)

# Autocomplete models by tier
AUTOCOMPLETE_MODELS = {
    hardware.HardwareTier.S: RecommendedModel(
        name="Granite 4.0 H-Tiny",
        docker_name="ai/granite-4.0-h-tiny",
        ram_gb=1.0,
        role=ModelRole.AUTOCOMPLETE,
        roles=["autocomplete"],
        context_length=131072,
        description="IBM's Granite - Ultra-fast autocomplete",
        fallback_name="ai/llama3.2"
    ),
    hardware.HardwareTier.A: RecommendedModel(
        name="Granite 4.0 H-Tiny",
        docker_name="ai/granite-4.0-h-tiny",
        ram_gb=1.0,
        role=ModelRole.AUTOCOMPLETE,
        roles=["autocomplete"],
        context_length=131072,
        description="IBM's Granite - Ultra-fast autocomplete",
        fallback_name="ai/llama3.2"
    ),
    hardware.HardwareTier.B: RecommendedModel(
        name="Granite 4.0 H-Tiny",
        docker_name="ai/granite-4.0-h-tiny",
        ram_gb=1.0,
        role=ModelRole.AUTOCOMPLETE,
        roles=["autocomplete"],
        context_length=131072,
        description="IBM's Granite - Ultra-fast autocomplete",
        fallback_name="ai/llama3.2"
    ),
    hardware.HardwareTier.C: RecommendedModel(
        name="Llama 3.2",
        docker_name="ai/llama3.2",
        ram_gb=1.8,
        role=ModelRole.AUTOCOMPLETE,
        roles=["autocomplete", "chat", "edit"],
        context_length=131072,
        description="Meta's Llama 3.2 - Fast and efficient",
        fallback_name="ai/granite-4.0-h-tiny"
    ),
}

# Primary coding models by tier (largest that fits safely)
PRIMARY_MODELS = {
    hardware.HardwareTier.S: [
        RecommendedModel(
            name="Granite 4.0 H-Small",
            docker_name="ai/granite-4.0-h-small",
            ram_gb=18.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            context_length=131072,
            description="IBM's Granite 4.0 - State-of-the-art code generation",
            fallback_name="ai/codestral"
        ),
        RecommendedModel(
            name="Codestral",
            docker_name="ai/codestral",
            ram_gb=12.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            context_length=32768,
            description="Mistral's Codestral - Excellent code generation",
            fallback_name="ai/devstral-small"
        ),
    ],
    hardware.HardwareTier.A: [
        RecommendedModel(
            name="Codestral",
            docker_name="ai/codestral",
            ram_gb=12.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            context_length=32768,
            description="Mistral's Codestral - Excellent code generation",
            fallback_name="ai/devstral-small"
        ),
        RecommendedModel(
            name="Devstral Small",
            docker_name="ai/devstral-small",
            ram_gb=9.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            context_length=32768,
            description="Mistral's Devstral - Fast and capable",
            fallback_name="ai/phi4"
        ),
    ],
    hardware.HardwareTier.B: [
        RecommendedModel(
            name="Phi-4",
            docker_name="ai/phi4",
            ram_gb=8.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit"],
            context_length=16384,
            description="Microsoft's Phi-4 - Excellent reasoning",
            fallback_name="ai/granite-4.0-h-micro"
        ),
        RecommendedModel(
            name="Granite 4.0 H-Micro",
            docker_name="ai/granite-4.0-h-micro",
            ram_gb=8.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            context_length=131072,
            description="IBM's Granite 4.0 Micro - Strong coding",
            fallback_name="ai/granite-4.0-h-nano"
        ),
    ],
    hardware.HardwareTier.C: [
        RecommendedModel(
            name="Granite 4.0 H-Nano",
            docker_name="ai/granite-4.0-h-nano",
            ram_gb=4.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            context_length=131072,
            description="IBM's Granite 4.0 Nano - Efficient coding",
            fallback_name="ai/llama3.2"
        ),
        RecommendedModel(
            name="Llama 3.2",
            docker_name="ai/llama3.2",
            ram_gb=1.8,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            context_length=131072,
            description="Meta's Llama 3.2 - Fast responses",
            fallback_name="ai/granite-4.0-h-tiny"
        ),
    ],
}

# Optional reasoning models (for Multi-Model presets)
REASONING_MODELS = {
    hardware.HardwareTier.S: RecommendedModel(
        name="Phi-4",
        docker_name="ai/phi4",
        ram_gb=8.0,
        role=ModelRole.CHAT,
        roles=["chat", "edit"],
        context_length=16384,
        description="Microsoft's Phi-4 - Reasoning and architecture",
        fallback_name="ai/llama3.2"
    ),
    hardware.HardwareTier.A: RecommendedModel(
        name="Phi-4",
        docker_name="ai/phi4",
        ram_gb=8.0,
        role=ModelRole.CHAT,
        roles=["chat", "edit"],
        context_length=16384,
        description="Microsoft's Phi-4 - Reasoning and architecture",
        fallback_name="ai/llama3.2"
    ),
}


def get_usable_ram(hw_info: hardware.HardwareInfo) -> float:
    """
    Get usable RAM for models based on tier-based reservation.
    
    Uses tier-specific reservation from HardwareInfo.get_tier_ram_reservation().
    """
    reservation = hw_info.get_tier_ram_reservation()
    return hw_info.ram_gb * (1 - reservation)


def generate_best_recommendation(hw_info: hardware.HardwareInfo) -> ModelRecommendation:
    """
    Generate the single best recommendation for the hardware.
    
    Strategy:
    1. Select largest primary model that fits (with buffer)
    2. Add autocomplete model (always included)
    3. Add embeddings model (always included)
    4. Leave buffer for system stability
    
    The recommendation uses at most 70% of usable RAM to leave buffer.
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
    include_autocomplete = autocomplete.docker_name != primary.docker_name
    
    return ModelRecommendation(
        primary=primary,
        autocomplete=autocomplete if include_autocomplete else None,
        embeddings=embeddings
    )


def generate_conservative_recommendation(hw_info: hardware.HardwareInfo) -> ModelRecommendation:
    """
    Generate a conservative recommendation prioritizing stability.
    
    Uses smaller models to leave more headroom for other apps.
    """
    tier = hw_info.tier
    usable_ram = get_usable_ram(hw_info)
    
    # For conservative, target only 50% of usable RAM
    target_ram = usable_ram * 0.50
    
    # Get embeddings
    embeddings = EMBED_MODEL
    remaining_ram = target_ram - embeddings.ram_gb
    
    # Get autocomplete
    autocomplete = AUTOCOMPLETE_MODELS.get(tier, AUTOCOMPLETE_MODELS[hardware.HardwareTier.C])
    
    # For conservative, autocomplete also serves as primary on lower tiers
    if tier in (hardware.HardwareTier.C, hardware.HardwareTier.B):
        return ModelRecommendation(
            primary=autocomplete,
            autocomplete=None,
            embeddings=embeddings
        )
    
    remaining_ram -= autocomplete.ram_gb
    
    # Select a smaller primary model
    primary_options = PRIMARY_MODELS.get(tier, PRIMARY_MODELS[hardware.HardwareTier.C])
    
    # For conservative, prefer the smaller options
    primary = None
    for model in reversed(primary_options):
        if model.ram_gb <= remaining_ram:
            primary = model
            break
    
    if primary is None:
        return ModelRecommendation(
            primary=autocomplete,
            autocomplete=None,
            embeddings=embeddings
        )
    
    include_autocomplete = autocomplete.docker_name != primary.docker_name
    
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
    Display a model recommendation in user-friendly format.
    """
    usable_ram = get_usable_ram(hw_info)
    total_ram = recommendation.total_ram()
    buffer = usable_ram - total_ram
    buffer_percent = (buffer / usable_ram * 100) if usable_ram > 0 else 0
    usage_percent = (total_ram / usable_ram * 100) if usable_ram > 0 else 0
    
    print()
    print(ui.colorize(f"{title}:", ui.Colors.GREEN + ui.Colors.BOLD))
    
    # Primary model
    print(f"  • {ui.colorize(recommendation.primary.docker_name, ui.Colors.CYAN)} (primary coding) - {recommendation.primary.ram_gb:.1f}GB")
    
    # Autocomplete (if separate from primary)
    if recommendation.autocomplete:
        print(f"  • {ui.colorize(recommendation.autocomplete.docker_name, ui.Colors.CYAN)} (autocomplete) - {recommendation.autocomplete.ram_gb:.1f}GB")
    
    # Embeddings
    if recommendation.embeddings:
        print(f"  • {ui.colorize(recommendation.embeddings.docker_name, ui.Colors.CYAN)} (codebase search) - {recommendation.embeddings.ram_gb:.1f}GB")
    
    # Reasoning (if included)
    if recommendation.reasoning:
        print(f"  • {ui.colorize(recommendation.reasoning.docker_name, ui.Colors.CYAN)} (reasoning) - {recommendation.reasoning.ram_gb:.1f}GB")
    
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


def get_alternatives_for_role(
    role: ModelRole,
    tier: hardware.HardwareTier,
    current_model: Optional[RecommendedModel] = None
) -> List[RecommendedModel]:
    """Get 2-3 vetted alternatives for a role."""
    alternatives = []
    
    if role == ModelRole.CHAT:
        primary_options = PRIMARY_MODELS.get(tier, [])
        alternatives = [m for m in primary_options if m != current_model][:3]
    
    elif role == ModelRole.AUTOCOMPLETE:
        all_autocomplete = list(AUTOCOMPLETE_MODELS.values())
        alternatives = [m for m in all_autocomplete if m != current_model][:3]
    
    elif role == ModelRole.EMBED:
        alternatives = [
            RecommendedModel(
                name="MXBAI Embed Large",
                docker_name="ai/mxbai-embed-large",
                ram_gb=0.8,
                role=ModelRole.EMBED,
                roles=["embed"],
                context_length=8192,
                description="High-quality embeddings"
            ),
            RecommendedModel(
                name="All-MiniLM (vLLM)",
                docker_name="ai/all-minilm-l6-v2-vllm",
                ram_gb=0.1,
                role=ModelRole.EMBED,
                roles=["embed"],
                context_length=512,
                description="Tiny but fast embeddings"
            ),
        ]
    
    return alternatives


def customize_role(
    recommendation: ModelRecommendation,
    role: ModelRole,
    hw_info: hardware.HardwareInfo
) -> ModelRecommendation:
    """Allow user to swap a model for a specific role."""
    tier = hw_info.tier
    
    if role == ModelRole.CHAT:
        current = recommendation.primary
    elif role == ModelRole.AUTOCOMPLETE:
        current = recommendation.autocomplete
    elif role == ModelRole.EMBED:
        current = recommendation.embeddings
    else:
        return recommendation
    
    alternatives = get_alternatives_for_role(role, tier, current)
    
    if not alternatives:
        ui.print_warning(f"No alternatives available for {role.value}")
        return recommendation
    
    print()
    ui.print_subheader(f"Change {role.value.capitalize()} Model")
    
    if current:
        print(f"  Current: {ui.colorize(current.docker_name, ui.Colors.GREEN)} - {current.ram_gb:.1f}GB")
    print()
    
    choices = []
    for m in alternatives:
        choices.append(f"{m.name} ({m.docker_name}) - {m.ram_gb:.1f}GB")
    choices.append("Keep current")
    
    choice = ui.prompt_choice("Select alternative:", choices, default=len(choices) - 1)
    
    if choice == len(choices) - 1:
        return recommendation
    
    new_model = alternatives[choice]
    
    if role == ModelRole.CHAT:
        recommendation.primary = new_model
    elif role == ModelRole.AUTOCOMPLETE:
        recommendation.autocomplete = new_model
    elif role == ModelRole.EMBED:
        recommendation.embeddings = new_model
    
    return recommendation


def add_optional_model(
    recommendation: ModelRecommendation,
    model_type: str,
    hw_info: hardware.HardwareInfo
) -> ModelRecommendation:
    """Add an optional model (reasoning)."""
    tier = hw_info.tier
    usable_ram = get_usable_ram(hw_info)
    current_total = recommendation.total_ram()
    
    if model_type == "reasoning":
        if recommendation.reasoning:
            ui.print_warning("Reasoning model already included")
            return recommendation
        
        reasoning = REASONING_MODELS.get(tier)
        if reasoning is None:
            ui.print_warning("No reasoning model available for your tier")
            return recommendation
        
        if current_total + reasoning.ram_gb > usable_ram * 0.90:
            ui.print_warning(f"Not enough RAM for reasoning model (+{reasoning.ram_gb:.1f}GB)")
            return recommendation
        
        recommendation.reasoning = reasoning
        ui.print_success(f"Added {reasoning.name} (+{reasoning.ram_gb:.1f}GB)")
    
    return recommendation


def show_customization_menu(
    recommendation: ModelRecommendation,
    hw_info: hardware.HardwareInfo
) -> ModelRecommendation:
    """Show the customization menu for modifying the recommendation."""
    while True:
        print()
        ui.print_subheader("Customize Setup")
        print()
        print("  Your current setup:")
        display_recommendation(recommendation, hw_info, title="Current")
        print()
        
        print(ui.colorize("  Level 1 - Swap Models:", ui.Colors.BOLD))
        print(f"    [1] Change primary model ({recommendation.primary.docker_name})")
        if recommendation.autocomplete:
            print(f"    [2] Change autocomplete model ({recommendation.autocomplete.docker_name})")
        if recommendation.embeddings:
            print(f"    [3] Change embeddings model ({recommendation.embeddings.docker_name})")
        print()
        
        print(ui.colorize("  Level 2 - Advanced Options:", ui.Colors.BOLD))
        if not recommendation.reasoning:
            reasoning = REASONING_MODELS.get(hw_info.tier)
            if reasoning:
                print(f"    [4] Add reasoning model ({reasoning.name}) +{reasoning.ram_gb:.1f}GB")
        print()
        print("    [0] Done - Accept current setup")
        print()
        
        response = input("  Select option: ").strip()
        
        if response == "0" or not response:
            break
        elif response == "1":
            recommendation = customize_role(recommendation, ModelRole.CHAT, hw_info)
        elif response == "2" and recommendation.autocomplete:
            recommendation = customize_role(recommendation, ModelRole.AUTOCOMPLETE, hw_info)
        elif response == "3" and recommendation.embeddings:
            recommendation = customize_role(recommendation, ModelRole.EMBED, hw_info)
        elif response == "4" and not recommendation.reasoning:
            recommendation = add_optional_model(recommendation, "reasoning", hw_info)
        else:
            ui.print_warning("Invalid option")
    
    return recommendation


def select_models_smart(hw_info: hardware.HardwareInfo, installed_ides: Optional[List[str]] = None) -> List[RecommendedModel]:
    """
    Smart model selection with single best recommendation.
    
    Main entry point for the new model selection flow.
    """
    ui.print_header("🤖 Smart Model Selection")
    
    usable_ram = get_usable_ram(hw_info)
    reservation = hw_info.get_tier_ram_reservation()
    reserved_ram = hw_info.ram_gb * reservation
    
    print()
    ui.print_success(f"Detected: {hw_info.apple_chip_model or hw_info.cpu_brand}, {hw_info.ram_gb:.0f}GB RAM (Tier {hw_info.tier.value})")
    
    if installed_ides:
        ide_str = ", ".join(installed_ides)
        ui.print_success(f"Scanned: {ide_str} installed")
    
    print()
    print(f"  System RAM:     {hw_info.ram_gb:.0f}GB")
    print(f"  Reserved ({reservation:.0%}):   {reserved_ram:.1f}GB (for OS, IDE, browser)")
    print(f"  Available:      {usable_ram:.1f}GB (for models)")
    
    recommendation = generate_best_recommendation(hw_info)
    display_recommendation(recommendation, hw_info)
    
    print()
    
    choices = ["Accept", "Customize"]
    choice = ui.prompt_choice("What would you like to do?", choices, default=0)
    
    if choice == 1:
        recommendation = show_customization_menu(recommendation, hw_info)
    
    print()
    ui.print_success("Final model selection:")
    display_recommendation(recommendation, hw_info, title="Selected")
    
    return recommendation.all_models()
