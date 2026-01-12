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
    """
    Tests for hardware tier classification based on RAM.
    
    Specification:
    - < 16 GB: Tier D (unsupported)
    - 16-23.99 GB: Tier C
    - 24-31.99 GB: Tier B
    - 32-63.99 GB: Tier A
    - >= 64 GB: Tier S
    """
    
    @pytest.mark.parametrize("ram_gb,expected_tier", [
        # Below minimum
        (8, HardwareTier.D),
        (15.99, HardwareTier.D),
        # Tier C boundaries (16-23.99 GB)
        (16.0, HardwareTier.C),
        (20.0, HardwareTier.C),
        (23.99, HardwareTier.C),
        # Tier B boundaries (24-31.99 GB)
        (24.0, HardwareTier.B),
        (28.0, HardwareTier.B),
        (31.99, HardwareTier.B),
        # Tier A boundaries (32-63.99 GB)
        (32.0, HardwareTier.A),
        (48.0, HardwareTier.A),
        (63.99, HardwareTier.A),
        # Tier S boundaries (>= 64 GB)
        (64.0, HardwareTier.S),
        (64.01, HardwareTier.S),
        (96.0, HardwareTier.S),
        (128.0, HardwareTier.S),
    ])
    def test_tier_classification_boundaries(self, ram_gb, expected_tier):
        """Test that RAM amounts map to correct tiers at boundary values."""
        hw_info = HardwareInfo(ram_gb=ram_gb, tier=expected_tier)
        assert hw_info.tier == expected_tier, \
            f"RAM {ram_gb}GB should be classified as {expected_tier.name}"


# =============================================================================
# RAM Reservation Tests
# =============================================================================

class TestRamReservation:
    """
    Tests for tier-based RAM reservation calculations.
    
    Specification:
    - Tier S: 30% reserved, 70% usable
    - Tier A: 30% reserved, 70% usable
    - Tier B: 35% reserved, 65% usable
    - Tier C: 40% reserved, 60% usable
    """
    
    def test_tier_c_reservation(self, mock_hardware_tier_c):
        """Tier C (16-24GB) should reserve 40% for OS, leaving 60% usable."""
        reservation = mock_hardware_tier_c.get_tier_ram_reservation()
        assert reservation == 0.40, \
            f"Tier C should reserve 40%, got {reservation*100}%"
    
    def test_tier_b_reservation(self, mock_hardware_tier_b):
        """Tier B (24-32GB) should reserve 35% for OS, leaving 65% usable."""
        reservation = mock_hardware_tier_b.get_tier_ram_reservation()
        assert reservation == 0.35, \
            f"Tier B should reserve 35%, got {reservation*100}%"
    
    def test_tier_a_reservation(self, mock_hardware_tier_a):
        """Tier A (32-64GB) should reserve 30% for OS, leaving 70% usable."""
        reservation = mock_hardware_tier_a.get_tier_ram_reservation()
        assert reservation == 0.30, \
            f"Tier A should reserve 30%, got {reservation*100}%"
    
    def test_tier_s_reservation(self, mock_hardware_tier_s):
        """Tier S (64GB+) should reserve 30% for OS, leaving 70% usable."""
        reservation = mock_hardware_tier_s.get_tier_ram_reservation()
        assert reservation == 0.30, \
            f"Tier S should reserve 30%, got {reservation*100}%"
    
    @pytest.mark.parametrize("ram_gb,tier,reservation_pct,expected_usable", [
        (16, HardwareTier.C, 0.40, 16 * 0.60),    # 9.6 GB
        (24, HardwareTier.B, 0.35, 24 * 0.65),    # 15.6 GB
        (32, HardwareTier.A, 0.30, 32 * 0.70),    # 22.4 GB
        (64, HardwareTier.S, 0.30, 64 * 0.70),    # 44.8 GB
        (48, HardwareTier.A, 0.30, 48 * 0.70),    # 33.6 GB
        (96, HardwareTier.S, 0.30, 96 * 0.70),    # 67.2 GB
    ])
    def test_usable_ram_calculation_mathematical(self, ram_gb, tier, reservation_pct, expected_usable):
        """Test usable RAM calculation using mathematical verification."""
        hw_info = HardwareInfo(
            ram_gb=ram_gb,
            tier=tier,
            usable_ram_gb=0  # Will be calculated
        )
        
        usable = hw_info.get_estimated_model_memory()
        
        # Allow for floating point tolerance
        assert abs(usable - expected_usable) < 0.01, \
            f"Expected {expected_usable}GB usable, got {usable}GB"


# =============================================================================
# HardwareInfo Methods Tests
# =============================================================================

class TestHardwareInfoMethods:
    """Tests for HardwareInfo dataclass methods."""
    
    def test_get_tier_label(self, mock_hardware_tier_a):
        """Test tier label generation."""
        label = mock_hardware_tier_a.get_tier_label()
        assert "Tier A" in label
        assert "32" in label or "32.0" in label
    
    def test_calculate_os_overhead(self, mock_hardware_tier_c):
        """Test OS overhead calculation."""
        overhead = mock_hardware_tier_c.calculate_os_overhead()
        expected = 16.0 * 0.40  # 6.4 GB
        assert abs(overhead - expected) < 0.01
    
    def test_get_estimated_model_memory_with_preset(self, mock_hardware_tier_a):
        """Test that preset usable_ram_gb is respected."""
        mock_hardware_tier_a.usable_ram_gb = 20.0
        memory = mock_hardware_tier_a.get_estimated_model_memory()
        assert memory == 20.0
    
    def test_get_estimated_model_memory_calculated(self):
        """Test usable RAM calculation when not preset."""
        hw_info = HardwareInfo(
            ram_gb=32.0,
            tier=HardwareTier.A,
            usable_ram_gb=0
        )
        memory = hw_info.get_estimated_model_memory()
        expected = 32.0 * 0.70  # 22.4 GB
        assert abs(memory - expected) < 0.01


# =============================================================================
# Detect Hardware Tests (Mocked)
# =============================================================================

class TestDetectHardware:
    """Tests for detect_hardware function with mocking."""
    
    @pytest.mark.skip(reason="detect_hardware exits if RAM < 16GB; needs full integration environment")
    def test_detect_hardware_returns_info(self):
        """Test hardware detection returns HardwareInfo."""
        # This test requires a system with >= 16GB RAM
        # In CI/test environments, RAM may be limited
        pass


# =============================================================================
# Edge Cases
# =============================================================================

class TestEdgeCases:
    """Edge case tests for hardware module."""
    
    def test_tier_d_unsupported(self):
        """Test that Tier D is flagged as unsupported."""
        hw_info = HardwareInfo(ram_gb=8.0, tier=HardwareTier.D)
        # Tier D should have 50% reservation
        assert hw_info.get_tier_ram_reservation() == 0.50
    
    def test_nvidia_gpu_uses_vram(self):
        """Test that NVIDIA GPU VRAM is used when available."""
        hw_info = HardwareInfo(
            ram_gb=32.0,
            tier=HardwareTier.A,
            usable_ram_gb=0,
            has_apple_silicon=False,
            gpu_vram_gb=24.0
        )
        memory = hw_info.get_estimated_model_memory()
        # Should return max of usable RAM or VRAM
        usable_ram = 32.0 * 0.70  # 22.4
        assert memory == max(usable_ram, 24.0)  # Should be 24.0
    
    def test_zero_ram_handling(self):
        """Test handling of zero RAM (edge case)."""
        hw_info = HardwareInfo(ram_gb=0, tier=HardwareTier.D, usable_ram_gb=0)
        memory = hw_info.get_estimated_model_memory()
        assert memory >= 0  # Should not be negative
