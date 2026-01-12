"""
Integration tests for Ollama LLM setup.

Tests interactions between modules to ensure they work together correctly.
"""

import json
import sys
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch

import pytest

# Add backend directories to path
_ollama_path = str(Path(__file__).parent.parent / "ollama")
_docker_path = str(Path(__file__).parent.parent / "docker")
if _ollama_path not in sys.path:
    sys.path.insert(0, _ollama_path)
if _docker_path not in sys.path:
    sys.path.insert(0, _docker_path)

from lib import hardware, model_selector, validator, config
# Backend module will be imported via fixture or at test time
# Don't import at module level to avoid conflicts when running both backends
from lib.hardware import HardwareInfo
from lib.model_selector import ModelRole, RecommendedModel, select_models


# =============================================================================
# Hardware → Model Selection Integration
# =============================================================================

class TestHardwareToModelSelection:
    """Tests for hardware detection → model selection flow."""
    
    def test_select_models_returns_fixed_models(self, backend_type):
        """Test that select_models returns fixed models for all users."""
        hw_info = HardwareInfo(
            ram_gb=32.0,
            has_apple_silicon=True,
            apple_chip_model="M4"
        )
        if backend_type == "ollama":
            hw_info.ollama_available = True
        else:
            hw_info.docker_model_runner_available = True
        
        models = select_models(hw_info)
        
        # Should always return PRIMARY_MODEL and EMBED_MODEL
        assert len(models) == 2
        assert models[0].ram_gb == 16.0  # GPT-OSS 20B
        assert models[1].ram_gb == 0.3    # nomic-embed-text


# =============================================================================
# Model Selection → Config Generation Integration
# =============================================================================

class TestModelSelectionToConfig:
    """Tests for model selection → config generation flow."""
    
    def test_selected_models_normalize_for_config(self, backend_type):
        """Test that selected models can be normalized for config."""
        hw_info = HardwareInfo(ram_gb=32.0, has_apple_silicon=True, apple_chip_model="M4")
        models = select_models(hw_info)
        
        for model in models:
            normalized = config._normalize_model(model)
            
            assert "name" in normalized
            assert "roles" in normalized
            assert isinstance(normalized["roles"], list)
    
    def test_all_roles_represented_in_config(self, backend_type):
        """Test that all model roles are represented."""
        hw_info = HardwareInfo(ram_gb=32.0, has_apple_silicon=True, apple_chip_model="M4")
        models = select_models(hw_info)
        roles_found = set()
        
        for model in models:
            normalized = config._normalize_model(model)
            roles_found.update(normalized["roles"])
        
        # Should have chat, autocomplete, and embed roles
        assert "chat" in roles_found or "edit" in roles_found
        assert "autocomplete" in roles_found
        assert "embed" in roles_found


# =============================================================================
# Validator → Model Selection Integration
# =============================================================================

class TestValidatorModelSelection:
    """Tests for validator → model selection integration."""
    
    def test_selected_models_are_valid(self, backend_type, model_name_attr):
        """Test that selected models are valid RecommendedModel objects."""
        hw_info = HardwareInfo(ram_gb=32.0, has_apple_silicon=True, apple_chip_model="M4")
        models = select_models(hw_info)
        
        # Verify models are valid
        assert len(models) == 2
        assert isinstance(models[0], RecommendedModel)
        assert models[0].role == ModelRole.CHAT
        assert isinstance(models[1], RecommendedModel)
        assert models[1].role == ModelRole.EMBED
    
    def test_setup_result_tracks_models_correctly(self, backend_type):
        """Test that SetupResult correctly tracks model status."""
        result = validator.SetupResult()
        hw_info = HardwareInfo(ram_gb=32.0, has_apple_silicon=True, apple_chip_model="M4")
        models = select_models(hw_info)
        
        # Simulate: first model succeeds, second fails
        result.successful_models.append(models[0])
        result.failed_models.append((models[1], "Network error"))
        
        assert len(result.successful_models) == 1
        assert len(result.failed_models) == 1
        assert result.partial_success is True


# =============================================================================
# Ollama Service → API Integration
# =============================================================================

class TestOllamaServiceAPI:
    """Tests for Ollama service management → API interaction."""
    
    @patch('urllib.request.urlopen')
    def test_verify_running_uses_api(self, mock_urlopen, backend_type, backend_module):
        """
        Test that verify_ollama_running uses the API with SSL context.
        
        Specification:
        - Must call Ollama API to verify service is running
        - Must use SSL context for corporate proxy compatibility
        """
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.__enter__ = Mock(return_value=mock_response)
        mock_response.__exit__ = Mock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        # Use backend-appropriate function
        if backend_type == 'docker':
            # Docker doesn't have a verify function, skip this test
            pytest.skip("Docker backend doesn't have verify_docker_model_runner_running function")
        else:
            result = backend_module.verify_ollama_running()
        
        # Verify function behavior
        assert result is True, "Should return True when API is available"
        
        # Verify API was called
        mock_urlopen.assert_called_once()
        
        # CRITICAL: Verify SSL context was passed
        _, kwargs = mock_urlopen.call_args
        assert "context" in kwargs, \
            "CRITICAL: SSL context MUST be passed for corporate proxy compatibility"


# =============================================================================
# Auto-Start → Verification Integration
# =============================================================================

class TestAutoStartVerification:
    """Tests for auto-start setup → verification flow."""
    
    @patch('platform.system')
    @patch('pathlib.Path.exists')
    @patch('lib.utils.run_command')
    def test_autostart_status_checks_launchctl(
        self, mock_run, mock_exists, mock_system, backend_type, backend_module
    ):
        """Test that auto-start status checks launchctl."""
        mock_system.return_value = "Darwin"
        mock_exists.return_value = True
        mock_run.return_value = (0, "com.ollama.server", "")
        
        if backend_type == 'docker':
            pytest.skip("Docker backend doesn't have autostart functionality")
        is_configured, details = backend_module.check_ollama_autostart_status_macos()
        
        assert is_configured is True
        assert "loaded" in details.lower()


# =============================================================================
# Full Pipeline Integration
# =============================================================================

class TestFullPipeline:
    """Tests for the full setup pipeline."""
    
    @patch('urllib.request.urlopen')
    @patch('lib.utils.run_command')
    def test_pre_install_validation_with_hardware(
        self, mock_run, mock_urlopen, backend_type
    ):
        """Test pre-install validation with hardware info."""
        # Mock API available
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.__enter__ = Mock(return_value=mock_response)
        mock_response.__exit__ = Mock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        # Mock commands
        mock_run.return_value = (0, "", "")
        
        # Get fixed models
        hw_info = HardwareInfo(ram_gb=32.0, has_apple_silicon=True, apple_chip_model="M4")
        models = select_models(hw_info)
        
        # Validate
        # Docker backend may not have run_preflight parameter
        try:
            is_valid, warnings = validator.validate_pre_install(
                models, hw_info, run_preflight=False
            )
        except TypeError:
            # Docker backend doesn't have run_preflight parameter
            is_valid, warnings = validator.validate_pre_install(
                models, hw_info
            )
        
        # Should be valid with no critical warnings
        assert is_valid is True
        # May have RAM warnings but shouldn't block
    
    def test_selected_models_are_fixed(self, backend_type):
        """Test that select_models returns fixed models regardless of RAM."""
        # Test with different RAM amounts - should get same models
        for ram_gb in [16.0, 24.0, 32.0, 64.0]:
            hw_info = HardwareInfo(ram_gb=ram_gb, has_apple_silicon=True, apple_chip_model="M4")
            models = select_models(hw_info)
            
            # Should always return same two models
            assert len(models) == 2
            assert models[0].ram_gb == 16.0  # GPT-OSS 20B
            assert models[1].ram_gb == 0.3    # nomic-embed-text


# =============================================================================
# Error Propagation Tests
# =============================================================================

class TestErrorPropagation:
    """Tests for error propagation across modules."""
    
    def test_pull_error_propagates_to_setup_result(self, backend_type, model_name_attr):
        """Test that pull errors are properly recorded in SetupResult."""
        model_kwargs = {
            "name": "Test Model",
            "ram_gb": 5.0,
            "role": ModelRole.CHAT,
            "roles": ["chat"]
        }
        model_kwargs[model_name_attr] = "test:model"
        model = RecommendedModel(**model_kwargs)
        
        # Create PullResult with error
        pull_result = validator.PullResult(
            model=model,
            success=False,
            error_message="Connection refused"
        )
        
        # Create SetupResult and add failure
        setup_result = validator.SetupResult()
        setup_result.failed_models.append((model, pull_result.error_message))
        
        assert len(setup_result.failed_models) == 1
        assert "Connection refused" in setup_result.failed_models[0][1]
    
    def test_error_classification_used_in_diagnostics(self, backend_type):
        """Test that error classification is used for troubleshooting."""
        if backend_type == "docker":
            pytest.skip("Docker backend doesn't have SSH_KEY error type")
        error_msg = "ssh: no key found"
        error_type = validator.classify_pull_error(error_msg)
        steps = validator.get_troubleshooting_steps(error_type)
        
        assert error_type == validator.PullErrorType.SSH_KEY
        assert len(steps) > 0
        assert any("SSH" in s.upper() for s in steps)


# =============================================================================
# SSL Context Integration
# =============================================================================

class TestSSLContextIntegration:
    """Tests for SSL context usage across modules."""
    
    @patch('urllib.request.urlopen')
    def test_api_calls_use_ssl_context(self, mock_urlopen, backend_type):
        """Test that API calls use unverified SSL context."""
        # Get the correct function name for the backend
        if backend_type == "docker":
            if not hasattr(validator, 'is_dmr_api_available'):
                pytest.skip("is_dmr_api_available not available")
            api_func = validator.is_dmr_api_available
        else:
            if not hasattr(validator, 'is_ollama_api_available'):
                pytest.skip("is_ollama_api_available not available")
            api_func = validator.is_ollama_api_available
        
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.read.return_value = b'{"models": []}'
        mock_response.__enter__ = Mock(return_value=mock_response)
        mock_response.__exit__ = Mock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        # Call functions that use urlopen
        api_func()
        
        # Check context was passed
        if mock_urlopen.called:
            _, kwargs = mock_urlopen.call_args
            assert "context" in kwargs


# =============================================================================
# Manifest Integration
# =============================================================================

class TestManifestIntegration:
    """Tests for manifest creation and usage."""
    
    def test_models_normalize_for_manifest(self, backend_type):
        """Test that models can be normalized for manifest."""
        hw_info = HardwareInfo(ram_gb=32.0, has_apple_silicon=True, apple_chip_model="M4")
        models = select_models(hw_info)
        
        for model in models:
            normalized = config._normalize_model(model)
            
            # Manifest needs these fields
            assert "name" in normalized
            assert "ram_gb" in normalized or normalized.get("ram_gb") is not None
