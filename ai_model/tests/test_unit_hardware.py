"""
Basic smoke tests for lib/hardware.py.

Minimal tests to ensure hardware detection works.
Runs against both ollama and docker backends.
"""

import sys
from pathlib import Path

import pytest

# Add backend directories to path
_ollama_path = str(Path(__file__).parent.parent / "ollama")
_docker_path = str(Path(__file__).parent.parent / "docker")
if _ollama_path not in sys.path:
    sys.path.insert(0, _ollama_path)
if _docker_path not in sys.path:
    sys.path.insert(0, _docker_path)

from lib.hardware import HardwareInfo


# =============================================================================
# Basic Smoke Tests
# =============================================================================

class TestHardwareInfoSmoke:
    """Basic smoke tests for HardwareInfo dataclass."""
    
    def test_can_create_hardware_info(self, backend_type):
        """Test that HardwareInfo can be created with defaults."""
        hw_info = HardwareInfo()
        assert hw_info.ram_gb == 0.0
        assert hw_info.cpu_cores == 0
        # Check backend-specific default
        if backend_type == "ollama":
            assert hw_info.ollama_available is False
        else:
            assert hw_info.docker_model_runner_available is False
    
    def test_can_create_apple_silicon_info(self):
        """Test that HardwareInfo can be created with Apple Silicon info."""
        hw_info = HardwareInfo(
            ram_gb=16.0,
            has_apple_silicon=True,
            apple_chip_model="M4",
            cpu_brand="Apple M4",
            cpu_cores=10,
            cpu_perf_cores=4,
            cpu_eff_cores=6,
            gpu_cores=10,
            neural_engine_cores=16
        )
        assert hw_info.has_apple_silicon is True
        assert hw_info.apple_chip_model == "M4"
        assert hw_info.ram_gb == 16.0
    
    def test_can_create_non_apple_silicon_info(self):
        """Test that HardwareInfo can be created for non-Apple Silicon."""
        hw_info = HardwareInfo(
            ram_gb=32.0,
            has_apple_silicon=False,
            cpu_brand="Intel Core i9",
            cpu_cores=16
        )
        assert hw_info.has_apple_silicon is False
        assert hw_info.ram_gb == 32.0
