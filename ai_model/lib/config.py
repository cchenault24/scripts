"""
Continue.dev configuration generation.

Provides functions to generate Continue.dev config.yaml and config.json files.
"""

import json
import shutil
from pathlib import Path
from typing import Any, Dict, List, Optional

from . import hardware
from . import models
from . import ui


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


def generate_setup_summary(
    model_list: List[models.ModelInfo],
    hw_info: hardware.HardwareInfo
) -> Dict[str, Any]:
    """
    Generate setup summary with hardware tier, models, and RAM usage.
    
    Args:
        model_list: List of selected models
        hw_info: Hardware information
    
    Returns:
        Dictionary with setup summary
    """
    total_ram_used = sum(m.ram_gb for m in model_list)
    usable_ram = hw_info.get_estimated_model_memory()
    reserve_ram = usable_ram - total_ram_used
    
    models_summary = []
    for model in model_list:
        models_summary.append({
            "name": model.name,
            "docker_name": model.docker_name,
            "variant": model.selected_variant or "default",
            "ram_gb": model.ram_gb,
            "roles": model.roles,
            "context_length": model.context_length
        })
    
    summary = {
        "hardware": {
            "tier": hw_info.tier.value,
            "ram_gb": hw_info.ram_gb,
            "usable_ram_gb": usable_ram,
            "cpu": hw_info.cpu_brand or "Unknown",
            "apple_chip": hw_info.apple_chip_model or None,
            "has_apple_silicon": hw_info.has_apple_silicon
        },
        "models": models_summary,
        "ram_usage": {
            "total_ram_gb": total_ram_used,
            "available_ram_gb": usable_ram,
            "reserve_ram_gb": reserve_ram,
            "usage_percent": (total_ram_used / usable_ram * 100) if usable_ram > 0 else 0
        },
        "timestamp": str(Path.home() / ".continue" / "setup-summary.json")
    }
    
    return summary


def save_setup_summary(
    model_list: List[models.ModelInfo],
    hw_info: hardware.HardwareInfo,
    output_path: Optional[Path] = None
) -> Path:
    """
    Save setup summary to JSON file.
    
    Args:
        model_list: List of selected models
        hw_info: Hardware information
        output_path: Optional output path (default: ~/.continue/setup-summary.json)
    
    Returns:
        Path to saved summary file
    """
    if output_path is None:
        output_path = Path.home() / ".continue" / "setup-summary.json"
    
    # Create directory if needed
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Generate summary
    summary = generate_setup_summary(model_list, hw_info)
    summary["timestamp"] = str(output_path)
    
    # Save to file
    with open(output_path, "w") as f:
        json.dump(summary, f, indent=2)
    
    ui.print_success(f"Setup summary saved to {output_path}")
    
    return output_path


def generate_continue_config(
    model_list: List[models.ModelInfo],
    hw_info: hardware.HardwareInfo,
    output_path: Optional[Path] = None
) -> Path:
    """Generate continue.dev config.yaml file."""
    # Input validation
    if not model_list:
        raise ValueError("model_list cannot be empty")
    if not hw_info:
        raise ValueError("hw_info is required")
    
    ui.print_header("📝 Generating Continue.dev Configuration")
    
    if output_path is None:
        output_path = Path.home() / ".continue" / "config.yaml"
    
    # Validate output path
    if output_path.parent and not output_path.parent.exists():
        try:
            output_path.parent.mkdir(parents=True, exist_ok=True)
        except (OSError, PermissionError) as e:
            raise ValueError(f"Cannot create config directory: {e}") from e
    
    # Create directory if needed
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Backup existing config if present
    if output_path.exists():
        backup_path = output_path.with_suffix(".yaml.backup")
        shutil.copy(output_path, backup_path)
        ui.print_info(f"Backed up existing config to {backup_path}")
    
    # Use the detected API endpoint from hardware info
    api_base = hw_info.dmr_api_endpoint
    ui.print_info(f"Using API endpoint: {api_base}")
    
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
        f"# Hardware: {hw_info.apple_chip_model or hw_info.cpu_brand}",
        f"# RAM: {hw_info.ram_gb:.0f}GB | Tier: {hw_info.tier.value}",
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
    chat_models = [m for m in model_list if "chat" in m.roles or "edit" in m.roles]
    autocomplete_models = [m for m in model_list if "autocomplete" in m.roles]
    embed_models = [m for m in model_list if "embed" in m.roles]
    
    # Sort chat models by RAM (largest first = highest quality)
    chat_models.sort(key=lambda m: m.ram_gb, reverse=True)
    
    # Sort autocomplete models by RAM (smallest first = fastest)
    autocomplete_models.sort(key=lambda m: m.ram_gb)
    
    # Build models section
    yaml_lines.append("models:")
    
    for i, model in enumerate(chat_models):
        model_id = models.get_model_id_for_continue(model, hw_info)
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
        model_id = models.get_model_id_for_continue(model, hw_info)
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
        model_id = models.get_model_id_for_continue(auto_model.docker_name, hw_info)
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
        model_id = models.get_model_id_for_continue(embed_model.docker_name, hw_info)
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
    
    # Add Apple Silicon specific optimizations
    if hw_info.has_apple_silicon:
        yaml_lines.extend([
            f"# Optimized for {hw_info.apple_chip_model or 'Apple Silicon'}",
            f"# Available unified memory: ~{hw_info.get_estimated_model_memory():.0f}GB",
            "# Metal GPU acceleration is enabled automatically",
            f"# Neural Engine: {hw_info.neural_engine_cores} cores available",
            "# Apple Silicon optimizations:",
            "#   - Metal Performance Shaders (MPS) for GPU acceleration",
            "#   - Unified memory architecture (shared CPU/GPU/NE memory)",
            "#   - Optimized quantization for Apple Silicon",
        ])
    
    # Write YAML config
    yaml_content = "\n".join(yaml_lines)
    
    with open(output_path, "w") as f:
        f.write(yaml_content)
    
    ui.print_success(f"Configuration saved to {output_path}")
    
    # Also create a JSON version for compatibility
    json_path = output_path.parent / "config.json"
    
    # Build JSON config
    json_config: Dict[str, Any] = {"models": []}
    
    for model in chat_models:
        model_id = models.get_model_id_for_continue(model, hw_info)
        json_config["models"].append({
            "name": model.name,
            "provider": "openai",
            "model": model_id,
            "apiBase": api_base_clean,
            "contextLength": model.context_length,
            "roles": ["chat", "edit", "apply"] + (["agent"] if "agent" in model.roles else []),
        })
    
    for model in autocomplete_only:
        model_id = models.get_model_id_for_continue(model, hw_info)
        json_config["models"].append({
            "name": f"{model.name} (Autocomplete)",
            "provider": "openai", 
            "model": model_id,
            "apiBase": api_base_clean,
            "roles": ["autocomplete"],
        })
    
    if autocomplete_models:
        auto_model = autocomplete_models[0]
        model_id = models.get_model_id_for_continue(auto_model.docker_name, hw_info)
        json_config["tabAutocompleteModel"] = {
            "provider": "openai",
            "model": model_id,
            "apiBase": api_base_clean,
        }
    
    if embed_models:
        embed_model = embed_models[0]
        model_id = models.get_model_id_for_continue(embed_model.docker_name, hw_info)
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
    
    ui.print_info(f"JSON config also saved to {json_path}")
    
    return output_path
