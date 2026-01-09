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
import subprocess
import sys
import time
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
    tier: HardwareTier = HardwareTier.C
    
    def get_tier_label(self) -> str:
        """Get human-readable tier label."""
        labels = {
            HardwareTier.S: f"Tier S (≥49GB RAM) - {self.ram_gb:.1f}GB detected",
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
    ModelInfo(
        name="Llama 3.2 8B",
        docker_name="ai.docker.com/meta/llama3.2:8b-instruct-q5_K_M",
        description="8B - Fast general-purpose assistant",
        ram_gb=5.0,
        context_length=131072,
        roles=["chat", "edit", "autocomplete"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B, HardwareTier.C],
        recommended_for=["All tiers", "Fast responses"]
    ),
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
        description="3B - Small and efficient general model",
        ram_gb=1.8,
        context_length=131072,
        roles=["chat", "autocomplete"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B, HardwareTier.C],
        recommended_for=["Quick edits", "Low memory"]
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
    
    # Classify tier
    if info.ram_gb >= 49:
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


def check_docker_model_runner(hardware: HardwareInfo) -> bool:
    """Check if Docker Model Runner is available."""
    print_subheader("Checking Docker Model Runner (DMR)")
    
    # Docker Model Runner was introduced in Docker Desktop 4.40+
    # It uses the 'docker model' command namespace
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
        for endpoint in [DMR_API_BASE, DMR_SOCKET_ENDPOINT, "http://localhost:8080/v1"]:
            try:
                req = urllib.request.Request(f"{endpoint}/models", method="GET")
                req.add_header("Content-Type", "application/json")
                with urllib.request.urlopen(req, timeout=5) as response:
                    if response.status == 200:
                        hardware.dmr_api_endpoint = endpoint
                        api_reachable = True
                        print_info(f"API endpoint: {endpoint}")
                        break
            except (urllib.error.URLError, urllib.error.HTTPError, OSError):
                continue
        
        if not api_reachable:
            print_info(f"API endpoint (default): {hardware.dmr_api_endpoint}")
            print_warning("Could not verify API endpoint - it may start when a model runs")
        
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


def get_models_for_tier(tier: HardwareTier) -> List[ModelInfo]:
    """Get models available for a specific hardware tier."""
    return [m for m in MODEL_CATALOG if tier in m.tiers]


def get_recommended_models(tier: HardwareTier) -> Dict[str, ModelInfo]:
    """Get recommended models for each role based on tier."""
    recommendations: Dict[str, ModelInfo] = {}
    
    available = get_models_for_tier(tier)
    
    # Chat/Edit model (primary)
    chat_models = [m for m in available if "chat" in m.roles or "edit" in m.roles]
    if chat_models:
        # Sort by RAM (descending) to get best quality within tier
        chat_models.sort(key=lambda m: m.ram_gb, reverse=True)
        recommendations["chat"] = chat_models[0]
    
    # Autocomplete model (fast)
    auto_models = [m for m in available if "autocomplete" in m.roles]
    if auto_models:
        # Sort by RAM (ascending) to get fastest
        auto_models.sort(key=lambda m: m.ram_gb)
        recommendations["autocomplete"] = auto_models[0]
    
    # Embedding model
    embed_models = [m for m in available if "embed" in m.roles]
    if embed_models:
        recommendations["embed"] = embed_models[0]
    
    return recommendations


def select_models(hardware: HardwareInfo) -> List[ModelInfo]:
    """Interactive model selection based on hardware tier."""
    print_header("🤖 Model Selection")
    
    print_info(f"Based on your hardware tier ({hardware.tier.value}), here are the available models:")
    print()
    
    available_models = get_models_for_tier(hardware.tier)
    recommendations = get_recommended_models(hardware.tier)
    
    # Show recommendations first
    print(colorize("  Recommended Configuration:", Colors.GREEN + Colors.BOLD))
    total_ram = 0.0
    for role, model in recommendations.items():
        print(f"    • {role.capitalize()}: {model.name} (~{model.ram_gb}GB)")
        total_ram += model.ram_gb
    print(f"    Total RAM: ~{total_ram:.1f}GB")
    print()
    
    # Ask if user wants to use recommended config
    if prompt_yes_no("Use recommended configuration?", default=True):
        selected = list(recommendations.values())
        # Remove duplicates (same model for multiple roles)
        unique = []
        seen_names = set()
        for m in selected:
            if m.docker_name not in seen_names:
                unique.append(m)
                seen_names.add(m.docker_name)
        return unique
    
    # Manual selection
    print()
    print_info("Select models manually. Models are grouped by role.")
    
    selected_models: List[ModelInfo] = []
    
    # Select chat/edit model
    chat_models = [m for m in available_models if "chat" in m.roles or "edit" in m.roles]
    if chat_models:
        print_subheader("Chat/Edit Model (Primary)")
        choices = [(m.name, f"{m.description} (~{m.ram_gb}GB)", False) for m in chat_models]
        # Set recommended as default
        if recommendations.get("chat"):
            for i, m in enumerate(chat_models):
                if m.docker_name == recommendations["chat"].docker_name:
                    choices[i] = (m.name, f"{m.description} (~{m.ram_gb}GB)", True)
        
        indices = prompt_multi_choice("Select chat/edit model(s):", choices, min_selections=1)
        for i in indices:
            selected_models.append(chat_models[i])
    
    # Select autocomplete model
    auto_models = [m for m in available_models if "autocomplete" in m.roles]
    if auto_models:
        print_subheader("Autocomplete Model (Fast)")
        choices = [(m.name, f"{m.description} (~{m.ram_gb}GB)", False) for m in auto_models]
        # Set recommended as default
        if recommendations.get("autocomplete"):
            for i, m in enumerate(auto_models):
                if m.docker_name == recommendations["autocomplete"].docker_name:
                    choices[i] = (m.name, f"{m.description} (~{m.ram_gb}GB)", True)
        
        if prompt_yes_no("Add a dedicated autocomplete model?", default=True):
            indices = prompt_multi_choice("Select autocomplete model:", choices, min_selections=1)
            for i in indices:
                if auto_models[i] not in selected_models:
                    selected_models.append(auto_models[i])
    
    # Select embedding model
    embed_models = [m for m in available_models if "embed" in m.roles]
    if embed_models:
        print_subheader("Embedding Model (Code Indexing)")
        print_info("Embedding models enable semantic code search in Continue.dev")
        
        if prompt_yes_no("Add an embedding model for code indexing?", default=True):
            choices = [(m.name, f"{m.description} (~{m.ram_gb}GB)", False) for m in embed_models]
            if recommendations.get("embed"):
                for i, m in enumerate(embed_models):
                    if m.docker_name == recommendations["embed"].docker_name:
                        choices[i] = (m.name, f"{m.description} (~{m.ram_gb}GB)", True)
            
            indices = prompt_multi_choice("Select embedding model:", choices, min_selections=1)
            for i in indices:
                if embed_models[i] not in selected_models:
                    selected_models.append(embed_models[i])
    
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
        
        # Run docker model pull
        # We don't capture output so user can see download progress
        try:
            process = subprocess.Popen(
                ["docker", "model", "pull", model.docker_name],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )
            
            # Stream output in real-time
            if process.stdout:
                for line in process.stdout:
                    line = line.strip()
                    if line:
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
            print_success(f"{model.name} downloaded successfully")
            successfully_pulled.append(model)
            
            # Verify the model is listed
            verify_code, verify_out, _ = run_command(["docker", "model", "list"])
            if verify_code == 0 and model.docker_name in verify_out:
                print_info("Model verified in Docker Model Runner")
        else:
            print_error(f"Failed to pull {model.name}")
            print_info("You can try pulling manually later with:")
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


def get_model_id_for_continue(docker_name: str) -> str:
    """
    Convert Docker Model Runner model name to Continue.dev compatible format.
    Docker Model Runner uses: ai.docker.com/<org>/<model>:<tag>
    Continue.dev expects just the model identifier.
    """
    # Remove the ai.docker.com/ prefix if present
    model_id = docker_name
    if model_id.startswith("ai.docker.com/"):
        model_id = model_id[len("ai.docker.com/"):]
    if model_id.startswith("ai/"):
        model_id = model_id[len("ai/"):]
    
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
    
    # Build config with comments
    yaml_lines = [
        "# Continue.dev Configuration for Docker Model Runner",
        "# Generated by docker-llm-setup.py",
        f"# Hardware: {hardware.apple_chip_model or hardware.cpu_brand}",
        f"# RAM: {hardware.ram_gb:.0f}GB | Tier: {hardware.tier.value}",
        "#",
        "# Documentation: https://docs.continue.dev/yaml-reference",
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
        model_id = get_model_id_for_continue(model.docker_name)
        yaml_lines.extend([
            f"  - name: {model.name}",
            f"    provider: openai",
            f"    model: {model_id}",
            f"    apiBase: {api_base}",
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
        model_id = get_model_id_for_continue(model.docker_name)
        yaml_lines.extend([
            f"  - name: {model.name} (Autocomplete)",
            f"    provider: openai",
            f"    model: {model_id}",
            f"    apiBase: {api_base}",
            "    roles:",
            "      - autocomplete",
            "",
        ])
    
    # Tab autocomplete configuration
    if autocomplete_models:
        auto_model = autocomplete_models[0]
        model_id = get_model_id_for_continue(auto_model.docker_name)
        yaml_lines.extend([
            "# Tab autocomplete settings",
            "tabAutocompleteModel:",
            f"  provider: openai",
            f"  model: {model_id}",
            f"  apiBase: {api_base}",
            "",
        ])
    
    # Embeddings configuration
    if embed_models:
        embed_model = embed_models[0]
        model_id = get_model_id_for_continue(embed_model.docker_name)
        yaml_lines.extend([
            "# Embeddings for semantic code search (@Codebase)",
            "embeddingsProvider:",
            f"  provider: openai",
            f"  model: {model_id}",
            f"  apiBase: {api_base}",
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
        model_id = get_model_id_for_continue(model.docker_name)
        json_config["models"].append({
            "name": model.name,
            "provider": "openai",
            "model": model_id,
            "apiBase": api_base,
            "contextLength": model.context_length,
            "roles": ["chat", "edit", "apply"] + (["agent"] if "agent" in model.roles else []),
        })
    
    for model in autocomplete_only:
        model_id = get_model_id_for_continue(model.docker_name)
        json_config["models"].append({
            "name": f"{model.name} (Autocomplete)",
            "provider": "openai", 
            "model": model_id,
            "apiBase": api_base,
            "roles": ["autocomplete"],
        })
    
    if autocomplete_models:
        auto_model = autocomplete_models[0]
        model_id = get_model_id_for_continue(auto_model.docker_name)
        json_config["tabAutocompleteModel"] = {
            "provider": "openai",
            "model": model_id,
            "apiBase": api_base,
        }
    
    if embed_models:
        embed_model = embed_models[0]
        model_id = get_model_id_for_continue(embed_model.docker_name)
        json_config["embeddingsProvider"] = {
            "provider": "openai",
            "model": model_id,
            "apiBase": api_base,
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
    
    # Step 1: Install Continue.dev
    print(f"  {step}. Install Continue.dev extension in VS Code:")
    if hardware.os_name == "Darwin":
        print(colorize("     • Open VS Code", Colors.DIM))
        print(colorize("     • Press Cmd+Shift+X to open Extensions", Colors.DIM))
        print(colorize("     • Search for 'Continue' and install 'Continue - Codestral, GPT-4, etc.'", Colors.DIM))
    else:
        print(colorize("     • Open VS Code", Colors.DIM))
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
            print(colorize(f"     docker model run {chat_models[0].docker_name}", Colors.CYAN))
            print(colorize("     (This starts the API server for Continue.dev to connect)", Colors.DIM))
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
    
    # Step: Restart VS Code
    print(f"  {step}. Restart VS Code:")
    if hardware.os_name == "Darwin":
        print(colorize("     • Quit VS Code completely (Cmd+Q)", Colors.DIM))
    else:
        print(colorize("     • Close all VS Code windows", Colors.DIM))
    print(colorize("     • Reopen VS Code", Colors.DIM))
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
