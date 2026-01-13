"""
Hardware detection and classification.

Detects system hardware and provides hardware information.
"""

import json
import platform
import re
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

from . import ui
from . import utils


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
    docker_allocated_ram_gib: float = 0.0  # Docker Engine/VM memory allocation (best-effort)
    dmr_context_size_tokens: int = 0  # Selected DMR/Continue context length based on Docker RAM
    dmr_context_reason: str = ""  # Why the context size was selected
    usable_ram_gb: float = 0.0  # Calculated usable RAM after OS overhead
    
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
        
        For Docker setups, Docker Desktop manually reserves 8GB, so we use: total_ram - 8GB.
        
        Breakdown of overhead:
        - macOS system: 4-6GB
        - VS Code/IntelliJ: 2-4GB  
        - Browser (Chrome/Safari): 3-6GB
        - Continue.dev overhead: 1-2GB
        - Model context/KV cache: 2-4GB
        
        On Apple Silicon, unified memory is shared between CPU/GPU/Neural Engine.
        """
        if self.usable_ram_gb > 0:
            return self.usable_ram_gb
        
        # For Docker setups, Docker Desktop manually reserves 8GB
        usable_ram = max(0, self.ram_gb - 8.0)
        
        # For discrete GPU systems, use VRAM if available and larger
        if not self.has_apple_silicon and self.gpu_vram_gb > 0:
            return max(usable_ram, self.gpu_vram_gb)
        
        return max(0, usable_ram)


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


def get_apple_silicon_usable_ram(hw_info: HardwareInfo) -> Optional[float]:
    """
    Get usable RAM for Apple Silicon systems.
    
    For Docker setups, Docker Desktop manually reserves 8GB, so we use: total_ram - 8GB.
    
    Args:
        hw_info: Hardware information
        
    Returns:
        Usable RAM in GB as float, or None for non-Apple Silicon systems
    """
    if not hw_info.has_apple_silicon:
        return None
    
    return hw_info.get_estimated_model_memory()


def get_apple_silicon_performance_score(hw_info: HardwareInfo) -> Optional[float]:
    """
    Calculate CPU performance score based on Apple Silicon capabilities.
    
    Factors considered:
    - Chip generation: M1=1.0, M2=1.2, M3=1.4, M4=1.6 (base multiplier)
    - Chip tier: base=1.0, Pro=1.3, Max=1.6, Ultra=2.0 (tier multiplier)
    - Performance cores: More P-cores = better inference speed
    - Neural Engine cores: More NE cores = better ML acceleration
    
    Formula: score = generation_mult * tier_mult * (1 + perf_cores/10) * (1 + ne_cores/20)
    
    Args:
        hw_info: Hardware information
        
    Returns:
        Performance score as float, or None for non-Apple Silicon systems
    """
    if not hw_info.has_apple_silicon:
        return None
    
    # Extract chip generation from chip model (M1, M2, M3, M4)
    chip_model = hw_info.apple_chip_model or ""
    generation_match = re.search(r"M(\d+)", chip_model)
    if not generation_match:
        return None
    
    generation_num = int(generation_match.group(1))
    generation_mult = {
        1: 1.0,
        2: 1.2,
        3: 1.4,
        4: 1.6,
    }.get(generation_num, 1.0)
    
    # Determine chip tier
    tier_mult = 1.0
    if "Ultra" in chip_model:
        tier_mult = 2.0
    elif "Max" in chip_model:
        tier_mult = 1.6
    elif "Pro" in chip_model:
        tier_mult = 1.3
    # base = 1.0 (default)
    
    # Get performance cores (default to detected or estimate)
    perf_cores = hw_info.cpu_perf_cores if hw_info.cpu_perf_cores > 0 else 4
    ne_cores = hw_info.neural_engine_cores if hw_info.neural_engine_cores > 0 else 16
    
    # Calculate score
    score = generation_mult * tier_mult * (1 + perf_cores / 10) * (1 + ne_cores / 20)
    
    return score


def get_apple_silicon_capabilities(hw_info: HardwareInfo) -> Optional[Dict[str, Any]]:
    """
    Get comprehensive Apple Silicon capabilities.
    
    Returns dict with:
    - usable_ram_gb: Calculated usable RAM
    - performance_score: CPU performance score
    - chip_generation: 1, 2, 3, or 4
    - chip_tier: "base", "pro", "max", or "ultra"
    - can_handle_fp16: Boolean (M3 Pro+ or M4+ can handle fp16 efficiently)
    - can_handle_large_models: Boolean (based on RAM + performance score)
    
    Args:
        hw_info: Hardware information
        
    Returns:
        Dict with capabilities, or None for non-Apple Silicon systems
    """
    if not hw_info.has_apple_silicon:
        return None
    
    usable_ram = get_apple_silicon_usable_ram(hw_info)
    performance_score = get_apple_silicon_performance_score(hw_info)
    
    if usable_ram is None or performance_score is None:
        return None
    
    # Extract chip generation and tier
    chip_model = hw_info.apple_chip_model or ""
    generation_match = re.search(r"M(\d+)", chip_model)
    chip_generation = int(generation_match.group(1)) if generation_match else 1
    
    chip_tier = "base"
    if "Ultra" in chip_model:
        chip_tier = "ultra"
    elif "Max" in chip_model:
        chip_tier = "max"
    elif "Pro" in chip_model:
        chip_tier = "pro"
    
    # FP16 capability: M3 Pro+ or M4+ can handle fp16 efficiently
    can_handle_fp16 = (chip_generation >= 4) or (chip_generation == 3 and chip_tier in ("pro", "max", "ultra"))
    
    # Large models: Based on RAM (>=32GB) and performance score (>=2.0)
    can_handle_large_models = usable_ram >= 32.0 and performance_score >= 2.0
    
    return {
        "usable_ram_gb": usable_ram,
        "performance_score": performance_score,
        "chip_generation": chip_generation,
        "chip_tier": chip_tier,
        "can_handle_fp16": can_handle_fp16,
        "can_handle_large_models": can_handle_large_models,
    }


def validate_apple_silicon_support(hw_info: HardwareInfo) -> Tuple[bool, Optional[str]]:
    """
    Validate that the system is Apple Silicon.
    
    Args:
        hw_info: Hardware information
        
    Returns:
        Tuple of (is_supported, error_message)
        - (True, None) if Apple Silicon is detected
        - (False, error_message) if not Apple Silicon
    """
    if not hw_info.has_apple_silicon:
        return (False, "This setup only supports Apple Silicon Macs")
    
    # Validate minimum requirements
    if hw_info.ram_gb < 16:
        return (False, f"Insufficient RAM: {hw_info.ram_gb:.1f}GB detected. Minimum 16GB required.")
    
    performance_score = get_apple_silicon_performance_score(hw_info)
    if performance_score is None or performance_score < 1.0:
        return (False, "Unable to calculate CPU performance score. Minimum performance score of 1.0 required.")
    
    return (True, None)


def detect_hardware() -> HardwareInfo:
    """Detect system hardware."""
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
    
    # Validate minimum RAM requirement (16GB)
    if info.ram_gb < 16:
        ui.print_error(f"Insufficient RAM: {info.ram_gb:.1f}GB detected")
        ui.print_error("Minimum 16GB RAM required for Docker Model Runner setup")
        ui.print_error("Please upgrade your hardware to at least 16GB RAM")
        raise SystemExit("Hardware requirements not met: Minimum 16GB RAM required")
    
    # Validate Apple Silicon requirement (after detection)
    if info.has_apple_silicon:
        is_supported, error_msg = validate_apple_silicon_support(info)
        if not is_supported:
            ui.print_error(error_msg or "This setup only supports Apple Silicon Macs")
            raise SystemExit("Hardware requirements not met: Apple Silicon required")
    
    # Calculate usable RAM (Docker Desktop reserves 8GB)
    info.usable_ram_gb = info.get_estimated_model_memory()
    
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
        ui.print_info(f"Usable RAM for models: ~{info.get_estimated_model_memory():.1f}GB (after OS overhead)")
    elif info.has_nvidia:
        ui.print_info(f"GPU: {info.gpu_name} ({info.gpu_vram_gb:.1f} GB VRAM)")
    else:
        ui.print_info("GPU: None detected (CPU inference only)")
    
    print()
    
    if info.has_apple_silicon:
        ui.print_success(f"Apple Silicon: {info.get_apple_silicon_info()}")
        ui.print_info("Metal GPU acceleration will be used for inference")
    
    return info
