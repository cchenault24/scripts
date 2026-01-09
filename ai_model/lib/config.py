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
    
    # Build config with comments
    # Note: 'name' and 'version' are required for backward compatibility with older Continue.dev extension versions (e.g., v1.2.11)
    # The 'schema' field is NOT included as it's not part of the official schema
    yaml_lines = [
        "# Continue.dev Configuration for Docker Model Runner",
        "# Generated by docker-llm-setup.py",
        f"# Hardware: {hw_info.apple_chip_model or hw_info.cpu_brand}",
        f"# RAM: {hw_info.ram_gb:.0f}GB | Tier: {hw_info.tier.value}",
        "#",
        "# Documentation: https://docs.continue.dev/yaml-reference",
        "",
        "name: Docker Model Runner Local LLM",
        "version: 1.0.0",
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
    # YAML indentation rules:
    # - Top-level keys: no indentation
    # - List items under a key: 2 spaces then dash
    # - Properties of list items: 4 spaces
    # - Nested list items: 6 spaces then dash
    # - Nested properties: 6 spaces
    yaml_lines.append("models:")
    
    for i, model in enumerate(chat_models):
        model_id = models.get_model_id_for_continue(model, hw_info)
        # Model list item: 2 spaces before dash, 4 spaces for properties
        yaml_lines.extend([
            f"  - name: {model.name}",
            f"    provider: openai",
            f"    model: {model_id}",
            f"    apiBase: {api_base_clean}",
        ])
        
        # Add roles
        roles = ["chat", "edit", "apply"]
        if "agent" in model.roles:
            roles.append("agent")
        if "autocomplete" in model.roles:
            roles.append("autocomplete")
        if "embed" in model.roles:
            roles.append("embed")
        # Roles property: 4 spaces, nested list items: 6 spaces before dash
        yaml_lines.append("    roles:")
        for role in roles:
            yaml_lines.append(f"      - {role}")
        
        # Add autocompleteOptions if model has autocomplete role
        if "autocomplete" in model.roles:
            # autocompleteOptions property: 4 spaces, nested properties: 6 spaces
            yaml_lines.extend([
                "    autocompleteOptions:",
                "      debounceDelay: 300",
                "      modelTimeout: 3000",
            ])
        
        # Add defaultCompletionOptions with contextLength
        # defaultCompletionOptions property: 4 spaces, nested properties: 6 spaces
        yaml_lines.extend([
            "    defaultCompletionOptions:",
            f"      contextLength: {model.context_length}",
        ])
        
        # Disable native tool calling to fix @codebase compatibility
        # Let Continue.dev handle @codebase with system message tools instead
        yaml_lines.append("    supportsToolCalls: false")
        
        yaml_lines.append("")
    
    # Add autocomplete models (with autocompleteOptions)
    # Same indentation rules: 2 spaces before dash, 4 spaces for properties, 6 spaces for nested items
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
            "    autocompleteOptions:",
            "      debounceDelay: 300",
            "      modelTimeout: 3000",
            "    defaultCompletionOptions:",
            f"      contextLength: {model.context_length}",
            "    supportsToolCalls: false",
            "",
        ])
    
    # Add embedding models (if different from chat and autocomplete models)
    # Same indentation rules: 2 spaces before dash, 4 spaces for properties, 6 spaces for nested items
    embed_only = [m for m in embed_models if m not in chat_models and m not in autocomplete_models]
    for model in embed_only:
        model_id = models.get_model_id_for_continue(model, hw_info)
        yaml_lines.extend([
            f"  - name: {model.name} (Embedding)",
            f"    provider: openai",
            f"    model: {model_id}",
            f"    apiBase: {api_base_clean}",
            "    roles:",
            "      - embed",
            "    defaultCompletionOptions:",
            f"      contextLength: {model.context_length}",
            "    supportsToolCalls: false",
            "",
        ])
    
    # Context providers (using new schema format)
    yaml_lines.extend([
        "# Context providers for code understanding",
        "# Note: contextProviders is deprecated, use 'context' instead",
        "context:",
        "  - provider: codebase",
        "  - provider: folder",
        "  - provider: file",
        "  - provider: code",
        "  - provider: terminal",
        "  - provider: diff",
        "  - provider: problems",
        "  - provider: open",
        "",
    ])
    
    # Experimental settings (extension-specific, not in official schema)
    # These may still work but are not documented in the official schema
    yaml_lines.extend([
        "# Experimental settings (extension-specific)",
        "# Note: These settings are not in the official schema but may still be supported",
        "# streamAfterToolRejection: prevents model from stopping mid-response if it tries to use a tool inappropriately",
        "# Note: codebaseUseToolCallingOnly removed - using supportsToolCalls: false on models instead",
        "experimental:",
        "  streamAfterToolRejection: true",
        "",
    ])
    
    # UI settings (extension-specific, not in official schema)
    # These may still work but are not documented in the official schema
    yaml_lines.extend([
        "# UI settings (extension-specific)",
        "# Note: These settings are not in the official schema but may still be supported",
        "# Improves readability and disables unnecessary features like TTS",
        "ui:",
        "  showChatScrollbar: true",
        "  wrapCodeblocks: true",
        "  formatMarkdown: true",
        "  textToSpeechOutput: false",
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
    
    # Build JSON config (using new schema format)
    # Note: 'name' and 'version' are required for backward compatibility with older Continue.dev extension versions
    json_config: Dict[str, Any] = {
        "name": "Docker Model Runner Local LLM",
        "version": "1.0.0",
        "models": []
    }
    
    for model in chat_models:
        model_id = models.get_model_id_for_continue(model, hw_info)
        roles = ["chat", "edit", "apply"]
        if "agent" in model.roles:
            roles.append("agent")
        if "autocomplete" in model.roles:
            roles.append("autocomplete")
        if "embed" in model.roles:
            roles.append("embed")
        
        model_config = {
            "name": model.name,
            "provider": "openai",
            "model": model_id,
            "apiBase": api_base_clean,
            "defaultCompletionOptions": {
                "contextLength": model.context_length,
            },
            "roles": roles,
            "supportsToolCalls": False,
        }
        
        # Add autocompleteOptions if model has autocomplete role
        if "autocomplete" in model.roles:
            model_config["autocompleteOptions"] = {
                "debounceDelay": 300,
                "modelTimeout": 3000,
            }
        
        json_config["models"].append(model_config)
    
    for model in autocomplete_only:
        model_id = models.get_model_id_for_continue(model, hw_info)
        json_config["models"].append({
            "name": f"{model.name} (Autocomplete)",
            "provider": "openai", 
            "model": model_id,
            "apiBase": api_base_clean,
            "roles": ["autocomplete"],
            "autocompleteOptions": {
                "debounceDelay": 300,
                "modelTimeout": 3000,
            },
            "defaultCompletionOptions": {
                "contextLength": model.context_length,
            },
            "supportsToolCalls": False,
        })
    
    # Add embedding models
    embed_only = [m for m in embed_models if m not in chat_models and m not in autocomplete_models]
    for model in embed_only:
        model_id = models.get_model_id_for_continue(model, hw_info)
        json_config["models"].append({
            "name": f"{model.name} (Embedding)",
            "provider": "openai",
            "model": model_id,
            "apiBase": api_base_clean,
            "roles": ["embed"],
            "defaultCompletionOptions": {
                "contextLength": model.context_length,
            },
            "supportsToolCalls": False,
        })
    
    # Context providers (new format)
    json_config["context"] = [
        {"provider": "codebase"},
        {"provider": "folder"},
        {"provider": "file"},
        {"provider": "code"},
        {"provider": "terminal"},
        {"provider": "diff"},
        {"provider": "problems"},
        {"provider": "open"},
    ]
    
    # Experimental and UI settings (extension-specific)
    json_config["experimental"] = {
        "streamAfterToolRejection": True,
    }
    
    json_config["ui"] = {
        "showChatScrollbar": True,
        "wrapCodeblocks": True,
        "formatMarkdown": True,
        "textToSpeechOutput": False,
    }
    
    with open(json_path, "w") as f:
        json.dump(json_config, f, indent=2)
    
    ui.print_info(f"JSON config also saved to {json_path}")
    
    return output_path


def generate_global_rule(
    output_path: Optional[Path] = None
) -> Path:
    """
    Generate Continue.dev global-rule.md file.
    
    Args:
        output_path: Optional output path (default: ~/.continue/rules/global-rule.md)
    
    Returns:
        Path to saved global-rule.md file
    """
    if output_path is None:
        output_path = Path.home() / ".continue" / "rules" / "global-rule.md"
    
    # Create directory if needed
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Backup existing rule if present
    if output_path.exists():
        backup_path = output_path.with_suffix(".md.backup")
        shutil.copy(output_path, backup_path)
        ui.print_info(f"Backed up existing global-rule.md to {backup_path}")
    
    # Generate global-rule.md content
    rule_content = """---
description: Senior-level coding assistant rules for React, TypeScript, Redux, and Material-UI projects
---

CRITICAL RESPONSE RULE: 
- General questions (definitions, explanations, concepts) → Answer ONLY with clear English text
- Code requests (implementation, debugging, refactoring) → Provide code with explanation
- When in doubt, default to English explanation first, then ask if code is needed

DO NOT write code for questions like "What is X?", "How does Y work?", "Explain Z"
ONLY write code when explicitly asked to implement, fix, or create something.

Output Format:
- Respond directly to the question asked
- Do not prefix responses with role labels, agent names, or tool descriptions
- Do not include metadata like "Agent:", "Tool:", "Creating file:", etc.
- Match response type to question type (English for questions, code for implementations)

Act as a senior-level coding assistant with deep expertise in React, TypeScript, Redux, and Material-UI. Provide guidance that reflects industry best practices and production-ready code quality.

This project uses React, TypeScript, Redux, and Material-UI. Always provide context-aware assistance based on these technologies.

Context Handling: Include project-wide context for architectural decisions and patterns. Keep context focused for specific coding tasks to balance comprehensiveness with performance.

Code Review: Apply strict standards by default - flag potential issues, enforce best practices, and point out style inconsistencies. Be adaptive for quick fixes or exploratory work where appropriate. Review code with the rigor expected at senior engineer level.

TypeScript: Balance type safety with practicality. Use type inference where clear, explicit types where needed. Match existing type patterns in the codebase. Avoid `any` type - prefer `unknown` for type-safe alternatives. Use `never` appropriately for exhaustiveness checking and functions that never return. Demonstrate senior-level TypeScript expertise including advanced types when appropriate.

Redux: Always match the existing Redux patterns used in the codebase. Do not suggest alternative patterns. Apply best practices for state management, action creators, and selectors.

Material-UI: Match the existing Material-UI version and component patterns currently used in the codebase. Do not suggest upgrades or newer approaches.

Code Formatting: Always suggest proper formatting based on Prettier/ESLint rules configured in the project.

Dependencies: Prefer native/built-in solutions over external dependencies when reasonable. When external dependencies are needed, match the project's existing dependency patterns. Consider long-term maintenance implications.

Code Review Priority: When reviewing code, prioritize in this order: 1) Security vulnerabilities and bugs, 2) Performance implications, 3) Maintainability and readability, 4) Accessibility compliance. Identify issues a senior engineer would catch.

React Components: Use functional components with hooks for all new code. When reviewing existing class components, only suggest refactoring if explicitly asked to modernize the code or if the class component has hooks-related bugs or limitations. Otherwise, work within the existing component pattern.

Error Handling: Point out missing error handling and edge cases, but don't automatically add it unless explicitly asked. Match the error handling patterns already established in the codebase. Consider production-level error scenarios.

Refactoring: Briefly mention improvement opportunities while staying focused on the main question. Suggest improvements for code quality and bugs, but not for style or preference changes. Think about scalability and maintainability.

Verbosity: Be concise for simple tasks and detailed for complex architectural decisions. Adapt explanation depth based on the complexity of the request. Communicate with the clarity expected between senior engineers.

Testing: Assume testing is handled separately. Do not mention testing considerations unless explicitly asked.

Code Quality: Provide production-ready code that considers edge cases, performance, accessibility, and long-term maintainability. Avoid overly clever solutions in favor of clear, maintainable code.
"""
    
    # Write global-rule.md
    with open(output_path, "w") as f:
        f.write(rule_content)
    
    ui.print_success(f"Global rule file saved to {output_path}")
    
    return output_path
