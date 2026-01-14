"""
Hardware detection and classification for llama.cpp.

Detects system hardware and provides hardware information for llama.cpp server configuration.
"""

import json
import platform
import re
from dataclasses import dataclass, field
from typing import Optional

from . import ui
from . import utils


@dataclass
class HardwareInfo:
    """System hardware information."""
    os_name: str = ""
    os_version: str = ""
    macos_version: str = ""
    cpu_brand: str = ""
    cpu_arch: str = ""
    cpu_cores: int = 0
    cpu_perf_cores: int = 0
    cpu_eff_cores: int = 0
    ram_gb: float = 0.0
    gpu_name: str = ""
    gpu_vram_gb: float = 0.0
    gpu_cores: int = 0
    neural_engine_cores: int = 0
    has_apple_silicon: bool = False
    apple_chip_model: str = ""
    usable_ram_gb: float = 0.0
    
    def get_apple_silicon_info(self) -> str:
        """Get Apple Silicon specific information."""
        if not self.has_apple_silicon:
            return "Not Apple Silicon"
        
        info_parts = [self.apple_chip_model or "Apple Silicon"]
        if self.gpu_cores > 0:
            info_parts.append(f"{self.gpu_cores}-core GPU")
        if self.neural_engine_cores > 0:
            info_parts.append(f"{self.neural_engine_cores}-core Neural Engine")
        info_parts.append(f"{self.ram_gb:.0f}GB Unified Memory")
        
        return " | ".join(info_parts)
    
    def get_ram_tier(self) -> str:
        """
        Get RAM tier for context size selection.
        
        Returns:
            RAM tier: "16GB", "24GB", "32GB", "48GB", or "64GB+"
        """
        if self.ram_gb >= 64:
            return "64GB+"
        elif self.ram_gb >= 48:
            return "48GB"
        elif self.ram_gb >= 32:
            return "32GB"
        elif self.ram_gb >= 24:
            return "24GB"
        else:
            return "16GB"


def detect_apple_silicon_details(info: HardwareInfo) -> None:
    """Detect detailed Apple Silicon information."""
    if not info.has_apple_silicon:
        return
    
    if "Apple" in info.cpu_brand:
        chip_patterns = [
            r"Apple M(\d+) (Ultra|Max|Pro)",
            r"Apple M(\d+)",
        ]
        for pattern in chip_patterns:
            match = re.search(pattern, info.cpu_brand)
            if match:
                if len(match.groups()) == 2:
                    info.apple_chip_model = f"M{match.group(1)} {match.group(2)}"
                else:
                    info.apple_chip_model = f"M{match.group(1)}"
                break
    
    code, stdout, _ = utils.run_command(["system_profiler", "SPHardwareDataType", "-json"])
    if code == 0:
        try:
            data = json.loads(stdout)
            hw_info = data.get("SPHardwareDataType", [{}])[0]
            
            if not info.apple_chip_model:
                chip_type = hw_info.get("chip_type", "")
                if chip_type:
                    info.apple_chip_model = chip_type.replace("Apple ", "")
            
            cores_str = hw_info.get("number_processors", "")
            if "proc" in cores_str.lower():
                match = re.search(r"(\d+):(\d+)", cores_str)
                if match:
                    info.cpu_perf_cores = int(match.group(1))
                    info.cpu_eff_cores = int(match.group(2))
        except (json.JSONDecodeError, KeyError, IndexError):
            pass
    
    code, stdout, _ = utils.run_command(["system_profiler", "SPDisplaysDataType", "-json"])
    if code == 0:
        try:
            data = json.loads(stdout)
            displays = data.get("SPDisplaysDataType", [])
            for display in displays:
                if "Apple" in display.get("sppci_model", ""):
                    gpu_model = display.get("sppci_model", "")
                    info.gpu_name = gpu_model
                    cores_match = re.search(r"(\d+)[- ]core", gpu_model.lower())
                    if cores_match:
                        info.gpu_cores = int(cores_match.group(1))
                    break
        except (json.JSONDecodeError, KeyError, IndexError):
            pass
    
    ne_cores = {
        "M1": 16, "M1 Pro": 16, "M1 Max": 16, "M1 Ultra": 32,
        "M2": 16, "M2 Pro": 16, "M2 Max": 16, "M2 Ultra": 32,
        "M3": 16, "M3 Pro": 16, "M3 Max": 16, "M3 Ultra": 32,
        "M4": 16, "M4 Pro": 16, "M4 Max": 16, "M4 Ultra": 32,
        "M5": 16, "M5 Pro": 16, "M5 Max": 16, "M5 Ultra": 32,
    }
    info.neural_engine_cores = ne_cores.get(info.apple_chip_model, 16)


def detect_hardware() -> HardwareInfo:
    """
    Detect system hardware information.
    
    Returns:
        HardwareInfo object with detected hardware details
    """
    info = HardwareInfo()
    
    info.os_name = platform.system()
    info.os_version = platform.version()
    info.cpu_arch = platform.machine()
    info.cpu_brand = platform.processor()
    
    if info.os_name == "Darwin":
        info.macos_version = platform.mac_ver()[0]
        info.has_apple_silicon = info.cpu_arch == "arm64"
        
        detect_apple_silicon_details(info)
        
        code, stdout, _ = utils.run_command(["sysctl", "-n", "hw.physicalcpu"])
        if code == 0:
            try:
                info.cpu_cores = int(stdout.strip())
            except ValueError:
                pass
        
        code, stdout, _ = utils.run_command(["sysctl", "-n", "hw.memsize"])
        if code == 0:
            try:
                memsize_bytes = int(stdout.strip())
                info.ram_gb = memsize_bytes / (1024 ** 3)
            except ValueError:
                pass
        
        if info.has_apple_silicon:
            info.usable_ram_gb = info.ram_gb * 0.5
        else:
            info.usable_ram_gb = max(0, info.ram_gb - 8.0)
    
    ui.print_info(f"OS: {info.os_name} {info.os_version}")
    if info.cpu_brand:
        ui.print_info(f"CPU: {info.cpu_brand}")
    ui.print_info(f"Architecture: {info.cpu_arch}")
    ui.print_info(f"CPU Cores: {info.cpu_cores}")
    ui.print_info(f"RAM: {info.ram_gb:.1f} GB")
    
    if info.has_apple_silicon:
        ui.print_success(f"GPU: {info.gpu_name or 'Apple Silicon GPU'} (Unified Memory: {info.ram_gb:.0f}GB)")
        if info.neural_engine_cores > 0:
            ui.print_info(f"Neural Engine: {info.neural_engine_cores} cores")
        ui.print_info(f"Usable RAM for models: ~{info.usable_ram_gb:.1f}GB (after OS overhead)")
        ui.print_success(f"Apple Silicon: {info.get_apple_silicon_info()}")
        ui.print_info("Metal GPU acceleration will be used for inference")
    
    return info
