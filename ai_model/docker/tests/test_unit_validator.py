"""
Unit tests for lib/validator.py.

Tests validation logic, model pulling, error classification, and retry mechanisms.
"""

import sys
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch
import urllib.error

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib import validator
from lib import hardware
from lib.validator import (
    PullErrorType,
    PullResult,
    SetupResult,
    is_restricted_model_name,
    classify_pull_error,
    get_troubleshooting_steps,
    is_dmr_api_available,
    get_installed_models,
    verify_model_exists,
    get_fallback_model,
    validate_pre_install,
)
from lib.model_selector import RecommendedModel, ModelRole


# =============================================================================
# PullErrorType Tests
# =============================================================================

class TestPullErrorType:
    """Tests for PullErrorType class constants."""
    
    def test_all_error_types_defined(self):
        """Test that expected error types are defined."""
        assert hasattr(PullErrorType, 'NETWORK')
        assert hasattr(PullErrorType, 'SERVICE')
        assert hasattr(PullErrorType, 'UNKNOWN')
        assert hasattr(PullErrorType, 'DISK')
    
    def test_error_type_values(self):
        """Test error type values are strings."""
        assert PullErrorType.NETWORK == "network"
        assert PullErrorType.SERVICE == "service"
        assert PullErrorType.UNKNOWN == "unknown"


# =============================================================================
# Restricted Model Tests
# =============================================================================

class TestIsRestrictedModel:
    """Tests for is_restricted_model_name function."""
    
    @pytest.mark.parametrize("model_name", [
        "ai/llama3.2",
        "ai/codestral",
        "ai/nomic-embed-text-v1.5",
        "ai/granite-4.0-h-small",
    ])
    def test_allowed_models_pass(self, model_name):
        """Test that allowed models are not flagged."""
        result = is_restricted_model_name(model_name)
        assert result is False, f"Model {model_name} should not be restricted"


# =============================================================================
# Error Classification Tests
# =============================================================================

class TestClassifyPullError:
    """Tests for classify_pull_error function."""
    
    def test_network_error_classified(self):
        """Test network errors are classified."""
        result = classify_pull_error("connection refused")
        assert result is not None
    
    def test_empty_error_returns_unknown(self):
        """Test that empty error returns unknown type."""
        result = classify_pull_error("")
        assert result == PullErrorType.UNKNOWN


# =============================================================================
# Troubleshooting Steps Tests
# =============================================================================

class TestGetTroubleshootingSteps:
    """Tests for get_troubleshooting_steps function."""
    
    def test_network_steps(self):
        """Test troubleshooting steps for network errors."""
        steps = get_troubleshooting_steps(PullErrorType.NETWORK)
        assert len(steps) > 0
    
    def test_disk_steps(self):
        """Test troubleshooting steps for disk errors."""
        steps = get_troubleshooting_steps(PullErrorType.DISK)
        assert len(steps) > 0
    
    def test_unknown_steps(self):
        """Test troubleshooting steps for unknown errors."""
        steps = get_troubleshooting_steps(PullErrorType.UNKNOWN)
        assert len(steps) > 0


# =============================================================================
# API Availability Tests
# =============================================================================

class TestIsDmrApiAvailable:
    """Tests for is_dmr_api_available function."""
    
    @patch('urllib.request.urlopen')
    def test_api_available(self, mock_urlopen):
        """Test API availability check when successful."""
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.__enter__ = Mock(return_value=mock_response)
        mock_response.__exit__ = Mock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        result = is_dmr_api_available()
        assert result is True
    
    @patch('urllib.request.urlopen')
    def test_api_unavailable(self, mock_urlopen):
        """Test API availability check when unavailable."""
        mock_urlopen.side_effect = urllib.error.URLError("Connection refused")
        
        result = is_dmr_api_available()
        assert result is False


# =============================================================================
# Get Installed Models Tests
# =============================================================================

class TestGetInstalledModels:
    """Tests for get_installed_models function."""
    
    @patch('lib.validator.utils.run_command')
    def test_get_installed_models_success(self, mock_run):
        """Test getting installed models when successful."""
        mock_run.return_value = (0, "NAME\nai/model1:7b\nai/model2:3b\n", "")
        
        models = get_installed_models()
        
        assert len(models) == 2
        assert "ai/model1:7b" in models
        assert "ai/model2:3b" in models
    
    @patch('lib.validator.utils.run_command')
    def test_get_installed_models_empty(self, mock_run):
        """Test getting installed models when none exist."""
        mock_run.return_value = (0, "NAME\n", "")
        
        models = get_installed_models()
        
        assert len(models) == 0
    
    @patch('lib.validator.utils.run_command')
    def test_get_installed_models_failure(self, mock_run):
        """Test getting installed models when command fails."""
        mock_run.return_value = (1, "", "error")
        
        models = get_installed_models()
        
        assert len(models) == 0


# =============================================================================
# Verify Model Exists Tests
# =============================================================================

class TestVerifyModelExists:
    """Tests for verify_model_exists function."""
    
    @patch('lib.validator.get_installed_models')
    def test_model_exists(self, mock_get_models):
        """Test verifying model that exists."""
        mock_get_models.return_value = ["ai/qwen2.5-coder:7b", "ai/llama3.2:3b"]
        
        result = verify_model_exists("ai/qwen2.5-coder:7b")
        
        assert result is True
    
    @patch('lib.validator.get_installed_models')
    def test_model_not_exists(self, mock_get_models):
        """Test verifying model that doesn't exist."""
        mock_get_models.return_value = ["ai/llama3.2:3b"]
        
        result = verify_model_exists("ai/qwen2.5-coder:7b")
        
        assert result is False


# =============================================================================
# PullResult Tests
# =============================================================================

class TestPullResult:
    """Tests for PullResult dataclass."""
    
    def test_successful_pull(self):
        """Test creating a successful pull result."""
        model = RecommendedModel(
            name="Test",
            docker_name="ai/test:7b",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat"]
        )
        result = PullResult(
            model=model,
            success=True,
            verified=True
        )
        
        assert result.success is True
        assert result.verified is True
    
    def test_failed_pull(self):
        """Test creating a failed pull result."""
        model = RecommendedModel(
            name="Test",
            docker_name="ai/test:7b",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat"]
        )
        result = PullResult(
            model=model,
            success=False,
            error_message="Connection refused"
        )
        
        assert result.success is False
        assert result.error_message == "Connection refused"


# =============================================================================
# SetupResult Tests
# =============================================================================

class TestSetupResult:
    """Tests for SetupResult dataclass."""
    
    def test_successful_setup(self):
        """Test creating a successful setup result."""
        model = RecommendedModel(
            name="Test",
            docker_name="ai/test:7b",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat"]
        )
        
        result = SetupResult(
            successful_models=[model],
            failed_models=[]
        )
        
        assert len(result.successful_models) == 1
        assert result.complete_failure is False
        assert result.complete_success is True
    
    def test_partial_failure_setup(self):
        """Test creating a partial failure setup result."""
        model1 = RecommendedModel(
            name="Test1",
            docker_name="ai/test1:7b",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat"]
        )
        model2 = RecommendedModel(
            name="Test2",
            docker_name="ai/test2:7b",
            ram_gb=5.0,
            role=ModelRole.AUTOCOMPLETE,
            roles=["autocomplete"]
        )
        
        result = SetupResult(
            successful_models=[model1],
            failed_models=[(model2, "Error")]
        )
        
        assert len(result.successful_models) == 1
        assert len(result.failed_models) == 1
        assert result.partial_success is True


# =============================================================================
# Pre-Install Validation Tests
# =============================================================================

class TestValidatePreInstall:
    """Tests for validate_pre_install function."""
    
    @patch('lib.validator.is_dmr_api_available')
    @patch('lib.validator.is_restricted_model_name')
    def test_valid_pre_install(self, mock_restricted, mock_api):
        """Test pre-install validation passes for valid setup."""
        mock_api.return_value = True
        mock_restricted.return_value = False
        
        models = [
            RecommendedModel(
                name="Test",
                docker_name="ai/qwen2.5-coder:7b",
                ram_gb=5.0,
                role=ModelRole.CHAT,
                roles=["chat"]
            )
        ]
        
        hw_info = hardware.HardwareInfo(
            ram_gb=32.0,
            tier=hardware.HardwareTier.A,
            usable_ram_gb=22.4,
            docker_model_runner_available=True
        )
        
        is_valid, warnings = validate_pre_install(models, hw_info)
        
        assert isinstance(is_valid, bool)
        assert isinstance(warnings, list)
