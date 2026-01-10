"""
Pytest configuration and shared fixtures for Ollama setup tests.

Provides common mocks, fixtures, and utilities used across all test files.
"""

import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional
from unittest.mock import MagicMock, Mock, patch

import pytest

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from lib import hardware


# =============================================================================
# Hardware Fixtures
# =============================================================================

@pytest.fixture
def mock_hardware_tier_c():
    """16GB RAM - Tier C (smallest supported tier)."""
    return hardware.HardwareInfo(
        os_name="Darwin",
        os_version="14.0",
        macos_version="14.0",
        cpu_brand="Apple M4",
        cpu_arch="arm64",
        cpu_cores=10,
        cpu_perf_cores=4,
        cpu_eff_cores=6,
        ram_gb=16.0,
        gpu_name="Apple M4",
        gpu_vram_gb=0,
        gpu_cores=10,
        neural_engine_cores=16,
        has_nvidia=False,
        has_apple_silicon=True,
        apple_chip_model="M4",
        ollama_version="0.13.5",
        ollama_available=True,
        ollama_api_endpoint="http://localhost:11434/v1",
        tier=hardware.HardwareTier.C,
        usable_ram_gb=9.6,  # 16 * 0.6 = 9.6GB usable
    )


@pytest.fixture
def mock_hardware_tier_b():
    """24GB RAM - Tier B."""
    return hardware.HardwareInfo(
        os_name="Darwin",
        os_version="14.0",
        macos_version="14.0",
        cpu_brand="Apple M2 Pro",
        cpu_arch="arm64",
        cpu_cores=12,
        cpu_perf_cores=8,
        cpu_eff_cores=4,
        ram_gb=24.0,
        gpu_name="Apple M2 Pro",
        gpu_vram_gb=0,
        gpu_cores=19,
        neural_engine_cores=16,
        has_nvidia=False,
        has_apple_silicon=True,
        apple_chip_model="M2 Pro",
        ollama_version="0.13.5",
        ollama_available=True,
        ollama_api_endpoint="http://localhost:11434/v1",
        tier=hardware.HardwareTier.B,
        usable_ram_gb=15.6,  # 24 * 0.65 = 15.6GB usable
    )


@pytest.fixture
def mock_hardware_tier_a():
    """32GB RAM - Tier A."""
    return hardware.HardwareInfo(
        os_name="Darwin",
        os_version="14.0",
        macos_version="14.0",
        cpu_brand="Apple M3 Pro",
        cpu_arch="arm64",
        cpu_cores=12,
        cpu_perf_cores=8,
        cpu_eff_cores=4,
        ram_gb=32.0,
        gpu_name="Apple M3 Pro",
        gpu_vram_gb=0,
        gpu_cores=18,
        neural_engine_cores=16,
        has_nvidia=False,
        has_apple_silicon=True,
        apple_chip_model="M3 Pro",
        ollama_version="0.13.5",
        ollama_available=True,
        ollama_api_endpoint="http://localhost:11434/v1",
        tier=hardware.HardwareTier.A,
        usable_ram_gb=22.4,  # 32 * 0.70 = 22.4GB usable
    )


@pytest.fixture
def mock_hardware_tier_s():
    """64GB RAM - Tier S (high-end)."""
    return hardware.HardwareInfo(
        os_name="Darwin",
        os_version="14.0",
        macos_version="14.0",
        cpu_brand="Apple M3 Max",
        cpu_arch="arm64",
        cpu_cores=16,
        cpu_perf_cores=12,
        cpu_eff_cores=4,
        ram_gb=64.0,
        gpu_name="Apple M3 Max",
        gpu_vram_gb=0,
        gpu_cores=40,
        neural_engine_cores=16,
        has_nvidia=False,
        has_apple_silicon=True,
        apple_chip_model="M3 Max",
        ollama_version="0.13.5",
        ollama_available=True,
        ollama_api_endpoint="http://localhost:11434/v1",
        tier=hardware.HardwareTier.S,
        usable_ram_gb=44.8,  # 64 * 0.70 = 44.8GB usable
    )


@pytest.fixture
def mock_hardware_linux():
    """Linux system with NVIDIA GPU."""
    return hardware.HardwareInfo(
        os_name="Linux",
        os_version="6.1.0",
        macos_version="",
        cpu_brand="Intel Core i9-13900K",
        cpu_arch="x86_64",
        cpu_cores=24,
        cpu_perf_cores=0,
        cpu_eff_cores=0,
        ram_gb=32.0,
        gpu_name="NVIDIA RTX 4090",
        gpu_vram_gb=24.0,
        gpu_cores=0,
        neural_engine_cores=0,
        has_nvidia=True,
        has_apple_silicon=False,
        apple_chip_model="",
        ollama_version="0.13.5",
        ollama_available=True,
        ollama_api_endpoint="http://localhost:11434/v1",
        tier=hardware.HardwareTier.A,
        usable_ram_gb=22.4,
    )


# =============================================================================
# Ollama API Fixtures
# =============================================================================

@pytest.fixture
def mock_ollama_api_response():
    """Mock successful Ollama API response with installed models."""
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


@pytest.fixture
def mock_ollama_empty_response():
    """Mock Ollama API response with no models installed."""
    return {"models": []}


@pytest.fixture
def mock_urlopen_success(mock_ollama_api_response):
    """Mock successful urllib.request.urlopen."""
    mock_response = MagicMock()
    mock_response.status = 200
    mock_response.read.return_value = json.dumps(mock_ollama_api_response).encode()
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
def mock_manifest(mock_home_dir):
    """Create mock installation manifest."""
    manifest = {
        "version": "2.0",
        "timestamp": "2024-01-01T00:00:00Z",
        "installer_version": "2.0.0",
        "installed": {
            "models": [
                {"name": "qwen2.5-coder:7b", "size_gb": 5.0},
                {"name": "nomic-embed-text", "size_gb": 0.3}
            ],
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
# Subprocess Fixtures
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
def mock_run_command():
    """Mock utils.run_command function."""
    def _run_command(cmd, timeout=300):
        cmd_str = " ".join(cmd)
        
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
    
    return _run_command


# =============================================================================
# Model Fixtures
# =============================================================================

@pytest.fixture
def mock_recommended_models():
    """Mock model recommendation result."""
    from lib.model_selector import RecommendedModel, ModelRole, ModelRecommendation
    
    primary = RecommendedModel(
        name="Qwen2.5 Coder 7B",
        ollama_name="qwen2.5-coder:7b",
        ram_gb=5.0,
        role=ModelRole.CHAT,
        roles=["chat", "edit", "autocomplete"],
        description="Primary coding model"
    )
    
    autocomplete = RecommendedModel(
        name="StarCoder2 3B",
        ollama_name="starcoder2:3b",
        ram_gb=2.0,
        role=ModelRole.AUTOCOMPLETE,
        roles=["autocomplete"],
        description="Fast autocomplete"
    )
    
    embed = RecommendedModel(
        name="Nomic Embed Text",
        ollama_name="nomic-embed-text",
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
    from lib import utils
    utils._UNVERIFIED_SSL_CONTEXT = None
    yield
    utils._UNVERIFIED_SSL_CONTEXT = None


@pytest.fixture
def capture_prints(capsys):
    """Capture and return printed output."""
    def _get_output():
        captured = capsys.readouterr()
        return captured.out
    return _get_output
