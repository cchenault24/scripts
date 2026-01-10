"""
Ollama LLM Setup Library

Modular components for Ollama and Continue.dev setup.

Modules:
- config: Continue.dev configuration generation
- hardware: Hardware detection and tier classification
- ide: IDE detection and integration (VS Code, Cursor, IntelliJ)
- model_selector: Smart model recommendation engine
- models: Model catalog and legacy support
- ollama: Ollama service management
- ui: Terminal UI utilities
- utils: General utilities
- validator: Model verification and fallback handling
"""

__version__ = "2.0.0"

# Import new modules for easier access
from . import config
from . import hardware
from . import ide
from . import model_selector
from . import models
from . import ollama
from . import ui
from . import utils
from . import validator

# Export key classes and functions
from .model_selector import (
    ModelRole,
    RecommendedModel,
    ModelRecommendation,
    generate_best_recommendation,
    select_models_smart,
    get_tier_ram_reservation,
    get_usable_ram,
)

from .validator import (
    SetupResult,
    PullResult,
    pull_models_with_tracking,
    display_setup_result,
    validate_pre_install,
)

from .hardware import (
    HardwareTier,
    HardwareInfo,
    detect_hardware,
)

from .ide import (
    detect_installed_ides,
    display_detected_ides,
)
