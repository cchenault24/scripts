"""
AI Fine-Tuning System for Docker Model Runner.

Provides comprehensive tuning profiles with model parameters, context optimization,
and hardware-aware parameter adjustment.
"""

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

from . import hardware


@dataclass
class TuningProfile:
    """Complete AI fine-tuning profile."""
    # Model parameters
    temperature: float  # 0.0-2.0
    top_p: float  # 0.0-1.0
    top_k: int  # 1-100
    frequency_penalty: float  # -2.0 to 2.0
    presence_penalty: float  # -2.0 to 2.0
    max_tokens: int  # Response length limit
    
    # Context settings
    context_length: int  # Token context window
    context_reserve: float  # Safety margin (0.0-1.0)
    
    # Autocomplete settings
    autocomplete_debounce: int  # ms
    autocomplete_timeout: int  # ms
    autocomplete_max_tokens: int
    
    # Performance settings
    streaming: bool
    use_cache: bool
    batch_size: int
    
    # Role-specific overrides
    chat_overrides: Optional[Dict[str, Any]] = None
    edit_overrides: Optional[Dict[str, Any]] = None
    autocomplete_overrides: Optional[Dict[str, Any]] = None
    
    def get_completion_options(self, role: str = "chat") -> Dict[str, Any]:
        """Get completion options for a specific role."""
        base = {
            "temperature": self.temperature,
            "top_p": self.top_p,
            "top_k": self.top_k,
            "frequency_penalty": self.frequency_penalty,
            "presence_penalty": self.presence_penalty,
            "max_tokens": self.max_tokens,
        }
        
        # Apply role-specific overrides
        if role == "chat" and self.chat_overrides:
            base.update(self.chat_overrides)
        elif role == "edit" and self.edit_overrides:
            base.update(self.edit_overrides)
        elif role == "autocomplete" and self.autocomplete_overrides:
            base.update(self.autocomplete_overrides)
        
        return base


def detect_performance_tier(hw_info: hardware.HardwareInfo) -> str:
    """Detect hardware performance tier for preset selection."""
    # Analyze RAM
    ram_gb = hw_info.ram_gb
    
    # Analyze CPU (Apple Silicon generation)
    cpu_score = 1.0
    if hw_info.has_apple_silicon:
        chip = hw_info.apple_chip_model or ""
        if "M4" in chip or "Ultra" in chip:
            cpu_score = 3.0
        elif "M3" in chip or "Max" in chip:
            cpu_score = 2.5
        elif "M2" in chip:
            cpu_score = 2.0
        elif "M1" in chip:
            cpu_score = 1.5
    
    # Calculate performance score
    perf_score = (ram_gb / 16.0) * 0.5 + cpu_score * 0.5
    
    # Classify tier
    if perf_score >= 2.5:
        return "quality"  # High-end hardware
    elif perf_score >= 1.5:
        return "balanced"  # Mid-range hardware
    else:
        return "performance"  # Lower-end hardware


def create_preset_profile(preset: str, hw_info: hardware.HardwareInfo) -> TuningProfile:
    """Create preset tuning profile based on hardware."""
    # Base profiles
    if preset == "performance":
        profile = TuningProfile(
            temperature=0.5,  # Lower for deterministic output
            top_p=0.85,
            top_k=30,
            frequency_penalty=0.1,
            presence_penalty=0.0,
            max_tokens=2048,  # Smaller responses
            context_length=16384,  # Smaller context
            context_reserve=0.25,  # More safety margin
            autocomplete_debounce=200,  # Faster
            autocomplete_timeout=1500,  # Faster timeout
            autocomplete_max_tokens=64,  # Shorter completions
            streaming=True,
            use_cache=True,
            batch_size=1,
            chat_overrides={"temperature": 0.6, "max_tokens": 2048},
            edit_overrides={"temperature": 0.4, "max_tokens": 1536},
            autocomplete_overrides={"temperature": 0.2, "max_tokens": 64, "top_p": 0.9},
        )
    elif preset == "quality":
        profile = TuningProfile(
            temperature=0.8,  # Higher for creative output
            top_p=0.95,
            top_k=50,
            frequency_penalty=0.15,
            presence_penalty=0.1,
            max_tokens=8192,  # Larger responses
            context_length=65536,  # Larger context
            context_reserve=0.15,  # Less safety margin
            autocomplete_debounce=300,
            autocomplete_timeout=3000,
            autocomplete_max_tokens=128,
            streaming=True,
            use_cache=True,
            batch_size=2,
            chat_overrides={"temperature": 0.8, "max_tokens": 8192},
            edit_overrides={"temperature": 0.7, "max_tokens": 4096},
            autocomplete_overrides={"temperature": 0.3, "max_tokens": 128, "top_p": 0.95},
        )
    else:  # balanced
        profile = TuningProfile(
            temperature=0.7,  # Balanced
            top_p=0.9,
            top_k=40,
            frequency_penalty=0.1,
            presence_penalty=0.05,
            max_tokens=4096,  # Medium responses
            context_length=32768,  # Medium context
            context_reserve=0.2,  # Standard safety margin
            autocomplete_debounce=250,
            autocomplete_timeout=2000,
            autocomplete_max_tokens=96,
            streaming=True,
            use_cache=True,
            batch_size=1,
            chat_overrides={"temperature": 0.7, "max_tokens": 4096},
            edit_overrides={"temperature": 0.6, "max_tokens": 2048},
            autocomplete_overrides={"temperature": 0.2, "max_tokens": 96, "top_p": 0.9},
        )
    
    # Optimize for hardware
    return optimize_for_hardware(profile, hw_info)


def optimize_for_hardware(profile: TuningProfile, hw_info: hardware.HardwareInfo) -> TuningProfile:
    """Optimize profile for specific hardware."""
    # Adjust based on RAM
    if hw_info.ram_gb < 24:
        # 20-24GB systems: reduce context and max tokens
        profile.context_length = min(profile.context_length, 16384)
        profile.max_tokens = min(profile.max_tokens, 2048)
        profile.autocomplete_max_tokens = min(profile.autocomplete_max_tokens, 64)
    elif hw_info.ram_gb >= 48:
        # High-end systems: can use larger contexts
        profile.context_length = min(profile.context_length * 2, 131072)
        profile.max_tokens = min(profile.max_tokens * 2, 16384)
    
    # Adjust based on Apple Silicon generation
    if hw_info.has_apple_silicon:
        chip = hw_info.apple_chip_model or ""
        if "M4" in chip or "Ultra" in chip:
            # Latest chips: can handle more
            profile.batch_size = min(profile.batch_size + 1, 4)
            profile.autocomplete_timeout = max(profile.autocomplete_timeout - 500, 1000)
        elif "M1" in chip:
            # Older chips: be more conservative
            profile.batch_size = 1
            profile.autocomplete_timeout = min(profile.autocomplete_timeout + 500, 3000)
    
    return profile


def auto_detect_tuning_profile(hw_info: hardware.HardwareInfo) -> Tuple[str, TuningProfile, str]:
    """Auto-detect optimal tuning profile based on hardware."""
    tier = detect_performance_tier(hw_info)
    profile = create_preset_profile(tier, hw_info)
    
    # Generate reasoning
    reasons = []
    if hw_info.ram_gb < 24:
        reasons.append(f"{hw_info.ram_gb:.0f}GB RAM")
    elif hw_info.ram_gb >= 48:
        reasons.append(f"{hw_info.ram_gb:.0f}GB RAM")
    
    if hw_info.has_apple_silicon:
        chip = hw_info.apple_chip_model or "Apple Silicon"
        reasons.append(chip)
    
    reason = f"Detected {tier} tier hardware"
    if reasons:
        reason += f" ({', '.join(reasons)})"
    
    return tier, profile, reason
