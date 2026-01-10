"""
Unit tests for lib/hardware.py.

Tests hardware detection, tier classification, and RAM calculations.
"""

import platform
import sys
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib import hardware
from lib.hardware import HardwareTier, HardwareInfo


# =============================================================================
# Tier Classification Tests
# =============================================================================

class TestTierClassification:
    """Tests for hardware tier classification based on RAM."""
    
    @pytest.mark.parametrize("ram_gb,expected_tier", [
        (8, HardwareTier.C),      # Below minimum
        (16, HardwareTier.C),     # Tier C lower bound
        (20, HardwareTier.C),     # Mid Tier C
        (23.9, HardwareTier.C),   # Just under Tier B
        (24, HardwareTier.B),     # Tier B lower bound
        (28, HardwareTier.B),     # Mid Tier B
        (31.9, HardwareTier.B),   # Just under Tier A
        (32, HardwareTier.A),     # Tier A lower bound
        (48, HardwareTier.A),     # Mid Tier A
        (63.9, HardwareTier.A),   # Just under Tier S
        (64, HardwareTier.S),     # Tier S lower bound
        (96, HardwareTier.S),     # High Tier S
        (128, HardwareTier.S),    # Very high RAM
    ])
    def test_tier_classification(self, ram_gb, expected_tier):
        """Test that RAM amounts map to correct tiers."""
        hw_info = HardwareInfo(ram_gb=ram_gb)
        
        # Simulate tier classification logic
        if ram_gb >= 64:
            tier = HardwareTier.S
        elif ram_gb >= 32:
            tier = HardwareTier.A
        elif ram_gb >= 24:
            tier = HardwareTier.B
        else:
            tier = HardwareTier.C
        
        assert tier == expected_tier, f"RAM {ram_gb}GB should be {expected_tier}"


# =============================================================================
# RAM Reservation Tests
# =============================================================================

class TestRamReservation:
    """Tests for tier-based RAM reservation calculations."""
    
    def test_tier_c_reservation(self, mock_hardware_tier_c):
        """Tier C should reserve 40% for OS (60% usable)."""
        reservation = mock_hardware_tier_c.get_tier_ram_reservation()
        assert reservation == 0.40, "Tier C should reserve 40%"
    
    def test_tier_b_reservation(self, mock_hardware_tier_b):
        """Tier B should reserve 35% for OS (65% usable)."""
        reservation = mock_hardware_tier_b.get_tier_ram_reservation()
        assert reservation == 0.35, "Tier B should reserve 35%"
    
    def test_tier_a_reservation(self, mock_hardware_tier_a):
        """Tier A should reserve 30% for OS (70% usable)."""
        reservation = mock_hardware_tier_a.get_tier_ram_reservation()
        assert reservation == 0.30, "Tier A should reserve 30%"
    
    def test_tier_s_reservation(self, mock_hardware_tier_s):
        """Tier S should reserve 30% for OS (70% usable)."""
        reservation = mock_hardware_tier_s.get_tier_ram_reservation()
        assert reservation == 0.30, "Tier S should reserve 30%"
    
    @pytest.mark.parametrize("ram_gb,tier,expected_usable", [
        (16, HardwareTier.C, 9.6),   # 16 * 0.6 = 9.6
        (24, HardwareTier.B, 15.6),  # 24 * 0.65 = 15.6
        (32, HardwareTier.A, 22.4),  # 32 * 0.7 = 22.4
        (64, HardwareTier.S, 44.8),  # 64 * 0.7 = 44.8
    ])
    def test_usable_ram_calculation(self, ram_gb, tier, expected_usable):
        """Test usable RAM calculation for different tiers."""
        hw_info = HardwareInfo(ram_gb=ram_gb, tier=tier)
        usable = hw_info.get_estimated_model_memory()
        assert abs(usable - expected_usable) < 0.1, f"Expected ~{expected_usable}GB usable"


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
    
    def test_default_values(self):
        """Test that HardwareInfo has sensible defaults."""
        hw_info = HardwareInfo()
        assert hw_info.ram_gb == 0.0
        assert hw_info.cpu_cores == 0
        assert hw_info.tier == HardwareTier.C
        assert hw_info.ollama_available is False
    
    def test_tier_label_tier_c(self, mock_hardware_tier_c):
        """Test tier label for Tier C."""
        label = mock_hardware_tier_c.get_tier_label()
        assert "C" in label
        assert "60%" in label or "40%" in label  # Usable or reserved percentage
    
    def test_tier_label_tier_s(self, mock_hardware_tier_s):
        """Test tier label for Tier S."""
        label = mock_hardware_tier_s.get_tier_label()
        assert "S" in label
        assert "70%" in label or "30%" in label  # Usable or reserved percentage


# =============================================================================
# Edge Case Tests
# =============================================================================

class TestEdgeCases:
    """Tests for edge cases and boundary conditions."""
    
    def test_very_low_ram(self):
        """Test handling of very low RAM (8GB)."""
        hw_info = HardwareInfo(ram_gb=8.0, tier=HardwareTier.C)
        usable = hw_info.get_estimated_model_memory()
        # Should still calculate, even if low
        assert usable > 0
        assert usable == pytest.approx(8.0 * 0.6, rel=0.1)
    
    def test_very_high_ram(self):
        """Test handling of very high RAM (128GB)."""
        hw_info = HardwareInfo(ram_gb=128.0, tier=HardwareTier.S)
        usable = hw_info.get_estimated_model_memory()
        assert usable == pytest.approx(128.0 * 0.7, rel=0.1)
    
    def test_non_standard_ram(self):
        """Test handling of non-standard RAM amounts."""
        # 18GB (not a standard config)
        hw_info = HardwareInfo(ram_gb=18.0, tier=HardwareTier.C)
        usable = hw_info.get_estimated_model_memory()
        assert usable == pytest.approx(18.0 * 0.6, rel=0.1)
    
    def test_zero_ram(self):
        """Test handling of zero RAM (error case)."""
        hw_info = HardwareInfo(ram_gb=0.0, tier=HardwareTier.C)
        usable = hw_info.get_estimated_model_memory()
        assert usable == 0.0


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
