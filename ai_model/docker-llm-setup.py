#!/usr/bin/env python3
"""
Docker Model Runner + Continue.dev Setup Script

An interactive Python script that helps you set up a locally hosted LLM
via Docker Model Runner and generates a continue.dev config.yaml for VS Code.

Requirements:
- Python 3.8+
- Docker Desktop 4.40+ (with Docker Model Runner / Docker AI enabled)

Author: AI-Generated for Local LLM Development
License: MIT
"""

import json
import os
import platform
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

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
    cpu_brand: str = ""
    cpu_arch: str = ""
    cpu_cores: int = 0
    ram_gb: float = 0.0
    gpu_name: str = ""
    gpu_vram_gb: float = 0.0
    has_nvidia: bool = False
    has_apple_silicon: bool = False
    docker_version: str = ""
    docker_model_runner_available: bool = False
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


# Model catalog for Docker Model Runner
# Docker Model Runner uses ai/ namespace for models
MODEL_CATALOG: List[ModelInfo] = [
    # Chat/Edit Models - Large
    ModelInfo(
        name="Llama 3.3 70B",
        docker_name="ai/llama3.3:70B-Q4_K_M",
        description="70B - Highest quality for complex refactoring (Tier S only)",
        ram_gb=35.0,
        context_length=32768,
        roles=["chat", "edit", "agent"],
        tiers=[HardwareTier.S],
        recommended_for=["Tier S primary model"]
    ),
    ModelInfo(
        name="Llama 3.1 70B",
        docker_name="ai/llama3.1:70B-Q4_K_M",
        description="70B - Excellent for architecture and complex tasks",
        ram_gb=35.0,
        context_length=32768,
        roles=["chat", "edit", "agent"],
        tiers=[HardwareTier.S],
        recommended_for=["Tier S alternative"]
    ),
    # Chat/Edit Models - Medium-Large
    ModelInfo(
        name="Codestral 22B",
        docker_name="ai/codestral:22B-Q4_K_M",
        description="22B - Excellent code generation and reasoning",
        ram_gb=11.0,
        context_length=32768,
        roles=["chat", "edit", "autocomplete"],
        tiers=[HardwareTier.S, HardwareTier.A],
        recommended_for=["Tier A/S primary", "Best for code generation"]
    ),
    ModelInfo(
        name="Qwen 2.5 Coder 32B",
        docker_name="ai/qwen2.5-coder:32B-Q4_K_M",
        description="32B - State-of-the-art open coding model",
        ram_gb=16.0,
        context_length=32768,
        roles=["chat", "edit", "autocomplete"],
        tiers=[HardwareTier.S, HardwareTier.A],
        recommended_for=["Best coding quality"]
    ),
    ModelInfo(
        name="Granite Code 20B",
        docker_name="ai/granite-code:20B-Q4_K_M",
        description="20B - IBM Granite code model",
        ram_gb=10.0,
        context_length=16384,
        roles=["chat", "edit"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B],
        recommended_for=["Tier B primary"]
    ),
    ModelInfo(
        name="Phi-4 14B",
        docker_name="ai/phi4:14B-Q4_K_M",
        description="14B - State-of-the-art reasoning model",
        ram_gb=7.0,
        context_length=16384,
        roles=["chat", "edit", "agent"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B],
        recommended_for=["Excellent reasoning"]
    ),
    ModelInfo(
        name="Qwen 2.5 Coder 14B",
        docker_name="ai/qwen2.5-coder:14B-Q4_K_M",
        description="14B - Strong coding with good performance",
        ram_gb=7.0,
        context_length=32768,
        roles=["chat", "edit", "autocomplete"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B],
        recommended_for=["Good balance of quality and speed"]
    ),
    # Chat/Edit Models - Small
    ModelInfo(
        name="Llama 3.1 8B",
        docker_name="ai/llama3.1:8B-Q5_K_M",
        description="8B - Fast general-purpose coding assistant",
        ram_gb=4.2,
        context_length=16384,
        roles=["chat", "edit", "autocomplete"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B, HardwareTier.C],
        recommended_for=["All tiers", "Fast responses"]
    ),
    ModelInfo(
        name="Qwen 2.5 Coder 7B",
        docker_name="ai/qwen2.5-coder:7B-Q4_K_M",
        description="7B - Efficient coding model",
        ram_gb=3.5,
        context_length=32768,
        roles=["chat", "edit", "autocomplete"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B, HardwareTier.C],
        recommended_for=["Tier C primary", "Fast autocomplete"]
    ),
    ModelInfo(
        name="CodeGemma 7B",
        docker_name="ai/codegemma:7B-Q4_K_M",
        description="7B - Google's code-optimized model",
        ram_gb=3.5,
        context_length=8192,
        roles=["chat", "autocomplete"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B, HardwareTier.C],
        recommended_for=["Fast autocomplete"]
    ),
    # Autocomplete Models - Ultra-fast
    ModelInfo(
        name="StarCoder2 3B",
        docker_name="ai/starcoder2:3B-Q4_K_M",
        description="3B - Ultra-fast autocomplete",
        ram_gb=1.5,
        context_length=4096,
        roles=["autocomplete"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B, HardwareTier.C],
        recommended_for=["Fastest autocomplete", "Low memory"]
    ),
    ModelInfo(
        name="Llama 3.2 3B",
        docker_name="ai/llama3.2:3B-Q4_K_M",
        description="3B - Small and efficient",
        ram_gb=1.5,
        context_length=4096,
        roles=["chat", "autocomplete"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B, HardwareTier.C],
        recommended_for=["Quick edits", "Low memory"]
    ),
    # Embedding Models
    ModelInfo(
        name="Nomic Embed Text",
        docker_name="ai/nomic-embed-text:latest",
        description="Best open embedding model for code indexing",
        ram_gb=0.3,
        context_length=8192,
        roles=["embed"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B, HardwareTier.C],
        recommended_for=["Code indexing", "Semantic search"]
    ),
    ModelInfo(
        name="BGE Large",
        docker_name="ai/bge-large:latest",
        description="High-quality embeddings from BAAI",
        ram_gb=0.4,
        context_length=512,
        roles=["embed"],
        tiers=[HardwareTier.S, HardwareTier.A, HardwareTier.B, HardwareTier.C],
        recommended_for=["Alternative embedding"]
    ),
]


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
        # CPU brand
        code, stdout, _ = run_command(["sysctl", "-n", "machdep.cpu.brand_string"])
        if code == 0:
            info.cpu_brand = stdout.strip()
        
        # CPU cores
        code, stdout, _ = run_command(["sysctl", "-n", "hw.physicalcpu"])
        if code == 0:
            info.cpu_cores = int(stdout.strip())
        
        # RAM
        code, stdout, _ = run_command(["sysctl", "-n", "hw.memsize"])
        if code == 0:
            info.ram_gb = int(stdout.strip()) / (1024 ** 3)
        
        # Apple Silicon detection
        info.has_apple_silicon = info.cpu_arch == "arm64"
        
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
    print_info(f"OS: {info.os_name} {info.os_version}")
    print_info(f"CPU: {info.cpu_brand or 'Unknown'}")
    print_info(f"Architecture: {info.cpu_arch}")
    print_info(f"CPU Cores: {info.cpu_cores}")
    print_info(f"RAM: {info.ram_gb:.1f} GB")
    
    if info.has_nvidia:
        print_info(f"GPU: {info.gpu_name} ({info.gpu_vram_gb:.1f} GB VRAM)")
    elif info.has_apple_silicon:
        print_info("GPU: Apple Silicon (Unified Memory)")
    else:
        print_info("GPU: None detected (CPU inference only)")
    
    print()
    print_success(f"Hardware Tier: {info.get_tier_label()}")
    
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
    print_subheader("Checking Docker Model Runner")
    
    # Docker Model Runner was introduced in Docker Desktop 4.40+
    # It uses the 'docker model' command
    code, stdout, stderr = run_command(["docker", "model", "list"])
    
    if code == 0:
        hardware.docker_model_runner_available = True
        print_success("Docker Model Runner is available")
        
        # Check for existing models
        if stdout.strip():
            print_info("Existing models found:")
            for line in stdout.strip().split("\n")[1:]:  # Skip header
                if line.strip():
                    print(f"    {line.strip()}")
        return True
    
    # Check if it's just not enabled
    if "docker model" in stderr.lower() or "unknown command" in stderr.lower():
        print_warning("Docker Model Runner is not enabled")
        print()
        print_info("Docker Model Runner requires Docker Desktop 4.40 or later.")
        print_info("To enable it:")
        print_info("  1. Open Docker Desktop")
        print_info("  2. Go to Settings → Features in development")
        print_info("  3. Enable 'Docker Model Runner' or 'Docker AI'")
        print_info("  4. Restart Docker Desktop")
        print()
        
        if prompt_yes_no("Would you like to continue setup anyway (models will be configured but not pulled)?"):
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
    print_header("📥 Downloading Models")
    
    if not hardware.docker_model_runner_available:
        print_warning("Docker Model Runner not available. Skipping model download.")
        print_info("Models will be downloaded when you first use them.")
        return models
    
    successfully_pulled: List[ModelInfo] = []
    
    for i, model in enumerate(models, 1):
        print_step(i, len(models), f"Pulling {model.name}...")
        print_info(f"Docker image: {model.docker_name}")
        print_info(f"Estimated size: ~{model.ram_gb * 0.5:.1f}GB download")
        print()
        
        # Run docker model pull
        code, stdout, stderr = run_command(
            ["docker", "model", "pull", model.docker_name],
            capture=False,  # Show progress
            timeout=3600  # 1 hour timeout for large models
        )
        
        if code == 0:
            print_success(f"{model.name} downloaded successfully")
            successfully_pulled.append(model)
        else:
            print_error(f"Failed to pull {model.name}")
            if stderr:
                print(colorize(f"  Error: {stderr[:200]}", Colors.DIM))
            
            if prompt_yes_no("Continue with remaining models?", default=True):
                continue
            else:
                break
        
        print()
    
    return successfully_pulled


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
    
    # Determine Docker Model Runner endpoint
    # Docker Model Runner typically exposes an OpenAI-compatible API
    # Default port is 12434 for Docker Model Runner
    api_base = "http://localhost:12434/v1"
    
    # Build config
    config: Dict[str, Any] = {
        "# Generated by Docker LLM Setup Script": None,
        "# https://docs.continue.dev/yaml-reference": None,
    }
    
    # Models section
    config_models = []
    
    # Find primary chat model
    chat_models = [m for m in models if "chat" in m.roles or "edit" in m.roles]
    autocomplete_models = [m for m in models if "autocomplete" in m.roles]
    embed_models = [m for m in models if "embed" in m.roles]
    
    # Add chat/edit models
    for model in chat_models:
        model_config = {
            "name": model.name,
            "provider": "openai",
            "model": model.docker_name.replace("ai/", ""),
            "apiBase": api_base,
            "contextLength": model.context_length,
            "roles": ["chat", "edit", "apply"],
        }
        config_models.append(model_config)
    
    # Add autocomplete model (if different from chat)
    for model in autocomplete_models:
        if model not in chat_models:
            model_config = {
                "name": f"{model.name} (Autocomplete)",
                "provider": "openai",
                "model": model.docker_name.replace("ai/", ""),
                "apiBase": api_base,
                "roles": ["autocomplete"],
            }
            config_models.append(model_config)
    
    config["models"] = config_models
    
    # Tab autocomplete configuration
    if autocomplete_models:
        auto_model = autocomplete_models[0]
        config["tabAutocompleteModel"] = {
            "provider": "openai",
            "model": auto_model.docker_name.replace("ai/", ""),
            "apiBase": api_base,
        }
    
    # Embeddings configuration
    if embed_models:
        embed_model = embed_models[0]
        config["embeddingsProvider"] = {
            "provider": "openai",
            "model": embed_model.docker_name.replace("ai/", ""),
            "apiBase": api_base,
        }
    
    # Context providers
    config["contextProviders"] = [
        {"name": "codebase"},
        {"name": "folder"},
        {"name": "file"},
        {"name": "code"},
        {"name": "terminal"},
        {"name": "diff"},
        {"name": "problems"},
    ]
    
    # Disable telemetry
    config["allowAnonymousTelemetry"] = False
    
    # Write YAML config
    yaml_content = generate_yaml(config)
    
    with open(output_path, "w") as f:
        f.write(yaml_content)
    
    print_success(f"Configuration saved to {output_path}")
    
    # Also create a JSON version for compatibility
    json_path = output_path.parent / "config.json"
    # Remove comment entries for JSON
    json_config = {k: v for k, v in config.items() if not k.startswith("#")}
    
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
    print(f"  Hardware Tier: {hardware.get_tier_label()}")
    print(f"  Models Configured: {len(models)}")
    for model in models:
        print(f"    • {model.name} ({', '.join(model.roles)})")
    print(f"  Config Location: {config_path}")
    print()
    
    print(colorize("Next Steps:", Colors.YELLOW + Colors.BOLD))
    print()
    print("  1. Install Continue.dev extension in VS Code:")
    print(colorize("     • Open VS Code", Colors.DIM))
    print(colorize("     • Press Cmd+Shift+X (or Ctrl+Shift+X)", Colors.DIM))
    print(colorize("     • Search for 'Continue' and install", Colors.DIM))
    print()
    
    if hardware.docker_model_runner_available:
        print("  2. Start Docker Model Runner:")
        print(colorize("     docker model start", Colors.CYAN))
        print()
        print("  3. Verify models are running:")
        print(colorize("     docker model list", Colors.CYAN))
        print()
    else:
        print("  2. Enable Docker Model Runner:")
        print(colorize("     • Open Docker Desktop → Settings", Colors.DIM))
        print(colorize("     • Features in development → Enable Docker Model Runner", Colors.DIM))
        print(colorize("     • Restart Docker Desktop", Colors.DIM))
        print()
        print("  3. Pull models:")
        for model in models:
            print(colorize(f"     docker model pull {model.docker_name}", Colors.CYAN))
        print()
    
    print("  4. Restart VS Code:")
    print(colorize("     • Quit VS Code completely (Cmd+Q)", Colors.DIM))
    print(colorize("     • Reopen VS Code", Colors.DIM))
    print()
    
    print("  5. Start using Continue.dev:")
    print(colorize("     • Press Cmd+L to open chat", Colors.DIM))
    print(colorize("     • Press Cmd+K for inline edits", Colors.DIM))
    print(colorize("     • Use @Codebase for semantic search", Colors.DIM))
    print()
    
    print(colorize("Documentation:", Colors.BLUE + Colors.BOLD))
    print("  • Continue.dev: https://docs.continue.dev")
    print("  • Docker Model Runner: https://docs.docker.com/ai/")
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
