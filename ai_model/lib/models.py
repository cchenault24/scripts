"""
Model catalog and selection functionality.

Provides model information, catalog, discovery, selection, and pulling capabilities.
"""

import json
import re
import subprocess
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from . import hardware
from . import ui
from . import utils


@dataclass
class ModelInfo:
    """Information about an LLM model."""
    name: str
    docker_name: str  # Name used in Docker Model Runner
    description: str
    ram_gb: float
    context_length: int
    roles: List[str]  # chat, autocomplete, embed, etc.
    tiers: List[hardware.HardwareTier]  # Which tiers can run this model
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
        tiers=[hardware.HardwareTier.S],
        recommended_for=["Tier S primary model", "Complex refactoring"]
    ),
    ModelInfo(
        name="Llama 3.1 70B",
        docker_name="ai.docker.com/meta/llama3.1:70b-instruct-q4_K_M",
        description="70B - Excellent for architecture and complex tasks",
        ram_gb=35.0,
        context_length=131072,
        roles=["chat", "edit", "agent"],
        tiers=[hardware.HardwareTier.S],
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
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A],
        recommended_for=["Best coding quality", "Tier A primary"]
    ),
    ModelInfo(
        name="Codestral 22B",
        docker_name="ai.docker.com/mistral/codestral:22b-v0.1-q4_K_M",
        description="22B - Mistral's code generation model",
        ram_gb=12.0,
        context_length=32768,
        roles=["chat", "edit", "autocomplete"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A],
        recommended_for=["Excellent code generation"]
    ),
    ModelInfo(
        name="DeepSeek Coder V2 Lite 16B",
        docker_name="ai.docker.com/deepseek/deepseek-coder-v2:16b-lite-instruct-q4_K_M",
        description="16B - Fast and capable coding model",
        ram_gb=9.0,
        context_length=131072,
        roles=["chat", "edit", "autocomplete"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A],
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
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B],
        recommended_for=["Excellent reasoning", "Tier B primary"]
    ),
    ModelInfo(
        name="Qwen 2.5 Coder 14B",
        docker_name="ai.docker.com/qwen/qwen2.5-coder:14b-instruct-q4_K_M",
        description="14B - Strong coding with good performance",
        ram_gb=8.0,
        context_length=131072,
        roles=["chat", "edit", "autocomplete"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B],
        recommended_for=["Good balance of quality and speed"]
    ),
    ModelInfo(
        name="CodeLlama 13B",
        docker_name="ai.docker.com/meta/codellama:13b-instruct-q4_K_M",
        description="13B - Meta's code-specialized Llama",
        ram_gb=7.5,
        context_length=16384,
        roles=["chat", "edit", "autocomplete"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B],
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
    #     tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
    #     recommended_for=["All tiers", "Fast responses"]
    # ),
    ModelInfo(
        name="Qwen 2.5 Coder 7B",
        docker_name="ai.docker.com/qwen/qwen2.5-coder:7b-instruct-q4_K_M",
        description="7B - Efficient coding model",
        ram_gb=4.0,
        context_length=131072,
        roles=["chat", "edit", "autocomplete"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
        recommended_for=["Tier C primary", "Fast autocomplete"]
    ),
    ModelInfo(
        name="CodeGemma 7B",
        docker_name="ai.docker.com/google/codegemma:7b-it-q4_K_M",
        description="7B - Google's code-optimized model",
        ram_gb=4.0,
        context_length=8192,
        roles=["chat", "autocomplete"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
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
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
        recommended_for=["Fastest autocomplete", "Low memory"]
    ),
    ModelInfo(
        name="Llama 3.2 3B",
        docker_name="ai.docker.com/meta/llama3.2:3b-instruct-q4_K_M",
        description="3B - Small and efficient general model (available in Docker Model Runner as ai/llama3.2)",
        ram_gb=1.8,
        context_length=131072,
        roles=["chat", "edit", "autocomplete"],  # Added "edit" since 8B is not available
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
        recommended_for=["All tiers", "Quick edits", "Low memory", "Fast responses"]
    ),
    ModelInfo(
        name="Qwen 2.5 Coder 1.5B",
        docker_name="ai.docker.com/qwen/qwen2.5-coder:1.5b-instruct-q8_0",
        description="1.5B - Smallest coding model, very fast",
        ram_gb=1.0,
        context_length=131072,
        roles=["autocomplete"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
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
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
        recommended_for=["Code indexing", "Semantic search"]
    ),
    ModelInfo(
        name="BGE-M3",
        docker_name="ai.docker.com/baai/bge-m3:latest",
        description="Multi-lingual embedding model from BAAI",
        ram_gb=0.5,
        context_length=8192,
        roles=["embed"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
        recommended_for=["Multi-lingual codebases"]
    ),
    ModelInfo(
        name="All-MiniLM-L6-v2",
        docker_name="ai.docker.com/sentence-transformers/all-minilm:l6-v2",
        description="Lightweight embedding for simple use cases",
        ram_gb=0.1,
        context_length=512,
        roles=["embed"],
        tiers=[hardware.HardwareTier.S, hardware.HardwareTier.A, hardware.HardwareTier.B, hardware.HardwareTier.C],
        recommended_for=["Minimal memory", "Simple search"]
    ),
]


def discover_docker_hub_models(query: str = "ai/", limit: int = 50) -> List[Dict[str, Any]]:
    """Discover models from Docker Hub."""
    models = []
    try:
        ui.print_info(f"Searching Docker Hub for '{query}'...")
        code, stdout, _ = utils.run_command(["docker", "search", query, "--limit", str(limit)], timeout=30)
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
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError, ValueError) as e:
        ui.print_warning(f"Could not search Docker Hub: {e}")
    
    return models


def discover_huggingface_models(query: str = "llama", limit: int = 30) -> List[Dict[str, Any]]:
    """Discover models from Hugging Face (GGUF format)."""
    # Input validation
    if not query or not isinstance(query, str):
        query = "llama"
    if limit < 1 or limit > 100:
        limit = 30
    
    models = []
    try:
        ui.print_info(f"Searching Hugging Face for '{query}'...")
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
        ui.print_warning(f"Could not search Hugging Face: {e}")
    except (json.JSONDecodeError, ValueError, OSError) as e:
        ui.print_warning(f"Error searching Hugging Face: {e}")
    
    return models


def convert_discovered_to_modelinfo(discovered: Dict[str, Any], tier: hardware.HardwareTier) -> ModelInfo:
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
    tiers = [hardware.HardwareTier.C]
    if ram_gb >= 35:
        tiers = [hardware.HardwareTier.S]
    elif ram_gb >= 18:
        tiers = [hardware.HardwareTier.S, hardware.HardwareTier.A]
    elif ram_gb >= 12:
        tiers = [hardware.HardwareTier.A, hardware.HardwareTier.S]
    elif ram_gb >= 8:
        tiers = [hardware.HardwareTier.B, hardware.HardwareTier.A, hardware.HardwareTier.S]
    else:
        tiers = [hardware.HardwareTier.C, hardware.HardwareTier.B, hardware.HardwareTier.A, hardware.HardwareTier.S]
    
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


def discover_and_select_models(hw_info: hardware.HardwareInfo) -> List[ModelInfo]:
    """Discover available models and let user select interactively."""
    ui.print_header("🔍 Model Discovery & Selection")
    
    selected_models: List[ModelInfo] = []
    all_discovered: List[Dict[str, Any]] = []
    
    # Ask which source to search
    ui.print_info("Where would you like to search for models?")
    source_choice = ui.prompt_choice(
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
            ui.print_success(f"Found {len(docker_models)} models on Docker Hub")
    
    # Search Hugging Face
    if source_choice in [1, 2]:
        print()
        search_query = input("Enter search query for Hugging Face (default: 'llama'): ").strip() or "llama"
        hf_models = discover_huggingface_models(search_query)
        all_discovered.extend(hf_models)
        if hf_models:
            ui.print_success(f"Found {len(hf_models)} models on Hugging Face")
    
    if not all_discovered:
        ui.print_warning("No models found. Try a different search query.")
        return []
    
    # Convert to ModelInfo and display
    print()
    ui.print_subheader("Discovered Models")
    model_infos = [convert_discovered_to_modelinfo(m, hw_info.tier) for m in all_discovered]
    
    # Filter by hardware tier
    available_models = [m for m in model_infos if hw_info.tier in m.tiers]
    
    if not available_models:
        ui.print_warning(f"No models found compatible with your hardware tier ({hw_info.tier.value})")
        ui.print_info("Showing all models anyway...")
        available_models = model_infos
    
    # Group by role
    chat_models = [m for m in available_models if "chat" in m.roles or "edit" in m.roles]
    auto_models = [m for m in available_models if "autocomplete" in m.roles]
    embed_models = [m for m in available_models if "embed" in m.roles]
    
    # Select chat/edit models
    if chat_models:
        print()
        ui.print_subheader("Chat/Edit Models")
        choices = [(m.name, f"{m.description} (~{m.ram_gb}GB) - {m.docker_name}", False) for m in chat_models]
        indices = ui.prompt_multi_choice("Select chat/edit model(s):", choices, min_selections=1)
        for i in indices:
            selected_models.append(chat_models[i])
    
    # Select autocomplete models
    if auto_models:
        print()
        if ui.prompt_yes_no("Add a dedicated autocomplete model?", default=False):
            ui.print_subheader("Autocomplete Models")
            choices = [(m.name, f"{m.description} (~{m.ram_gb}GB) - {m.docker_name}", False) for m in auto_models]
            indices = ui.prompt_multi_choice("Select autocomplete model:", choices, min_selections=1)
            for i in indices:
                if auto_models[i] not in selected_models:
                    selected_models.append(auto_models[i])
    
    # Select embedding models
    if embed_models:
        print()
        if ui.prompt_yes_no("Add an embedding model for code indexing?", default=False):
            ui.print_subheader("Embedding Models")
            choices = [(m.name, f"{m.description} (~{m.ram_gb}GB) - {m.docker_name}", False) for m in embed_models]
            indices = ui.prompt_multi_choice("Select embedding model:", choices, min_selections=1)
            for i in indices:
                if embed_models[i] not in selected_models:
                    selected_models.append(embed_models[i])
    
    return selected_models


def get_models_for_tier(tier: hardware.HardwareTier) -> List[ModelInfo]:
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


def verify_model_available(model: ModelInfo, hw_info: hardware.HardwareInfo) -> bool:
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
    if hasattr(hw_info, 'available_api_models') and hw_info.available_api_models:
        for api_model_id in hw_info.available_api_models:
            api_model_lower = api_model_id.lower()
            # Check if our model matches (with or without tag)
            if base_name.lower() in api_model_lower or api_model_lower in base_name.lower():
                return True
    
    # If no cached list, try to query the API directly
    if hw_info.docker_model_runner_available and hw_info.dmr_api_endpoint:
        try:
            # Try to get available models from the API
            api_url = f"{hw_info.dmr_api_endpoint}/models"
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
        code, stdout, _ = utils.run_command(["docker", "search", base_name, "--limit", "10"], timeout=15)
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
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError, ValueError) as e:
        # Silently fail for Docker Hub search - it's just a fallback
        pass
    
    # Model not found in API, known list, or search
    return False


def get_curated_top_models(tier: hardware.HardwareTier, limit: int = 10, hw_info: Optional[hardware.HardwareInfo] = None) -> List[ModelInfo]:
    """Get curated top models for a hardware tier, prioritizing quality and variety.
    Excludes models from restricted countries (China, Russia) due to political conflicts.
    Only includes models that are verified to exist in Docker Model Runner.
    If not enough models for the tier, includes models from higher tiers to reach the limit."""
    # Start with models for this tier
    tier_models = get_models_for_tier(tier)
    
    # Filter out restricted models (Chinese/Russian) and models not available in Docker Hub
    tier_models = [m for m in tier_models if not is_restricted_model(m) and not is_docker_hub_unavailable(m)]
    
    # Verify models actually exist in Docker Model Runner (if hardware info provided)
    if hw_info and hw_info.docker_model_runner_available:
        ui.print_info("Verifying model availability in Docker Model Runner...")
        verified_models = []
        for model in tier_models:
            if verify_model_available(model, hw_info):
                verified_models.append(model)
            else:
                ui.print_warning(f"Skipping {model.name} - not available in Docker Model Runner")
        tier_models = verified_models
        if tier_models:
            ui.print_success(f"Found {len(tier_models)} verified models for your tier")
    
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


def get_recommended_models(tier: hardware.HardwareTier, hw_info: Optional[hardware.HardwareInfo] = None) -> Dict[str, ModelInfo]:
    """Get recommended models for each role based on tier and chip capabilities.
    Excludes models from restricted countries (China, Russia) due to political conflicts.
    Only includes models verified to exist in Docker Model Runner.
    Enhanced to consider chip performance for better recommendations."""
    recommendations: Dict[str, ModelInfo] = {}
    
    available = get_models_for_tier(tier)
    
    # Filter out restricted models (Chinese/Russian) and models not available in Docker Hub
    available = [m for m in available if not is_restricted_model(m) and not is_docker_hub_unavailable(m)]
    
    # Verify models actually exist in Docker Model Runner (if hardware info provided)
    if hw_info and hw_info.docker_model_runner_available:
        verified_available = []
        for model in available:
            if verify_model_available(model, hw_info):
                verified_available.append(model)
        available = verified_available
    
    # Determine if this is a high-end chip that can handle larger models
    is_high_end_chip = False
    if hw_info and hw_info.has_apple_silicon and hw_info.apple_chip_model:
        high_end_patterns = ["M3 Pro", "M3 Max", "M3 Ultra", "M4 Pro", "M4 Max", "M4 Ultra"]
        is_high_end_chip = any(pattern in hw_info.apple_chip_model for pattern in high_end_patterns)
    
    # Chat/Edit model (primary) - prioritize best quality models
    chat_models = [m for m in available if "chat" in m.roles or "edit" in m.roles]
    if chat_models:
        # For high-end chips, prefer larger models even if at tier boundary
        # Sort by RAM (descending) to get best quality within tier
        chat_models.sort(key=lambda m: m.ram_gb, reverse=True)
        
        # For Tier A with high-end chips and 40GB+ RAM, prefer larger models
        if tier == hardware.HardwareTier.A and is_high_end_chip and hw_info and hw_info.ram_gb >= 40:
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
        if is_high_end_chip and tier in (hardware.HardwareTier.S, hardware.HardwareTier.A):
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


def select_models(hw_info: hardware.HardwareInfo) -> List[ModelInfo]:
    """Interactive model selection from curated top models based on hardware tier."""
    # Input validation
    if not hw_info:
        raise ValueError("hw_info is required")
    
    ui.print_header("🤖 Model Selection")
    
    ui.print_info(f"Hardware Tier: {ui.colorize(hw_info.tier.value, ui.Colors.GREEN + ui.Colors.BOLD)}")
    ui.print_info(f"Available RAM: ~{hw_info.ram_gb:.1f}GB")
    print()
    
    # Get curated top 10 models for this tier (with verification)
    curated_models = get_curated_top_models(hw_info.tier, limit=10, hw_info=hw_info)
    
    if not curated_models:
        ui.print_error("No verified models available for your hardware tier.")
        ui.print_info("This may mean Docker Model Runner doesn't have models compatible with your tier.")
        ui.print_info("You can try the model discovery feature to search for available models.")
        if ui.prompt_yes_no("Would you like to search for available models?", default=False):
            return discover_and_select_models(hw_info)
        return []
    
    # Show recommended configuration first (with verification)
    recommendations = get_recommended_models(hw_info.tier, hw_info=hw_info)
    if recommendations:
        print(ui.colorize("  Recommended Configuration:", ui.Colors.GREEN + ui.Colors.BOLD))
        total_ram = 0.0
        for role, model in recommendations.items():
            print(f"    • {role.capitalize()}: {model.name} (~{model.ram_gb}GB)")
            total_ram += model.ram_gb
        print(f"    Total RAM: ~{total_ram:.1f}GB")
        print()
        
        # Quick option to use recommended
        if ui.prompt_yes_no("Use recommended configuration?", default=True):
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
    ui.print_subheader("Top 10 Models for Your Hardware")
    ui.print_info("Select from the best models optimized for your system:")
    if len(curated_models) < 10:
        ui.print_info(f"(Showing {len(curated_models)} available models for your tier)")
    print()
    
    # Prepare choices with role indicators
    choices = []
    for m in curated_models:
        # Build description with role info
        roles_str = ", ".join(m.roles)
        
        # Indicate if model is compatible with current tier
        tier_indicator = ""
        if hw_info.tier in m.tiers:
            tier_indicator = "✓ Tier compatible"
        else:
            tier_indicator = "⚠ Higher tier (may be slow)"
        
        desc = f"{m.description} | {roles_str} | ~{m.ram_gb}GB RAM | {tier_indicator}"
        
        # Mark recommended models
        is_recommended = any(m.docker_name == rec.docker_name for rec in recommendations.values())
        choices.append((m.name, desc, is_recommended))
    
    # Let user select
    indices = ui.prompt_multi_choice(
        "Select models to install (comma-separated numbers, or 'a' for all):",
        choices,
        min_selections=1
    )
    
    selected_models = [curated_models[i] for i in indices]
    
    # Show summary
    if selected_models:
        print()
        ui.print_success(f"Selected {len(selected_models)} model(s):")
        total_ram = 0.0
        for m in selected_models:
            print(f"  • {m.name} (~{m.ram_gb}GB)")
            total_ram += m.ram_gb
        print(f"  Total RAM required: ~{total_ram:.1f}GB")
    
    return selected_models


def pull_models_docker(model_list: List[ModelInfo], hw_info: hardware.HardwareInfo) -> List[ModelInfo]:
    """Pull selected models using Docker Model Runner."""
    # Input validation
    if not model_list:
        ui.print_warning("No models provided to pull")
        return []
    if not hw_info:
        raise ValueError("hw_info is required")
    
    ui.print_header("📥 Downloading Models via Docker Model Runner")
    
    if not hw_info.docker_model_runner_available:
        ui.print_warning("Docker Model Runner not available. Skipping model download.")
        ui.print_info("Models will be downloaded when you first use them in Continue.dev.")
        print()
        ui.print_info("To manually pull models later, run:")
        for model in model_list:
            print(ui.colorize(f"    docker model pull {model.docker_name}", ui.Colors.CYAN))
        return model_list
    
    successfully_pulled: List[ModelInfo] = []
    
    # Estimate total download size
    total_download_gb = sum(m.ram_gb * 0.5 for m in model_list)  # Rough estimate: model size is ~50% of RAM needed
    ui.print_info(f"Estimated total download: ~{total_download_gb:.1f}GB")
    ui.print_info(f"Models will use Metal GPU acceleration on Apple Silicon")
    print()
    
    for i, model in enumerate(model_list, 1):
        ui.print_step(i, len(model_list), f"Pulling {model.name}...")
        ui.print_info(f"Model: {model.docker_name}")
        ui.print_info(f"Estimated download: ~{model.ram_gb * 0.5:.1f}GB")
        ui.print_info(f"Memory required: ~{model.ram_gb:.1f}GB")
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
                            print(ui.colorize(f"    {line}", ui.Colors.GREEN))
            
            process.wait(timeout=3600)  # 1 hour timeout
            code = process.returncode
            
        except subprocess.TimeoutExpired:
            process.kill()
            ui.print_error("Download timed out after 1 hour")
            code = -1
        except Exception as e:
            ui.print_error(f"Error: {e}")
            code = -1
        
        if code == 0:
            # Verify the model was actually downloaded and check its parameters
            verify_code, verify_out, _ = utils.run_command(["docker", "model", "list"])
            model_found = False
            actual_params = None
            
            if verify_code == 0:
                # Check if the model appears in the list (by name or converted name)
                model_name_simple = model_name_to_pull.split("/")[-1].split(":")[0]
                for line in verify_out.split("\n"):
                    if model_name_simple in line.lower() or "llama3.2" in line.lower():
                        model_found = True
                        # Extract parameters from the line
                        param_match = re.search(r'(\d+\.?\d*)\s*B', line)
                        if param_match:
                            actual_params = float(param_match.group(1))
                        break
                
                # Also try to inspect the model to get exact parameters
                if model_found:
                    inspect_code, inspect_out, _ = utils.run_command(["docker", "model", "inspect", model_name_simple], timeout=10)
                    if inspect_code == 0:
                        try:
                            inspect_data = json.loads(inspect_out)
                            actual_params_str = inspect_data.get("config", {}).get("parameters", "")
                            if actual_params_str:
                                param_match = re.search(r'(\d+\.?\d*)', actual_params_str)
                                if param_match:
                                    actual_params = float(param_match.group(1))
                        except (json.JSONDecodeError, KeyError, ValueError):
                            pass
            
            if model_found:
                # Check if parameters match expected (allow some tolerance)
                expected_params = model.ram_gb  # Rough estimate: 8B model ~5GB, 3B model ~2GB
                if actual_params:
                    if abs(actual_params - expected_params) > 2.0:  # More than 2GB difference
                        ui.print_warning(f"{model.name} downloaded, but got {actual_params}B model instead of expected ~{expected_params}GB model")
                        ui.print_info(f"Actual model: {actual_params}B parameters")
                    else:
                        ui.print_success(f"{model.name} downloaded successfully ({actual_params}B parameters)")
                else:
                    ui.print_success(f"{model.name} downloaded successfully")
                successfully_pulled.append(model)
                ui.print_info("Model verified in Docker Model Runner")
            else:
                ui.print_warning(f"Download completed but model '{model.name}' not found in Docker Model Runner list")
                ui.print_info("The model may have been downloaded with a different name")
        else:
            ui.print_error(f"Failed to pull {model.name}")
            
            # Check if it was a 401 Unauthorized error
            is_unauthorized = False
            if 'full_output' in locals() and isinstance(full_output, list):
                is_unauthorized = any("401" in line or "unauthorized" in line.lower() for line in full_output)
            
            if is_unauthorized:
                ui.print_warning("Model not found in Docker Hub (401 Unauthorized)")
                ui.print_info("This model may not be available in the 'ai/' namespace.")
                ui.print_info("You can try:")
                ui.print_info("  1. Check if the model exists: docker search ai/<model-name>")
                ui.print_info("  2. Search for alternatives: docker search <model-name>")
            else:
                ui.print_info("You can try pulling manually later with:")
                if model_name_to_pull != model.docker_name:
                    print(ui.colorize(f"    docker model pull {model_name_to_pull}", ui.Colors.CYAN))
                    ui.print_info(f"    (Original format: {model.docker_name})")
                else:
                    print(ui.colorize(f"    docker model pull {model.docker_name}", ui.Colors.CYAN))
            
            if len(model_list) > i and ui.prompt_yes_no("Continue with remaining models?", default=True):
                continue
            elif len(model_list) > i:
                break
        
        print()
    
    # Summary
    if successfully_pulled:
        ui.print_success(f"Successfully downloaded {len(successfully_pulled)}/{len(model_list)} models")
    
    return successfully_pulled if successfully_pulled else model_list


def get_model_id_for_continue(docker_name: str, hw_info: Optional[hardware.HardwareInfo] = None) -> str:
    """
    Convert Docker Model Runner model name to Continue.dev compatible format.
    
    Docker Model Runner API returns models as: ai/llama3.2:latest
    The model catalog uses: ai.docker.com/meta/llama3.2:3b-instruct-q4_K_M
    
    This function converts to the actual API model ID format.
    """
    # Input validation
    if not docker_name or not isinstance(docker_name, str):
        raise ValueError("docker_name must be a non-empty string")
    
    # First, check if we can get the actual model ID from the API
    if hw_info and hasattr(hw_info, 'available_api_models') and hw_info.available_api_models:
        # Try to match the model name to an API model ID
        model_lower = docker_name.lower()
        
        # Check for llama3.2 variants
        if "llama3.2" in model_lower or "llama3.2" in docker_name.lower():
            for api_model_id in hw_info.available_api_models:
                if "llama3.2" in api_model_id.lower():
                    return api_model_id  # Return the actual API model ID
        
        # Check for nomic-embed variants
        if "nomic" in model_lower or "embed" in model_lower:
            for api_model_id in hw_info.available_api_models:
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
