"""
Validation functions for llama.cpp server setup.

Provides validation for system requirements, model files, and configurations.
"""

import hashlib
from pathlib import Path
from typing import List, Optional, Tuple

from . import hardware
from . import llamacpp
from . import ui
from . import utils


def validate_system_requirements() -> Tuple[bool, List[str]]:
    """
    Validate system meets requirements.
    
    Returns:
        Tuple of (is_valid, list_of_warnings)
    """
    warnings = []
    
    import platform
    if platform.system() != "Darwin":
        return False, ["This script requires macOS"]
    
    hw_info = hardware.detect_hardware()
    
    if not hw_info.has_apple_silicon:
        return False, ["This script requires Apple Silicon (M1-M5)"]
    
    if hw_info.ram_gb < 16:
        return False, [f"Insufficient RAM: {hw_info.ram_gb:.1f}GB (minimum 16GB required)"]
    
    if hw_info.ram_gb < 24:
        warnings.append(f"RAM ({hw_info.ram_gb:.1f}GB) is below recommended 24GB for GPT-OSS 20B")
        warnings.append("Context size may be limited")
    
    return True, warnings


def validate_model_file(model_path: Path) -> Tuple[bool, str]:
    """
    Validate model file exists and is correct format.
    
    Args:
        model_path: Path to model file
    
    Returns:
        Tuple of (is_valid, message)
    """
    if not model_path.exists():
        return False, f"Model file not found: {model_path}"
    
    if not model_path.is_file():
        return False, f"Model path is not a file: {model_path}"
    
    if model_path.suffix != ".gguf":
        return False, f"Model file must be .gguf format: {model_path}"
    
    # Check file size (should be at least 1GB for GPT-OSS 20B)
    file_size_gb = model_path.stat().st_size / (1024 ** 3)
    if file_size_gb < 1.0:
        return False, f"Model file seems too small: {file_size_gb:.2f}GB"
    
    return True, "Model file is valid"


def validate_binary(binary_path: Path) -> Tuple[bool, str]:
    """
    Validate binary exists and is executable.
    
    Args:
        binary_path: Path to binary
    
    Returns:
        Tuple of (is_valid, message)
    """
    if not binary_path.exists():
        return False, f"Binary not found: {binary_path}"
    
    if not binary_path.is_file():
        return False, f"Binary path is not a file: {binary_path}"
    
    import os
    if not os.access(binary_path, os.X_OK):
        return False, f"Binary is not executable: {binary_path}"
    
    return True, "Binary is valid"


def validate_port_available(port: int, host: str = "127.0.0.1") -> Tuple[bool, str]:
    """
    Validate port is available.
    
    Args:
        port: Port number to check
        host: Host address
    
    Returns:
        Tuple of (is_available, message)
    """
    import socket
    
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(1)
            result = s.connect_ex((host, port))
            if result == 0:
                return False, f"Port {port} is already in use"
            return True, f"Port {port} is available"
    except Exception as e:
        return False, f"Could not check port: {e}"


def validate_configuration(config: llamacpp.ServerConfig) -> Tuple[bool, List[str]]:
    """
    Validate server configuration.
    
    Args:
        config: Server configuration
    
    Returns:
        Tuple of (is_valid, list_of_warnings)
    """
    warnings = []
    
    # Validate binary
    if not config.binary_path:
        return False, ["Binary path not set"]
    
    is_valid, message = validate_binary(config.binary_path)
    if not is_valid:
        return False, [message]
    
    # Validate model
    if not config.model_path:
        return False, ["Model path not set"]
    
    is_valid, message = validate_model_file(config.model_path)
    if not is_valid:
        return False, [message]
    
    # Validate port
    is_available, message = validate_port_available(config.port, config.host)
    if not is_available:
        warnings.append(message)
        warnings.append("Server may fail to start if port is in use")
    
    # Validate context size
    if config.context_size < 1024:
        warnings.append(f"Context size ({config.context_size}) is very small")
    
    if config.context_size > 131072:
        warnings.append(f"Context size ({config.context_size}) exceeds maximum recommended")
    
    return True, warnings


def check_for_conflicts() -> List[str]:
    """
    Check for potential conflicts with other services.
    
    Returns:
        List of warning messages
    """
    warnings = []
    
    # Check for Ollama
    code, _, _ = utils.run_command(["which", "ollama"], timeout=5)
    if code == 0:
        # Check if Ollama is using the same port
        import socket
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(1)
                result = s.connect_ex(("127.0.0.1", 11434))
                if result == 0:
                    warnings.append("Ollama is running on port 11434")
        except Exception:
            pass
    
    # Check for Docker Model Runner
    try:
        import urllib.request
        req = urllib.request.Request("http://127.0.0.1:12434/v1/models", method="GET")
        with urllib.request.urlopen(req, timeout=2, context=utils.get_unverified_ssl_context()) as response:
            if response.status == 200:
                warnings.append("Docker Model Runner is running on port 12434")
    except Exception:
        pass
    
    return warnings
