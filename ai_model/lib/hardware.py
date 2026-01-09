"""
Hardware detection and classification.

Detects system hardware, classifies into tiers, and provides hardware information.
"""

import json
import platform
import re
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List

from . import ui
from . import utils


class HardwareTier(Enum):
    """Hardware tier classification based on RAM."""
    S = "S"  # ≥49GB RAM
    A = "A"  # 33-48GB RAM
    B = "B"  # 17-32GB RAM
    C = "C"  # <17GB RAM


@dataclass
class HardwareInfo:
    """System hardware information."""
    os_name: str = ""
    os_version: str = ""
    macos_version: str = ""  # e.g., "14.0" for Sonoma
    cpu_brand: str = ""
    cpu_arch: str = ""
    cpu_cores: int = 0
    cpu_perf_cores: int = 0  # Apple Silicon performance cores
    cpu_eff_cores: int = 0   # Apple Silicon efficiency cores
    ram_gb: float = 0.0
    gpu_name: str = ""
    gpu_vram_gb: float = 0.0
    gpu_cores: int = 0       # Apple Silicon GPU cores
    neural_engine_cores: int = 0  # Apple Neural Engine cores
    has_nvidia: bool = False
    has_apple_silicon: bool = False
    apple_chip_model: str = ""  # e.g., "M1", "M2 Pro", "M3 Max"
    docker_version: str = ""
    docker_model_runner_available: bool = False
    dmr_api_endpoint: str = "http://localhost:12434/v1"  # Default, will be updated by docker module
    available_api_models: List[str] = field(default_factory=list)  # Models available via API
    available_docker_hub_models: List[str] = field(default_factory=list)  # Models available on Docker Hub
    discovered_model_tags: Dict[str, List[Dict[str, Any]]] = field(default_factory=dict)  # Cached model tag discovery results
    tier: HardwareTier = HardwareTier.C
    
    def get_tier_label(self) -> str:
        """Get human-readable tier label."""
        # Check if this is a high-end chip promoted to Tier S
        is_high_end_promoted = False
        if self.has_apple_silicon and self.apple_chip_model:
            high_end_patterns = ["M3 Pro", "M3 Max", "M3 Ultra", "M4 Pro", "M4 Max", "M4 Ultra"]
            is_high_end_promoted = (self.tier == HardwareTier.S and 
                                   40 <= self.ram_gb < 49 and
                                   any(pattern in self.apple_chip_model for pattern in high_end_patterns))
        
        labels = {
            HardwareTier.S: f"Tier S ({'40-48GB RAM, High-End Chip' if is_high_end_promoted else '≥49GB RAM'}) - {self.ram_gb:.1f}GB detected",
            HardwareTier.A: f"Tier A (33-48GB RAM) - {self.ram_gb:.1f}GB detected",
            HardwareTier.B: f"Tier B (17-32GB RAM) - {self.ram_gb:.1f}GB detected",
            HardwareTier.C: f"Tier C (<17GB RAM) - {self.ram_gb:.1f}GB detected",
        }
        return labels.get(self.tier, "Unknown")
    
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
    
    def get_estimated_model_memory(self) -> float:
        """
        Get estimated memory available for models.
        On Apple Silicon, unified memory is shared between CPU/GPU/Neural Engine.
        We reserve ~4-8GB for system and other apps.
        """
        if self.has_apple_silicon:
            # Reserve more memory on systems with less RAM
            if self.ram_gb >= 64:
                return self.ram_gb - 8  # Reserve 8GB for system
            elif self.ram_gb >= 32:
                return self.ram_gb - 6  # Reserve 6GB for system
            elif self.ram_gb >= 16:
                return self.ram_gb - 4  # Reserve 4GB for system
            else:
                return self.ram_gb - 3  # Reserve 3GB for system
        else:
            # For discrete GPU systems, use VRAM if available
            if self.gpu_vram_gb > 0:
                return self.gpu_vram_gb
            # Fallback to system RAM with reservation
            return max(0, self.ram_gb - 4)


def detect_apple_silicon_details(info: HardwareInfo) -> None:
    """Detect detailed Apple Silicon information."""
    if not info.has_apple_silicon:
        return
    
    # Get chip model from CPU brand string or system_profiler
    if "Apple" in info.cpu_brand:
        # Extract chip model (M1, M2, M3, M4 and variants)
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
    
    # Try to get more details from system_profiler
    code, stdout, _ = utils.run_command(["system_profiler", "SPHardwareDataType", "-json"])
    if code == 0:
        try:
            data = json.loads(stdout)
            hw_info = data.get("SPHardwareDataType", [{}])[0]
            
            # Get chip name if not already set
            if not info.apple_chip_model:
                chip_type = hw_info.get("chip_type", "")
                if chip_type:
                    info.apple_chip_model = chip_type.replace("Apple ", "")
            
            # Get number of cores
            cores_str = hw_info.get("number_processors", "")
            if "proc" in cores_str.lower():
                # Parse "proc X:Y" format (X performance, Y efficiency)
                match = re.search(r"(\d+):(\d+)", cores_str)
                if match:
                    info.cpu_perf_cores = int(match.group(1))
                    info.cpu_eff_cores = int(match.group(2))
        except (json.JSONDecodeError, KeyError, IndexError):
            pass
    
    # Try to get GPU core count from system_profiler
    code, stdout, _ = utils.run_command(["system_profiler", "SPDisplaysDataType", "-json"])
    if code == 0:
        try:
            data = json.loads(stdout)
            displays = data.get("SPDisplaysDataType", [])
            for display in displays:
                # Look for integrated GPU info
                if "Apple" in display.get("sppci_model", ""):
                    # GPU cores might be in the model name or chipset
                    gpu_model = display.get("sppci_model", "")
                    info.gpu_name = gpu_model
                    # Try to extract core count from various sources
                    cores_match = re.search(r"(\d+)[- ]core", gpu_model.lower())
                    if cores_match:
                        info.gpu_cores = int(cores_match.group(1))
                    break
        except (json.JSONDecodeError, KeyError, IndexError):
            pass
    
    # Estimate Neural Engine cores based on chip model
    ne_cores = {
        "M1": 16, "M1 Pro": 16, "M1 Max": 16, "M1 Ultra": 32,
        "M2": 16, "M2 Pro": 16, "M2 Max": 16, "M2 Ultra": 32,
        "M3": 16, "M3 Pro": 16, "M3 Max": 16, "M3 Ultra": 32,
        "M4": 16, "M4 Pro": 16, "M4 Max": 16, "M4 Ultra": 32,
    }
    info.neural_engine_cores = ne_cores.get(info.apple_chip_model, 16)


def detect_hardware() -> HardwareInfo:
    """Detect system hardware and classify into tier."""
    ui.print_subheader("Detecting Hardware")
    
    info = HardwareInfo()
    
    # OS Detection
    info.os_name = platform.system()
    info.os_version = platform.release()
    info.cpu_arch = platform.machine()
    
    # Validate that we got some basic info
    if not info.os_name:
        ui.print_warning("Could not detect OS name")
    
    # CPU Detection
    if info.os_name == "Darwin":  # macOS
        # Get macOS version name
        code, stdout, _ = utils.run_command(["sw_vers", "-productVersion"])
        if code == 0:
            info.macos_version = stdout.strip()
        
        # CPU brand
        code, stdout, _ = utils.run_command(["sysctl", "-n", "machdep.cpu.brand_string"])
        if code == 0:
            info.cpu_brand = stdout.strip()
        else:
            # Fallback for Apple Silicon which might not have brand_string
            code, stdout, _ = utils.run_command(["sysctl", "-n", "machdep.cpu.brand"])
            if code == 0:
                info.cpu_brand = stdout.strip()
        
        # If still no brand, use uname
        if not info.cpu_brand:
            info.cpu_brand = f"Apple {platform.processor() or 'Silicon'}"
        
        # CPU cores
        code, stdout, _ = utils.run_command(["sysctl", "-n", "hw.physicalcpu"])
        if code == 0:
            info.cpu_cores = int(stdout.strip())
        
        # Performance and efficiency cores (Apple Silicon)
        code, stdout, _ = utils.run_command(["sysctl", "-n", "hw.perflevel0.physicalcpu"])
        if code == 0:
            info.cpu_perf_cores = int(stdout.strip())
        
        code, stdout, _ = utils.run_command(["sysctl", "-n", "hw.perflevel1.physicalcpu"])
        if code == 0:
            info.cpu_eff_cores = int(stdout.strip())
        
        # RAM
        code, stdout, _ = utils.run_command(["sysctl", "-n", "hw.memsize"])
        if code == 0:
            info.ram_gb = int(stdout.strip()) / (1024 ** 3)
        
        # Apple Silicon detection
        info.has_apple_silicon = info.cpu_arch == "arm64"
        
        # Get detailed Apple Silicon info
        if info.has_apple_silicon:
            detect_apple_silicon_details(info)
            info.gpu_name = f"Apple {info.apple_chip_model} GPU" if info.apple_chip_model else "Apple Silicon GPU"
            # Unified memory means GPU can use all system RAM
            info.gpu_vram_gb = info.ram_gb
        
    elif info.os_name == "Linux":
        # CPU brand
        try:
            with open("/proc/cpuinfo") as f:
                for line in f:
                    if "model name" in line:
                        info.cpu_brand = line.split(":")[1].strip()
                        break
        except Exception:
            pass
        
        # CPU cores
        code, stdout, _ = utils.run_command(["nproc"])
        if code == 0:
            info.cpu_cores = int(stdout.strip())
        
        # RAM
        try:
            with open("/proc/meminfo") as f:
                for line in f:
                    if "MemTotal" in line:
                        kb = int(line.split()[1])
                        info.ram_gb = kb / (1024 ** 2)
                        break
        except Exception:
            pass
        
        # NVIDIA GPU detection
        code, stdout, _ = utils.run_command(["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader,nounits"])
        if code == 0 and stdout.strip():
            parts = stdout.strip().split(",")
            if len(parts) >= 2:
                info.gpu_name = parts[0].strip()
                info.gpu_vram_gb = float(parts[1].strip()) / 1024
                info.has_nvidia = True
    
    elif info.os_name == "Windows":
        # CPU
        code, stdout, _ = utils.run_command(["wmic", "cpu", "get", "name"])
        if code == 0:
            lines = stdout.strip().split("\n")
            if len(lines) > 1:
                info.cpu_brand = lines[1].strip()
        
        # Cores
        code, stdout, _ = utils.run_command(["wmic", "cpu", "get", "NumberOfCores"])
        if code == 0:
            lines = stdout.strip().split("\n")
            if len(lines) > 1:
                info.cpu_cores = int(lines[1].strip())
        
        # RAM
        code, stdout, _ = utils.run_command(["wmic", "OS", "get", "TotalVisibleMemorySize"])
        if code == 0:
            lines = stdout.strip().split("\n")
            if len(lines) > 1:
                info.ram_gb = int(lines[1].strip()) / (1024 ** 2)
        
        # NVIDIA GPU
        code, stdout, _ = utils.run_command(["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader,nounits"])
        if code == 0 and stdout.strip():
            parts = stdout.strip().split(",")
            if len(parts) >= 2:
                info.gpu_name = parts[0].strip()
                info.gpu_vram_gb = float(parts[1].strip()) / 1024
                info.has_nvidia = True
    
    # Classify tier - enhanced to consider chip performance, not just RAM
    # High-end chips (M3/M4 Pro/Max/Ultra) with 40GB+ RAM can handle Tier S models
    is_high_end_chip = False
    if info.has_apple_silicon and info.apple_chip_model:
        # Check for high-end chip variants
        high_end_patterns = ["M3 Pro", "M3 Max", "M3 Ultra", "M4 Pro", "M4 Max", "M4 Ultra"]
        is_high_end_chip = any(pattern in info.apple_chip_model for pattern in high_end_patterns)
    
    # Enhanced tier classification
    if info.ram_gb >= 49:
        info.tier = HardwareTier.S
    elif info.ram_gb >= 40 and is_high_end_chip:
        # High-end chips (M3/M4 Pro/Max/Ultra) with 40-48GB RAM can handle Tier S models
        info.tier = HardwareTier.S
    elif info.ram_gb >= 33:
        info.tier = HardwareTier.A
    elif info.ram_gb >= 17:
        info.tier = HardwareTier.B
    else:
        info.tier = HardwareTier.C
    
    # Print detected hardware
    if info.os_name == "Darwin" and info.macos_version:
        ui.print_info(f"OS: macOS {info.macos_version}")
    else:
        ui.print_info(f"OS: {info.os_name} {info.os_version}")
    
    ui.print_info(f"CPU: {info.cpu_brand or 'Unknown'}")
    ui.print_info(f"Architecture: {info.cpu_arch}")
    
    if info.cpu_perf_cores > 0 and info.cpu_eff_cores > 0:
        ui.print_info(f"CPU Cores: {info.cpu_cores} ({info.cpu_perf_cores}P + {info.cpu_eff_cores}E)")
    else:
        ui.print_info(f"CPU Cores: {info.cpu_cores}")
    
    ui.print_info(f"RAM: {info.ram_gb:.1f} GB")
    
    if info.has_apple_silicon:
        ui.print_success(f"GPU: {info.gpu_name} (Unified Memory: {info.ram_gb:.0f}GB)")
        if info.gpu_cores > 0:
            ui.print_info(f"GPU Cores: {info.gpu_cores}")
        if info.neural_engine_cores > 0:
            ui.print_info(f"Neural Engine: {info.neural_engine_cores} cores")
        ui.print_info(f"Estimated memory for models: ~{info.get_estimated_model_memory():.0f}GB")
    elif info.has_nvidia:
        ui.print_info(f"GPU: {info.gpu_name} ({info.gpu_vram_gb:.1f} GB VRAM)")
    else:
        ui.print_info("GPU: None detected (CPU inference only)")
    
    print()
    ui.print_success(f"Hardware Tier: {info.get_tier_label()}")
    
    if info.has_apple_silicon:
        ui.print_success(f"Apple Silicon: {info.get_apple_silicon_info()}")
        ui.print_info("Metal GPU acceleration will be used for inference")
    
    return info
