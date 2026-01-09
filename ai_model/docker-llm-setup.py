#!/usr/bin/env python3
"""
Docker Model Runner + Continue.dev Setup Script

An interactive Python script that helps you set up a locally hosted LLM
via Docker Model Runner (DMR) and generates a continue.dev config.yaml for VS Code.

Optimized for Mac with Apple Silicon (M1/M2/M3/M4) using Docker Model Runner.

Requirements:
- Python 3.8+
- Docker Desktop 4.40+ (with Docker Model Runner enabled)
- macOS with Apple Silicon (recommended) or Linux/Windows with NVIDIA GPU

Docker Model Runner Commands:
- docker model pull <model>   - Download a model
- docker model run <model>    - Run a model interactively
- docker model list           - List available models
- docker model rm <model>     - Remove a model

Author: AI-Generated for Local LLM Development
License: MIT
"""

import json
import os
import platform
import re
import shutil
import socket
import subprocess
import sys
import time
import urllib.request
import urllib.error
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# Docker Model Runner API configuration
# DMR exposes an OpenAI-compatible API endpoint
DMR_API_HOST = "localhost"
DMR_API_PORT = 12434  # Default Docker Model Runner port
DMR_API_BASE = f"http://{DMR_API_HOST}:{DMR_API_PORT}/v1"

# Alternative: Docker Model Runner can also be accessed via Docker socket
# For some setups, the endpoint might be different
DMR_SOCKET_ENDPOINT = "http://model-runner.docker.internal/v1"

# ANSI color codes for terminal output
class Colors:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RED = "\033[91m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    BLUE = "\033[94m"
    MAGENTA = "\033[95m"
    CYAN = "\033[96m"
    WHITE = "\033[97m"
    BG_BLUE = "\033[44m"
    BG_GREEN = "\033[42m"


def colorize(text: str, color: str) -> str:
    """Apply color to text."""
    return f"{color}{text}{Colors.RESET}"


def print_header(text: str) -> None:
    """Print a styled header."""
    width = max(60, len(text) + 10)
    print()
    print(colorize("═" * width, Colors.CYAN))
    print(colorize(f"  {text}", Colors.CYAN + Colors.BOLD))
    print(colorize("═" * width, Colors.CYAN))
    print()


def print_subheader(text: str) -> None:
    """Print a styled subheader."""
    print()
    print(colorize(f"▸ {text}", Colors.BLUE + Colors.BOLD))
    print(colorize("─" * 50, Colors.DIM))


def print_success(text: str) -> None:
    """Print success message."""
    print(colorize(f"✓ {text}", Colors.GREEN))


def print_error(text: str) -> None:
    """Print error message."""
    print(colorize(f"✗ {text}", Colors.RED))


def print_warning(text: str) -> None:
    """Print warning message."""
    print(colorize(f"⚠ {text}", Colors.YELLOW))


def print_info(text: str) -> None:
    """Print info message."""
    print(colorize(f"ℹ {text}", Colors.BLUE))


def print_step(step: int, total: int, text: str) -> None:
    """Print a step indicator."""
    print(colorize(f"[{step}/{total}] {text}", Colors.MAGENTA))


def clear_screen() -> None:
    """Clear the terminal screen."""
    os.system("cls" if platform.system() == "Windows" else "clear")


def prompt_yes_no(question: str, default: bool = True) -> bool:
    """Prompt user for yes/no answer."""
    suffix = "[Y/n]" if default else "[y/N]"
    while True:
        response = input(f"{colorize('?', Colors.CYAN)} {question} {colorize(suffix, Colors.DIM)}: ").strip().lower()
        if not response:
            return default
        if response in ("y", "yes"):
            return True
        if response in ("n", "no"):
            return False
        print_warning("Please enter 'y' or 'n'")


def prompt_choice(question: str, choices: List[str], default: int = 0) -> int:
    """Prompt user to select from choices."""
    print(f"\n{colorize('?', Colors.CYAN)} {question}")
    for i, choice in enumerate(choices):
        marker = colorize("●", Colors.GREEN) if i == default else colorize("○", Colors.DIM)
        print(f"  {marker} [{i + 1}] {choice}")
    
    while True:
        response = input(f"\n  Enter choice (1-{len(choices)}) [{default + 1}]: ").strip()
        if not response:
            return default
        try:
            idx = int(response) - 1
            if 0 <= idx < len(choices):
                return idx
        except ValueError:
            pass
        print_warning(f"Please enter a number between 1 and {len(choices)}")


def prompt_multi_choice(question: str, choices: List[Tuple[str, str, bool]], min_selections: int = 0) -> List[int]:
    """Prompt user to select multiple choices."""
    selected = [i for i, (_, _, default) in enumerate(choices) if default]
    
    while True:
        print(f"\n{colorize('?', Colors.CYAN)} {question}")
        print(colorize("  (Enter numbers separated by commas, or 'a' for all, 'n' for none)", Colors.DIM))
        
        for i, (name, desc, _) in enumerate(choices):
            marker = colorize("●", Colors.GREEN) if i in selected else colorize("○", Colors.DIM)
            print(f"  {marker} [{i + 1}] {name}")
            if desc:
                print(colorize(f"      {desc}", Colors.DIM))
        
        response = input(f"\n  Selection [{','.join(str(i+1) for i in selected) or 'none'}]: ").strip().lower()
        
        if not response:
            if len(selected) >= min_selections:
                return selected
            print_warning(f"Please select at least {min_selections} option(s)")
            continue
        
        if response == "a":
            return list(range(len(choices)))
        if response == "n":
            if min_selections == 0:
                return []
            print_warning(f"Please select at least {min_selections} option(s)")
            continue
        
        try:
            new_selected = []
            for part in response.split(","):
                part = part.strip()
                if "-" in part:
                    start, end = map(int, part.split("-"))
                    new_selected.extend(range(start - 1, end))
                else:
                    new_selected.append(int(part) - 1)
            
            new_selected = [i for i in new_selected if 0 <= i < len(choices)]
            if len(new_selected) >= min_selections:
                return list(set(new_selected))
            print_warning(f"Please select at least {min_selections} option(s)")
        except ValueError:
            print_warning("Invalid input. Enter numbers separated by commas")


def run_command(cmd: List[str], capture: bool = True, timeout: int = 300) -> Tuple[int, str, str]:
    """Run a shell command and return (returncode, stdout, stderr)."""
    try:
        result = subprocess.run(
            cmd,
            capture_output=capture,
            text=True,
            timeout=timeout
        )
        return result.returncode, result.stdout or "", result.stderr or ""
    except subprocess.TimeoutExpired:
        return -1, "", "Command timed out"
    except FileNotFoundError:
        return -1, "", f"Command not found: {cmd[0]}"
    except Exception as e:
        return -1, "", str(e)


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
    dmr_api_endpoint: str = DMR_API_BASE
    available_api_models: List[str] = field(default_factory=list)  # Models available via API
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


@dataclass
class ModelInfo:
    """Information about an LLM model."""
    name: str
    docker_name: str  # Name used in Docker Model Runner
    description: str
    ram_gb: float
    context_length: int
    roles: List[str]  # chat, autocomplete, embed, etc.
    tiers: List[HardwareTier]  # Which tiers can run this model
    recommended_for: List[str] = field(default_factory=list)


# Model catalog for Docker Model Runner (DMR)
# Docker Model Runner uses the namespace: ai.docker.com/ or just model names
# Models are optimized for Apple Silicon with Metal acceleration
# Format: ai.docker.com/<org>/<model>:<tag> or simplified <model>:<tag>
MODEL_CATALOG: List[ModelInfo] = [
    # =========================================================================
    # Chat/Edit Models - Large (Tier S: 49GB+ RAM)
    # =========================================================================
    ModelInfo(
        name="Llama 3.3 70B",
        docker_name="ai.docker.com/meta/llama3.3:70b-instruct-q4_K_M",
        description="70B - Highest quality for complex refactoring (Tier S only)",
        ram_gb=35.0,
        context_length=131072,
        roles=["chat", "edit", "agent"],
        tiers=[HardwareTier.S],
        recommended_for=["Tier S primary model", "Complex refactoring"]
    ),
    ModelInfo(
        name="Llama 3.1 70B",
        docker_name="ai.docker.com/meta/llama3.1:70b-instruct-q4_K_M",
        description="70B - Excellent for architecture and complex tasks",
        ram_gb=35.0,
        context_length=131072,
        roles=["chat", "edit", "agent"],
        tiers=[HardwareTier.S],
        recommended_for=["Tier S alternative"]
    ),
    # =========================================================================
    # Chat/Edit Models - Medium-Large (Tier A: 33-48GB RAM)
    # =========================================================================
    ModelInfo(
        name="Qwen 2.5 Coder 32B",
        docker_name="ai.docker.com/qwen/qwen2.5-coder:32b-instruct-q4_K_M",
        description="32B - State-of-the-art open coding model",
        ram_gb=18.0,
        context_length=131072,
        roles=["chat", "edit", "autocomplete"],
        tiers=[HardwareTier.S, HardwareTier.A],
        recommended_for=["Best coding quality", "Tier A primary"]
    ),
    ModelInfo(
        name="Codestral 22B",
        docker_name="ai.docker.com/mistral/codestral:22b-v0.1-q4_K_M",
        description="22B - Mistral's code generation model",
        ram_gb=12.0,
        context_length=32768,
        roles=["chat", "edit", "autocomplete"],
        tiers=[HardwareTier.S, HardwareTier.A],
        recommended_for=["Excellent code generation"]
    ),
    ModelInfo(
        name="DeepSeek Coder V2 Lite 16B",
        docker_name="ai.docker.com/deepseek/deepseek-coder-v2:16b-lite-instruct-q4_K_M",
        description="16B - Fast and capable coding model",
        ram_gb=9.0,
        context_length=131072,
        roles=["chat", "edit", "autocomplete"],
        tiers=[HardwareTier.S, HardwareTier.A],
        recommended_for=["Good balance of speed and quality"]
    ),
    # =========================================================================
    # Chat/Edit Models - Medium (Tier B: 17-32GB RAM)
    # =========================================================================
    ModelInfo(
        name="Phi-4 14B",
        docker_name="ai.docker.com/microsoft/phi4:14b-q4_K_M",
        description="14B - Microsoft's state-of-the-art reasoning model",
        ram_gb=8.0,
        context_length=16384,
        roles=["chat", "edit", "agent"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B],
        recommended_for=["Excellent reasoning", "Tier B primary"]
    ),
    ModelInfo(
        name="Qwen 2.5 Coder 14B",
        docker_name="ai.docker.com/qwen/qwen2.5-coder:14b-instruct-q4_K_M",
        description="14B - Strong coding with good performance",
        ram_gb=8.0,
        context_length=131072,
        roles=["chat", "edit", "autocomplete"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B],
        recommended_for=["Good balance of quality and speed"]
    ),
    ModelInfo(
        name="CodeLlama 13B",
        docker_name="ai.docker.com/meta/codellama:13b-instruct-q4_K_M",
        description="13B - Meta's code-specialized Llama",
        ram_gb=7.5,
        context_length=16384,
        roles=["chat", "edit", "autocomplete"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B],
        recommended_for=["Code generation"]
    ),
    # =========================================================================
    # Chat/Edit Models - Small (All Tiers, optimized for Tier C: <17GB RAM)
    # =========================================================================
    # Note: Llama 3.2 8B is NOT available in Docker Model Runner
    # Docker Model Runner only provides ai/llama3.2 which is the 3B variant
    # Keeping this commented out to prevent confusion
    # ModelInfo(
    #     name="Llama 3.2 8B",
    #     docker_name="ai.docker.com/meta/llama3.2:8b-instruct-q5_K_M",
    #     description="8B - Fast general-purpose assistant",
    #     ram_gb=5.0,
    #     context_length=131072,
    #     roles=["chat", "edit", "autocomplete"],
    #     tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B, HardwareTier.C],
    #     recommended_for=["All tiers", "Fast responses"]
    # ),
    ModelInfo(
        name="Qwen 2.5 Coder 7B",
        docker_name="ai.docker.com/qwen/qwen2.5-coder:7b-instruct-q4_K_M",
        description="7B - Efficient coding model",
        ram_gb=4.0,
        context_length=131072,
        roles=["chat", "edit", "autocomplete"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B, HardwareTier.C],
        recommended_for=["Tier C primary", "Fast autocomplete"]
    ),
    ModelInfo(
        name="CodeGemma 7B",
        docker_name="ai.docker.com/google/codegemma:7b-it-q4_K_M",
        description="7B - Google's code-optimized model",
        ram_gb=4.0,
        context_length=8192,
        roles=["chat", "autocomplete"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B, HardwareTier.C],
        recommended_for=["Fast autocomplete"]
    ),
    # =========================================================================
    # Autocomplete Models - Ultra-fast (All Tiers)
    # =========================================================================
    ModelInfo(
        name="StarCoder2 3B",
        docker_name="ai.docker.com/bigcode/starcoder2:3b-q4_K_M",
        description="3B - Ultra-fast autocomplete optimized for code",
        ram_gb=1.8,
        context_length=16384,
        roles=["autocomplete"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B, HardwareTier.C],
        recommended_for=["Fastest autocomplete", "Low memory"]
    ),
    ModelInfo(
        name="Llama 3.2 3B",
        docker_name="ai.docker.com/meta/llama3.2:3b-instruct-q4_K_M",
        description="3B - Small and efficient general model (available in Docker Model Runner as ai/llama3.2)",
        ram_gb=1.8,
        context_length=131072,
        roles=["chat", "edit", "autocomplete"],  # Added "edit" since 8B is not available
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B, HardwareTier.C],
        recommended_for=["All tiers", "Quick edits", "Low memory", "Fast responses"]
    ),
    ModelInfo(
        name="Qwen 2.5 Coder 1.5B",
        docker_name="ai.docker.com/qwen/qwen2.5-coder:1.5b-instruct-q8_0",
        description="1.5B - Smallest coding model, very fast",
        ram_gb=1.0,
        context_length=131072,
        roles=["autocomplete"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B, HardwareTier.C],
        recommended_for=["Minimal memory usage", "Ultra-fast autocomplete"]
    ),
    # =========================================================================
    # Embedding Models (All Tiers)
    # =========================================================================
    ModelInfo(
        name="Nomic Embed Text v1.5",
        docker_name="ai.docker.com/nomic/nomic-embed-text:v1.5",
        description="Best open embedding model for code indexing (8192 tokens)",
        ram_gb=0.3,
        context_length=8192,
        roles=["embed"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B, HardwareTier.C],
        recommended_for=["Code indexing", "Semantic search"]
    ),
    ModelInfo(
        name="BGE-M3",
        docker_name="ai.docker.com/baai/bge-m3:latest",
        description="Multi-lingual embedding model from BAAI",
        ram_gb=0.5,
        context_length=8192,
        roles=["embed"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B, HardwareTier.C],
        recommended_for=["Multi-lingual codebases"]
    ),
    ModelInfo(
        name="All-MiniLM-L6-v2",
        docker_name="ai.docker.com/sentence-transformers/all-minilm:l6-v2",
        description="Lightweight embedding for simple use cases",
        ram_gb=0.1,
        context_length=512,
        roles=["embed"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B, HardwareTier.C],
        recommended_for=["Minimal memory", "Simple search"]
    ),
]


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
    code, stdout, _ = run_command(["system_profiler", "SPHardwareDataType", "-json"])
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
    code, stdout, _ = run_command(["system_profiler", "SPDisplaysDataType", "-json"])
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
    print_subheader("Detecting Hardware")
    
    info = HardwareInfo()
    
    # OS Detection
    info.os_name = platform.system()
    info.os_version = platform.release()
    info.cpu_arch = platform.machine()
    
    # CPU Detection
    if info.os_name == "Darwin":  # macOS
        # Get macOS version name
        code, stdout, _ = run_command(["sw_vers", "-productVersion"])
        if code == 0:
            info.macos_version = stdout.strip()
        
        # CPU brand
        code, stdout, _ = run_command(["sysctl", "-n", "machdep.cpu.brand_string"])
        if code == 0:
            info.cpu_brand = stdout.strip()
        else:
            # Fallback for Apple Silicon which might not have brand_string
            code, stdout, _ = run_command(["sysctl", "-n", "machdep.cpu.brand"])
            if code == 0:
                info.cpu_brand = stdout.strip()
        
        # If still no brand, use uname
        if not info.cpu_brand:
            info.cpu_brand = f"Apple {platform.processor() or 'Silicon'}"
        
        # CPU cores
        code, stdout, _ = run_command(["sysctl", "-n", "hw.physicalcpu"])
        if code == 0:
            info.cpu_cores = int(stdout.strip())
        
        # Performance and efficiency cores (Apple Silicon)
        code, stdout, _ = run_command(["sysctl", "-n", "hw.perflevel0.physicalcpu"])
        if code == 0:
            info.cpu_perf_cores = int(stdout.strip())
        
        code, stdout, _ = run_command(["sysctl", "-n", "hw.perflevel1.physicalcpu"])
        if code == 0:
            info.cpu_eff_cores = int(stdout.strip())
        
        # RAM
        code, stdout, _ = run_command(["sysctl", "-n", "hw.memsize"])
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
        code, stdout, _ = run_command(["nproc"])
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
        code, stdout, _ = run_command(["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader,nounits"])
        if code == 0 and stdout.strip():
            parts = stdout.strip().split(",")
            if len(parts) >= 2:
                info.gpu_name = parts[0].strip()
                info.gpu_vram_gb = float(parts[1].strip()) / 1024
                info.has_nvidia = True
    
    elif info.os_name == "Windows":
        # CPU
        code, stdout, _ = run_command(["wmic", "cpu", "get", "name"])
        if code == 0:
            lines = stdout.strip().split("\n")
            if len(lines) > 1:
                info.cpu_brand = lines[1].strip()
        
        # Cores
        code, stdout, _ = run_command(["wmic", "cpu", "get", "NumberOfCores"])
        if code == 0:
            lines = stdout.strip().split("\n")
            if len(lines) > 1:
                info.cpu_cores = int(lines[1].strip())
        
        # RAM
        code, stdout, _ = run_command(["wmic", "OS", "get", "TotalVisibleMemorySize"])
        if code == 0:
            lines = stdout.strip().split("\n")
            if len(lines) > 1:
                info.ram_gb = int(lines[1].strip()) / (1024 ** 2)
        
        # NVIDIA GPU
        code, stdout, _ = run_command(["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader,nounits"])
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
        print_info(f"OS: macOS {info.macos_version}")
    else:
        print_info(f"OS: {info.os_name} {info.os_version}")
    
    print_info(f"CPU: {info.cpu_brand or 'Unknown'}")
    print_info(f"Architecture: {info.cpu_arch}")
    
    if info.cpu_perf_cores > 0 and info.cpu_eff_cores > 0:
        print_info(f"CPU Cores: {info.cpu_cores} ({info.cpu_perf_cores}P + {info.cpu_eff_cores}E)")
    else:
        print_info(f"CPU Cores: {info.cpu_cores}")
    
    print_info(f"RAM: {info.ram_gb:.1f} GB")
    
    if info.has_apple_silicon:
        print_success(f"GPU: {info.gpu_name} (Unified Memory: {info.ram_gb:.0f}GB)")
        if info.gpu_cores > 0:
            print_info(f"GPU Cores: {info.gpu_cores}")
        if info.neural_engine_cores > 0:
            print_info(f"Neural Engine: {info.neural_engine_cores} cores")
        print_info(f"Estimated memory for models: ~{info.get_estimated_model_memory():.0f}GB")
    elif info.has_nvidia:
        print_info(f"GPU: {info.gpu_name} ({info.gpu_vram_gb:.1f} GB VRAM)")
    else:
        print_info("GPU: None detected (CPU inference only)")
    
    print()
    print_success(f"Hardware Tier: {info.get_tier_label()}")
    
    if info.has_apple_silicon:
        print_success(f"Apple Silicon: {info.get_apple_silicon_info()}")
        print_info("Metal GPU acceleration will be used for inference")
    
    return info


def check_docker() -> Tuple[bool, str]:
    """Check if Docker is installed and running."""
    print_subheader("Checking Docker Installation")
    
    # Check if docker command exists
    if not shutil.which("docker"):
        print_error("Docker not found in PATH")
        return False, ""
    
    # Check docker version
    code, stdout, stderr = run_command(["docker", "--version"])
    if code != 0:
        print_error(f"Failed to get Docker version: {stderr}")
        return False, ""
    
    version = stdout.strip()
    print_info(f"Docker version: {version}")
    
    # Check if Docker daemon is running
    code, stdout, stderr = run_command(["docker", "info"])
    if code != 0:
        print_error("Docker daemon is not running")
        print_info("Please start Docker Desktop and try again")
        return False, version
    
    print_success("Docker is installed and running")
    return True, version


def fetch_available_models_from_api(endpoint: str) -> List[str]:
    """
    Fetch list of available models from Docker Model Runner API.
    According to docs: https://docs.docker.com/ai/model-runner/api-reference/
    The API exposes OpenAI-compatible endpoints including /models
    """
    available_models = []
    try:
        import urllib.request
        import json
        import urllib.error
        
        api_url = f"{endpoint}/models"
        req = urllib.request.Request(api_url, method="GET")
        req.add_header("Content-Type", "application/json")
        
        with urllib.request.urlopen(req, timeout=5) as response:
            if response.status == 200:
                data = json.loads(response.read().decode('utf-8'))
                if "data" in data:
                    for model in data["data"]:
                        model_id = model.get("id", "")
                        if model_id:
                            available_models.append(model_id)
    except (urllib.error.URLError, urllib.error.HTTPError, OSError, json.JSONDecodeError):
        pass
    
    return available_models


def check_docker_model_runner(hardware: HardwareInfo) -> bool:
    """Check if Docker Model Runner is available."""
    print_subheader("Checking Docker Model Runner (DMR)")
    
    # Docker Model Runner was introduced in Docker Desktop 4.40+
    # It uses the 'docker model' command namespace
    # Docs: https://docs.docker.com/ai/model-runner/
    code, stdout, stderr = run_command(["docker", "model", "list"])
    
    if code == 0:
        hardware.docker_model_runner_available = True
        print_success("Docker Model Runner is available and running")
        
        # Determine the API endpoint
        # Try the standard localhost endpoint first
        hardware.dmr_api_endpoint = DMR_API_BASE
        
        # Check if we can reach the API
        import urllib.request
        import urllib.error
        
        api_reachable = False
        available_api_models = []
        for endpoint in [DMR_API_BASE, DMR_SOCKET_ENDPOINT, "http://localhost:8080/v1"]:
            try:
                req = urllib.request.Request(f"{endpoint}/models", method="GET")
                req.add_header("Content-Type", "application/json")
                with urllib.request.urlopen(req, timeout=5) as response:
                    if response.status == 200:
                        hardware.dmr_api_endpoint = endpoint
                        api_reachable = True
                        print_info(f"API endpoint: {endpoint}")
                        # Fetch available models from API
                        available_api_models = fetch_available_models_from_api(endpoint)
                        if available_api_models:
                            print_info(f"Found {len(available_api_models)} model(s) via API")
                        break
            except (urllib.error.URLError, urllib.error.HTTPError, OSError):
                continue
        
        if not api_reachable:
            print_info(f"API endpoint (default): {hardware.dmr_api_endpoint}")
            print_warning("Could not verify API endpoint - it may start when a model runs")
        
        # Store available models for later verification
        hardware.available_api_models = available_api_models
        
        # Check for existing models
        lines = stdout.strip().split("\n")
        if len(lines) > 1:  # Has models (first line is header)
            print_info("Installed models:")
            for line in lines[1:]:
                if line.strip():
                    parts = line.split()
                    if parts:
                        print(f"    • {parts[0]}")
        else:
            print_info("No models installed yet")
        
        # Show Apple Silicon optimization status
        if hardware.has_apple_silicon:
            print_success("Metal GPU acceleration enabled for Apple Silicon")
        
        return True
    
    # Check if it's just not enabled or not installed
    error_lower = stderr.lower()
    if "unknown command" in error_lower or "docker model" in error_lower or "not found" in error_lower:
        print_warning("Docker Model Runner is not enabled")
        print()
        print_info("Docker Model Runner requires Docker Desktop 4.40 or later.")
        print()
        
        if hardware.os_name == "Darwin":
            print_info(colorize("To enable on macOS:", Colors.BOLD))
            print_info("  1. Open Docker Desktop")
            print_info("  2. Click the ⚙️ Settings icon (top right)")
            print_info("  3. Go to 'Features in development' or 'Beta features'")
            print_info("  4. Enable 'Docker Model Runner' or 'Enable Docker AI'")
            print_info("  5. Click 'Apply & restart'")
            print()
            print_info("Or run this command:")
            print(colorize("     docker desktop enable model-runner --tcp 12434", Colors.CYAN))
        else:
            print_info("To enable Docker Model Runner:")
            print_info("  1. Open Docker Desktop")
            print_info("  2. Go to Settings → Features in development")
            print_info("  3. Enable 'Docker Model Runner' or 'Enable Docker AI'")
            print_info("  4. Click 'Apply & restart'")
        
        print()
        
        if prompt_yes_no("Would you like to continue setup anyway (config will be generated but models won't be pulled)?"):
            hardware.dmr_api_endpoint = DMR_API_BASE
            return True
        return False
    
    print_error(f"Error checking Docker Model Runner: {stderr}")
    return False


def discover_docker_hub_models(query: str = "ai/", limit: int = 50) -> List[Dict[str, Any]]:
    """Discover models from Docker Hub."""
    models = []
    try:
        print_info(f"Searching Docker Hub for '{query}'...")
        code, stdout, _ = run_command(["docker", "search", query, "--limit", str(limit)], timeout=30)
        if code == 0:
            lines = stdout.strip().split("\n")
            if len(lines) > 1:  # Has results (first line is header)
                for line in lines[1:]:
                    if line.strip():
                        parts = line.split()
                        if parts:
                            model_name = parts[0]
                            description = " ".join(parts[1:]) if len(parts) > 1 else "No description"
                            # Only include models in ai/ namespace
                            if model_name.startswith("ai/"):
                                models.append({
                                    "name": model_name,
                                    "description": description[:100],  # Limit description length
                                    "source": "docker_hub",
                                    "stars": parts[1] if len(parts) > 1 and parts[1].isdigit() else "0"
                                })
    except Exception as e:
        print_warning(f"Could not search Docker Hub: {e}")
    
    return models


def discover_huggingface_models(query: str = "llama", limit: int = 30) -> List[Dict[str, Any]]:
    """Discover models from Hugging Face (GGUF format)."""
    models = []
    try:
        print_info(f"Searching Hugging Face for '{query}'...")
        url = f"https://huggingface.co/api/models?search={query}&filter=gguf&limit={limit}"
        req = urllib.request.Request(url)
        req.add_header("User-Agent", "Docker-Model-Runner-Setup/1.0")
        
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read())
            if isinstance(data, list):
                for model in data[:limit]:
                    model_id = model.get("id", "")
                    if model_id:
                        models.append({
                            "name": f"hf.co/{model_id}",
                            "description": model.get("pipeline_tag", "GGUF model"),
                            "source": "huggingface",
                            "downloads": model.get("downloads", 0)
                        })
    except urllib.error.URLError as e:
        print_warning(f"Could not search Hugging Face: {e}")
    except Exception as e:
        print_warning(f"Error searching Hugging Face: {e}")
    
    return models


def convert_discovered_to_modelinfo(discovered: Dict[str, Any], hardware: HardwareTier) -> ModelInfo:
    """Convert a discovered model to ModelInfo format."""
    model_name = discovered["name"]
    # Extract a friendly name
    friendly_name = model_name.split("/")[-1].replace("-", " ").replace("_", " ").title()
    
    # Estimate RAM based on model name patterns
    ram_gb = 8.0  # Default
    if "70b" in model_name.lower() or "70B" in model_name.lower():
        ram_gb = 35.0
    elif "32b" in model_name.lower() or "32B" in model_name.lower():
        ram_gb = 18.0
    elif "22b" in model_name.lower() or "22B" in model_name.lower():
        ram_gb = 12.0
    elif "14b" in model_name.lower() or "14B" in model_name.lower():
        ram_gb = 8.0
    elif "8b" in model_name.lower() or "8B" in model_name.lower():
        ram_gb = 5.0
    elif "7b" in model_name.lower() or "7B" in model_name.lower():
        ram_gb = 4.0
    elif "3b" in model_name.lower() or "3B" in model_name.lower():
        ram_gb = 2.0
    elif "1.5b" in model_name.lower() or "1.5B" in model_name.lower():
        ram_gb = 1.0
    
    # Determine roles based on name
    roles = ["chat", "edit"]
    if "embed" in model_name.lower():
        roles = ["embed"]
    elif "coder" in model_name.lower() or "code" in model_name.lower():
        roles = ["chat", "edit", "autocomplete"]
    
    # Determine tier
    tiers = [HardwareTier.C]
    if ram_gb >= 35:
        tiers = [HardwareTier.S]
    elif ram_gb >= 18:
        tiers = [HardwareTier.S, HardwareTier.A]
    elif ram_gb >= 12:
        tiers = [HardwareTier.A, HardwareTier.S]
    elif ram_gb >= 8:
        tiers = [HardwareTier.B, HardwareTier.A, HardwareTier.S]
    else:
        tiers = [HardwareTier.C, HardwareTier.B, HardwareTier.A, HardwareTier.S]
    
    return ModelInfo(
        name=friendly_name,
        docker_name=model_name,
        description=discovered.get("description", "Discovered model"),
        ram_gb=ram_gb,
        context_length=32768,  # Default
        roles=roles,
        tiers=tiers,
        recommended_for=[]
    )


def discover_and_select_models(hardware: HardwareInfo) -> List[ModelInfo]:
    """Discover available models and let user select interactively."""
    print_header("🔍 Model Discovery & Selection")
    
    selected_models: List[ModelInfo] = []
    all_discovered: List[Dict[str, Any]] = []
    
    # Ask which source to search
    print_info("Where would you like to search for models?")
    source_choice = prompt_choice(
        "Select source:",
        ["Docker Hub (ai/ namespace)", "Hugging Face (hf.co/)", "Both"],
        default=0
    )
    
    # Search Docker Hub
    if source_choice in [0, 2]:
        print()
        search_query = input("Enter search query for Docker Hub (default: 'ai/'): ").strip() or "ai/"
        docker_models = discover_docker_hub_models(search_query)
        all_discovered.extend(docker_models)
        if docker_models:
            print_success(f"Found {len(docker_models)} models on Docker Hub")
    
    # Search Hugging Face
    if source_choice in [1, 2]:
        print()
        search_query = input("Enter search query for Hugging Face (default: 'llama'): ").strip() or "llama"
        hf_models = discover_huggingface_models(search_query)
        all_discovered.extend(hf_models)
        if hf_models:
            print_success(f"Found {len(hf_models)} models on Hugging Face")
    
    if not all_discovered:
        print_warning("No models found. Try a different search query.")
        return []
    
    # Convert to ModelInfo and display
    print()
    print_subheader("Discovered Models")
    model_infos = [convert_discovered_to_modelinfo(m, hardware.tier) for m in all_discovered]
    
    # Filter by hardware tier
    available_models = [m for m in model_infos if hardware.tier in m.tiers]
    
    if not available_models:
        print_warning(f"No models found compatible with your hardware tier ({hardware.tier.value})")
        print_info("Showing all models anyway...")
        available_models = model_infos
    
    # Group by role
    chat_models = [m for m in available_models if "chat" in m.roles or "edit" in m.roles]
    auto_models = [m for m in available_models if "autocomplete" in m.roles]
    embed_models = [m for m in available_models if "embed" in m.roles]
    
    # Select chat/edit models
    if chat_models:
        print()
        print_subheader("Chat/Edit Models")
        choices = [(m.name, f"{m.description} (~{m.ram_gb}GB) - {m.docker_name}", False) for m in chat_models]
        indices = prompt_multi_choice("Select chat/edit model(s):", choices, min_selections=1)
        for i in indices:
            selected_models.append(chat_models[i])
    
    # Select autocomplete models
    if auto_models:
        print()
        if prompt_yes_no("Add a dedicated autocomplete model?", default=False):
            print_subheader("Autocomplete Models")
            choices = [(m.name, f"{m.description} (~{m.ram_gb}GB) - {m.docker_name}", False) for m in auto_models]
            indices = prompt_multi_choice("Select autocomplete model:", choices, min_selections=1)
            for i in indices:
                if auto_models[i] not in selected_models:
                    selected_models.append(auto_models[i])
    
    # Select embedding models
    if embed_models:
        print()
        if prompt_yes_no("Add an embedding model for code indexing?", default=False):
            print_subheader("Embedding Models")
            choices = [(m.name, f"{m.description} (~{m.ram_gb}GB) - {m.docker_name}", False) for m in embed_models]
            indices = prompt_multi_choice("Select embedding model:", choices, min_selections=1)
            for i in indices:
                if embed_models[i] not in selected_models:
                    selected_models.append(embed_models[i])
    
    return selected_models


def get_models_for_tier(tier: HardwareTier) -> List[ModelInfo]:
    """Get models available for a specific hardware tier."""
    return [m for m in MODEL_CATALOG if tier in m.tiers]


def is_restricted_model(model: ModelInfo) -> bool:
    """Check if a model is from restricted countries (China, Russia) due to political conflicts."""
    restricted_keywords = [
        "qwen",  # Chinese (Alibaba)
        "deepseek",  # Chinese
        "baai",  # Chinese (Beijing Academy of Artificial Intelligence)
        "bge-",  # Chinese (BAAI models)
    ]
    model_lower = model.name.lower() + " " + model.docker_name.lower()
    return any(keyword in model_lower for keyword in restricted_keywords)


def is_docker_hub_unavailable(model: ModelInfo) -> bool:
    """Check if a model is not available in Docker Hub's ai/ namespace.
    These models would fail with 401 Unauthorized when trying to pull.
    Only models confirmed to exist in Docker Hub's ai/ namespace are included."""
    # Models that don't exist in Docker Hub's ai/ namespace (verified)
    # These models are not available and will fail with 401 Unauthorized
    unavailable_models = [
        "starcoder2",  # Not in ai/ namespace (401 error confirmed)
        "codestral",  # Not in ai/ namespace
        "codegemma",  # Not in ai/ namespace (only in other namespaces)
        "codellama",  # Not in ai/ namespace
        # Note: nomic-embed-text exists as ai/nomic-embed-text-v1.5, but our format is different
        # Keeping it filtered since the exact name doesn't match
    ]
    
    # Convert model name to what it would be in Docker Hub format
    if model.docker_name.startswith("ai.docker.com/"):
        remaining = model.docker_name[len("ai.docker.com/"):]
        parts = remaining.split("/")
        if len(parts) > 1:
            model_part = parts[1]
        else:
            model_part = parts[0]
        if ":" in model_part:
            model_part = model_part.split(":")[0]
    else:
        # Already in Docker Hub format or other format
        if model.docker_name.startswith("ai/"):
            model_part = model.docker_name[3:]
            if ":" in model_part:
                model_part = model_part.split(":")[0]
        else:
            return False
    
    model_lower = model_part.lower()
    return any(unavailable in model_lower for unavailable in unavailable_models)


def verify_model_available(model: ModelInfo, hardware: HardwareInfo) -> bool:
    """
    Verify that a model actually exists and can be pulled from Docker Model Runner.
    
    According to Docker Model Runner docs (https://docs.docker.com/ai/model-runner/):
    - Models are pulled from Docker Hub and stored locally
    - The API exposes OpenAI-compatible endpoints
    - Models can be checked via the API or docker search
    
    This function checks:
    1. Docker Model Runner API (if available) - most accurate
    2. Known working models with size variants
    3. Docker Hub search as fallback
    """
    # Convert model name to Docker Hub format for checking
    model_name_to_check = model.docker_name
    
    if model.docker_name.startswith("ai.docker.com/"):
        # Convert to Docker Hub format
        remaining = model.docker_name[len("ai.docker.com/"):]
        parts = remaining.split("/")
        if len(parts) > 1:
            model_part = parts[1]
        else:
            model_part = parts[0]
        
        # Remove tag (everything after :)
        if ":" in model_part:
            model_part = model_part.split(":")[0]
        
        # Convert to Docker Hub format: ai/modelname
        model_name_to_check = f"ai/{model_part}"
    
    model_lower = model_name_to_check.lower()
    base_name = model_name_to_check.split(":")[0] if ":" in model_name_to_check else model_name_to_check
    
    # First, try to use cached API models list (fetched during DMR check)
    # According to docs: https://docs.docker.com/ai/model-runner/api-reference/
    if hasattr(hardware, 'available_api_models') and hardware.available_api_models:
        for api_model_id in hardware.available_api_models:
            api_model_lower = api_model_id.lower()
            # Check if our model matches (with or without tag)
            if base_name.lower() in api_model_lower or api_model_lower in base_name.lower():
                return True
    
    # If no cached list, try to query the API directly
    if hardware.docker_model_runner_available and hardware.dmr_api_endpoint:
        try:
            import urllib.request
            import json
            import urllib.error
            
            # Try to get available models from the API
            api_url = f"{hardware.dmr_api_endpoint}/models"
            req = urllib.request.Request(api_url, method="GET")
            req.add_header("Content-Type", "application/json")
            
            with urllib.request.urlopen(req, timeout=5) as response:
                if response.status == 200:
                    data = json.loads(response.read().decode('utf-8'))
                    # Check if model is in the API response
                    if "data" in data:
                        for api_model in data["data"]:
                            model_id = api_model.get("id", "").lower()
                            # Check if our model matches (with or without tag)
                            if base_name.lower() in model_id or model_id in base_name.lower():
                                return True
        except (urllib.error.URLError, urllib.error.HTTPError, OSError, json.JSONDecodeError):
            # API not available or error, fall through to other checks
            pass
    
    # Known working models in Docker Model Runner (from official docs and testing)
    # Format: (base_name, available_size_variants)
    # Based on: https://docs.docker.com/ai/model-runner/
    known_working_models = {
        "ai/llama3.2": ["3b"],  # Only 3B variant exists in Docker Model Runner, not 8B
        "ai/llama3.3": ["70b"],  # Only 70B variant exists
        "ai/llama3.1": ["70b"],  # Only 70B variant exists
        "ai/nomic-embed-text-v1.5": [None],  # No size variant
        "ai/qwen2.5-coder": ["7b"],  # Only 7B variant exists
        "ai/phi4": ["14b"],  # Only 14B variant exists
    }
    
    # Check if base model is known
    for known_base, available_sizes in known_working_models.items():
        if base_name.lower() == known_base.lower():
            # Check size variant if specified
            if None in available_sizes:
                # No size variant needed
                return True
            
            # Check if requested size matches available sizes
            requested_size = None
            if "8b" in model_lower or ":8b" in model_lower or "-8b" in model_lower:
                requested_size = "8b"
            elif "3b" in model_lower or ":3b" in model_lower or "-3b" in model_lower:
                requested_size = "3b"
            elif "7b" in model_lower or ":7b" in model_lower or "-7b" in model_lower:
                requested_size = "7b"
            elif "14b" in model_lower or ":14b" in model_lower or "-14b" in model_lower:
                requested_size = "14b"
            elif "70b" in model_lower or ":70b" in model_lower or "-70b" in model_lower:
                requested_size = "70b"
            
            if requested_size:
                # Check if requested size is available
                size_list = [s.lower() if s else None for s in available_sizes]
                return requested_size in size_list
            else:
                # No specific size requested, check if any variant exists
                return len(available_sizes) > 0
    
    # For unknown models, try to search Docker Hub
    # This is slower but more accurate for models not in our known list
    try:
        search_name = base_name.replace("ai/", "")
        code, stdout, _ = run_command(["docker", "search", base_name, "--limit", "10"], timeout=15)
        if code == 0:
            lines = stdout.strip().split("\n")
            for line in lines[1:]:  # Skip header
                if line.strip():
                    parts = line.split()
                    if parts and base_name.lower() in parts[0].lower():
                        # Found in search - model exists in Docker Hub
                        # Note: We can't verify size variants via search, so return True
                        # The actual pull will fail if the size variant doesn't exist
                        return True
    except Exception:
        pass
    
    # Model not found in API, known list, or search
    return False


def get_curated_top_models(tier: HardwareTier, limit: int = 10, hardware: Optional[HardwareInfo] = None) -> List[ModelInfo]:
    """Get curated top models for a hardware tier, prioritizing quality and variety.
    Excludes models from restricted countries (China, Russia) due to political conflicts.
    Only includes models that are verified to exist in Docker Model Runner.
    If not enough models for the tier, includes models from higher tiers to reach the limit."""
    # Start with models for this tier
    tier_models = get_models_for_tier(tier)
    
    # Filter out restricted models (Chinese/Russian) and models not available in Docker Hub
    tier_models = [m for m in tier_models if not is_restricted_model(m) and not is_docker_hub_unavailable(m)]
    
    # Verify models actually exist in Docker Model Runner (if hardware info provided)
    if hardware and hardware.docker_model_runner_available:
        print_info("Verifying model availability in Docker Model Runner...")
        verified_models = []
        for model in tier_models:
            if verify_model_available(model, hardware):
                verified_models.append(model)
            else:
                print_warning(f"Skipping {model.name} - not available in Docker Model Runner")
        tier_models = verified_models
        if tier_models:
            print_success(f"Found {len(tier_models)} verified models for your tier")
    
    # If we don't have enough models, include models from all tiers (filtered)
    if len(tier_models) < limit:
        all_models = [m for m in MODEL_CATALOG if not is_restricted_model(m) and not is_docker_hub_unavailable(m)]
        # Prioritize tier-compatible models, then add others
        available = tier_models.copy()
        seen_names = {m.docker_name for m in available}
        
        # Add models from other tiers that aren't already included
        for m in all_models:
            if m.docker_name not in seen_names and len(available) < limit:
                available.append(m)
                seen_names.add(m.docker_name)
    else:
        available = tier_models
    
    if not available:
        return []
    
    # Prioritize models by:
    # 1. Tier-compatible models first
    # 2. Chat/Edit models (sorted by quality/RAM descending)
    # 3. Coding-specific models (coder, code-focused)
    # 4. Autocomplete models (for speed)
    # 5. Embedding models
    
    curated = []
    seen_names = set()
    
    # Separate tier-compatible from others
    tier_compatible = [m for m in available if tier in m.tiers]
    other_models = [m for m in available if tier not in m.tiers]
    
    # 1. Top chat/edit models from tier-compatible (best quality first)
    chat_models = [m for m in tier_compatible if ("chat" in m.roles or "edit" in m.roles) and "embed" not in m.roles]
    chat_models.sort(key=lambda m: m.ram_gb, reverse=True)
    for m in chat_models[:6]:
        if m.docker_name not in seen_names:
            curated.append(m)
            seen_names.add(m.docker_name)
    
    # 2. Coding-specific models from tier-compatible
    coder_models = [m for m in tier_compatible if ("coder" in m.name.lower() or "code" in m.name.lower()) and m.docker_name not in seen_names]
    coder_models.sort(key=lambda m: m.ram_gb, reverse=True)
    for m in coder_models:
        if len(curated) < limit:
            curated.append(m)
            seen_names.add(m.docker_name)
    
    # 3. Fast autocomplete models from tier-compatible
    auto_models = [m for m in tier_compatible if "autocomplete" in m.roles and m.docker_name not in seen_names]
    auto_models.sort(key=lambda m: m.ram_gb)  # Smallest first
    for m in auto_models[:3]:
        if len(curated) < limit:
            curated.append(m)
            seen_names.add(m.docker_name)
    
    # 4. Embedding models from tier-compatible
    embed_models = [m for m in tier_compatible if "embed" in m.roles and m.docker_name not in seen_names]
    for m in embed_models[:2]:
        if len(curated) < limit:
            curated.append(m)
            seen_names.add(m.docker_name)
    
    # 5. Fill remaining slots with other tier-compatible models
    remaining_tier = [m for m in tier_compatible if m.docker_name not in seen_names]
    remaining_tier.sort(key=lambda m: m.ram_gb, reverse=True)
    for m in remaining_tier:
        if len(curated) >= limit:
            break
        curated.append(m)
        seen_names.add(m.docker_name)
    
    # 6. If still not enough, add models from other tiers (prioritize smaller ones)
    if len(curated) < limit:
        other_chat = [m for m in other_models if ("chat" in m.roles or "edit" in m.roles) and "embed" not in m.roles and m.docker_name not in seen_names]
        other_chat.sort(key=lambda m: m.ram_gb)  # Smaller first (more likely to work)
        for m in other_chat:
            if len(curated) >= limit:
                break
            curated.append(m)
            seen_names.add(m.docker_name)
    
    # 7. Fill any remaining slots
    remaining_all = [m for m in other_models if m.docker_name not in seen_names]
    remaining_all.sort(key=lambda m: m.ram_gb)  # Smaller first
    for m in remaining_all:
        if len(curated) >= limit:
            break
        curated.append(m)
        seen_names.add(m.docker_name)
    
    return curated[:limit]


def get_recommended_models(tier: HardwareTier, hardware: Optional[HardwareInfo] = None) -> Dict[str, ModelInfo]:
    """Get recommended models for each role based on tier and chip capabilities.
    Excludes models from restricted countries (China, Russia) due to political conflicts.
    Only includes models verified to exist in Docker Model Runner.
    Enhanced to consider chip performance for better recommendations."""
    recommendations: Dict[str, ModelInfo] = {}
    
    available = get_models_for_tier(tier)
    
    # Filter out restricted models (Chinese/Russian) and models not available in Docker Hub
    available = [m for m in available if not is_restricted_model(m) and not is_docker_hub_unavailable(m)]
    
    # Verify models actually exist in Docker Model Runner (if hardware info provided)
    if hardware and hardware.docker_model_runner_available:
        verified_available = []
        for model in available:
            if verify_model_available(model, hardware):
                verified_available.append(model)
        available = verified_available
    
    # Determine if this is a high-end chip that can handle larger models
    is_high_end_chip = False
    if hardware and hardware.has_apple_silicon and hardware.apple_chip_model:
        high_end_patterns = ["M3 Pro", "M3 Max", "M3 Ultra", "M4 Pro", "M4 Max", "M4 Ultra"]
        is_high_end_chip = any(pattern in hardware.apple_chip_model for pattern in high_end_patterns)
    
    # Chat/Edit model (primary) - prioritize best quality models
    chat_models = [m for m in available if "chat" in m.roles or "edit" in m.roles]
    if chat_models:
        # For high-end chips, prefer larger models even if at tier boundary
        # Sort by RAM (descending) to get best quality within tier
        chat_models.sort(key=lambda m: m.ram_gb, reverse=True)
        
        # For Tier A with high-end chips and 40GB+ RAM, prefer larger models
        if tier == HardwareTier.A and is_high_end_chip and hardware and hardware.ram_gb >= 40:
            # Prefer models that are close to Tier S quality
            # Look for models that are 20GB+ (like devstral:27b, codestral:22b)
            large_models = [m for m in chat_models if m.ram_gb >= 20]
            if large_models:
                recommendations["chat"] = large_models[0]
            else:
                recommendations["chat"] = chat_models[0]
        else:
            recommendations["chat"] = chat_models[0]
    
    # Autocomplete model (fast) - balance speed and quality
    auto_models = [m for m in available if "autocomplete" in m.roles]
    if auto_models:
        # For high-end chips, we can use slightly larger autocomplete models for better quality
        if is_high_end_chip and tier in (HardwareTier.S, HardwareTier.A):
            # Prefer medium-sized autocomplete models (5-15GB) for better quality
            medium_auto = [m for m in auto_models if 5 <= m.ram_gb <= 15]
            if medium_auto:
                medium_auto.sort(key=lambda m: m.ram_gb, reverse=True)  # Best quality first
                recommendations["autocomplete"] = medium_auto[0]
            else:
                # Fallback to smallest for speed
                auto_models.sort(key=lambda m: m.ram_gb)
                recommendations["autocomplete"] = auto_models[0]
        else:
            # For other systems, prioritize speed (smallest)
            auto_models.sort(key=lambda m: m.ram_gb)
            recommendations["autocomplete"] = auto_models[0]
    
    # Embedding model (excluding restricted ones)
    embed_models = [m for m in available if "embed" in m.roles]
    if embed_models:
        recommendations["embed"] = embed_models[0]
    
    return recommendations


def select_models(hardware: HardwareInfo) -> List[ModelInfo]:
    """Interactive model selection from curated top models based on hardware tier."""
    print_header("🤖 Model Selection")
    
    print_info(f"Hardware Tier: {colorize(hardware.tier.value, Colors.GREEN + Colors.BOLD)}")
    print_info(f"Available RAM: ~{hardware.ram_gb:.1f}GB")
    print()
    
    # Get curated top 10 models for this tier (with verification)
    curated_models = get_curated_top_models(hardware.tier, limit=10, hardware=hardware)
    
    if not curated_models:
        print_error("No verified models available for your hardware tier.")
        print_info("This may mean Docker Model Runner doesn't have models compatible with your tier.")
        print_info("You can try the model discovery feature to search for available models.")
        if prompt_yes_no("Would you like to search for available models?", default=False):
            return discover_and_select_models(hardware)
        return []
    
    # Show recommended configuration first (with verification)
    recommendations = get_recommended_models(hardware.tier, hardware=hardware)
    if recommendations:
        print(colorize("  Recommended Configuration:", Colors.GREEN + Colors.BOLD))
        total_ram = 0.0
        for role, model in recommendations.items():
            print(f"    • {role.capitalize()}: {model.name} (~{model.ram_gb}GB)")
            total_ram += model.ram_gb
        print(f"    Total RAM: ~{total_ram:.1f}GB")
        print()
        
        # Quick option to use recommended
        if prompt_yes_no("Use recommended configuration?", default=True):
            selected = list(recommendations.values())
            # Remove duplicates
            unique = []
            seen_names = set()
            for m in selected:
                if m.docker_name not in seen_names:
                    unique.append(m)
                    seen_names.add(m.docker_name)
            return unique
    
    # Show curated top models
    print_subheader("Top 10 Models for Your Hardware")
    print_info("Select from the best models optimized for your system:")
    if len(curated_models) < 10:
        print_info(f"(Showing {len(curated_models)} available models for your tier)")
    print()
    
    # Prepare choices with role indicators
    choices = []
    for m in curated_models:
        # Build description with role info
        roles_str = ", ".join(m.roles)
        
        # Indicate if model is compatible with current tier
        tier_indicator = ""
        if hardware.tier in m.tiers:
            tier_indicator = "✓ Tier compatible"
        else:
            tier_indicator = "⚠ Higher tier (may be slow)"
        
        desc = f"{m.description} | {roles_str} | ~{m.ram_gb}GB RAM | {tier_indicator}"
        
        # Mark recommended models
        is_recommended = any(m.docker_name == rec.docker_name for rec in recommendations.values())
        choices.append((m.name, desc, is_recommended))
    
    # Let user select
    indices = prompt_multi_choice(
        "Select models to install (comma-separated numbers, or 'a' for all):",
        choices,
        min_selections=1
    )
    
    selected_models = [curated_models[i] for i in indices]
    
    # Show summary
    if selected_models:
        print()
        print_success(f"Selected {len(selected_models)} model(s):")
        total_ram = 0.0
        for m in selected_models:
            print(f"  • {m.name} (~{m.ram_gb}GB)")
            total_ram += m.ram_gb
        print(f"  Total RAM required: ~{total_ram:.1f}GB")
    
    return selected_models


def pull_models_docker(models: List[ModelInfo], hardware: HardwareInfo) -> List[ModelInfo]:
    """Pull selected models using Docker Model Runner."""
    print_header("📥 Downloading Models via Docker Model Runner")
    
    if not hardware.docker_model_runner_available:
        print_warning("Docker Model Runner not available. Skipping model download.")
        print_info("Models will be downloaded when you first use them in Continue.dev.")
        print()
        print_info("To manually pull models later, run:")
        for model in models:
            print(colorize(f"    docker model pull {model.docker_name}", Colors.CYAN))
        return models
    
    successfully_pulled: List[ModelInfo] = []
    
    # Estimate total download size
    total_download_gb = sum(m.ram_gb * 0.5 for m in models)  # Rough estimate: model size is ~50% of RAM needed
    print_info(f"Estimated total download: ~{total_download_gb:.1f}GB")
    print_info(f"Models will use Metal GPU acceleration on Apple Silicon")
    print()
    
    for i, model in enumerate(models, 1):
        print_step(i, len(models), f"Pulling {model.name}...")
        print_info(f"Model: {model.docker_name}")
        print_info(f"Estimated download: ~{model.ram_gb * 0.5:.1f}GB")
        print_info(f"Memory required: ~{model.ram_gb:.1f}GB")
        print()
        
        # Determine model name format and handle legacy ai.docker.com format
        # Docker Model Runner supports:
        # - Docker Hub: ai/model-name (e.g., ai/llama3.2)
        # - Hugging Face: hf.co/username/model-name
        # Legacy format: ai.docker.com/org/model:tag (convert directly to ai/model-name)
        model_name_to_pull = model.docker_name
        
        # Convert legacy ai.docker.com format directly to Docker Hub format
        # No DNS check needed - ai.docker.com doesn't exist, always convert
        if model.docker_name.startswith("ai.docker.com/"):
            # Convert to Docker Hub format
            # ai.docker.com/org/model:tag -> ai/model-name
            # Remove ai.docker.com/ prefix
            remaining = model.docker_name[len("ai.docker.com/"):]
            
            # Remove organization prefix (meta/, mistral/, microsoft/, etc.)
            parts = remaining.split("/")
            if len(parts) > 1:
                # Has org prefix, remove it
                model_part = parts[1]
            else:
                model_part = parts[0]
            
            # Special handling for nomic-embed-text: version is part of model name, not a tag
            # ai.docker.com/nomic/nomic-embed-text:v1.5 -> ai/nomic-embed-text-v1.5
            if "nomic-embed-text" in model_part.lower():
                # Extract version from tag and append to model name
                if ":" in model_part:
                    model_base, version = model_part.split(":", 1)
                    # Convert v1.5 -> v1.5, or just use as-is
                    model_part = f"{model_base}-{version}"
                model_name_to_pull = f"ai/{model_part}"
            else:
                # For other models, remove tag (everything after :)
                if ":" in model_part:
                    model_part = model_part.split(":")[0]
                
                # Convert to Docker Hub format: ai/modelname
                model_name_to_pull = f"ai/{model_part}"
        
        # Run docker model pull
        # We don't capture output so user can see download progress
        
        # Initialize full_output for error handling
        full_output = []
        code = -1
        
        try:
            process = subprocess.Popen(
                ["docker", "model", "pull", model_name_to_pull],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )
            
            # Stream output in real-time and capture for analysis
            if process.stdout:
                for line in process.stdout:
                    line = line.strip()
                    if line:
                        full_output.append(line)
                        # Show progress lines
                        if "pulling" in line.lower() or "download" in line.lower() or "%" in line:
                            print(f"    {line}")
                        elif "complete" in line.lower() or "done" in line.lower():
                            print(colorize(f"    {line}", Colors.GREEN))
            
            process.wait(timeout=3600)  # 1 hour timeout
            code = process.returncode
            
        except subprocess.TimeoutExpired:
            process.kill()
            print_error("Download timed out after 1 hour")
            code = -1
        except Exception as e:
            print_error(f"Error: {e}")
            code = -1
        
        if code == 0:
            # Verify the model was actually downloaded and check its parameters
            verify_code, verify_out, _ = run_command(["docker", "model", "list"])
            model_found = False
            actual_params = None
            
            if verify_code == 0:
                # Check if the model appears in the list (by name or converted name)
                model_name_simple = model_name_to_pull.split("/")[-1].split(":")[0]
                for line in verify_out.split("\n"):
                    if model_name_simple in line.lower() or "llama3.2" in line.lower():
                        model_found = True
                        # Extract parameters from the line
                        import re
                        param_match = re.search(r'(\d+\.?\d*)\s*B', line)
                        if param_match:
                            actual_params = float(param_match.group(1))
                        break
                
                # Also try to inspect the model to get exact parameters
                if model_found:
                    inspect_code, inspect_out, _ = run_command(["docker", "model", "inspect", model_name_simple], timeout=10)
                    if inspect_code == 0:
                        try:
                            import json
                            inspect_data = json.loads(inspect_out)
                            actual_params_str = inspect_data.get("config", {}).get("parameters", "")
                            if actual_params_str:
                                param_match = re.search(r'(\d+\.?\d*)', actual_params_str)
                                if param_match:
                                    actual_params = float(param_match.group(1))
                        except:
                            pass
            
            if model_found:
                # Check if parameters match expected (allow some tolerance)
                expected_params = model.ram_gb  # Rough estimate: 8B model ~5GB, 3B model ~2GB
                if actual_params:
                    if abs(actual_params - expected_params) > 2.0:  # More than 2GB difference
                        print_warning(f"{model.name} downloaded, but got {actual_params}B model instead of expected ~{expected_params}GB model")
                        print_info(f"Actual model: {actual_params}B parameters")
                    else:
                        print_success(f"{model.name} downloaded successfully ({actual_params}B parameters)")
                else:
                    print_success(f"{model.name} downloaded successfully")
                successfully_pulled.append(model)
                print_info("Model verified in Docker Model Runner")
            else:
                print_warning(f"Download completed but model '{model.name}' not found in Docker Model Runner list")
                print_info("The model may have been downloaded with a different name")
        else:
            print_error(f"Failed to pull {model.name}")
            
            # Check if it was a 401 Unauthorized error
            is_unauthorized = False
            if 'full_output' in locals() and isinstance(full_output, list):
                is_unauthorized = any("401" in line or "unauthorized" in line.lower() for line in full_output)
            
            if is_unauthorized:
                print_warning("Model not found in Docker Hub (401 Unauthorized)")
                print_info("This model may not be available in the 'ai/' namespace.")
                print_info("You can try:")
                print_info("  1. Check if the model exists: docker search ai/<model-name>")
                print_info("  2. Search for alternatives: docker search <model-name>")
            else:
                print_info("You can try pulling manually later with:")
                if model_name_to_pull != model.docker_name:
                    print(colorize(f"    docker model pull {model_name_to_pull}", Colors.CYAN))
                    print_info(f"    (Original format: {model.docker_name})")
                else:
                    print(colorize(f"    docker model pull {model.docker_name}", Colors.CYAN))
            
            if len(models) > i and prompt_yes_no("Continue with remaining models?", default=True):
                continue
            elif len(models) > i:
                break
        
        print()
    
    # Summary
    if successfully_pulled:
        print_success(f"Successfully downloaded {len(successfully_pulled)}/{len(models)} models")
    
    return successfully_pulled if successfully_pulled else models


def get_model_id_for_continue(docker_name: str, hardware: Optional[HardwareInfo] = None) -> str:
    """
    Convert Docker Model Runner model name to Continue.dev compatible format.
    
    Docker Model Runner API returns models as: ai/llama3.2:latest
    The model catalog uses: ai.docker.com/meta/llama3.2:3b-instruct-q4_K_M
    
    This function converts to the actual API model ID format.
    """
    # First, check if we can get the actual model ID from the API
    if hardware and hasattr(hardware, 'available_api_models') and hardware.available_api_models:
        # Try to match the model name to an API model ID
        model_lower = docker_name.lower()
        
        # Check for llama3.2 variants
        if "llama3.2" in model_lower or "llama3.2" in docker_name.lower():
            for api_model_id in hardware.available_api_models:
                if "llama3.2" in api_model_id.lower():
                    return api_model_id  # Return the actual API model ID
        
        # Check for nomic-embed variants
        if "nomic" in model_lower or "embed" in model_lower:
            for api_model_id in hardware.available_api_models:
                if "nomic" in api_model_id.lower() or "embed" in api_model_id.lower():
                    return api_model_id
    
    # Fallback: Convert from catalog format to Docker Hub format
    model_id = docker_name
    
    # Remove the ai.docker.com/ prefix if present
    if model_id.startswith("ai.docker.com/"):
        remaining = model_id[len("ai.docker.com/"):]
        parts = remaining.split("/")
        if len(parts) > 1:
            # Has org prefix (meta/, qwen/, etc.), remove it
            model_part = parts[1]
        else:
            model_part = parts[0]
        
        # Remove size/tag variants and convert to base model name
        # ai.docker.com/meta/llama3.2:3b-instruct-q4_K_M -> ai/llama3.2
        if ":" in model_part:
            model_part = model_part.split(":")[0]
        
        # Remove size indicators (3b, 8b, etc.) from model name
        import re
        model_part = re.sub(r'[-_]?[0-9]+b', '', model_part, flags=re.IGNORECASE)
        model_part = re.sub(r'[-_]?instruct[-_]?q[0-9]_[KM]', '', model_part, flags=re.IGNORECASE)
        
        # Convert to Docker Hub format: ai/modelname
        model_id = f"ai/{model_part}"
        
        # Add :latest tag (Docker Model Runner uses this)
        if ":" not in model_id:
            model_id = f"{model_id}:latest"
    
    # If it already starts with ai/, ensure it has :latest tag
    elif model_id.startswith("ai/"):
        if ":" not in model_id:
            model_id = f"{model_id}:latest"
    
    return model_id


def generate_continue_config(
    models: List[ModelInfo],
    hardware: HardwareInfo,
    output_path: Optional[Path] = None
) -> Path:
    """Generate continue.dev config.yaml file."""
    print_header("📝 Generating Continue.dev Configuration")
    
    if output_path is None:
        output_path = Path.home() / ".continue" / "config.yaml"
    
    # Create directory if needed
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Backup existing config if present
    if output_path.exists():
        backup_path = output_path.with_suffix(".yaml.backup")
        shutil.copy(output_path, backup_path)
        print_info(f"Backed up existing config to {backup_path}")
    
    # Use the detected API endpoint from hardware info
    api_base = hardware.dmr_api_endpoint
    print_info(f"Using API endpoint: {api_base}")
    
    # Ensure apiBase doesn't have trailing slash and includes /v1 for OpenAI-compatible API
    # Continue.dev expects the full base URL including /v1 for OpenAI-compatible APIs
    api_base_clean = api_base.rstrip('/')
    # Ensure it includes /v1 if not already present
    if '/v1' not in api_base_clean:
        # If the endpoint doesn't have /v1, we need to determine the correct base
        # For Docker Model Runner, the API is typically at /v1
        if api_base_clean.endswith(':12434') or api_base_clean.endswith(':8080'):
            api_base_clean = f"{api_base_clean}/v1"
        elif 'model-runner.docker.internal' in api_base_clean:
            api_base_clean = f"{api_base_clean}/v1" if not api_base_clean.endswith('/v1') else api_base_clean
    
    # Build config with comments and required fields
    yaml_lines = [
        "# Continue.dev Configuration for Docker Model Runner",
        "# Generated by docker-llm-setup.py",
        f"# Hardware: {hardware.apple_chip_model or hardware.cpu_brand}",
        f"# RAM: {hardware.ram_gb:.0f}GB | Tier: {hardware.tier.value}",
        "#",
        "# Documentation: https://docs.continue.dev/yaml-reference",
        "",
        "# Required fields",
        "name: Docker Model Runner Local LLM",
        "version: 1.0.0",
        "schema: v1",
        "",
    ]
    
    # Find models by role
    chat_models = [m for m in models if "chat" in m.roles or "edit" in m.roles]
    autocomplete_models = [m for m in models if "autocomplete" in m.roles]
    embed_models = [m for m in models if "embed" in m.roles]
    
    # Sort chat models by RAM (largest first = highest quality)
    chat_models.sort(key=lambda m: m.ram_gb, reverse=True)
    
    # Sort autocomplete models by RAM (smallest first = fastest)
    autocomplete_models.sort(key=lambda m: m.ram_gb)
    
    # Build models section
    yaml_lines.append("models:")
    
    for i, model in enumerate(chat_models):
        model_id = get_model_id_for_continue(model.docker_name, hardware)
        yaml_lines.extend([
            f"  - name: {model.name}",
            f"    provider: openai",
            f"    model: {model_id}",
            f"    apiBase: {api_base_clean}",
            f"    contextLength: {model.context_length}",
        ])
        
        # Add roles
        roles = ["chat", "edit", "apply"]
        if "agent" in model.roles:
            roles.append("agent")
        yaml_lines.append("    roles:")
        for role in roles:
            yaml_lines.append(f"      - {role}")
        
        # Add system message for primary model
        if i == 0:
            yaml_lines.extend([
                "    systemMessage: |",
                "      You are an expert coding assistant. You help with:",
                "      - Writing clean, efficient code",
                "      - Debugging and fixing issues", 
                "      - Explaining code and concepts",
                "      - Refactoring and optimization",
                "      Be concise, accurate, and provide working code examples.",
            ])
        yaml_lines.append("")
    
    # Add autocomplete model (if different from chat models)
    autocomplete_only = [m for m in autocomplete_models if m not in chat_models]
    for model in autocomplete_only:
        model_id = get_model_id_for_continue(model.docker_name, hardware)
        yaml_lines.extend([
            f"  - name: {model.name} (Autocomplete)",
            f"    provider: openai",
            f"    model: {model_id}",
            f"    apiBase: {api_base_clean}",
            "    roles:",
            "      - autocomplete",
            "",
        ])
    
    # Tab autocomplete configuration
    if autocomplete_models:
        auto_model = autocomplete_models[0]
        model_id = get_model_id_for_continue(auto_model.docker_name, hardware)
        yaml_lines.extend([
            "# Tab autocomplete settings",
            "tabAutocompleteModel:",
            f"  provider: openai",
            f"  model: {model_id}",
            f"  apiBase: {api_base_clean}",
            "",
        ])
    
    # Embeddings configuration
    if embed_models:
        embed_model = embed_models[0]
        model_id = get_model_id_for_continue(embed_model.docker_name, hardware)
        yaml_lines.extend([
            "# Embeddings for semantic code search (@Codebase)",
            "embeddingsProvider:",
            f"  provider: openai",
            f"  model: {model_id}",
            f"  apiBase: {api_base_clean}",
            "",
        ])
    
    # Context providers
    yaml_lines.extend([
        "# Context providers for code understanding",
        "contextProviders:",
        "  - name: codebase",
        "    params: {}",
        "  - name: folder",
        "  - name: file",
        "  - name: code",
        "  - name: terminal",
        "  - name: diff",
        "  - name: problems",
        "  - name: open",
        "",
        "# Slash commands",
        "slashCommands:",
        "  - name: edit",
        "    description: Edit selected code",
        "  - name: comment",
        "    description: Add comments to code",
        "  - name: share",
        "    description: Share conversation",
        "",
        "# Privacy settings",
        "allowAnonymousTelemetry: false",
        "",
    ])
    
    # Add Apple Silicon specific notes
    if hardware.has_apple_silicon:
        yaml_lines.extend([
            f"# Optimized for {hardware.apple_chip_model or 'Apple Silicon'}",
            f"# Available unified memory: ~{hardware.get_estimated_model_memory():.0f}GB",
            "# Metal GPU acceleration is enabled automatically",
        ])
    
    # Write YAML config
    yaml_content = "\n".join(yaml_lines)
    
    with open(output_path, "w") as f:
        f.write(yaml_content)
    
    print_success(f"Configuration saved to {output_path}")
    
    # Also create a JSON version for compatibility
    json_path = output_path.parent / "config.json"
    
    # Build JSON config
    json_config: Dict[str, Any] = {"models": []}
    
    for model in chat_models:
        model_id = get_model_id_for_continue(model.docker_name, hardware)
        json_config["models"].append({
            "name": model.name,
            "provider": "openai",
            "model": model_id,
            "apiBase": api_base_clean,
            "contextLength": model.context_length,
            "roles": ["chat", "edit", "apply"] + (["agent"] if "agent" in model.roles else []),
        })
    
    for model in autocomplete_only:
        model_id = get_model_id_for_continue(model.docker_name, hardware)
        json_config["models"].append({
            "name": f"{model.name} (Autocomplete)",
            "provider": "openai", 
            "model": model_id,
            "apiBase": api_base_clean,
            "roles": ["autocomplete"],
        })
    
    if autocomplete_models:
        auto_model = autocomplete_models[0]
        model_id = get_model_id_for_continue(auto_model.docker_name, hardware)
        json_config["tabAutocompleteModel"] = {
            "provider": "openai",
            "model": model_id,
            "apiBase": api_base_clean,
        }
    
    if embed_models:
        embed_model = embed_models[0]
        model_id = get_model_id_for_continue(embed_model.docker_name, hardware)
        json_config["embeddingsProvider"] = {
            "provider": "openai",
            "model": model_id,
            "apiBase": api_base_clean,
        }
    
    json_config["contextProviders"] = [
        {"name": "codebase", "params": {}},
        {"name": "folder"},
        {"name": "file"},
        {"name": "code"},
        {"name": "terminal"},
        {"name": "diff"},
        {"name": "problems"},
    ]
    
    json_config["allowAnonymousTelemetry"] = False
    
    with open(json_path, "w") as f:
        json.dump(json_config, f, indent=2)
    
    print_info(f"JSON config also saved to {json_path}")
    
    return output_path


def generate_yaml(config: Dict[str, Any], indent: int = 0) -> str:
    """Generate YAML string from config dict."""
    lines = []
    prefix = "  " * indent
    
    for key, value in config.items():
        if key.startswith("#"):
            lines.append(f"{prefix}{key}")
            continue
        
        if value is None:
            continue
        
        if isinstance(value, dict):
            lines.append(f"{prefix}{key}:")
            lines.append(generate_yaml(value, indent + 1))
        elif isinstance(value, list):
            lines.append(f"{prefix}{key}:")
            for item in value:
                if isinstance(item, dict):
                    # First item on same line with dash
                    first = True
                    for k, v in item.items():
                        if first:
                            if isinstance(v, list):
                                lines.append(f"{prefix}  - {k}:")
                                for vi in v:
                                    lines.append(f"{prefix}      - {vi}")
                            else:
                                lines.append(f"{prefix}  - {k}: {format_yaml_value(v)}")
                            first = False
                        else:
                            if isinstance(v, list):
                                lines.append(f"{prefix}    {k}:")
                                for vi in v:
                                    lines.append(f"{prefix}      - {vi}")
                            else:
                                lines.append(f"{prefix}    {k}: {format_yaml_value(v)}")
                else:
                    lines.append(f"{prefix}  - {format_yaml_value(item)}")
        else:
            lines.append(f"{prefix}{key}: {format_yaml_value(value)}")
    
    return "\n".join(lines)


def format_yaml_value(value: Any) -> str:
    """Format a value for YAML output."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        # Quote strings with special characters
        if any(c in value for c in ":#{}[]&*!|>'\"%@`"):
            return f'"{value}"'
        return value
    return str(value)


def install_vscode_extension(extension_id: str) -> bool:
    """Install a VS Code extension using the CLI."""
    # Check if VS Code CLI is available
    code_path = shutil.which("code")
    if not code_path:
        return False
    
    # Check if extension is already installed
    code, stdout, _ = run_command(["code", "--list-extensions"], timeout=10)
    if code == 0 and extension_id in stdout:
        return True  # Already installed
    
    # Install the extension
    code, stdout, stderr = run_command(["code", "--install-extension", extension_id], timeout=60)
    return code == 0


def start_model_server(model_name: str) -> Optional[subprocess.Popen]:
    """Start the Docker Model Runner API server in the background."""
    try:
        process = subprocess.Popen(
            ["docker", "model", "run", model_name],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        # Give it a moment to start
        time.sleep(2)
        # Check if it's still running (didn't immediately fail)
        if process.poll() is None:
            return process
        else:
            return None
    except Exception:
        return None


def restart_vscode() -> bool:
    """Restart VS Code (macOS only for now)."""
    if platform.system() != "Darwin":
        return False
    
    try:
        # Quit VS Code
        run_command(["killall", "Visual Studio Code"], timeout=5)
        time.sleep(1)
        # Reopen VS Code
        run_command(["open", "-a", "Visual Studio Code"], timeout=5)
        return True
    except Exception:
        return False


def show_next_steps(config_path: Path, models: List[ModelInfo], hardware: HardwareInfo) -> None:
    """Display next steps after setup."""
    print_header("✅ Setup Complete!")
    
    print(colorize("Installation Summary:", Colors.GREEN + Colors.BOLD))
    print()
    print(f"  Hardware: {hardware.apple_chip_model or hardware.cpu_brand}")
    print(f"  Tier: {hardware.get_tier_label()}")
    if hardware.has_apple_silicon:
        print(f"  GPU: Metal acceleration enabled ({hardware.ram_gb:.0f}GB unified memory)")
    print(f"  API Endpoint: {hardware.dmr_api_endpoint}")
    print()
    print(f"  Models Configured: {len(models)}")
    for model in models:
        roles_str = ", ".join(model.roles)
        print(f"    • {model.name} ({roles_str}) - ~{model.ram_gb}GB")
    print()
    print(f"  Config: {config_path}")
    print()
    
    print(colorize("━" * 60, Colors.DIM))
    print(colorize("Next Steps:", Colors.YELLOW + Colors.BOLD))
    print()
    
    step = 1
    
    # Step 1: Install Continue.dev (automated if possible)
    print(f"  {step}. Install Continue.dev extension in VS Code:")
    
    # Check if VS Code CLI is available
    vscode_available = shutil.which("code") is not None
    
    if vscode_available:
        # Check if already installed
        code, stdout, _ = run_command(["code", "--list-extensions"], timeout=10)
        already_installed = code == 0 and "Continue.continue" in stdout
        
        if already_installed:
            print_success("Continue.dev extension is already installed")
        else:
            if prompt_yes_no("    Install Continue.dev extension automatically?", default=True):
                print_info("    Installing Continue.dev extension...")
                if install_vscode_extension("Continue.continue"):
                    print_success("    Continue.dev extension installed successfully")
                else:
                    print_warning("    Failed to install automatically. Please install manually:")
                    if hardware.os_name == "Darwin":
                        print(colorize("       • Press Cmd+Shift+X → Search 'Continue' → Install", Colors.DIM))
                    else:
                        print(colorize("       • Press Ctrl+Shift+X → Search 'Continue' → Install", Colors.DIM))
            else:
                print_info("    Skipping automatic installation.")
                if hardware.os_name == "Darwin":
                    print(colorize("     • Press Cmd+Shift+X to open Extensions", Colors.DIM))
                    print(colorize("     • Search for 'Continue' and install", Colors.DIM))
                else:
                    print(colorize("     • Press Ctrl+Shift+X to open Extensions", Colors.DIM))
                    print(colorize("     • Search for 'Continue' and install", Colors.DIM))
    else:
        print_info("    VS Code CLI not found. Please install manually:")
        if hardware.os_name == "Darwin":
            print(colorize("     • Press Cmd+Shift+X to open Extensions", Colors.DIM))
            print(colorize("     • Search for 'Continue' and install", Colors.DIM))
        else:
            print(colorize("     • Press Ctrl+Shift+X to open Extensions", Colors.DIM))
            print(colorize("     • Search for 'Continue' and install", Colors.DIM))
    print()
    step += 1
    
    # Step 2: Docker Model Runner setup
    if hardware.docker_model_runner_available:
        print(f"  {step}. Verify Docker Model Runner is running:")
        print(colorize("     docker model list", Colors.CYAN))
        print()
        step += 1
        
        # Run a model if needed
        chat_models = [m for m in models if "chat" in m.roles]
        if chat_models:
            print(f"  {step}. Start the model server (if not already running):")
            
            # Convert model name for Docker Hub format
            model_to_run = chat_models[0].docker_name
            if model_to_run.startswith("ai.docker.com/"):
                remaining = model_to_run[len("ai.docker.com/"):]
                parts = remaining.split("/")
                if len(parts) > 1:
                    model_part = parts[1]
                else:
                    model_part = parts[0]
                if ":" in model_part:
                    model_part = model_part.split(":")[0]
                model_to_run = f"ai/{model_part}"
            
            # Check if API is already running
            import urllib.request
            api_running = False
            try:
                req = urllib.request.Request(f"{hardware.dmr_api_endpoint}/models", method="GET")
                with urllib.request.urlopen(req, timeout=2) as response:
                    if response.status == 200:
                        api_running = True
            except:
                pass
            
            if api_running:
                print_success("    Model server is already running")
            else:
                if prompt_yes_no("    Start the model server now?", default=True):
                    print_info("    Starting model server in background...")
                    process = start_model_server(model_to_run)
                    if process:
                        print_success("    Model server started")
                        print_info("    (Server is running in background)")
                    else:
                        print_warning("    Failed to start automatically. Start manually with:")
                        print(colorize(f"       docker model run {model_to_run}", Colors.CYAN))
                else:
                    print_info("    Start manually with:")
                    print(colorize(f"       docker model run {model_to_run}", Colors.CYAN))
            print()
            step += 1
    else:
        print(f"  {step}. Enable Docker Model Runner:")
        if hardware.os_name == "Darwin":
            print(colorize("     Option A - Via Docker Desktop:", Colors.DIM))
            print(colorize("       • Open Docker Desktop", Colors.DIM))
            print(colorize("       • Settings → Features in development", Colors.DIM))
            print(colorize("       • Enable 'Docker Model Runner' or 'Enable Docker AI'", Colors.DIM))
            print(colorize("       • Click 'Apply & restart'", Colors.DIM))
            print()
            print(colorize("     Option B - Via terminal:", Colors.DIM))
            print(colorize("       docker desktop enable model-runner --tcp 12434", Colors.CYAN))
        else:
            print(colorize("     • Open Docker Desktop → Settings", Colors.DIM))
            print(colorize("     • Features in development → Enable Docker Model Runner", Colors.DIM))
            print(colorize("     • Apply & restart", Colors.DIM))
        print()
        step += 1
        
        print(f"  {step}. Pull the models:")
        for model in models:
            print(colorize(f"     docker model pull {model.docker_name}", Colors.CYAN))
        print()
        step += 1
    
    # Step: Restart VS Code (automated if possible)
    print(f"  {step}. Restart VS Code:")
    
    # Check if VS Code is running
    vscode_running = False
    if hardware.os_name == "Darwin":
        code, _, _ = run_command(["pgrep", "-f", "Visual Studio Code"], timeout=5)
        vscode_running = code == 0
    else:
        code, _, _ = run_command(["pgrep", "-f", "code"], timeout=5)
        vscode_running = code == 0
    
    if vscode_running:
        if prompt_yes_no("    Restart VS Code automatically now?", default=False):
            print_warning("    This will close all VS Code windows. Make sure you've saved your work!")
            if prompt_yes_no("    Continue with restart?", default=False):
                if restart_vscode():
                    print_success("    VS Code restarted")
                else:
                    print_warning("    Failed to restart automatically. Please restart manually:")
                    if hardware.os_name == "Darwin":
                        print(colorize("       • Quit VS Code completely (Cmd+Q)", Colors.DIM))
                    else:
                        print(colorize("       • Close all VS Code windows", Colors.DIM))
                    print(colorize("       • Reopen VS Code", Colors.DIM))
            else:
                print_info("    Skipping automatic restart.")
                if hardware.os_name == "Darwin":
                    print(colorize("     • Quit VS Code completely (Cmd+Q)", Colors.DIM))
                else:
                    print(colorize("     • Close all VS Code windows", Colors.DIM))
                print(colorize("     • Reopen VS Code", Colors.DIM))
        else:
            print_info("    Please restart VS Code manually:")
            if hardware.os_name == "Darwin":
                print(colorize("     • Quit VS Code completely (Cmd+Q)", Colors.DIM))
            else:
                print(colorize("     • Close all VS Code windows", Colors.DIM))
            print(colorize("     • Reopen VS Code", Colors.DIM))
    else:
        print_info("    VS Code is not running. Open VS Code when ready.")
    print()
    step += 1
    
    # Step: Start using
    print(f"  {step}. Start coding with AI:")
    if hardware.os_name == "Darwin":
        print(colorize("     • Cmd+L - Open Continue.dev chat", Colors.DIM))
        print(colorize("     • Cmd+K - Inline code edits", Colors.DIM))
        print(colorize("     • Cmd+I - Quick actions", Colors.DIM))
    else:
        print(colorize("     • Ctrl+L - Open Continue.dev chat", Colors.DIM))
        print(colorize("     • Ctrl+K - Inline code edits", Colors.DIM))
        print(colorize("     • Ctrl+I - Quick actions", Colors.DIM))
    print(colorize("     • @Codebase - Semantic code search", Colors.DIM))
    print(colorize("     • @file - Reference specific files", Colors.DIM))
    print()
    
    print(colorize("━" * 60, Colors.DIM))
    print(colorize("Useful Commands:", Colors.BLUE + Colors.BOLD))
    print()
    print("  Check installed models:")
    print(colorize("     docker model list", Colors.CYAN))
    print()
    print("  Run a model interactively:")
    if models:
        print(colorize(f"     docker model run {models[0].docker_name}", Colors.CYAN))
    else:
        print(colorize("     docker model run <model-name>", Colors.CYAN))
    print()
    print("  Remove a model:")
    print(colorize("     docker model rm <model-name>", Colors.CYAN))
    print()
    print("  View config:")
    print(colorize(f"     cat {config_path}", Colors.CYAN))
    print()
    
    print(colorize("━" * 60, Colors.DIM))
    print(colorize("Documentation:", Colors.BLUE + Colors.BOLD))
    print()
    print("  • Continue.dev: https://docs.continue.dev")
    print("  • Docker Model Runner: https://docs.docker.com/desktop/features/ai/")
    if hardware.has_apple_silicon:
        print("  • Apple Silicon optimization: Metal acceleration is automatic")
    print()


def main() -> int:
    """Main entry point."""
    clear_screen()
    
    print_header("🚀 Docker Model Runner + Continue.dev Setup")
    print_info("This script will help you set up a locally hosted LLM")
    print_info("via Docker Model Runner and configure Continue.dev for VS Code.")
    print()
    
    if not prompt_yes_no("Ready to begin setup?", default=True):
        print_info("Setup cancelled. Run again when ready!")
        return 0
    
    # Step 1: Hardware detection
    print()
    hardware = detect_hardware()
    
    # Step 2: Check Docker
    print()
    docker_ok, docker_version = check_docker()
    if not docker_ok:
        print()
        print_error("Docker is required for this setup.")
        print_info("Please install Docker Desktop from: https://docker.com/desktop")
        return 1
    
    hardware.docker_version = docker_version
    
    # Step 3: Check Docker Model Runner
    print()
    dmr_ok = check_docker_model_runner(hardware)
    if not dmr_ok:
        print()
        print_error("Docker Model Runner is required but not available.")
        return 1
    
    # Step 4: Model selection
    print()
    selected_models = select_models(hardware)
    
    if not selected_models:
        print_error("No models selected. Aborting setup.")
        return 1
    
    # Step 5: Confirm selection
    print()
    print_subheader("Configuration Summary")
    total_ram = sum(m.ram_gb for m in selected_models)
    print(f"  Selected {len(selected_models)} model(s):")
    for model in selected_models:
        print(f"    • {model.name} (~{model.ram_gb}GB RAM)")
    print(f"  Total estimated RAM: ~{total_ram:.1f}GB")
    print()
    
    if not prompt_yes_no("Proceed with this configuration?", default=True):
        print_info("Setup cancelled. Run again to reconfigure.")
        return 0
    
    # Step 6: Pull models
    print()
    pulled_models = pull_models_docker(selected_models, hardware)
    
    # Step 7: Generate config
    print()
    config_path = generate_continue_config(pulled_models, hardware)
    
    # Step 8: Show next steps
    print()
    show_next_steps(config_path, pulled_models, hardware)
    
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print()
        print_warning("Setup interrupted by user.")
        sys.exit(130)
    except Exception as e:
        print_error(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
