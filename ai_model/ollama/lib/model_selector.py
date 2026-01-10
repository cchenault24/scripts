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
# Primary source: Continue.dev recommended models
# Filtered to only Ollama-compatible models (no cloud APIs)
# Supplemented with proven local models (Granite Code, Phi-4, etc.)
# =============================================================================

# Embedding models - universal across all tiers
EMBED_MODEL = RecommendedModel(
    name="Nomic Embed Text",
    ollama_name="nomic-embed-text:latest",
    ram_gb=0.3,
    role=ModelRole.EMBED,
    roles=["embed"],
    description="Best open embedding model for code indexing (8192 tokens)",
    fallback_name="mxbai-embed-large:latest"
)

# Autocomplete models by tier
AUTOCOMPLETE_MODELS = {
    hardware.HardwareTier.S: RecommendedModel(
        name="Granite Code 3B",
        ollama_name="granite-code:3b",
        ram_gb=2.0,
        role=ModelRole.AUTOCOMPLETE,
        roles=["autocomplete", "chat", "edit"],
        description="Fast autocomplete with IBM Granite",
        fallback_name="starcoder2:3b"
    ),
    hardware.HardwareTier.A: RecommendedModel(
        name="Granite Code 3B",
        ollama_name="granite-code:3b",
        ram_gb=2.0,
        role=ModelRole.AUTOCOMPLETE,
        roles=["autocomplete", "chat", "edit"],
        description="Fast autocomplete with IBM Granite",
        fallback_name="starcoder2:3b"
    ),
    hardware.HardwareTier.B: RecommendedModel(
        name="Granite Code 3B",
        ollama_name="granite-code:3b",
        ram_gb=2.0,
        role=ModelRole.AUTOCOMPLETE,
        roles=["autocomplete", "chat", "edit"],
        description="Fast autocomplete with IBM Granite",
        fallback_name="starcoder2:3b"
    ),
    hardware.HardwareTier.C: RecommendedModel(
        name="Granite Code 3B",
        ollama_name="granite-code:3b",
        ram_gb=2.0,
        role=ModelRole.AUTOCOMPLETE,
        roles=["autocomplete", "chat", "edit"],
        description="Fast autocomplete - also serves as primary on 16GB",
        fallback_name="starcoder2:3b"
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
            name="Qwen2.5 Coder 14B",
            ollama_name="qwen2.5-coder:14b",
            ram_gb=9.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="Alibaba's Qwen2.5 Coder - Excellent code generation",
            fallback_name="qwen2.5-coder:7b"
        ),
    ],
    hardware.HardwareTier.A: [
        # Tier A (32-64GB): 14B models with good quality
        RecommendedModel(
            name="Qwen2.5 Coder 14B",
            ollama_name="qwen2.5-coder:14b",
            ram_gb=9.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="Alibaba's Qwen2.5 Coder - Excellent code generation",
            fallback_name="qwen2.5-coder:7b"
        ),
        RecommendedModel(
            name="Codestral 22B",
            ollama_name="codestral:22b",
            ram_gb=13.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="Mistral's Codestral - Best open coding model",
            fallback_name="codestral:latest"
        ),
    ],
    hardware.HardwareTier.B: [
        # Tier B (24-32GB): 7-8B models
        RecommendedModel(
            name="Qwen2.5 Coder 7B",
            ollama_name="qwen2.5-coder:7b",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="Alibaba's Qwen2.5 Coder 7B - Fast and capable",
            fallback_name="granite-code:8b"
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
    hardware.HardwareTier.C: [
        # Tier C (16-24GB): 3-8B models
        RecommendedModel(
            name="Granite Code 8B",
            ollama_name="granite-code:8b",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="IBM's Granite Code - Reliable coding model",
            fallback_name="granite-code:latest"
        ),
        RecommendedModel(
            name="Granite Code 3B",
            ollama_name="granite-code:3b",
            ram_gb=2.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="IBM's Granite Code 3B - Compact but capable",
            fallback_name="codegemma:2b"
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


def get_tier_ram_reservation(tier: hardware.HardwareTier) -> float:
    """
    Get the RAM reservation percentage for a hardware tier.
    
    Returns the percentage of RAM to reserve for OS/apps (not available for models).
    
    - Tier C (16-24GB): Reserve 40% for OS/apps
    - Tier B (24-32GB): Reserve 35% for OS/apps
    - Tier A/S (32GB+): Reserve 30% for OS/apps
    """
    reservations = {
        hardware.HardwareTier.S: 0.30,
        hardware.HardwareTier.A: 0.30,
        hardware.HardwareTier.B: 0.35,
        hardware.HardwareTier.C: 0.40,
        hardware.HardwareTier.D: 0.50,  # Unsupported, but defined for safety
    }
    return reservations.get(tier, 0.40)


def get_usable_ram(hw_info: hardware.HardwareInfo) -> float:
    """
    Get usable RAM for models based on tier-based reservation.
    
    Uses tier-specific reservation instead of flat 30%.
    """
    reservation = get_tier_ram_reservation(hw_info.tier)
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
    include_autocomplete = autocomplete.ollama_name != primary.ollama_name
    
    return ModelRecommendation(
        primary=primary,
        autocomplete=autocomplete if include_autocomplete else None,
        embeddings=embeddings
    )


def generate_multi_model_recommendation(hw_info: hardware.HardwareInfo) -> Optional[ModelRecommendation]:
    """
    Generate a multi-model recommendation with specialized models for each task.
    
    Only available for Tier S (64GB+) and Tier A (48GB+) systems.
    Includes: primary + reasoning + autocomplete + embeddings
    """
    tier = hw_info.tier
    usable_ram = get_usable_ram(hw_info)
    
    # Multi-model only available for Tier S and high-end Tier A
    if tier not in (hardware.HardwareTier.S, hardware.HardwareTier.A):
        return None
    
    if tier == hardware.HardwareTier.A and hw_info.ram_gb < 48:
        return None  # Need at least 48GB for multi-model on Tier A
    
    # Build multi-model portfolio
    embeddings = EMBED_MODEL
    autocomplete = AUTOCOMPLETE_MODELS.get(tier)
    reasoning = REASONING_MODELS.get(tier)
    
    # Select primary model
    primary_options = PRIMARY_MODELS.get(tier, [])
    primary = primary_options[0] if primary_options else None
    
    if primary is None:
        return None
    
    # Calculate total RAM
    total = (
        primary.ram_gb +
        (autocomplete.ram_gb if autocomplete else 0) +
        embeddings.ram_gb +
        (reasoning.ram_gb if reasoning else 0)
    )
    
    # Check if it fits
    if total > usable_ram * 0.85:  # Allow up to 85% for multi-model
        # Try without reasoning model
        total -= (reasoning.ram_gb if reasoning else 0)
        reasoning = None
        
        if total > usable_ram * 0.85:
            return None  # Still doesn't fit
    
    return ModelRecommendation(
        primary=primary,
        autocomplete=autocomplete,
        embeddings=embeddings,
        reasoning=reasoning
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
        # Use autocomplete as the only model (besides embeddings)
        return ModelRecommendation(
            primary=autocomplete,
            autocomplete=None,  # Primary is also autocomplete
            embeddings=embeddings
        )
    
    remaining_ram -= autocomplete.ram_gb
    
    # Select a smaller primary model
    primary_options = PRIMARY_MODELS.get(tier, PRIMARY_MODELS[hardware.HardwareTier.C])
    
    # For conservative, prefer the smaller options
    primary = None
    for model in reversed(primary_options):  # Start from smallest
        if model.ram_gb <= remaining_ram:
            primary = model
            break
    
    if primary is None:
        # Just use autocomplete as primary
        return ModelRecommendation(
            primary=autocomplete,
            autocomplete=None,
            embeddings=embeddings
        )
    
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
    Display a model recommendation in user-friendly format.
    
    Format:
    ✓ Detected: M3 Pro, 36GB RAM (Tier A)
    ✓ Scanned: VS Code installed
    
    Recommended setup:
      • codestral:22b-q4 (primary coding) - 13GB
      • granite-code:3b (autocomplete) - 2GB  
      • nomic-embed-text (codebase search) - 0.3GB
      
    Total: 15.3GB / 25.2GB usable (39% buffer remaining)
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


def get_alternatives_for_role(
    role: ModelRole,
    tier: hardware.HardwareTier,
    current_model: Optional[RecommendedModel] = None
) -> List[RecommendedModel]:
    """
    Get 2-3 vetted alternatives for a role.
    
    Used for Level 1 customization (role swapping).
    """
    alternatives = []
    
    if role == ModelRole.CHAT:
        # Primary/chat model alternatives
        primary_options = PRIMARY_MODELS.get(tier, [])
        alternatives = [m for m in primary_options if m != current_model][:3]
    
    elif role == ModelRole.AUTOCOMPLETE:
        # Autocomplete alternatives
        all_autocomplete = list(AUTOCOMPLETE_MODELS.values())
        alternatives = [m for m in all_autocomplete if m != current_model][:3]
    
    elif role == ModelRole.EMBED:
        # Embedding alternatives
        alternatives = [
            RecommendedModel(
                name="MxBai Embed Large",
                ollama_name="mxbai-embed-large:latest",
                ram_gb=0.7,
                role=ModelRole.EMBED,
                roles=["embed"],
                description="High-quality embeddings"
            ),
            RecommendedModel(
                name="All-MiniLM",
                ollama_name="all-minilm:latest",
                ram_gb=0.1,
                role=ModelRole.EMBED,
                roles=["embed"],
                description="Tiny but fast embeddings"
            ),
        ]
    
    return alternatives


def customize_role(
    recommendation: ModelRecommendation,
    role: ModelRole,
    hw_info: hardware.HardwareInfo
) -> ModelRecommendation:
    """
    Allow user to swap a model for a specific role.
    
    Level 1 customization: Shows 2-3 vetted alternatives for the role.
    """
    tier = hw_info.tier
    
    # Get current model for this role
    if role == ModelRole.CHAT:
        current = recommendation.primary
    elif role == ModelRole.AUTOCOMPLETE:
        current = recommendation.autocomplete
    elif role == ModelRole.EMBED:
        current = recommendation.embeddings
    else:
        return recommendation
    
    # Get alternatives
    alternatives = get_alternatives_for_role(role, tier, current)
    
    if not alternatives:
        ui.print_warning(f"No alternatives available for {role.value}")
        return recommendation
    
    # Display current and alternatives
    print()
    ui.print_subheader(f"Change {role.value.capitalize()} Model")
    
    if current:
        print(f"  Current: {ui.colorize(current.ollama_name, ui.Colors.GREEN)} - {current.ram_gb:.1f}GB")
    print()
    
    # Build choices list
    choices = []
    for m in alternatives:
        choices.append(f"{m.name} ({m.ollama_name}) - {m.ram_gb:.1f}GB")
    choices.append("Keep current")
    
    choice = ui.prompt_choice("Select alternative:", choices, default=len(choices) - 1)
    
    if choice == len(choices) - 1:
        # Keep current
        return recommendation
    
    # Update recommendation with new model
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
    """
    Add an optional model (reasoning or vision).
    
    Level 2 customization: Advanced options.
    """
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
        
        # Check if it fits
        if current_total + reasoning.ram_gb > usable_ram * 0.90:
            ui.print_warning(f"Not enough RAM for reasoning model (+{reasoning.ram_gb:.1f}GB)")
            return recommendation
        
        recommendation.reasoning = reasoning
        ui.print_success(f"Added {reasoning.name} (+{reasoning.ram_gb:.1f}GB)")
    
    elif model_type == "vision":
        if recommendation.vision:
            ui.print_warning("Vision model already included")
            return recommendation
        
        vision = VISION_MODELS.get(tier)
        if vision is None:
            ui.print_warning("No vision model available for your tier")
            return recommendation
        
        # Check if it fits
        if current_total + vision.ram_gb > usable_ram * 0.90:
            ui.print_warning(f"Not enough RAM for vision model (+{vision.ram_gb:.1f}GB)")
            return recommendation
        
        recommendation.vision = vision
        ui.print_success(f"Added {vision.name} (+{vision.ram_gb:.1f}GB)")
    
    return recommendation


def show_customization_menu(
    recommendation: ModelRecommendation,
    hw_info: hardware.HardwareInfo
) -> ModelRecommendation:
    """
    Show the customization menu for modifying the recommendation.
    
    Two levels:
    - Level 1: Role swapping (change model for a role)
    - Level 2: Advanced options (add reasoning/vision models)
    """
    while True:
        print()
        ui.print_subheader("Customize Setup")
        print()
        print("  Your current setup:")
        display_recommendation(recommendation, hw_info, title="Current")
        print()
        
        # Level 1: Role swapping
        print(ui.colorize("  Level 1 - Swap Models:", ui.Colors.BOLD))
        print(f"    [1] Change primary model ({recommendation.primary.ollama_name})")
        if recommendation.autocomplete:
            print(f"    [2] Change autocomplete model ({recommendation.autocomplete.ollama_name})")
        if recommendation.embeddings:
            print(f"    [3] Change embeddings model ({recommendation.embeddings.ollama_name})")
        print()
        
        # Level 2: Advanced options
        print(ui.colorize("  Level 2 - Advanced Options:", ui.Colors.BOLD))
        if not recommendation.reasoning:
            reasoning = REASONING_MODELS.get(hw_info.tier)
            if reasoning:
                print(f"    [4] Add reasoning model ({reasoning.name}) +{reasoning.ram_gb:.1f}GB")
        if not recommendation.vision:
            vision = VISION_MODELS.get(hw_info.tier)
            if vision:
                print(f"    [5] Add vision model ({vision.name}) +{vision.ram_gb:.1f}GB")
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
        elif response == "5" and not recommendation.vision:
            recommendation = add_optional_model(recommendation, "vision", hw_info)
        else:
            ui.print_warning("Invalid option")
    
    return recommendation


def select_models_smart(hw_info: hardware.HardwareInfo, installed_ides: List[str] = None) -> List[RecommendedModel]:
    """
    Smart model selection with single best recommendation.
    
    Main entry point for the new model selection flow:
    1. Show hardware detection summary
    2. Display single best recommendation
    3. [Accept] or [Customize]
    
    Args:
        hw_info: Hardware information
        installed_ides: List of installed IDEs (auto-detected if None)
    
    Returns:
        List of RecommendedModel objects to install
    """
    ui.print_header("🤖 Smart Model Selection")
    
    # Display hardware summary
    usable_ram = get_usable_ram(hw_info)
    reservation = get_tier_ram_reservation(hw_info.tier)
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
    
    # Generate best recommendation
    recommendation = generate_best_recommendation(hw_info)
    
    # Display recommendation
    display_recommendation(recommendation, hw_info)
    
    print()
    
    # Accept or Customize
    choices = ["Accept", "Customize"]
    choice = ui.prompt_choice("What would you like to do?", choices, default=0)
    
    if choice == 1:
        # Customize
        recommendation = show_customization_menu(recommendation, hw_info)
    
    # Show final selection
    print()
    ui.print_success("Final model selection:")
    display_recommendation(recommendation, hw_info, title="Selected")
    
    return recommendation.all_models()
