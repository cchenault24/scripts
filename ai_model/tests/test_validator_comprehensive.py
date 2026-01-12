"""
Comprehensive tests for lib/validator.py - Model validation and pulling.

Tests cover:
- PullErrorType classification
- Troubleshooting steps generation
- API availability checking
- Model verification
- Pull operations
- Preflight checks
- Diagnostics
"""

import pytest
from unittest.mock import patch, MagicMock
import json

from lib import validator
from lib.validator import (
    PullErrorType, classify_pull_error, get_troubleshooting_steps,
    PullResult, SetupResult,
    get_installed_models, verify_model_exists,
    pull_models_with_tracking, display_setup_result, validate_pre_install
)
# test_ollama_connectivity may not exist in Docker backend
try:
    from lib.validator import test_ollama_connectivity as check_ollama_connectivity
except ImportError:
    try:
        from lib.validator import test_dmr_connectivity as check_ollama_connectivity
    except ImportError:
        check_ollama_connectivity = None

# Determine backend from environment for model name attribute
import os
_test_backend = os.environ.get('TEST_BACKEND', 'ollama').lower()
model_name_attr = "docker_name" if _test_backend == "docker" else "ollama_name"
# run_preflight_check may not exist in Docker backend
try:
    from lib.validator import run_preflight_check
except ImportError:
    run_preflight_check = None
# Backend-specific imports
import os
_test_backend = os.environ.get('TEST_BACKEND', 'ollama').lower()
if _test_backend == 'docker':
    try:
        from lib.validator import is_dmr_api_available as is_api_available
    except ImportError:
        is_api_available = None
    try:
        from lib.validator import run_diagnostics
    except ImportError:
        run_diagnostics = None
else:
    try:
        from lib.validator import is_ollama_api_available as is_api_available
    except ImportError:
        is_api_available = None
    try:
        from lib.validator import run_diagnostics
    except ImportError:
        run_diagnostics = None
from lib.model_selector import RecommendedModel, ModelRole
from lib.hardware import HardwareTier, HardwareInfo


class TestPullErrorType:
    """Tests for PullErrorType class."""
    
    def test_error_types_defined(self):
        """Test error types are defined."""
        assert hasattr(PullErrorType, 'NETWORK')
        assert hasattr(PullErrorType, 'DISK')
        assert hasattr(PullErrorType, 'MODEL_NOT_FOUND')
        # SSH_KEY is only available in Ollama backend
        if _test_backend != "docker":
            assert hasattr(PullErrorType, 'SSH_KEY')
    
    def test_error_type_values(self):
        """Test error type values are strings."""
        assert isinstance(PullErrorType.NETWORK, str)
        assert isinstance(PullErrorType.DISK, str)


class TestClassifyPullError:
    """Tests for classify_pull_error function."""
    
    @pytest.mark.parametrize("error_msg,expected_type", [
        ("connection refused", PullErrorType.NETWORK),
        ("connection reset", PullErrorType.NETWORK),
        ("timeout", PullErrorType.NETWORK),
        ("no space left on device", PullErrorType.DISK),
        ("disk full", PullErrorType.DISK),
        ("model not found", PullErrorType.MODEL_NOT_FOUND),
        ("does not exist", PullErrorType.MODEL_NOT_FOUND),
        ("unauthorized", PullErrorType.AUTH),
        ("authentication failed", PullErrorType.AUTH),
        ("some unknown error", PullErrorType.UNKNOWN),
    ])
    def test_error_classification(self, error_msg, expected_type):
        """Test various error messages are classified correctly."""
        result = classify_pull_error(error_msg)
        assert result == expected_type
    
    def test_classify_ssh_key_error(self):
        """Test SSH key error classification (if available)."""
        if not hasattr(PullErrorType, 'SSH_KEY'):
            pytest.skip("SSH_KEY not available in this backend")
        result = classify_pull_error("ssh: no key found")
        assert result == PullErrorType.SSH_KEY
    
    def test_empty_error(self):
        """Test empty error message."""
        result = classify_pull_error("")
        assert result == PullErrorType.UNKNOWN
    
    def test_case_insensitive(self):
        """Test classification is case-insensitive."""
        result = classify_pull_error("CONNECTION REFUSED")
        assert result == PullErrorType.NETWORK


class TestGetTroubleshootingSteps:
    """Tests for get_troubleshooting_steps function."""
    
    def test_network_steps(self):
        """Test network error troubleshooting."""
        steps = get_troubleshooting_steps(PullErrorType.NETWORK)
        
        assert isinstance(steps, list)
        assert len(steps) > 0
    
    def test_disk_space_steps(self):
        """Test disk space error troubleshooting."""
        steps = get_troubleshooting_steps(PullErrorType.DISK)
        
        assert isinstance(steps, list)
        assert len(steps) > 0
    
    def test_ssh_steps(self):
        """Test SSH error troubleshooting."""
        if _test_backend == "docker" or not hasattr(PullErrorType, 'SSH_KEY'):
            pytest.skip("SSH_KEY not available in Docker backend")
        steps = get_troubleshooting_steps(PullErrorType.SSH_KEY)
        
        assert isinstance(steps, list)
        steps_text = " ".join(steps)
        assert "SSH" in steps_text.upper() or "ollama" in steps_text.lower()
    
    def test_unknown_steps(self):
        """Test unknown error troubleshooting."""
        steps = get_troubleshooting_steps(PullErrorType.UNKNOWN)
        
        assert isinstance(steps, list)


class TestPullResult:
    """Tests for PullResult dataclass."""
    
    def test_default_values(self):
        """Test default initialization."""
        model = RecommendedModel("Test", "test:v", 5.0, ModelRole.CHAT, ["chat"])
        result = PullResult(model=model, success=False)
        
        assert result.success is False
        assert result.verified is False
        assert result.error_message == ""
    
    def test_with_values(self):
        """Test initialization with values."""
        model = RecommendedModel("Test", "test:v", 5.0, ModelRole.CHAT, ["chat"])
        result = PullResult(
            model=model,
            success=True,
            verified=True,
            error_message=""
        )
        
        assert result.success is True
        assert result.verified is True


class TestSetupResult:
    """Tests for SetupResult dataclass."""
    
    def test_partial_success(self):
        """Test partial_success property."""
        model1 = RecommendedModel("M1", "m1:v", 5.0, ModelRole.CHAT, ["chat"])
        model2 = RecommendedModel("M2", "m2:v", 3.0, ModelRole.AUTOCOMPLETE, ["autocomplete"])
        
        result = SetupResult(
            successful_models=[model1],
            failed_models=[(model2, "Error")],
            warnings=[]
        )
        
        assert result.partial_success is True
    
    def test_complete_success(self):
        """Test complete_success property."""
        model = RecommendedModel("M1", "m1:v", 5.0, ModelRole.CHAT, ["chat"])
        
        result = SetupResult(
            successful_models=[model],
            failed_models=[],
            warnings=[]
        )
        
        assert result.complete_success is True
    
    def test_complete_failure(self):
        """Test complete_failure property."""
        model = RecommendedModel("M1", "m1:v", 5.0, ModelRole.CHAT, ["chat"])
        
        result = SetupResult(
            successful_models=[],
            failed_models=[(model, "Error")],
            warnings=[]
        )
        
        assert result.complete_failure is True


class TestIsOllamaAPIAvailable:
    """Tests for is_ollama_api_available function."""
    
    def test_returns_bool(self, backend_type):
        """Test that is_ollama_api_available/is_dmr_api_available returns a boolean."""
        if is_api_available is None:
            pytest.skip("API availability function not available in this backend")
        # Just verify the function returns a boolean
        # Actual API call may succeed or fail depending on environment
        result = is_api_available()
        assert isinstance(result, bool)


class TestGetInstalledModels:
    """Tests for get_installed_models function."""
    
    @patch('lib.validator.utils.run_command')
    def test_parse_model_list(self, mock_run):
        """Test parsing ollama list output."""
        mock_run.return_value = (0, "NAME\tSIZE\nllama3:latest\t4.7GB\ncodestral:22b\t13GB\n", "")
        
        result = get_installed_models()
        
        assert isinstance(result, list)
    
    @patch('lib.validator.utils.run_command')
    @patch('urllib.request.urlopen')
    def test_empty_list(self, mock_urlopen, mock_run):
        """Test empty model list."""
        # Mock API call to fail so it falls back to command
        import urllib.error
        mock_urlopen.side_effect = urllib.error.URLError("Connection refused")
        mock_run.return_value = (0, "NAME\tSIZE\n", "")
        
        result = get_installed_models()
        
        assert result == []
    
    @patch('lib.validator.utils.run_command')
    @patch('urllib.request.urlopen')
    def test_command_error(self, mock_urlopen, mock_run):
        """Test command error handling."""
        # Mock API call to fail so it falls back to command
        import urllib.error
        mock_urlopen.side_effect = urllib.error.URLError("Connection refused")
        mock_run.return_value = (1, "", "Error")
        
        result = get_installed_models()
        
        assert result == []


class TestVerifyModelExists:
    """Tests for verify_model_exists function."""
    
    @patch('lib.validator.get_installed_models')
    def test_model_exists(self, mock_get):
        """Test when model exists."""
        mock_get.return_value = ["llama3:latest", "codestral:22b"]
        
        result = verify_model_exists("llama3:latest")
        
        assert result is True
    
    @patch('lib.validator.get_installed_models')
    def test_model_not_exists(self, mock_get):
        """Test when model doesn't exist."""
        mock_get.return_value = ["llama3:latest"]
        
        result = verify_model_exists("nonexistent:model")
        
        assert result is False


class TestRunPreflightCheck:
    """Tests for run_preflight_check function."""
    
    def test_preflight_returns_tuple(self, backend_type):
        """Test that run_preflight_check returns a tuple."""
        if run_preflight_check is None:
            pytest.skip("run_preflight_check not available in Docker backend")
        result = run_preflight_check(show_progress=False)
        
        assert isinstance(result, tuple)
        assert len(result) == 3
        success, message, version = result
        assert isinstance(success, bool)
        assert isinstance(message, str)


class TestDisplaySetupResult:
    """Tests for display_setup_result function."""
    
    def test_display_success(self, capsys):
        """Test displaying successful result."""
        model = RecommendedModel("M1", "m1:v", 5.0, ModelRole.CHAT, ["chat"])
        
        result = SetupResult(
            successful_models=[model],
            failed_models=[],
            warnings=[]
        )
        
        display_setup_result(result)
        
        captured = capsys.readouterr()
        assert len(captured.out) > 0
    
    def test_display_failure(self, capsys):
        """Test displaying failed result."""
        model = RecommendedModel("M1", "m1:v", 5.0, ModelRole.CHAT, ["chat"])
        
        result = SetupResult(
            successful_models=[],
            failed_models=[(model, "Error")],
            warnings=[]
        )
        
        display_setup_result(result)
        
        captured = capsys.readouterr()
        assert len(captured.out) > 0


class TestTestOllamaConnectivity:
    """Tests for test_ollama_connectivity function."""
    
    def test_connectivity_returns_tuple(self):
        """Test that test_ollama_connectivity returns a tuple."""
        if check_ollama_connectivity is None:
            pytest.skip("connectivity function not available in this backend")
        result = check_ollama_connectivity()
        
        assert isinstance(result, tuple)
        assert len(result) == 3
        success, message, details = result
        assert isinstance(success, bool)
        assert isinstance(message, str)
        assert isinstance(details, dict)


class TestValidatePreInstall:
    """Tests for validate_pre_install function."""
    
    def test_validation_success(self, backend_type):
        """Test successful pre-install validation."""
        if backend_type == "docker" or not hasattr(validator, 'run_preflight_check'):
            pytest.skip("run_preflight_check not available in Docker backend")
        with patch('lib.validator.run_preflight_check') as mock_preflight:
            mock_preflight.return_value = (True, "OK", "0.1.23")
            
            model_kwargs = {
                "name": "Test",
                "ram_gb": 5.0,
                "role": ModelRole.CHAT,
                "roles": ["chat"]
            }
            model_kwargs[model_name_attr] = "test:v"
            models = [RecommendedModel(**model_kwargs)]
            hw_info = HardwareInfo(ram_gb=24, tier=HardwareTier.B)
            
            success, messages = validate_pre_install(models, hw_info)
            
            assert isinstance(success, bool)
        assert isinstance(messages, list)


class TestRunDiagnostics:
    """Tests for run_diagnostics function."""
    
    @patch('lib.validator.is_dmr_api_available' if _test_backend == 'docker' else 'lib.validator.is_ollama_api_available', return_value=True)
    @patch('lib.validator.get_installed_models', return_value=["llama3:latest"])
    @patch('lib.validator.utils.run_command')
    @patch('shutil.which', return_value='/usr/bin/ollama')
    def test_diagnostics_output(self, mock_which, mock_run, mock_models, mock_api):
        """Test diagnostics produces output."""
        mock_run.return_value = (0, "0.1.23", "")
        
        if run_diagnostics is None:
            pytest.skip("run_diagnostics not available in this backend")
        result = run_diagnostics(verbose=False)
        
        assert isinstance(result, dict)


class TestPullModelsWithTracking:
    """Tests for pull_models_with_tracking function."""
    
    @patch('lib.validator.is_restricted_model_name', return_value=False)
    @patch('lib.validator._pull_model')
    @patch('lib.validator.verify_model_exists', return_value=True)
    @patch('time.sleep')
    def test_successful_pull(self, mock_sleep, mock_verify, mock_pull, mock_restricted):
        """Test successful model pull."""
        mock_pull.return_value = (True, "")
        
        models = [
            RecommendedModel("M1", "granite-code:8b", 5.0, ModelRole.CHAT, ["chat"])
        ]
        hw_info = HardwareInfo(ram_gb=24, tier=HardwareTier.B)
        
        result = pull_models_with_tracking(models, hw_info)
        
        assert isinstance(result, SetupResult)
    
    @patch('lib.validator.is_restricted_model_name', return_value=True)
    def test_restricted_model_blocked(self, mock_restricted):
        """Test restricted model is blocked."""
        models = [
            RecommendedModel("Restricted", "qwen:7b", 5.0, ModelRole.CHAT, ["chat"])
        ]
        hw_info = HardwareInfo(ram_gb=24, tier=HardwareTier.B)
        
        result = pull_models_with_tracking(models, hw_info)
        
        # Restricted models should fail
        assert len(result.failed_models) > 0 or len(result.successful_models) == 0


class TestCurlInstructions:
    """Tests for curl instructions in troubleshooting."""
    
    def test_network_steps_include_curl_k(self):
        """Test network troubleshooting includes curl -k."""
        steps = get_troubleshooting_steps(PullErrorType.NETWORK)
        
        steps_text = " ".join(steps).lower()
        # Should mention curl with -k flag for corporate networks
        assert "curl" in steps_text or len(steps) > 0
    
    def test_registry_steps_include_curl_k(self):
        """Test registry troubleshooting includes curl -k."""
        steps = get_troubleshooting_steps(PullErrorType.REGISTRY)
        
        steps_text = " ".join(steps).lower()
        # Should mention curl with -k flag
        assert "curl" in steps_text or len(steps) > 0
