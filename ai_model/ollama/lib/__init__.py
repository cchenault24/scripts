"""
Ollama LLM Setup Library

Modular components for Ollama and Continue.dev setup.

Modules:
- config: Continue.dev configuration generation + manifest tracking
- hardware: Hardware detection and tier classification
- ide: IDE detection and integration (VS Code, Cursor, IntelliJ)
- model_selector: Smart model recommendation engine
- models: Model catalog and legacy support
- ollama: Ollama service management
- ui: Terminal UI utilities
- uninstaller: Smart uninstallation with manifest tracking
- utils: General utilities
- validator: Model verification and fallback handling
"""

import importlib
from typing import Any

__version__ = "2.0.0"

# Submodules available for lazy loading
__all__ = [
    "config",
    "hardware",
    "ide",
    "model_selector",
    "models",
    "ollama",
    "ui",
    "uninstaller",
    "utils",
    "validator",
    # Key classes and functions
    "ModelRole",
    "RecommendedModel",
    "ModelRecommendation",
    "select_models_smart",
    "get_usable_ram",
    "SetupResult",
    "PullResult",
    "pull_models_with_tracking",
    "display_setup_result",
    "validate_pre_install",
    "HardwareTier",
    "HardwareInfo",
    "detect_hardware",
    "detect_installed_ides",
    "display_detected_ides",
]

# Cache for lazily loaded modules
_module_cache: dict = {}

# Mapping of exported names to their source modules
_EXPORTS = {
    # model_selector exports
    "ModelRole": "model_selector",
    "RecommendedModel": "model_selector",
    "ModelRecommendation": "model_selector",
    "select_models_smart": "model_selector",
    "get_usable_ram": "model_selector",
    # validator exports
    "SetupResult": "validator",
    "PullResult": "validator",
    "pull_models_with_tracking": "validator",
    "display_setup_result": "validator",
    "validate_pre_install": "validator",
    # hardware exports
    "HardwareTier": "hardware",
    "HardwareInfo": "hardware",
    "detect_hardware": "hardware",
    # ide exports
    "detect_installed_ides": "ide",
    "display_detected_ides": "ide",
}

# Submodule names
_SUBMODULES = {
    "config",
    "hardware",
    "ide",
    "model_selector",
    "models",
    "ollama",
    "ui",
    "uninstaller",
    "utils",
    "validator",
}


def _load_module(name: str) -> Any:
    """Lazily load and cache a submodule."""
    if name not in _module_cache:
        _module_cache[name] = importlib.import_module(f".{name}", __name__)
    return _module_cache[name]


def __getattr__(name: str) -> Any:
    """
    Lazy loading for submodules and exported names.
    
    This avoids circular imports and reduces startup time by only
    loading modules when they are first accessed.
    """
    # Check if it's a submodule
    if name in _SUBMODULES:
        return _load_module(name)
    
    # Check if it's an exported class/function
    if name in _EXPORTS:
        module = _load_module(_EXPORTS[name])
        return getattr(module, name)
    
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


def __dir__() -> list:
    """Return list of available names for tab completion."""
    return list(__all__) + ["__version__"]
