"""
Unit tests for lib/validator.py.

Tests model validation, pulling, error classification, and diagnostics.
"""

import json
import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib import validator
from lib.model_selector import RecommendedModel, ModelRole
from lib.hardware import HardwareTier


# =============================================================================
# Error Classification Tests
# =============================================================================

class TestErrorClassification:
    """Tests for pull error classification."""
    
    @pytest.mark.parametrize("error_msg,expected_type", [
        ("ssh: no key found", validator.PullErrorType.SSH_KEY),
        ("SSH_AUTH_SOCK error", validator.PullErrorType.SSH_KEY),
        ("connection refused", validator.PullErrorType.NETWORK),
        ("connection reset by peer", validator.PullErrorType.NETWORK),
        ("timeout connecting", validator.PullErrorType.NETWORK),
        ("could not resolve host", validator.PullErrorType.NETWORK),
        ("unauthorized", validator.PullErrorType.AUTH),
        ("403 forbidden", validator.PullErrorType.AUTH),
        ("is ollama running", validator.PullErrorType.SERVICE),
        ("service unavailable", validator.PullErrorType.SERVICE),
        ("registry.ollama.ai error", validator.PullErrorType.REGISTRY),
        ("manifest unknown", validator.PullErrorType.REGISTRY),
        ("no space left on device", validator.PullErrorType.DISK),
        ("permission denied", validator.PullErrorType.DISK),
        ("model not found", validator.PullErrorType.MODEL_NOT_FOUND),
        ("unknown model", validator.PullErrorType.MODEL_NOT_FOUND),
        ("some random error", validator.PullErrorType.UNKNOWN),
    ])
    def test_classify_pull_error(self, error_msg, expected_type):
        """Test error classification for various error messages."""
        result = validator.classify_pull_error(error_msg)
        assert result == expected_type, f"'{error_msg}' should classify as {expected_type}"
    
    def test_classify_empty_error(self):
        """Test classification of empty error message."""
        result = validator.classify_pull_error("")
        assert result == validator.PullErrorType.UNKNOWN


# =============================================================================
# Troubleshooting Steps Tests
# =============================================================================

class TestTroubleshootingSteps:
    """Tests for troubleshooting step generation."""
    
    def test_ssh_key_steps(self):
        """Test SSH key error troubleshooting steps."""
        steps = validator.get_troubleshooting_steps(validator.PullErrorType.SSH_KEY)
        
        assert len(steps) > 0
        # Should mention SSH_AUTH_SOCK
        steps_text = " ".join(steps)
        assert "SSH" in steps_text.upper()
    
    def test_network_steps(self):
        """Test network error troubleshooting steps."""
        steps = validator.get_troubleshooting_steps(validator.PullErrorType.NETWORK)
        
        assert len(steps) > 0
        steps_text = " ".join(steps)
        assert "network" in steps_text.lower() or "connection" in steps_text.lower()
    
    def test_unknown_error_steps(self):
        """Test unknown error troubleshooting steps."""
        steps = validator.get_troubleshooting_steps(validator.PullErrorType.UNKNOWN)
        
        assert len(steps) > 0
        # Should include general restart advice
        steps_text = " ".join(steps)
        assert "restart" in steps_text.lower() or "reinstall" in steps_text.lower()


# =============================================================================
# API Availability Tests
# =============================================================================

class TestAPIAvailability:
    """
    Tests for Ollama API availability checks.
    
    CRITICAL: All API calls must use SSL context for corporate proxy compatibility.
    """
    
    @patch('urllib.request.urlopen')
    def test_is_ollama_api_available_success(self, mock_urlopen):
        """
        Test API availability when Ollama is running.
        
        Specification:
        - Returns True when API responds with HTTP 200
        - Must use SSL context for corporate compatibility
        """
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.__enter__ = Mock(return_value=mock_response)
        mock_response.__exit__ = Mock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        result = validator.is_ollama_api_available()
        
        # Verify result
        assert result is True, "Should return True when API is available"
        
        # Verify SSL context was used
        if mock_urlopen.called:
            _, kwargs = mock_urlopen.call_args
            assert "context" in kwargs, \
                "CRITICAL: SSL context MUST be passed for corporate proxy compatibility"
    
    @patch('urllib.request.urlopen')
    def test_is_ollama_api_available_failure(self, mock_urlopen):
        """
        Test API availability when Ollama is not running.
        
        Specification:
        - Returns False when connection is refused
        - Should not raise exception
        """
        import urllib.error
        mock_urlopen.side_effect = urllib.error.URLError("Connection refused")
        
        result = validator.is_ollama_api_available()
        
        # Verify graceful failure
        assert result is False, "Should return False when API is unavailable"
    
    @patch('urllib.request.urlopen')
    def test_is_ollama_api_available_timeout(self, mock_urlopen):
        """
        Test API availability on timeout.
        
        Specification:
        - Returns False on timeout
        - Should not raise exception
        """
        import socket
        mock_urlopen.side_effect = socket.timeout("Connection timed out")
        
        result = validator.is_ollama_api_available()
        
        assert result is False, "Should return False on timeout"


# =============================================================================
# Model Verification Tests
# =============================================================================

class TestModelVerification:
    """Tests for model verification."""
    
    @patch('lib.validator.get_installed_models')
    def test_verify_model_exists_exact_match(self, mock_get_models):
        """Test model verification with exact name match."""
        mock_get_models.return_value = ["qwen2.5-coder:7b", "nomic-embed-text"]
        
        result = validator.verify_model_exists("qwen2.5-coder:7b")
        assert result is True
    
    @patch('lib.validator.get_installed_models')
    def test_verify_model_exists_base_name_match(self, mock_get_models):
        """Test model verification with base name match."""
        mock_get_models.return_value = ["qwen2.5-coder:7b-q4"]
        
        result = validator.verify_model_exists("qwen2.5-coder:7b")
        assert result is True
    
    @patch('lib.validator.get_installed_models')
    def test_verify_model_not_exists(self, mock_get_models):
        """Test model verification when model doesn't exist."""
        mock_get_models.return_value = ["qwen2.5-coder:7b"]
        
        result = validator.verify_model_exists("codestral:22b")
        assert result is False


# =============================================================================
# Pull Model Tests
# =============================================================================

class TestPullModel:
    """Tests for model pulling functionality."""
    
    @patch('subprocess.Popen')
    @patch('lib.utils.run_command')
    def test_pull_model_single_attempt_success(self, mock_run, mock_popen):
        """Test successful single pull attempt."""
        mock_process = MagicMock()
        mock_process.stdout = iter(["pulling manifest", "success"])
        mock_process.stderr = MagicMock()
        mock_process.stderr.read.return_value = ""
        mock_process.wait.return_value = None
        mock_process.returncode = 0
        mock_process.poll.return_value = 0
        mock_popen.return_value = mock_process
        
        with patch('lib.ui.print_success'):
            success, error = validator._pull_model_single_attempt("test:model", show_progress=True)
        
        assert success is True
        assert error == ""
    
    @patch('lib.utils.run_command')
    def test_pull_model_single_attempt_failure(self, mock_run):
        """Test failed single pull attempt."""
        mock_run.return_value = (1, "", "error: model not found")
        
        success, error = validator._pull_model_single_attempt("test:model", show_progress=False)
        
        assert success is False
        assert "not found" in error.lower() or error != ""
    
    @patch('lib.validator._pull_model_single_attempt')
    @patch('time.sleep')
    def test_pull_model_with_retry(self, mock_sleep, mock_pull):
        """Test pull with retry on failure."""
        # First attempt fails, second succeeds
        mock_pull.side_effect = [
            (False, "connection error"),
            (True, "")
        ]
        
        success, error = validator._pull_model("test:model", show_progress=False)
        
        assert success is True
        assert mock_pull.call_count >= 1
    
    @patch('lib.validator._pull_model_single_attempt')
    def test_pull_model_no_retry_for_not_found(self, mock_pull):
        """Test that model not found errors don't retry."""
        mock_pull.return_value = (False, "model not found")
        
        with patch('lib.ui.print_warning'):
            success, error = validator._pull_model("test:model", show_progress=False)
        
        assert success is False
        # Should only try once for model not found
        assert mock_pull.call_count == 1


# =============================================================================
# Pull Result Tests
# =============================================================================

class TestPullResult:
    """Tests for PullResult dataclass."""
    
    def test_pull_result_success(self):
        """Test successful PullResult."""
        model = RecommendedModel(
            name="Test",
            ollama_name="test:model",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat"],
            description="Test"
        )
        result = validator.PullResult(model=model, success=True, verified=True)
        
        assert result.success is True
        assert result.verified is True
        assert result.error_message == ""
    
    def test_pull_result_failure(self):
        """Test failed PullResult."""
        model = RecommendedModel(
            name="Test",
            ollama_name="test:model",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat"],
            description="Test"
        )
        result = validator.PullResult(
            model=model,
            success=False,
            error_message="Network error"
        )
        
        assert result.success is False
        assert "Network" in result.error_message


# =============================================================================
# Setup Result Tests
# =============================================================================

class TestSetupResult:
    """Tests for SetupResult dataclass."""
    
    def test_complete_success(self):
        """Test complete success detection."""
        model = RecommendedModel(
            name="Test",
            ollama_name="test:model",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat"],
            description="Test"
        )
        result = validator.SetupResult()
        result.successful_models.append(model)
        
        assert result.complete_success is True
        assert result.partial_success is False
        assert result.complete_failure is False
    
    def test_partial_success(self):
        """Test partial success detection."""
        model1 = RecommendedModel(
            name="Test1",
            ollama_name="test1:model",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat"],
            description="Test"
        )
        model2 = RecommendedModel(
            name="Test2",
            ollama_name="test2:model",
            ram_gb=5.0,
            role=ModelRole.EMBED,
            roles=["embed"],
            description="Test"
        )
        
        result = validator.SetupResult()
        result.successful_models.append(model1)
        result.failed_models.append((model2, "Error"))
        
        assert result.partial_success is True
        assert result.complete_success is False
        assert result.complete_failure is False
    
    def test_complete_failure(self):
        """Test complete failure detection."""
        model = RecommendedModel(
            name="Test",
            ollama_name="test:model",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat"],
            description="Test"
        )
        result = validator.SetupResult()
        result.failed_models.append((model, "Error"))
        
        assert result.complete_failure is True
        assert result.complete_success is False
        assert result.partial_success is False
    
    def test_complete_failure_no_models(self):
        """
        Test complete_failure when there are no models at all.
        
        Specification: complete_failure should be False when there are no models.
        """
        result = validator.SetupResult()
        
        # No models at all
        assert result.complete_failure is False, \
            "complete_failure should be False when there are no models"
        assert result.complete_success is False
        assert result.partial_success is False


# =============================================================================
# Connectivity Tests
# =============================================================================

class TestConnectivity:
    """Tests for connectivity testing."""
    
    @patch('urllib.request.urlopen')
    @patch('lib.utils.run_command')
    @patch('lib.ui.print_info')
    @patch('lib.ui.print_success')
    @patch('lib.ui.print_warning')
    @patch('lib.ui.print_error')
    def test_connectivity_all_pass(
        self, mock_error, mock_warning, mock_success,
        mock_info, mock_run, mock_urlopen
    ):
        """Test connectivity when all checks pass."""
        # Mock successful API response
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.__enter__ = Mock(return_value=mock_response)
        mock_response.__exit__ = Mock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        # Mock successful search
        mock_run.return_value = (0, "granite-code", "")
        
        success, message, details = validator.test_ollama_connectivity()
        
        assert success is True
        assert details["ollama_api"] is True


# =============================================================================
# Fallback Model Tests
# =============================================================================

class TestFallbackModels:
    """Tests for fallback model selection."""
    
    def test_get_fallback_for_embed(self):
        """Test getting fallback for embedding model."""
        model = RecommendedModel(
            name="Nomic Embed",
            ollama_name="nomic-embed-text",
            ram_gb=0.3,
            role=ModelRole.EMBED,
            roles=["embed"],
            description="Test"
        )
        
        fallback = validator.get_fallback_model(model, HardwareTier.C)
        
        assert fallback is not None
        assert fallback.role == ModelRole.EMBED
        assert fallback.ollama_name != model.ollama_name
    
    def test_get_fallback_for_chat(self):
        """Test getting fallback for chat model."""
        model = RecommendedModel(
            name="Primary",
            ollama_name="qwen2.5-coder:7b",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit"],
            description="Test"
        )
        
        fallback = validator.get_fallback_model(model, HardwareTier.C)
        
        assert fallback is not None
        assert fallback.ollama_name != model.ollama_name
    
    def test_get_fallback_uses_builtin(self):
        """Test that built-in fallback is tried first."""
        model = RecommendedModel(
            name="Primary",
            ollama_name="qwen2.5-coder:7b",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit"],
            description="Test",
            fallback_name="codellama:7b"
        )
        
        fallback = validator.get_fallback_model(model, HardwareTier.C)
        
        assert fallback is not None
        assert fallback.ollama_name == "codellama:7b"


# =============================================================================
# Pre-flight Check Tests
# =============================================================================

class TestPreflightCheck:
    """Tests for pre-flight checks."""
    
    @patch('lib.validator.is_ollama_api_available')
    @patch('lib.ui.print_info')
    def test_preflight_api_not_available(self, mock_info, mock_api):
        """Test pre-flight when API is not available."""
        mock_api.return_value = False
        
        success, message, error_type = validator.run_preflight_check(show_progress=False)
        
        assert success is False
        assert error_type == validator.PullErrorType.SERVICE


# =============================================================================
# Diagnostics Tests
# =============================================================================

class TestDiagnostics:
    """Tests for diagnostic functions."""
    
    @patch('lib.utils.run_command')
    @patch('urllib.request.urlopen')
    @patch('lib.validator._pull_model_single_attempt')
    @patch('lib.ui.print_header')
    @patch('lib.ui.print_success')
    @patch('lib.ui.print_warning')
    @patch('lib.ui.print_error')
    @patch('lib.ui.print_info')
    def test_run_diagnostics(
        self, mock_info, mock_error, mock_warning, mock_success,
        mock_header, mock_pull, mock_urlopen, mock_run
    ):
        """Test running full diagnostics."""
        # Mock ollama installed
        mock_run.side_effect = [
            (0, "ollama version 0.13.5", ""),  # --version
            (0, "NAME\nmodel1\n", ""),  # list
            (0, "", ""),  # other commands
        ]
        
        # Mock API available
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.__enter__ = Mock(return_value=mock_response)
        mock_response.__exit__ = Mock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        # Mock test pull
        mock_pull.return_value = (True, "")
        
        results = validator.run_diagnostics(verbose=False)
        
        assert "ollama_installed" in results
        assert "issues_found" in results
        assert "recommendations" in results
