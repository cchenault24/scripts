"""
Pytest configuration and shared fixtures for ai_model setup tests.

Provides common mocks, fixtures, and utilities used across all test files.
Supports both ollama and docker backends via parametrization.
"""

import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional
from unittest.mock import MagicMock, Mock, patch

import pytest

# Add backend directories to path for imports
# Determine which backend to use from environment variable
_ollama_path = str(Path(__file__).parent.parent / "ollama")
_docker_path = str(Path(__file__).parent.parent / "docker")

# Only add the correct backend path based on TEST_BACKEND env var
# This prevents import conflicts
_test_backend = os.environ.get('TEST_BACKEND', '').lower()
if _test_backend == 'ollama':
    if _ollama_path not in sys.path:
        sys.path.insert(0, _ollama_path)
    # Remove docker path if present
    if _docker_path in sys.path:
        sys.path.remove(_docker_path)
elif _test_backend == 'docker':
    if _docker_path not in sys.path:
        sys.path.insert(0, _docker_path)
    # Remove ollama path if present
    if _ollama_path in sys.path:
        sys.path.remove(_ollama_path)
else:
    # Both backends - add both (for parametrized tests)
    if _ollama_path not in sys.path:
        sys.path.insert(0, _ollama_path)
    if _docker_path not in sys.path:
        sys.path.insert(0, _docker_path)

# Hardware will be imported dynamically based on backend_type in fixtures


# =============================================================================
# Backend Parametrization
# =============================================================================

def pytest_generate_tests(metafunc):
    """Generate backend_type parameter based on environment or default to both."""
    if "backend_type" in metafunc.fixturenames:
        import os
        backend_env = os.environ.get('TEST_BACKEND')
        if backend_env:
            # Run only for specified backend
            metafunc.parametrize("backend_type", [backend_env], indirect=False)
        else:
            # Run for both backends
            metafunc.parametrize("backend_type", ["ollama", "docker"], indirect=False)


@pytest.fixture
def backend_type(request):
    """Backend type fixture (parametrized via pytest_generate_tests)."""
    return request.param


@pytest.fixture
def backend_module(backend_type):
    """Dynamically import the correct backend module."""
    if backend_type == "ollama":
        if _ollama_path not in sys.path:
            sys.path.insert(0, _ollama_path)
        from lib import ollama as backend_module
    else:
        if _docker_path not in sys.path:
            sys.path.insert(0, _docker_path)
        from lib import docker as backend_module
    return backend_module


@pytest.fixture
def model_name_attr(backend_type):
    """Return the model name attribute for the current backend."""
    return "ollama_name" if backend_type == "ollama" else "docker_name"


@pytest.fixture
def api_endpoint(backend_type):
    """Return the API endpoint for the current backend."""
    if backend_type == "ollama":
        return "http://localhost:11434/v1"
    else:
        return "http://localhost:12434/v1"


@pytest.fixture
def setup_script_name(backend_type):
    """Return the setup script name for the current backend."""
    return "ollama-llm-setup" if backend_type == "ollama" else "docker-llm-setup"


# =============================================================================
# Hardware Fixtures (Backend-Aware)
# =============================================================================

def _create_hardware_info(ram_gb, tier, backend_type, **kwargs):
    """Helper to create HardwareInfo with backend-specific fields.
    
    Note: tier parameter is ignored (kept for backward compatibility with existing tests).
    """
    # Import hardware from the correct backend
    if backend_type == "ollama":
        if _ollama_path not in sys.path:
            sys.path.insert(0, _ollama_path)
        from lib import hardware
    else:
        if _docker_path not in sys.path:
            sys.path.insert(0, _docker_path)
        from lib import hardware
    
    base_info = {
        "os_name": kwargs.get("os_name", "Darwin"),
        "os_version": kwargs.get("os_version", "14.0"),
        "macos_version": kwargs.get("macos_version", "14.0"),
        "cpu_brand": kwargs.get("cpu_brand", "Apple M4"),
        "cpu_arch": kwargs.get("cpu_arch", "arm64"),
        "cpu_cores": kwargs.get("cpu_cores", 10),
        "cpu_perf_cores": kwargs.get("cpu_perf_cores", 4),
        "cpu_eff_cores": kwargs.get("cpu_eff_cores", 6),
        "ram_gb": ram_gb,
        "gpu_name": kwargs.get("gpu_name", "Apple M4"),
        "gpu_vram_gb": kwargs.get("gpu_vram_gb", 0),
        "gpu_cores": kwargs.get("gpu_cores", 10),
        "neural_engine_cores": kwargs.get("neural_engine_cores", 16),
        "has_nvidia": kwargs.get("has_nvidia", False),
        "has_apple_silicon": kwargs.get("has_apple_silicon", True),
        "apple_chip_model": kwargs.get("apple_chip_model", "M4"),
        "usable_ram_gb": kwargs.get("usable_ram_gb", ram_gb),
    }
    
    # Add backend-specific fields
    if backend_type == "ollama":
        base_info.update({
            "ollama_version": kwargs.get("ollama_version", "0.13.5"),
            "ollama_available": kwargs.get("ollama_available", True),
            "ollama_api_endpoint": kwargs.get("ollama_api_endpoint", "http://localhost:11434/v1"),
        })
    else:
        base_info.update({
            "docker_version": kwargs.get("docker_version", "27.0.3"),
            "docker_model_runner_available": kwargs.get("docker_model_runner_available", True),
            "dmr_api_endpoint": kwargs.get("dmr_api_endpoint", "http://localhost:12434/v1"),
        })
    
    return hardware.HardwareInfo(**base_info)


@pytest.fixture
def mock_hardware_16gb(backend_type):
    """16GB RAM - minimum supported."""
    return _create_hardware_info(16.0, None, backend_type, usable_ram_gb=16.0)


@pytest.fixture
def mock_hardware_24gb(backend_type):
    """24GB RAM."""
    return _create_hardware_info(
        24.0, None, backend_type,
        cpu_brand="Apple M2 Pro",
        cpu_cores=12,
        cpu_perf_cores=8,
        cpu_eff_cores=4,
        gpu_name="Apple M2 Pro",
        gpu_cores=19,
        apple_chip_model="M2 Pro",
        usable_ram_gb=24.0,
    )


@pytest.fixture
def mock_hardware_32gb(backend_type):
    """32GB RAM."""
    return _create_hardware_info(
        32.0, None, backend_type,
        cpu_brand="Apple M3 Pro",
        cpu_cores=12,
        cpu_perf_cores=8,
        cpu_eff_cores=4,
        gpu_name="Apple M3 Pro",
        gpu_cores=18,
        apple_chip_model="M3 Pro",
        usable_ram_gb=32.0,
    )


@pytest.fixture
def mock_hardware_64gb(backend_type):
    """64GB RAM."""
    return _create_hardware_info(
        64.0, None, backend_type,
        cpu_brand="Apple M3 Max",
        cpu_cores=16,
        cpu_perf_cores=12,
        cpu_eff_cores=4,
        gpu_name="Apple M3 Max",
        gpu_cores=40,
        apple_chip_model="M3 Max",
        usable_ram_gb=64.0,
    )


@pytest.fixture
def mock_hardware_linux(backend_type):
    """Linux system with NVIDIA GPU."""
    # Import hardware from correct backend
    if backend_type == "ollama":
        if _ollama_path not in sys.path:
            sys.path.insert(0, _ollama_path)
        from lib import hardware
    else:
        if _docker_path not in sys.path:
            sys.path.insert(0, _docker_path)
        from lib import hardware
    return _create_hardware_info(
        32.0,
        None,
        backend_type,
        os_name="Linux",
        os_version="6.1.0",
        macos_version="",
        cpu_brand="Intel Core i9-13900K",
        cpu_arch="x86_64",
        cpu_cores=24,
        cpu_perf_cores=0,
        cpu_eff_cores=0,
        gpu_name="NVIDIA RTX 4090",
        gpu_vram_gb=24.0,
        gpu_cores=0,
        neural_engine_cores=0,
        has_nvidia=True,
        has_apple_silicon=False,
        apple_chip_model="",
        usable_ram_gb=22.4,
    )


# =============================================================================
# API Response Fixtures (Backend-Aware)
# =============================================================================

@pytest.fixture
def mock_api_response(backend_type):
    """Mock successful API response with installed models."""
    if backend_type == "ollama":
        return {
            "models": [
                {
                    "name": "qwen2.5-coder:7b",
                    "size": 4500000000,
                    "digest": "sha256:abc123",
                    "modified_at": "2024-01-01T00:00:00Z"
                },
                {
                    "name": "nomic-embed-text",
                    "size": 274000000,
                    "digest": "sha256:def456",
                    "modified_at": "2024-01-01T00:00:00Z"
                }
            ]
        }
    else:
        return {
            "data": [
                {
                    "id": "ai/qwen2.5-coder:7b",
                    "object": "model",
                    "created": 1704067200,
                    "owned_by": "docker"
                },
                {
                    "id": "ai/nomic-embed-text-v1.5",
                    "object": "model",
                    "created": 1704067200,
                    "owned_by": "docker"
                }
            ]
        }


@pytest.fixture
def mock_empty_api_response(backend_type):
    """Mock API response with no models installed."""
    if backend_type == "ollama":
        return {"models": []}
    else:
        return {"data": []}


@pytest.fixture
def mock_urlopen_success(mock_api_response):
    """Mock successful urllib.request.urlopen."""
    mock_response = MagicMock()
    mock_response.status = 200
    mock_response.read.return_value = json.dumps(mock_api_response).encode()
    mock_response.__enter__ = Mock(return_value=mock_response)
    mock_response.__exit__ = Mock(return_value=False)
    return mock_response


@pytest.fixture
def mock_urlopen_failure():
    """Mock failed urllib.request.urlopen."""
    import urllib.error
    return urllib.error.URLError("Connection refused")


# =============================================================================
# User Input Fixtures
# =============================================================================

@pytest.fixture
def mock_user_accepts_all():
    """Mock user accepting all prompts with 'y'."""
    def input_generator():
        responses = iter(["y", "y", "y", "y", "y", "y", "y", "y", "y", "y"])
        return lambda _: next(responses)
    return input_generator()


@pytest.fixture
def mock_user_declines_all():
    """Mock user declining all prompts with 'n'."""
    def input_generator():
        responses = iter(["n", "n", "n", "n", "n", "n", "n", "n", "n", "n"])
        return lambda _: next(responses)
    return input_generator()


class MockInputSequence:
    """Helper class to mock a sequence of user inputs."""
    
    def __init__(self, responses: List[str]):
        self.responses = iter(responses)
        self.call_count = 0
    
    def __call__(self, prompt: str = "") -> str:
        self.call_count += 1
        try:
            return next(self.responses)
        except StopIteration:
            return ""


@pytest.fixture
def input_sequence():
    """Factory fixture to create input sequences."""
    def _create_sequence(responses: List[str]) -> MockInputSequence:
        return MockInputSequence(responses)
    return _create_sequence


# =============================================================================
# File System Fixtures
# =============================================================================

@pytest.fixture
def mock_home_dir(tmp_path):
    """Mock home directory with Continue.dev structure."""
    continue_dir = tmp_path / ".continue"
    continue_dir.mkdir()
    (continue_dir / "rules").mkdir()
    return tmp_path


@pytest.fixture
def mock_launch_agents_dir(tmp_path):
    """Mock LaunchAgents directory."""
    launch_agents = tmp_path / "Library" / "LaunchAgents"
    launch_agents.mkdir(parents=True)
    return launch_agents


@pytest.fixture
def mock_existing_config(mock_home_dir):
    """Create existing Continue.dev config."""
    config_path = mock_home_dir / ".continue" / "config.yaml"
    config_path.write_text("# Existing config\nmodels:\n  - name: test")
    return config_path


@pytest.fixture
def mock_manifest(mock_home_dir, backend_type):
    """Create mock installation manifest."""
    installer_type = backend_type
    if backend_type == "ollama":
        models = [
            {"name": "qwen2.5-coder:7b", "size_gb": 5.0},
            {"name": "nomic-embed-text", "size_gb": 0.3}
        ]
    else:
        models = [
            {"name": "ai/qwen2.5-coder:7b", "size_gb": 5.0},
            {"name": "ai/nomic-embed-text-v1.5", "size_gb": 0.3}
        ]
    
    manifest = {
        "version": "2.0",
        "timestamp": "2024-01-01T00:00:00Z",
        "installer_version": "2.0.0",
        "installer_type": installer_type,
        "installed": {
            "models": models,
            "files": []
        },
        "pre_existing": {
            "models": []
        }
    }
    manifest_path = mock_home_dir / ".continue" / "setup-manifest.json"
    manifest_path.write_text(json.dumps(manifest))
    return manifest_path


# =============================================================================
# Subprocess Fixtures (Backend-Aware)
# =============================================================================

@pytest.fixture
def mock_subprocess_success():
    """Mock successful subprocess execution."""
    mock_result = Mock()
    mock_result.returncode = 0
    mock_result.stdout = "success"
    mock_result.stderr = ""
    return mock_result


@pytest.fixture
def mock_subprocess_failure():
    """Mock failed subprocess execution."""
    mock_result = Mock()
    mock_result.returncode = 1
    mock_result.stdout = ""
    mock_result.stderr = "error: command failed"
    return mock_result


@pytest.fixture
def mock_run_command(backend_type):
    """Mock utils.run_command function for both backends."""
    def _run_command(cmd, capture=True, timeout=300, clean_env=False):
        cmd_str = " ".join(cmd) if isinstance(cmd, list) else str(cmd)
        
        if backend_type == "ollama":
            if "ollama list" in cmd_str:
                return 0, "NAME\nqwen2.5-coder:7b\nnomic-embed-text\n", ""
            elif "ollama --version" in cmd_str:
                return 0, "ollama version 0.13.5", ""
            elif "ollama pull" in cmd_str:
                return 0, "success", ""
            elif "launchctl" in cmd_str:
                return 0, "", ""
            elif "pgrep" in cmd_str:
                return 0, "12345", ""
            else:
                return 0, "", ""
        else:  # docker
            if "docker model list" in cmd_str:
                return 0, "NAME\nai/qwen2.5-coder:7b\nai/nomic-embed-text-v1.5\n", ""
            elif "docker --version" in cmd_str:
                return 0, "Docker version 27.0.3, build abc123", ""
            elif "docker model pull" in cmd_str:
                return 0, "Downloaded: ai/qwen2.5-coder:7b\n", ""
            elif "docker model rm" in cmd_str:
                return 0, "", ""
            elif "docker info" in cmd_str:
                return 0, "Server Version: 27.0.3\n", ""
            elif "pgrep" in cmd_str:
                return 0, "12345", ""
            else:
                return 0, "", ""
    
    return _run_command


# =============================================================================
# Model Fixtures (Backend-Aware)
# =============================================================================

# Recommendation functions removed - we install fixed models for all users


@pytest.fixture
def mock_recommended_models(backend_type):
    """Mock model selection result - returns list of fixed models."""
    # Import from correct backend
    if backend_type == "ollama":
        if _ollama_path not in sys.path:
            sys.path.insert(0, _ollama_path)
    else:
        if _docker_path not in sys.path:
            sys.path.insert(0, _docker_path)
    from lib.model_selector import RecommendedModel, ModelRole, PRIMARY_MODEL, EMBED_MODEL
    from lib.hardware import HardwareInfo
    
    # Return fixed models (same as select_models would return)
    return [PRIMARY_MODEL, EMBED_MODEL]
            description="Embedding model"
        )
    else:  # docker
        primary = RecommendedModel(
            name="Qwen2.5 Coder 7B",
            docker_name="ai/qwen2.5-coder:7b",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit", "autocomplete"],
            description="Primary coding model"
        )
        
        autocomplete = RecommendedModel(
            name="StarCoder2 3B",
            docker_name="ai/starcoder2:3b",
            ram_gb=2.0,
            role=ModelRole.AUTOCOMPLETE,
            roles=["autocomplete"],
            description="Fast autocomplete"
        )
        
        embed = RecommendedModel(
            name="Nomic Embed Text",
            docker_name="ai/nomic-embed-text-v1.5",
            ram_gb=0.3,
            role=ModelRole.EMBED,
            roles=["embed"],
            description="Embedding model"
        )
    
    return ModelRecommendation(
        primary=primary,
        autocomplete=autocomplete,
        embeddings=embed
    )


# =============================================================================
# SSL/Network Fixtures
# =============================================================================

@pytest.fixture
def mock_ssl_context():
    """Mock SSL context for network calls."""
    import ssl
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


# =============================================================================
# Cleanup Fixtures
# =============================================================================

@pytest.fixture(autouse=True)
def reset_module_state():
    """Reset any module-level state between tests."""
    # Reset SSL context singleton
    # Try both paths
    for path in [_ollama_path, _docker_path]:
        if path in sys.path:
            try:
                from lib import utils
                utils._UNVERIFIED_SSL_CONTEXT = None
                break
            except ImportError:
                continue
    yield
    # Cleanup after test
    for path in [_ollama_path, _docker_path]:
        if path in sys.path:
            try:
                from lib import utils
                utils._UNVERIFIED_SSL_CONTEXT = None
                break
            except ImportError:
                continue


@pytest.fixture
def capture_prints(capsys):
    """Capture and return printed output."""
    def _get_output():
        captured = capsys.readouterr()
        return captured.out
    return _get_output
