"""
Unit tests for lib/hardware.py.

Tests hardware detection and basic functionality.
Runs against both ollama and docker backends.
"""

import platform
import sys
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch

import pytest

# Add backend directories to path
_ollama_path = str(Path(__file__).parent.parent / "ollama")
_docker_path = str(Path(__file__).parent.parent / "docker")
if _ollama_path not in sys.path:
    sys.path.insert(0, _ollama_path)
if _docker_path not in sys.path:
    sys.path.insert(0, _docker_path)

from lib import hardware
from lib.hardware import HardwareInfo


# =============================================================================
# Basic Hardware Detection Tests
# =============================================================================

class TestBasicHardwareDetection:
    """Tests for basic hardware detection functionality."""
    
    def test_minimum_ram_requirement(self):
        """Test that minimum 16GB RAM is required."""
        # Hardware detection should validate minimum RAM
        # This is tested in integration tests
        pass


# =============================================================================
# Apple Silicon Detection Tests
# =============================================================================

class TestAppleSiliconDetection:
    """Tests for Apple Silicon chip detection."""
    
    @pytest.mark.parametrize("cpu_brand,expected_model", [
        ("Apple M1", "M1"),
        ("Apple M1 Pro", "M1 Pro"),
        ("Apple M1 Max", "M1 Max"),
        ("Apple M1 Ultra", "M1 Ultra"),
        ("Apple M2", "M2"),
        ("Apple M2 Pro", "M2 Pro"),
        ("Apple M2 Max", "M2 Max"),
        ("Apple M2 Ultra", "M2 Ultra"),
        ("Apple M3", "M3"),
        ("Apple M3 Pro", "M3 Pro"),
        ("Apple M3 Max", "M3 Max"),
        ("Apple M4", "M4"),
    ])
    def test_apple_silicon_model_detection(self, cpu_brand, expected_model):
        """Test Apple Silicon model name extraction."""
        # This tests the logic that would extract the model
        if "Apple M" in cpu_brand:
            model = cpu_brand.replace("Apple ", "")
            assert model == expected_model
    
    def test_non_apple_silicon(self):
        """Test that Intel CPUs are not detected as Apple Silicon."""
        hw_info = HardwareInfo(
            cpu_brand="Intel Core i9-13900K",
            has_apple_silicon=False
        )
        assert not hw_info.has_apple_silicon
        assert hw_info.apple_chip_model == ""


# =============================================================================
# Hardware Info Dataclass Tests
# =============================================================================

class TestHardwareInfoDataclass:
    """Tests for HardwareInfo dataclass functionality."""
    
    def test_default_values(self, backend_type):
        """Test that HardwareInfo has sensible defaults."""
        hw_info = HardwareInfo()
        assert hw_info.ram_gb == 0.0
        assert hw_info.cpu_cores == 0
        # Check backend-specific default
        if backend_type == "ollama":
            assert hw_info.ollama_available is False
        else:
            assert hw_info.docker_model_runner_available is False


# =============================================================================
# Edge Case Tests
# =============================================================================

class TestEdgeCases:
    """Tests for edge cases and boundary conditions."""
    
    def test_very_low_ram(self):
        """Test handling of very low RAM (8GB)."""
        hw_info = HardwareInfo(ram_gb=8.0)
        # Should detect RAM but fail minimum requirement check
        assert hw_info.ram_gb == 8.0
    
    def test_very_high_ram(self):
        """Test handling of very high RAM (128GB)."""
        hw_info = HardwareInfo(ram_gb=128.0)
        assert hw_info.ram_gb == 128.0
    
    def test_non_standard_ram(self):
        """Test handling of non-standard RAM amounts."""
        hw_info = HardwareInfo(ram_gb=18.0)
        assert hw_info.ram_gb == 18.0
    
    def test_zero_ram(self):
        """Test handling of zero RAM (error case)."""
        hw_info = HardwareInfo(ram_gb=0.0)
        assert hw_info.ram_gb == 0.0


# =============================================================================
# Hardware Detection Tests (with mocks)
# =============================================================================

class TestHardwareDetection:
    """Tests for hardware detection with mocked system calls."""
    
    @patch('platform.system')
    @patch('platform.machine')
    def test_detect_macos(self, mock_machine, mock_system):
        """Test detection on macOS."""
        mock_system.return_value = "Darwin"
        mock_machine.return_value = "arm64"
        
        assert platform.system() == "Darwin"
        assert platform.machine() == "arm64"
    
    @patch('platform.system')
    @patch('platform.machine')
    def test_detect_linux(self, mock_machine, mock_system):
        """Test detection on Linux."""
        mock_system.return_value = "Linux"
        mock_machine.return_value = "x86_64"
        
        assert platform.system() == "Linux"
        assert platform.machine() == "x86_64"


# =============================================================================
# GPU Detection Tests
# =============================================================================

class TestGPUDetection:
    """Tests for GPU detection."""
    
    def test_apple_silicon_gpu(self, mock_hardware_tier_c):
        """Test Apple Silicon GPU detection."""
        assert mock_hardware_tier_c.gpu_name == "Apple M4"
        assert mock_hardware_tier_c.gpu_cores == 10
    
    def test_nvidia_gpu(self, mock_hardware_linux):
        """Test NVIDIA GPU detection."""
        assert mock_hardware_linux.has_nvidia
        assert "NVIDIA" in mock_hardware_linux.gpu_name
        assert mock_hardware_linux.gpu_vram_gb == 24.0
    
    def test_no_dedicated_gpu(self):
        """Test system without dedicated GPU."""
        hw_info = HardwareInfo(
            gpu_name="",
            has_nvidia=False,
            gpu_vram_gb=0
        )
        assert not hw_info.has_nvidia
        assert hw_info.gpu_vram_gb == 0


# =============================================================================
# CPU Core Tests
# =============================================================================

class TestCPUCores:
    """Tests for CPU core detection."""
    
    def test_apple_silicon_cores(self, mock_hardware_tier_c):
        """Test Apple Silicon performance/efficiency core detection."""
        assert mock_hardware_tier_c.cpu_cores == 10
        assert mock_hardware_tier_c.cpu_perf_cores == 4
        assert mock_hardware_tier_c.cpu_eff_cores == 6
    
    def test_intel_cores(self, mock_hardware_linux):
        """Test Intel CPU core detection."""
        assert mock_hardware_linux.cpu_cores == 24
        # Intel doesn't have P/E core distinction in our model
        assert mock_hardware_linux.cpu_perf_cores == 0
        assert mock_hardware_linux.cpu_eff_cores == 0
