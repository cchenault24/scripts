"""
Model Selector for OpenCode + Ollama Setup.

Single-model selection with hardware-based recommendations.
User chooses from Gemma4 model variants.
"""

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple
from enum import Enum

from . import hardware
from . import ui


class ModelRole(Enum):
    """Model roles for OpenCode."""
    CHAT = "chat"
    COMPLETION = "completion"
    EDIT = "edit"


@dataclass
class GemmaModel:
    """A Gemma4 model variant."""
    name: str  # Display name (e.g., "Gemma4 26B (Optimized)")
    ollama_name: str  # Full Ollama name (e.g., "VladimirGav/gemma4-26b-16GB-VRAM:latest")
    size_label: str  # Human-readable size (e.g., "26B")
    ram_gb: float  # Estimated RAM usage
    min_ram_required: int  # Minimum system RAM (GB)
    max_ram_recommended: int  # Maximum recommended RAM (GB)
    description: str  # Model description
    recommended: bool = False  # Whether this is the default recommendation
    performance_tier: str = "balanced"  # "fast", "balanced", "quality"


# =============================================================================
# GEMMA4 MODEL CATALOG
# =============================================================================

GEMMA4_MODELS = [
    GemmaModel(
        name="Gemma4 2B (Efficient)",
        ollama_name="gemma4:e2b",
        size_label="2B",
        ram_gb=2.5,
        min_ram_required=4,
        max_ram_recommended=12,
        description="Fast, efficient model for basic coding tasks. Best for lower-RAM systems.",
        recommended=False,
        performance_tier="fast"
    ),
    GemmaModel(
        name="Gemma4 4B (Balanced)",
        ollama_name="gemma4:e4b",
        size_label="4B",
        ram_gb=4.5,
        min_ram_required=8,
        max_ram_recommended=16,
        description="Balanced performance and quality. Good for general coding.",
        recommended=False,
        performance_tier="balanced"
    ),
    GemmaModel(
        name="Gemma4 26B (Optimized for 16GB VRAM)",
        ollama_name="VladimirGav/gemma4-26b-16GB-VRAM:latest",
        size_label="26B",
        ram_gb=16.0,
        min_ram_required=16,
        max_ram_recommended=32,
        description="Optimized 26B model for Mac Silicon with 16GB+ RAM. Best balance of quality and performance.",
        recommended=True,  # Default recommendation for 16GB+ systems
        performance_tier="quality"
    ),
    GemmaModel(
        name="Gemma4 26B (Standard)",
        ollama_name="gemma4:26b",
        size_label="26B",
        ram_gb=16.0,
        min_ram_required=16,
        max_ram_recommended=32,
        description="Standard 26B model, high quality code generation.",
        recommended=False,
        performance_tier="quality"
    ),
    GemmaModel(
        name="Gemma4 31B (Maximum Quality)",
        ollama_name="gemma4:31b",
        size_label="31B",
        ram_gb=20.0,
        min_ram_required=24,
        max_ram_recommended=64,
        description="Largest model, best quality for high-RAM systems. Slower but most capable.",
        recommended=False,
        performance_tier="quality"
    ),
]


def get_recommended_model(hw_info: hardware.HardwareInfo) -> GemmaModel:
    """
    Get recommended model based on hardware specs.

    Args:
        hw_info: Hardware information

    Returns:
        Recommended GemmaModel
    """
    available_ram = hw_info.ram_gb

    # Find best model for available RAM
    suitable_models = [
        m for m in GEMMA4_MODELS
        if m.min_ram_required <= available_ram <= m.max_ram_recommended
    ]

    if not suitable_models:
        # RAM too low - recommend smallest model
        if available_ram < 16:
            return GEMMA4_MODELS[0]  # gemma4:e2b (2B)
        # RAM too high - recommend largest model
        else:
            return GEMMA4_MODELS[-1]  # gemma4:31b (31B)

    # Prefer models marked as recommended
    recommended = [m for m in suitable_models if m.recommended]
    if recommended:
        return recommended[0]

    # Otherwise, pick the largest suitable model
    return max(suitable_models, key=lambda m: m.ram_gb)


def display_model_menu(hw_info: hardware.HardwareInfo, recommended_model: GemmaModel) -> None:
    """
    Display the model selection menu with hardware info.

    Args:
        hw_info: Hardware information
        recommended_model: The recommended model for this hardware
    """
    print()
    ui.print_header("📦 Model Selection")
    print()

    # Display hardware info
    chip_model = hw_info.apple_chip_model or hw_info.cpu_brand
    ui.print_success(f"Detected: {chip_model}")
    print(f"  Total RAM:       {hw_info.ram_gb:.0f} GB")
    print(f"  Available RAM:   ~{hw_info.usable_ram_gb:.0f} GB (for AI models)")
    print()

    # Display model options
    ui.print_info("Available Gemma4 models:")
    print()

    for i, model in enumerate(GEMMA4_MODELS, start=1):
        # Mark recommended model
        marker = ui.colorize(" ★ RECOMMENDED", ui.Colors.GREEN) if model == recommended_model else ""

        # Check if RAM is suitable
        ram_ok = hw_info.ram_gb >= model.min_ram_required
        ram_indicator = "✓" if ram_ok else "✗"
        ram_color = ui.Colors.GREEN if ram_ok else ui.Colors.RED

        print(f"  {i}. {ui.colorize(model.name, ui.Colors.CYAN)}{marker}")
        print(f"     {model.ollama_name}")
        print(f"     {ui.colorize(ram_indicator, ram_color)} RAM: {model.ram_gb:.1f} GB (requires {model.min_ram_required}+ GB system RAM)")
        print(f"     {model.description}")
        print()


def select_model_interactive(hw_info: hardware.HardwareInfo) -> GemmaModel:
    """
    Interactive model selection with hardware-based recommendation.

    Args:
        hw_info: Hardware information

    Returns:
        Selected GemmaModel
    """
    # Validate Apple Silicon support
    is_supported, error_msg = hardware.validate_apple_silicon_support(hw_info)
    if not is_supported:
        ui.print_error(error_msg or "This setup only supports Apple Silicon Macs")
        raise SystemExit("Hardware requirements not met: Apple Silicon required")

    # Get recommendation
    recommended_model = get_recommended_model(hw_info)

    # Display menu
    display_model_menu(hw_info, recommended_model)

    # Prompt for selection
    recommended_index = GEMMA4_MODELS.index(recommended_model) + 1
    print(f"Recommended: Option {recommended_index} ({ui.colorize(recommended_model.name, ui.Colors.CYAN)})")
    print()

    while True:
        try:
            choice = input(f"Select model (1-{len(GEMMA4_MODELS)}) or press Enter for recommended [{recommended_index}]: ").strip()

            # Use recommended if empty
            if not choice:
                selected_model = recommended_model
                break

            # Parse choice
            choice_num = int(choice)
            if 1 <= choice_num <= len(GEMMA4_MODELS):
                selected_model = GEMMA4_MODELS[choice_num - 1]

                # Warn if RAM insufficient
                if hw_info.ram_gb < selected_model.min_ram_required:
                    ui.print_warning(
                        f"\n⚠️  Warning: {selected_model.name} requires {selected_model.min_ram_required}GB+ RAM, "
                        f"but you have {hw_info.ram_gb:.0f}GB."
                    )
                    confirm = input("Continue anyway? (y/N): ").strip().lower()
                    if confirm != 'y':
                        print()
                        continue

                break
            else:
                print(ui.colorize(f"Please enter a number between 1 and {len(GEMMA4_MODELS)}", ui.Colors.RED))
        except ValueError:
            print(ui.colorize("Please enter a valid number", ui.Colors.RED))
        except KeyboardInterrupt:
            print()
            raise SystemExit("Setup cancelled by user")

    print()
    ui.print_success(f"Selected: {selected_model.name}")
    print(f"  Model: {ui.colorize(selected_model.ollama_name, ui.Colors.CYAN)}")
    print(f"  Size: {selected_model.size_label}")
    print(f"  RAM Usage: ~{selected_model.ram_gb:.1f} GB")
    print()

    return selected_model
