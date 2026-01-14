"""
Continue.dev configuration generation with AI fine-tuning support.

Provides functions to generate optimized Continue.dev config files with
model parameters, context optimization, and enhanced global rules.
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Union

from . import hardware
from . import models
from . import tuning
from . import ui


def ensure_vpn_resilient_url(url: str) -> str:
    """Ensure URL uses 127.0.0.1 instead of localhost for VPN resilience."""
    return url.replace("://localhost:", "://127.0.0.1:").replace("://localhost/", "://127.0.0.1/")


def _ensure_pyyaml():
    """Ensure PyYAML is installed and importable."""
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
    """Atomic write JSON with fsync + replace."""
    tmp_path = path.with_suffix(f"{path.suffix}.tmp")
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2)
        f.flush()
        os.fsync(f.fileno())
    tmp_path.replace(path)


def generate_continue_config(
    model_list: List[Any],
    hw_info: hardware.HardwareInfo,
    tuning_profile: tuning.TuningProfile,
    target_ide: List[str],
    output_path: Optional[Path] = None
) -> Path:
    """
    Generate optimized Continue.dev config with fine-tuning parameters.
    
    Args:
        model_list: List of RecommendedModel objects
        hw_info: Hardware information
        tuning_profile: Tuning profile with all parameters
        target_ide: List of IDEs to configure (e.g., ["vscode"], ["intellij"])
        output_path: Optional output path (default: ~/.continue/config.yaml)
    
    Returns:
        Path to saved config file
    """
    if not model_list:
        raise ValueError("model_list cannot be empty")
    if not hw_info:
        raise ValueError("hw_info is required")
    
    generate_yaml = "vscode" in target_ide
    
    ui.print_header("📝 Generating Continue.dev Configuration")
    
    if output_path is None:
        if generate_yaml:
            output_path = Path.home() / ".continue" / "config.yaml"
        else:
            output_path = Path.home() / ".continue" / "config.json"
    
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Backup existing config
    if output_path.exists():
        backup_path = output_path.with_suffix(f"{output_path.suffix}.backup")
        shutil.copy(output_path, backup_path)
        ui.print_info(f"Backed up existing config to {backup_path}")
    
    # Get API endpoint
    api_base = hw_info.dmr_api_endpoint
    api_base = ensure_vpn_resilient_url(api_base)
    api_base_clean = api_base.rstrip('/')
    if '/v1' not in api_base_clean:
        if api_base_clean.endswith(':12434') or api_base_clean.endswith(':8080'):
            api_base_clean = f"{api_base_clean}/v1"
        elif '127.0.0.1' in api_base_clean:
            api_base_clean = f"{api_base_clean}/v1" if not api_base_clean.endswith('/v1') else api_base_clean
    
    ui.print_info(f"Using API endpoint: {api_base_clean}")
    ui.print_info(f"Tuning profile: {tuning_profile.temperature} temp, {tuning_profile.context_length:,} context")
    
    # Find models by role
    chat_models = [m for m in model_list if "chat" in m.roles or "edit" in m.roles]
    autocomplete_models = [m for m in model_list if "autocomplete" in m.roles]
    embed_models = [m for m in model_list if "embed" in m.roles]
    
    # Sort by priority
    chat_models.sort(key=lambda m: m.ram_gb, reverse=True)
    autocomplete_models.sort(key=lambda m: m.ram_gb)
    
    # Effective context length (from tuning profile, capped by model max)
    def _effective_context_length(model_ctx: int) -> int:
        return min(model_ctx, tuning_profile.context_length)
    
    # Build config
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
    
    # Add chat/edit models with parameters
    for model in chat_models:
        model_id = models.get_model_id_for_continue(model, hw_info)
        roles = ["chat", "edit", "apply"]
        if "autocomplete" in model.roles:
            roles.append("autocomplete")
        if "embed" in model.roles:
            roles.append("embed")
        
        completion_options = tuning_profile.get_completion_options("chat")
        
        model_cfg: Dict[str, Any] = {
            "name": model.name,
            "provider": "openai",
            "model": model_id,
            "apiBase": api_base_clean,
            "contextLength": _effective_context_length(model.context_length),
            "roles": roles,
            "completionOptions": completion_options,
        }
        
        if "autocomplete" in model.roles:
            autocomplete_opts = tuning_profile.get_completion_options("autocomplete")
            model_cfg["autocompleteOptions"] = {
                "debounceDelay": tuning_profile.autocomplete_debounce,
                "modelTimeout": tuning_profile.autocomplete_timeout,
                "maxPromptTokens": 2048,
                "useCache": tuning_profile.use_cache,
                **autocomplete_opts,
            }
        
        yaml_config["models"].append(model_cfg)
    
    # Add autocomplete-only models
    autocomplete_only = [m for m in autocomplete_models if m not in chat_models]
    for model in autocomplete_only:
        model_id = models.get_model_id_for_continue(model, hw_info)
        autocomplete_opts = tuning_profile.get_completion_options("autocomplete")
        model_cfg = {
            "name": f"{model.name} (Autocomplete)",
            "provider": "openai",
            "model": model_id,
            "apiBase": api_base_clean,
            "roles": ["autocomplete"],
            "contextLength": _effective_context_length(model.context_length),
            "autocompleteOptions": {
                "debounceDelay": tuning_profile.autocomplete_debounce,
                "modelTimeout": tuning_profile.autocomplete_timeout,
                "maxPromptTokens": 2048,
                "useCache": tuning_profile.use_cache,
                **autocomplete_opts,
            },
        }
        yaml_config["models"].append(model_cfg)
    
    # Add embedding models
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
        yaml_config["models"].append(model_cfg)
    
    # Write YAML config (if VS Code)
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
            if output_path.exists():
                backup_path = output_path.with_suffix(f"{output_path.suffix}.backup")
                if backup_path.exists():
                    shutil.copy(backup_path, output_path)
                    ui.print_warning(f"Rolled back to backup: {backup_path}")
            raise
    
    # Always create JSON version
    if generate_yaml:
        json_path = output_path.parent / "config.json"
    else:
        json_path = output_path
    
    json_config: Dict[str, Any] = {
        "name": "Docker Model Runner Local LLM",
        "version": "1.0.0",
        "models": [],
        "context": yaml_config.get("context", []),
    }
    
    # Convert models to JSON format
    for model_cfg in yaml_config["models"]:
        json_config["models"].append(model_cfg)
    
    try:
        if json_path.exists():
            backup_json = json_path.with_suffix(f"{json_path.suffix}.backup")
            shutil.copy(json_path, backup_json)
            ui.print_info(f"Backed up existing JSON config to {backup_json}")
        _atomic_write_json(json_path, json_config)
    except Exception as e:
        ui.print_error(f"Failed to write JSON config: {e}")
        backup_json = json_path.with_suffix(f"{json_path.suffix}.backup")
        if backup_json.exists():
            shutil.copy(backup_json, json_path)
            ui.print_warning(f"Rolled back JSON to backup: {backup_json}")
        raise
    
    if generate_yaml:
        ui.print_info(f"JSON config also saved to {json_path}")
    else:
        ui.print_success(f"Configuration saved to {json_path}")
        return json_path
    
    return output_path


def generate_global_rule(
    tuning_profile: tuning.TuningProfile,
    output_path: Optional[Path] = None
) -> Path:
    """
    Generate comprehensive global rules with fine-tuning context.
    
    Args:
        tuning_profile: Tuning profile for context
        output_path: Optional output path (default: ~/.continue/rules/global-rule.md)
    
    Returns:
        Path to saved global-rule.md file
    """
    if output_path is None:
        output_path = Path.home() / ".continue" / "rules" / "global-rule.md"
    
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    if output_path.exists():
        backup_path = output_path.with_suffix(".md.backup")
        shutil.copy(output_path, backup_path)
        ui.print_info(f"Backed up existing global-rule.md to {backup_path}")
    
    rule_content = f"""---
description: AI coding assistant rules with fine-tuned parameters (temperature={tuning_profile.temperature}, context={tuning_profile.context_length:,} tokens)
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

## Code Quality Standards

Act as a senior-level coding assistant. Provide guidance that reflects industry best practices and production-ready code quality.

### Error Handling
- Point out missing error handling and edge cases
- Match the error handling patterns already established in the codebase
- Consider production-level error scenarios
- Use try-catch blocks appropriately for error recovery

### Performance
- Optimize for performance when relevant
- Consider memory usage and computational complexity
- Suggest performance improvements when appropriate
- Profile before optimizing (measure, don't guess)

### Security
- Flag security vulnerabilities (SQL injection, XSS, CSRF, etc.)
- Suggest secure coding practices
- Validate and sanitize inputs
- Use parameterized queries for database access

### Maintainability
- Write clear, self-documenting code
- Use meaningful variable and function names
- Follow DRY (Don't Repeat Yourself) principle
- Keep functions focused and single-purpose

## Architecture Patterns

### Design Principles
- Prefer composition over inheritance
- Use dependency injection for testability
- Follow SOLID principles
- Design for extensibility and maintainability

### Code Organization
- Group related functionality together
- Separate concerns (business logic, data access, presentation)
- Use appropriate design patterns when they add value
- Avoid over-engineering simple problems

## Response Guidelines

### Code Generation
- Provide complete, working code examples
- Include necessary imports and dependencies
- Explain complex logic with comments
- Consider edge cases and error handling

### Code Review
- Apply strict standards by default
- Flag potential issues, enforce best practices
- Point out style inconsistencies
- Be adaptive for quick fixes or exploratory work

### Refactoring
- Briefly mention improvement opportunities
- Suggest improvements for code quality and bugs
- Think about scalability and maintainability
- Don't suggest changes for style or preference

### Verbosity
- Be concise for simple tasks
- Be detailed for complex architectural decisions
- Adapt explanation depth based on complexity
- Communicate with clarity expected between senior engineers

## Testing

- Assume testing is handled separately
- Do not mention testing considerations unless explicitly asked
- When asked about testing, provide comprehensive test strategies
- Include unit, integration, and end-to-end test considerations

## Documentation

- Write clear docstrings for public APIs
- Document complex algorithms and business logic
- Keep documentation up-to-date with code changes
- Use examples in documentation when helpful

## Performance Tuning Context

This configuration uses:
- Temperature: {tuning_profile.temperature} (controls randomness)
- Context Length: {tuning_profile.context_length:,} tokens
- Top P: {tuning_profile.top_p} (nucleus sampling)
- Max Tokens: {tuning_profile.max_tokens} (response length limit)

Adjust these parameters in the Continue.dev config if you need different behavior.
"""
    
    with open(output_path, "w") as f:
        f.write(rule_content)
    
    ui.print_success(f"Global rule file saved to {output_path}")
    
    return output_path


def generate_codebase_rules(output_path: Optional[Path] = None) -> Path:
    """Generate codebase awareness rules file for Agent mode."""
    ui.print_subheader("📝 Generating Codebase Awareness Rules")
    
    if output_path is None:
        output_path = Path.home() / ".continue" / "rules" / "codebase-context.md"
    
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
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

**Agent Mode** (Recommended):
- Agent mode reads this file automatically
- Uses the context to make better suggestions
- No indexing required - works immediately
- Best for: Complex tasks, architectural questions, multi-file changes

**Codebase Search** (Also available):
- Uses embedding models for semantic search
- Type `@Codebase` or `@Folder` in chat
- Best for: "Find all code related to X" queries
- Requires: Embedding model (already configured)

**💡 Pro Tip**: Use both! Agent mode for planning, codebase search for discovery.

---

📝 **Edit this file** to match your actual project structure and conventions.
The more specific you are, the better Agent mode will understand your codebase.
"""
    
    with open(output_path, "w") as f:
        f.write(rules_content)
    
    ui.print_success(f"Codebase awareness rules created at {output_path}")
    ui.print_info("💡 Edit this file to provide context about your project")
    
    return output_path


def generate_continueignore(output_path: Optional[Path] = None) -> Path:
    """Generate .continueignore file to ignore non-source code files."""
    if output_path is None:
        output_path = Path.home() / ".continue" / ".continueignore"
    
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    if output_path.exists():
        backup_path = output_path.with_suffix(".continueignore.backup")
        shutil.copy(output_path, backup_path)
        ui.print_info(f"Backed up existing .continueignore to {backup_path}")
    
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
build/
*.whl
.python-version
*.pyc
*.pyo
*.pyd

# Node.js and JavaScript
node_modules/
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
    
    with open(output_path, "w") as f:
        f.write(ignore_content)
    
    ui.print_success(f".continueignore file saved to {output_path}")
    
    return output_path


def save_setup_summary(
    model_list: List[Any],
    hw_info: hardware.HardwareInfo,
    tuning_profile: tuning.TuningProfile,
    output_path: Optional[Path] = None
) -> Path:
    """Save setup summary to JSON file."""
    if output_path is None:
        output_path = Path.home() / ".continue" / "setup-summary.json"
    
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    total_ram_used = sum(m.ram_gb for m in model_list)
    usable_ram = hw_info.get_estimated_model_memory() if hasattr(hw_info, 'get_estimated_model_memory') else hw_info.ram_gb
    reserve_ram = usable_ram - total_ram_used
    
    models_summary = []
    for model in model_list:
        models_summary.append({
            "name": model.name,
            "docker_name": model.docker_name,
            "ram_gb": model.ram_gb,
            "roles": getattr(model, 'roles', ["chat"]),
            "context_length": getattr(model, 'context_length', 131072),
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
        "tuning": {
            "temperature": tuning_profile.temperature,
            "top_p": tuning_profile.top_p,
            "context_length": tuning_profile.context_length,
            "max_tokens": tuning_profile.max_tokens,
        },
        "ram_usage": {
            "total_ram_gb": total_ram_used,
            "available_ram_gb": usable_ram,
            "reserve_ram_gb": reserve_ram,
            "usage_percent": (total_ram_used / usable_ram * 100) if usable_ram > 0 else 0
        },
        "timestamp": str(output_path)
    }
    
    with open(output_path, "w") as f:
        json.dump(summary, f, indent=2)
    
    ui.print_success(f"Setup summary saved to {output_path}")
    
    return output_path


# =============================================================================
# Manifest and Fingerprinting Functions
# =============================================================================

def _get_utc_timestamp() -> str:
    """Get current UTC timestamp in ISO format."""
    return datetime.now(timezone.utc).isoformat()


def calculate_file_hash(filepath: Path) -> str:
    """Calculate SHA-256 hash of a file for fingerprinting."""
    if not filepath.exists():
        return ""
    
    try:
        with open(filepath, 'rb') as f:
            return hashlib.sha256(f.read()).hexdigest()
    except (OSError, IOError, PermissionError):
        # File access issues - return empty hash
        return ""


def is_our_file(filepath: Path, manifest: Optional[Dict[str, Any]] = None) -> Union[bool, str]:
    """
    Check if file was created by our installer.
    
    Args:
        filepath: Path to check
        manifest: Optional manifest for comparison
    
    Returns:
        True if definitely ours, False if not, "maybe" if uncertain
    """
    if not filepath.exists():
        return False
    
    # Check 1: In manifest?
    if manifest:
        manifest_files = manifest.get("installed", {}).get("files", [])
        for entry in manifest_files:
            if entry.get("path") == str(filepath):
                # Verify fingerprint still matches
                current_hash = calculate_file_hash(filepath)
                if current_hash == entry.get("fingerprint"):
                    return True
                else:
                    return "maybe"  # In manifest but modified
    
    # Check 2: Has our fingerprint header?
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            first_lines = "".join([f.readline() for _ in range(5)])
            if "Generated by docker-llm-setup.py" in first_lines:
                return True
    except (OSError, IOError, UnicodeDecodeError, PermissionError):
        # File access or encoding issues
        pass
    
    # Check 3: Timestamp during installation window?
    if manifest:
        try:
            install_time = datetime.fromisoformat(manifest.get("timestamp", ""))
            file_mtime = datetime.fromtimestamp(filepath.stat().st_mtime)
            
            # Within 1 hour of installation
            if abs((file_mtime - install_time).total_seconds()) < 3600:
                return "maybe"  # Uncertain - ask user
        except (ValueError, OSError, TypeError):
            # Invalid timestamp format or file stat issues
            pass
    
    return False


def check_config_customization(config_path: Path, manifest: Optional[Dict[str, Any]] = None) -> str:
    """
    Check if user customized config file.
    
    Args:
        config_path: Path to config file
        manifest: Optional manifest for comparison
    
    Returns:
        Status: "missing", "unknown", "modified", "unchanged"
    """
    if not config_path.exists():
        return "missing"
    
    if not manifest:
        # No manifest - check for fingerprint
        status = is_our_file(config_path)
        if status is True:
            return "unchanged"
        elif status == "maybe":
            return "modified"
        return "unknown"
    
    # Find in manifest
    config_entry = None
    for file_entry in manifest.get("installed", {}).get("files", []):
        if file_entry.get("path") == str(config_path):
            config_entry = file_entry
            break
    
    if not config_entry:
        return "unknown"  # Not in manifest
    
    # Check fingerprint
    current_hash = calculate_file_hash(config_path)
    if current_hash != config_entry.get("fingerprint"):
        return "modified"  # User customized it
    
    return "unchanged"
