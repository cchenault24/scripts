"""
Continue.dev configuration generation.

Provides functions to generate Continue.dev config.yaml and config.json files.
"""

import hashlib
import json
import logging
import os
import subprocess
import sys
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Union

from . import hardware
from . import models
from . import ui

# Module logger for error reporting
_logger = logging.getLogger(__name__)


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


def ensure_vpn_resilient_url(url: str) -> str:
    """
    Ensure URL uses 127.0.0.1 instead of localhost for VPN resilience.
    
    VPNs can modify DNS resolution and break localhost connections.
    Using the IP address directly bypasses DNS.
    
    Args:
        url: URL that may contain 'localhost'
    
    Returns:
        URL with 'localhost' replaced by '127.0.0.1'
    """
    return url.replace("://localhost:", "://127.0.0.1:").replace("://localhost/", "://127.0.0.1/")


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
    model_list: List[Any],  # Accepts ModelInfo or RecommendedModel
    hw_info: hardware.HardwareInfo
) -> Dict[str, Any]:
    """
    Generate setup summary with models and RAM usage.
    
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
        # Handle both ModelInfo and RecommendedModel objects
        selected_variant = getattr(model, 'selected_variant', None)
        context_length = getattr(model, 'context_length', 131072)  # Default matches GPT-OSS 20B
        roles = getattr(model, 'roles', ["chat"])  # Fallback for safety
        
        models_summary.append({
            "name": model.name,
            "docker_name": model.docker_name,
            "variant": selected_variant or "default",
            "ram_gb": model.ram_gb,
            "roles": roles,
            "context_length": context_length
        })
    
    summary = {
        "hardware": {
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
    model_list: List[Any],  # Accepts ModelInfo or RecommendedModel
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
    model_list: List[Any],  # Accepts ModelInfo or RecommendedModel
    hw_info: hardware.HardwareInfo,
    output_path: Optional[Path] = None,
    target_ide: Optional[List[str]] = None
) -> Path:
    """
    Generate continue.dev config files.
    
    Args:
        model_list: List of selected models
        hw_info: Hardware information
        output_path: Optional output path (default: ~/.continue/config.yaml)
        target_ide: List of IDEs to configure (e.g., ["vscode"], ["intellij"], or ["vscode", "intellij"])
                   Defaults to ["vscode"] for backward compatibility.
                   If "intellij" only, skips YAML generation (IntelliJ doesn't use YAML).
    
    Returns:
        Path to saved config file (YAML if VS Code, JSON if IntelliJ only)
    """
    # Input validation
    if not model_list:
        raise ValueError("model_list cannot be empty")
    if not hw_info:
        raise ValueError("hw_info is required")
    
    # Default to VS Code for backward compatibility
    if target_ide is None:
        target_ide = ["vscode"]
    
    # Determine if we should generate YAML (VS Code uses YAML, IntelliJ doesn't)
    generate_yaml = "vscode" in target_ide
    
    ui.print_header("📝 Generating Continue.dev Configuration")
    
    # Determine output path based on target IDE
    if output_path is None:
        if generate_yaml:
            output_path = Path.home() / ".continue" / "config.yaml"
        else:
            # IntelliJ only - use JSON path
            output_path = Path.home() / ".continue" / "config.json"
    
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
        backup_path = output_path.with_suffix(f"{output_path.suffix}.backup")
        shutil.copy(output_path, backup_path)
        ui.print_info(f"Backed up existing config to {backup_path}")
    
    # Use the detected API endpoint from hardware info
    api_base = hw_info.dmr_api_endpoint
    ui.print_info(f"Using API endpoint: {api_base}")
    
    # VPN Resilience: Ensure we use 127.0.0.1 instead of localhost
    # VPNs can modify DNS resolution and break localhost connections
    api_base = ensure_vpn_resilient_url(api_base)
    
    # Ensure apiBase doesn't have trailing slash and includes /v1 for OpenAI-compatible API
    # Continue.dev expects the full base URL including /v1 for OpenAI-compatible APIs
    api_base_clean = api_base.rstrip('/')
    # Ensure it includes /v1 if not already present
    if '/v1' not in api_base_clean:
        # If the endpoint doesn't have /v1, we need to determine the correct base
        # For Docker Model Runner, the API is typically at /v1
        if api_base_clean.endswith(':12434') or api_base_clean.endswith(':8080'):
            api_base_clean = f"{api_base_clean}/v1"
        elif 'model-runner.docker.internal' in api_base_clean or '127.0.0.1' in api_base_clean:
            api_base_clean = f"{api_base_clean}/v1" if not api_base_clean.endswith('/v1') else api_base_clean
    
    def _ensure_pyyaml():
        """Ensure PyYAML is installed and importable (best-effort auto-install)."""
        try:
            import yaml  # type: ignore
            return yaml
        except Exception:
            ui.print_info("Installing PyYAML for proper YAML generation...")
            install_commands = [
                [sys.executable, "-m", "pip", "install", "--quiet", "--user", "pyyaml>=6.0"],
                [sys.executable, "-m", "pip", "install", "--quiet", "--break-system-packages", "pyyaml>=6.0"],
                [sys.executable, "-m", "pip", "install", "--quiet", "pyyaml>=6.0"],
            ]
            for cmd in install_commands:
                try:
                    result = subprocess.run(cmd, capture_output=True, timeout=120, text=True)
                    if result.returncode == 0:
                        import yaml  # type: ignore
                        ui.print_success("PyYAML installed")
                        return yaml
                except Exception:
                    continue
            raise RuntimeError("PyYAML is required but could not be installed automatically")

    def _atomic_write_text(path: Path, content: str) -> None:
        """Atomic write with fsync + replace."""
        tmp_path = path.with_suffix(f"{path.suffix}.tmp")
        with open(tmp_path, "w", encoding="utf-8") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        tmp_path.replace(path)

    def _atomic_write_json(path: Path, obj: Dict[str, Any]) -> None:
        tmp_path = path.with_suffix(f"{path.suffix}.tmp")
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(obj, f, indent=2)
            f.flush()
            os.fsync(f.fileno())
        tmp_path.replace(path)

    def _migrate_context_length_to_root(model_cfg: Dict[str, Any]) -> None:
        """
        Migration: move model.defaultCompletionOptions.contextLength -> model.contextLength
        Remove defaultCompletionOptions if empty afterwards.
        """
        dco = model_cfg.get("defaultCompletionOptions")
        if isinstance(dco, dict) and "contextLength" in dco and "contextLength" not in model_cfg:
            model_cfg["contextLength"] = dco.get("contextLength")
            dco.pop("contextLength", None)
            if not dco:
                model_cfg.pop("defaultCompletionOptions", None)

    # Dynamic context sizing (based on Docker RAM allocation, if available)
    dynamic_ctx = hw_info.dmr_context_size_tokens if hw_info and hw_info.dmr_context_size_tokens else None
    if dynamic_ctx:
        ui.print_info(f"Using dynamic contextLength={dynamic_ctx} tokens for Continue config")
        if hw_info.dmr_context_reason:
            ui.print_info(f"Reason: {hw_info.dmr_context_reason}")
    
    # Find models by role
    chat_models = [m for m in model_list if "chat" in m.roles or "edit" in m.roles]
    autocomplete_models = [m for m in model_list if "autocomplete" in m.roles]
    embed_models = [m for m in model_list if "embed" in m.roles]
    
    # Sort chat models by RAM (largest first = highest quality)
    chat_models.sort(key=lambda m: m.ram_gb, reverse=True)
    
    # Sort autocomplete models by RAM (smallest first = fastest)
    autocomplete_models.sort(key=lambda m: m.ram_gb)
    
    def _effective_context_length(model_ctx: int) -> int:
        """Use Docker-RAM-based context sizing, capped by model's max context."""
        if not dynamic_ctx:
            return model_ctx
        try:
            return int(min(int(model_ctx), int(dynamic_ctx)))
        except Exception:
            return model_ctx

    # Build YAML config (dict) using proper YAML serialization (no string replacement)
    yaml_config: Dict[str, Any] = {
        "name": "Docker Model Runner Local LLM",
        "version": "1.0.0",
        "models": [],
        "context": [
            {"provider": "codebase"},
            {"provider": "folder"},
            {"provider": "file"},
            {"provider": "code"},
            {"provider": "terminal"},
            {"provider": "diff"},
            {"provider": "problems"},
            {"provider": "open"},
        ],
    }

    for model in chat_models:
        model_id = models.get_model_id_for_continue(model, hw_info)
        roles = ["chat", "edit", "apply"]
        if "autocomplete" in model.roles:
            roles.append("autocomplete")
        if "embed" in model.roles:
            roles.append("embed")

        model_cfg: Dict[str, Any] = {
            "name": model.name,
            "provider": "openai",
            "model": model_id,
            "apiBase": api_base_clean,
            # Migration target: contextLength must be at model root level
            "contextLength": _effective_context_length(model.context_length),
            "roles": roles,
        }

        if "autocomplete" in model.roles:
            model_cfg["autocompleteOptions"] = {
                "debounceDelay": 300,
                "modelTimeout": 3000,
            }

        _migrate_context_length_to_root(model_cfg)
        yaml_config["models"].append(model_cfg)
    
    # Add autocomplete models (with autocompleteOptions)
    autocomplete_only = [m for m in autocomplete_models if m not in chat_models]
    for model in autocomplete_only:
        model_id = models.get_model_id_for_continue(model, hw_info)
        model_cfg = {
            "name": f"{model.name} (Autocomplete)",
            "provider": "openai",
            "model": model_id,
            "apiBase": api_base_clean,
            "roles": ["autocomplete"],
            "autocompleteOptions": {
                "debounceDelay": 300,
                "modelTimeout": 3000,
            },
            "contextLength": _effective_context_length(model.context_length),
        }
        _migrate_context_length_to_root(model_cfg)
        yaml_config["models"].append(model_cfg)
    
    # Add embedding models (if different from chat and autocomplete models)
    embed_only = [m for m in embed_models if m not in chat_models and m not in autocomplete_models]
    for model in embed_only:
        model_id = models.get_model_id_for_continue(model, hw_info)
        model_cfg = {
            "name": f"{model.name} (Embedding)",
            "provider": "openai",
            "model": model_id,
            "apiBase": api_base_clean,
            "roles": ["embed"],
            "contextLength": _effective_context_length(model.context_length),
        }
        _migrate_context_length_to_root(model_cfg)
        yaml_config["models"].append(model_cfg)
    
    # Note: 'experimental' and 'ui' are NOT in the official schema and cause validation errors
    # The schema has additionalProperties: false, so only explicitly defined properties are allowed
    # These settings were removed to comply with the schema validation
    
    # Write YAML config (only if VS Code is in target_ide)
    if generate_yaml:
        yaml = _ensure_pyyaml()
        try:
            yaml_content = yaml.safe_dump(
                yaml_config,
                sort_keys=False,
                default_flow_style=False,
                allow_unicode=True,
            )
            _atomic_write_text(output_path, yaml_content)
            ui.print_success(f"Configuration saved to {output_path}")
        except Exception as e:
            ui.print_error(f"Failed to write YAML config: {e}")
            # Roll back to backup if available
            if output_path.exists():
                backup_path = output_path.with_suffix(f"{output_path.suffix}.backup")
                if backup_path.exists():
                    shutil.copy(backup_path, output_path)
                    ui.print_warning(f"Rolled back to backup: {backup_path}")
            raise
    
    # Always create JSON version (works for both VS Code and IntelliJ)
    if generate_yaml:
        json_path = output_path.parent / "config.json"
    else:
        # IntelliJ only - use the output_path for JSON
        json_path = output_path
    
    # Build JSON config (using new schema format)
    # Note: 'name' and 'version' are REQUIRED fields per the Continue.dev config schema (config-yaml-schema.json)
    json_config: Dict[str, Any] = {
        "name": "Docker Model Runner Local LLM",
        "version": "1.0.0",
        "models": [],
        "context": yaml_config.get("context", []),
    }
    
    for model in chat_models:
        model_id = models.get_model_id_for_continue(model, hw_info)
        # Only valid roles per schema: chat, autocomplete, embed, rerank, edit, apply, summarize
        # Note: "agent" is not in the schema's role enum, so we don't include it
        roles = ["chat", "edit", "apply"]
        if "autocomplete" in model.roles:
            roles.append("autocomplete")
        if "embed" in model.roles:
            roles.append("embed")
        
        model_config: Dict[str, Any] = {
            "name": model.name,
            "provider": "openai",
            "model": model_id,
            "apiBase": api_base_clean,
            "contextLength": _effective_context_length(model.context_length),
            "roles": roles,
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
            "contextLength": _effective_context_length(model.context_length),
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
            "contextLength": _effective_context_length(model.context_length),
        })
    
    # Note: 'experimental' and 'ui' are NOT in the official schema and cause validation errors
    # The schema has additionalProperties: false, so only explicitly defined properties are allowed
    # These settings were removed to comply with the schema validation
    
    # Remove any defaultCompletionOptions left by older code paths (defensive)
    for m in json_config.get("models", []):
        if isinstance(m, dict):
            _migrate_context_length_to_root(m)

    try:
        # Backup existing JSON if present
        if json_path.exists():
            backup_json = json_path.with_suffix(f"{json_path.suffix}.backup")
            shutil.copy(json_path, backup_json)
            ui.print_info(f"Backed up existing JSON config to {backup_json}")
        _atomic_write_json(json_path, json_config)
    except Exception as e:
        ui.print_error(f"Failed to write JSON config: {e}")
        # Roll back to backup if available
        backup_json = json_path.with_suffix(f"{json_path.suffix}.backup")
        if backup_json.exists():
            shutil.copy(backup_json, json_path)
            ui.print_warning(f"Rolled back JSON to backup: {backup_json}")
        raise
    
    if generate_yaml:
        ui.print_info(f"JSON config also saved to {json_path}")
    else:
        ui.print_success(f"Configuration saved to {json_path}")
        # Return JSON path for IntelliJ-only case
        return json_path
    
    return output_path


def generate_codebase_rules(output_path: Optional[Path] = None) -> Path:
    """
    Generate Continue.dev codebase awareness rules file for Agent mode.
    
    This complements the legacy @Codebase embedding-based search by providing
    structured context that Agent mode can use to understand the project.
    
    Args:
        output_path: Optional output path (default: ~/.continue/rules/codebase-context.md)
    
    Returns:
        Path to saved rules file
    """
    ui.print_subheader("📝 Generating Codebase Awareness Rules")
    
    if output_path is None:
        output_path = Path.home() / ".continue" / "rules" / "codebase-context.md"
    
    # Create directory if needed
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Backup existing file if present
    if output_path.exists():
        backup_path = output_path.with_suffix(".md.backup")
        shutil.copy(output_path, backup_path)
        ui.print_info(f"Backed up existing rules to {backup_path}")
    
    rules_content = """# Codebase Context

This file helps Continue's Agent mode understand your codebase.
Edit this file to provide project-specific context for better AI assistance.

## Project Structure

<!-- Describe your project's key directories and their purposes -->
Example:
- `/src` - Main source code
- `/tests` - Test files
- `/docs` - Documentation
- `/config` - Configuration files

## Key Technologies

<!-- List the main technologies, frameworks, and patterns used -->
Example:
- Language: Python 3.11+
- Framework: FastAPI / Django / Flask
- Database: PostgreSQL / MongoDB
- Key Libraries: pandas, numpy, requests

## Coding Standards

<!-- Describe your team's coding conventions -->
Example:
- Follow PEP 8 for Python code
- Use type hints for all functions
- Write docstrings for public APIs
- Maintain test coverage above 80%

## Architecture Patterns

<!-- Document architectural decisions and patterns -->
Example:
- MVC architecture with service layer
- Repository pattern for data access
- Event-driven for async operations
- Microservices with REST APIs

## Common Tasks

<!-- List frequent development tasks and how to do them -->
Example:
- Adding new endpoints: Create in `/src/api/routes/`
- Database migrations: Use `alembic revision --autogenerate`
- Running tests: `pytest tests/`
- Building: `docker-compose build`

## Important Context

<!-- Add any other context that helps AI understand your code -->
Example:
- Authentication is handled by JWT tokens in `/src/auth/`
- Configuration uses environment variables (see `.env.example`)
- Logging follows structured logging with JSON output
- API documentation auto-generated from OpenAPI specs

---

## How This Works

**Agent Mode** (New approach - Recommended):
- Agent mode reads this file automatically
- Uses the context to make better suggestions
- No indexing required - works immediately
- Best for: Complex tasks, architectural questions, multi-file changes

**@Codebase Search** (Legacy approach - Still works):
- Uses embedding models for semantic search
- Type `@Codebase` or `@Folder` in chat
- Best for: "Find all code related to X" queries
- Requires: Embedding model (already configured)

**💡 Pro Tip**: Use both! Agent mode for planning, @Codebase for discovery.

---

📝 **Edit this file** to match your actual project structure and conventions.
The more specific you are, the better Agent mode will understand your codebase.
"""
    
    with open(output_path, "w") as f:
        f.write(rules_content)
    
    ui.print_success(f"Codebase awareness rules created at {output_path}")
    ui.print_info("💡 Edit this file to provide context about your project")
    
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


def generate_continueignore(
    output_path: Optional[Path] = None
) -> Path:
    """
    Generate .continueignore file to ignore non-source code files and directories.
    
    Args:
        output_path: Optional output path (default: ~/.continue/.continueignore)
    
    Returns:
        Path to saved .continueignore file
    """
    if output_path is None:
        # Default to ~/.continue/.continueignore (Continue.dev configuration directory)
        output_path = Path.home() / ".continue" / ".continueignore"
    
    # Create directory if needed
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Backup existing .continueignore if present
    if output_path.exists():
        backup_path = output_path.with_suffix(".continueignore.backup")
        shutil.copy(output_path, backup_path)
        ui.print_info(f"Backed up existing .continueignore to {backup_path}")
    
    # Generate .continueignore content
    ignore_content = """# Version control
.git/
.svn/
.hg/
.gitignore
.gitattributes

# Python cache and compiled files
__pycache__/
*.py[cod]
*$py.class
*.so
*.egg
*.egg-info/
dist/
dist
build/
*.whl
.python-version
*.pyc
*.pyo
*.pyd

# Node.js and JavaScript
node_modules/
node_modules
bower_components
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.pnpm-debug.log*
.yarn/
.pnp.*
.yarn/cache
.yarn/unplugged
.yarn/build-state.yml
.yarn/install-state.gz
.yarn-dev-pid
.pnp.js
.next/
.nuxt/
.output/
.turbo/
.parcel-cache/
.cache/
.eslintcache
.stylelintcache

# Java and JVM languages
target/
.gradle/
.gradle_home
.mvn/
*.class
*.jar
*.war
*.ear
*.nar
*.hprof

# Go
vendor/
*.exe
*.exe~
*.dll
*.so
*.dylib

# Rust
target/
Cargo.lock

# PHP
vendor/
composer.lock

# Ruby
vendor/bundle/
vendor/bundle
.bundle/
*.gem
*.rbc
.byebug_history

# Virtual environments
venv/
.venv/
env/
ENV/
.ENV/
.conda/

# IDE and editor files
.vscode/
.idea/
**/.idea
.theia
*.swp
*.swo
*~
.project
*.project
.pydevproject
*.iml
*.classpath
*.classpath.txt
.settings/
.metadata
.recommenders
*.sublime-project
*.sublime-workspace
*.code-workspace

# OS files
.DS_Store
*.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db
Desktop.ini
$RECYCLE.BIN/

# Testing and coverage
.coverage
.coverage.*
htmlcov/
.pytest_cache/
.tox/
.hypothesis/
.nyc_output/
coverage/
*.lcov
.jest/
reports
screenshots
public/screenshots
task-*.json

# Logs and temporary files
*.log
*.tmp
*.temp
*.bak
*.backup
*.hash
tmp/
temp/
temp/*
.tmp/
/log/*
/tmp/*
/tmp/pids/*

# Documentation builds
docs/_build/
site/
_book/
.docusaurus/

# Jupyter Notebook
.ipynb_checkpoints
*.ipynb_checkpoints

# Environment variables
.env
.env.bundle
.env.local
.env.*.local
.envrc

# Build and output directories
out/
output/
bin/
obj/
lib/
libs/
*.a
*.o
*.dylib
*.dll
public/assets
buildinfo

# Package manager locks and caches
package-lock.json
yarn.lock
pnpm-lock.yaml
composer.lock
Pipfile.lock
poetry.lock
Gemfile.lock
Podfile.lock

# Framework-specific
.sass-cache/
.angular/
.vuepress/dist/
.serverless/
.aws-sam/
.terraform/
.terraform.lock.hcl
.terraform.tfstate*
terraform.tfstate*
*.tfstate
*.tfstate.*
*.tfvars
vars.json

# Database files
*.db
*.sqlite
*.sqlite3
*.db-journal
database.*
database1.*
db/*.sqlite3
db/*.sqlite3-journal
db/development.*
db/*.zip
*.trace.db

# Compiled assets
*.min.js
*.min.css
*.css
*.html
*.js
*.map
assets/dist/
public/dist/
static/dist/

# Container and VM files
.vagrant
.containerid
.pongo/.bash_history

# Generated and cache files
.repository/.cache/*
**/*.lastUpdated
luacov.stats.out
luacov.report.out
servroot

# Certificates and keys
*.pfx
*.crt
*.key
certificates/
keystores/
ssl/

# Miscellaneous
audio
images
backup
help
tags
"""
    
    # Write .continueignore
    with open(output_path, "w") as f:
        f.write(ignore_content)
    
    ui.print_success(f".continueignore file saved to {output_path}")
    
    return output_path


# =============================================================================
# Manifest and Fingerprinting Functions
# =============================================================================

# Version for fingerprinting
INSTALLER_VERSION = "2.0.0"

# Fingerprint header for generated files
FINGERPRINT_COMMENT = f"# Generated by docker-llm-setup.py v{INSTALLER_VERSION}"


def _get_utc_timestamp() -> str:
    """Get current UTC timestamp in ISO format."""
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).isoformat()


def calculate_file_hash(filepath: Path) -> str:
    """Calculate SHA-256 hash of a file for fingerprinting."""
    import hashlib
    if not filepath.exists():
        return ""
    
    try:
        with open(filepath, 'rb') as f:
            return hashlib.sha256(f.read()).hexdigest()
    except (OSError, IOError, PermissionError):
        return ""


def classify_file_type(filepath: Path) -> str:
    """Classify a file by its type for manifest."""
    suffix = filepath.suffix.lower()
    name = filepath.name.lower()
    
    if suffix in ('.yaml', '.yml'):
        return 'config_yaml'
    elif suffix == '.json':
        if 'manifest' in name:
            return 'manifest'
        elif 'summary' in name:
            return 'summary'
        return 'config_json'
    elif suffix == '.md':
        return 'rule'
    elif name == '.continueignore':
        return 'ignore'
    elif suffix == '.backup':
        return 'backup'
    else:
        return 'other'


def add_fingerprint_header(content: str, file_type: str) -> str:
    """Add fingerprint header to generated files."""
    timestamp = _get_utc_timestamp()
    
    if file_type in ("yaml", "yml", "md", "ignore"):
        header = f"""{FINGERPRINT_COMMENT}
# Timestamp: {timestamp}
# DO NOT EDIT MANUALLY - This file is managed by docker-llm-setup
# To customize, use the setup script's customization options

"""
        return header + content
    
    return content


def add_fingerprint_to_json(data: Dict[str, Any]) -> Dict[str, Any]:
    """Add fingerprint metadata to a JSON object."""
    data["_metadata"] = {
        "generator": f"docker-llm-setup.py v{INSTALLER_VERSION}",
        "timestamp": _get_utc_timestamp(),
        "warning": "DO NOT EDIT MANUALLY - This file is managed by docker-llm-setup"
    }
    return data


def _normalize_model_name_for_comparison(model_name: str) -> str:
    """Normalize model name for comparison (handles tags)."""
    if not model_name:
        return ""
    
    if ":" in model_name:
        base, tag = model_name.split(":", 1)
        tag_parts = tag.split("-")
        if tag_parts:
            normalized_tag = tag_parts[0]
            return f"{base}:{normalized_tag}"
    return model_name


def _models_overlap(model1: str, model2: str) -> bool:
    """Check if two model names refer to the same model."""
    norm1 = _normalize_model_name_for_comparison(model1)
    norm2 = _normalize_model_name_for_comparison(model2)
    return norm1 == norm2


def _normalize_model(model: Any) -> Dict[str, Any]:
    """Normalize a model to a common dictionary format."""
    # Try to import RecommendedModel type
    try:
        from .model_selector import RecommendedModel
        if isinstance(model, RecommendedModel):
            return {
                "name": model.name,
                "docker_name": model.docker_name,
                "ram_gb": model.ram_gb,
                "roles": model.roles,
                "context_length": model.context_length,
            }
    except ImportError:
        pass
    
    # Handle old ModelInfo format
    if hasattr(model, 'docker_name'):
        return {
            "name": model.name,
            "docker_name": model.docker_name,
            "ram_gb": model.ram_gb,
            "roles": getattr(model, 'roles', ["chat"]),
            "context_length": getattr(model, 'context_length', 131072),
        }
    
    # Handle dictionary format
    if isinstance(model, dict):
        return model
    
    raise ValueError(f"Unknown model type: {type(model)}")


def create_installation_manifest(
    installed_models: List[Any],
    created_files: List[Path],
    hw_info: 'hardware.HardwareInfo',
    target_ide: List[str],
    pre_existing_models: List[str]
) -> Path:
    """
    Create manifest of what was installed for uninstaller.
    """
    # Normalize models and filter out any that overlap with pre-existing
    normalized_models = []
    for m in installed_models:
        model_dict = _normalize_model(m)
        model_name = model_dict["docker_name"]
        
        overlaps = False
        for pre_existing_name in pre_existing_models:
            if _models_overlap(model_name, pre_existing_name):
                overlaps = True
                break
        
        if not overlaps:
            normalized_models.append({
                "name": model_name,
                "display_name": model_dict["name"],
                "size_gb": model_dict["ram_gb"],
                "pulled_at": _get_utc_timestamp(),
                "roles": model_dict["roles"]
            })
    
    # Create file entries with fingerprints
    file_entries = []
    for f in created_files:
        if f.exists():
            file_entries.append({
                "path": str(f),
                "fingerprint": calculate_file_hash(f),
                "type": classify_file_type(f),
                "created_at": _get_utc_timestamp()
            })
    
    # Backup file paths
    continue_dir = Path.home() / ".continue"
    backup_files = {
        "config_yaml": str(continue_dir / "config.yaml.backup"),
        "config_json": str(continue_dir / "config.json.backup"),
        "global_rule": str(continue_dir / "rules" / "global-rule.md.backup")
    }
    
    # Check which backups actually exist
    existing_backups = {
        k: v for k, v in backup_files.items() 
        if Path(v).exists()
    }
    
    manifest = {
        "version": "2.0",
        "timestamp": _get_utc_timestamp(),
        "installer_version": INSTALLER_VERSION,
        "installer_type": "docker",
        "hardware_snapshot": {
            "ram_gb": hw_info.ram_gb,
            "cpu": hw_info.cpu_brand or "Unknown",
            "apple_chip": hw_info.apple_chip_model,
            "has_apple_silicon": hw_info.has_apple_silicon
        },
        "pre_existing": {
            "models": pre_existing_models,
            "backups": existing_backups
        },
        "installed": {
            "models": normalized_models,
            "files": file_entries,
            "cache_dirs": [str(continue_dir / "cache")],
            "ide_extensions": [f"{ide}:Continue.continue" for ide in target_ide],
            "docker_model_runner_available": getattr(hw_info, 'docker_model_runner_available', False),
            "target_ides": target_ide
        }
    }
    
    manifest_path = continue_dir / "setup-manifest.json"
    
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    
    with open(manifest_path, 'w') as f:
        json.dump(manifest, f, indent=2)
    
    ui.print_success(f"Installation manifest saved to {manifest_path}")
    
    return manifest_path


def load_installation_manifest() -> Optional[Dict[str, Any]]:
    """Load the installation manifest if it exists."""
    manifest_path = Path.home() / ".continue" / "setup-manifest.json"
    
    if not manifest_path.exists():
        return None
    
    try:
        with open(manifest_path, 'r') as f:
            return json.load(f)
    except json.JSONDecodeError:
        return None
    except (OSError, IOError, PermissionError):
        return None


def is_our_file(filepath: Path, manifest: Optional[Dict[str, Any]] = None) -> Union[bool, str]:
    """Check if file was created by our installer."""
    from typing import Union
    
    if not filepath.exists():
        return False
    
    # Check in manifest
    if manifest:
        manifest_files = manifest.get("installed", {}).get("files", [])
        for entry in manifest_files:
            if entry.get("path") == str(filepath):
                current_hash = calculate_file_hash(filepath)
                if current_hash == entry.get("fingerprint"):
                    return True
                else:
                    return "maybe"
    
    # Check for fingerprint header
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            first_lines = "".join([f.readline() for _ in range(5)])
            if "Generated by docker-llm-setup.py" in first_lines:
                return True
    except (OSError, IOError, UnicodeDecodeError, PermissionError):
        pass
    
    return False


def check_config_customization(config_path: Path, manifest: Optional[Dict[str, Any]] = None) -> str:
    """Check if user customized config file."""
    if not config_path.exists():
        return "missing"
    
    if not manifest:
        status = is_our_file(config_path)
        if status is True:
            return "unchanged"
        elif status == "maybe":
            return "modified"
        return "unknown"
    
    config_entry = None
    for file_entry in manifest.get("installed", {}).get("files", []):
        if file_entry.get("path") == str(config_path):
            config_entry = file_entry
            break
    
    if not config_entry:
        return "unknown"
    
    current_hash = calculate_file_hash(config_path)
    if current_hash != config_entry.get("fingerprint"):
        return "modified"
    
    return "unchanged"
