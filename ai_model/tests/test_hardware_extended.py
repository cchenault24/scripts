"""
Extended tests for lib/hardware.py - Additional coverage for hardware detection.

Tests cover more edge cases and methods that weren't previously tested.
"""

import pytest
from unittest.mock import patch, MagicMock
import platform as platform_module

from lib import hardware
from lib.hardware import HardwareTier, HardwareInfo, detect_hardware


class TestHardwareInfoMethods:
    """Tests for HardwareInfo methods."""
    
    def test_get_tier_label_all_tiers(self):
        """Test get_tier_label for all tiers."""
        for tier in [HardwareTier.S, HardwareTier.A, HardwareTier.B, HardwareTier.C, HardwareTier.D]:
            hw = HardwareInfo(ram_gb=32, tier=tier)
            label = hw.get_tier_label()
            assert isinstance(label, str)
            assert tier.value in label
    
    def test_get_tier_ram_reservation_tier_d(self):
        """Test RAM reservation for Tier D."""
        hw = HardwareInfo(ram_gb=8, tier=HardwareTier.D)
        reservation = hw.get_tier_ram_reservation()
        # Tier D should have some reservation
        assert 0 <= reservation <= 1.0
    
    def test_calculate_os_overhead_all_tiers(self):
        """Test OS overhead calculation for all tiers."""
        for tier, ram in [(HardwareTier.S, 64), (HardwareTier.A, 32), 
                          (HardwareTier.B, 24), (HardwareTier.C, 16)]:
            hw = HardwareInfo(ram_gb=ram, tier=tier)
            overhead = hw.calculate_os_overhead()
            assert overhead > 0
            assert overhead < ram
    
    def test_get_apple_silicon_info_variants(self):
        """Test Apple Silicon info for different variants."""
        # Test with M1
        hw_m1 = HardwareInfo(has_apple_silicon=True, apple_chip_model="M1", gpu_cores=8)
        info = hw_m1.get_apple_silicon_info()
        assert "M1" in info or info == ""
        
        # Test with M2 Pro
        hw_m2pro = HardwareInfo(has_apple_silicon=True, apple_chip_model="M2 Pro", gpu_cores=19)
        info2 = hw_m2pro.get_apple_silicon_info()
        assert "M2" in info2 or info2 == ""
    
    def test_get_estimated_model_memory_edge_cases(self):
        """Test memory estimation edge cases."""
        # Very small RAM
        hw_small = HardwareInfo(ram_gb=4, tier=HardwareTier.C)
        mem_small = hw_small.get_estimated_model_memory()
        assert mem_small > 0
        
        # Very large RAM
        hw_large = HardwareInfo(ram_gb=256, tier=HardwareTier.S)
        mem_large = hw_large.get_estimated_model_memory()
        assert mem_large > 100  # Should be substantial


class TestHardwareInfoFromDataclass:
    """Tests for HardwareInfo when created directly (not from detect_hardware)."""
    
    def test_hardware_info_all_fields(self):
        """Test HardwareInfo with all fields set."""
        hw = HardwareInfo(
            os_name="Linux",
            os_version="5.15.0",
            ram_gb=32,
            cpu_brand="Intel i9",
            cpu_cores=16,
            tier=HardwareTier.A
        )
        
        assert hw.os_name == "Linux"
        assert hw.ram_gb == 32
        assert hw.tier == HardwareTier.A


class TestHardwareDataclassFields:
    """Tests for HardwareInfo dataclass fields."""
    
    def test_all_fields_accessible(self, backend_type, api_endpoint):
        """Test all fields are accessible."""
        hw_kwargs = {
            "os_name": "Linux",
            "os_version": "5.15.0",
            "ram_gb": 32,
            "cpu_brand": "Intel i9",
            "cpu_cores": 16,
            "cpu_perf_cores": 8,
            "cpu_eff_cores": 8,
            "gpu_name": "NVIDIA RTX 4090",
            "gpu_cores": 128,
            "gpu_vram_gb": 24,
            "has_apple_silicon": False,
            "apple_chip_model": "",
            "has_nvidia": True,
            "tier": HardwareTier.A,
        }
        if backend_type == "ollama":
            hw_kwargs["ollama_available"] = True
            hw_kwargs["ollama_version"] = "0.1.23"
            hw_kwargs["ollama_api_endpoint"] = api_endpoint
        else:
            hw_kwargs["docker_model_runner_available"] = True
            hw_kwargs["docker_version"] = "0.1.23"
            hw_kwargs["dmr_api_endpoint"] = api_endpoint
        hw = HardwareInfo(**hw_kwargs)
        
        assert hw.os_name == "Linux"
        assert hw.cpu_cores == 16
        assert hw.has_nvidia is True
        if backend_type == "ollama":
            assert hw.ollama_available is True
        else:
            assert hw.docker_model_runner_available is True
