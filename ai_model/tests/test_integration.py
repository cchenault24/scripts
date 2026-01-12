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
# Import backend module dynamically based on TEST_BACKEND
import os
_test_backend = os.environ.get('TEST_BACKEND', 'ollama').lower()
if _test_backend == 'docker':
    from lib import docker as backend_module
else:
    from lib import ollama as backend_module
from lib.hardware import HardwareTier, HardwareInfo
from lib.model_selector import ModelRole, RecommendedModel, ModelRecommendation


# =============================================================================
# Hardware → Model Selection Integration
# =============================================================================

class TestHardwareToModelSelection:
    """Tests for hardware detection → model recommendation flow."""
    
    def test_tier_c_gets_appropriate_models(self, mock_hardware_tier_c):
        """Test that Tier C hardware gets small models."""
        recommendation = model_selector.generate_best_recommendation(mock_hardware_tier_c)
        
        # Total RAM should fit in usable RAM
        total_ram = recommendation.total_ram()
        usable_ram = mock_hardware_tier_c.usable_ram_gb
        
        assert total_ram <= usable_ram, f"Models ({total_ram}GB) exceed usable RAM ({usable_ram}GB)"
        assert recommendation.primary is not None
        assert recommendation.embeddings is not None
    
    def test_tier_s_gets_larger_models(self, mock_hardware_tier_s):
        """Test that Tier S hardware gets larger models."""
        recommendation = model_selector.generate_best_recommendation(mock_hardware_tier_s)
        
        # Should still fit in usable RAM
        total_ram = recommendation.total_ram()
        usable_ram = mock_hardware_tier_s.usable_ram_gb
        
        assert total_ram <= usable_ram
        # Primary model should be larger than Tier C
        assert recommendation.primary.ram_gb >= 5.0
    
    @pytest.mark.parametrize("tier,max_primary_ram", [
        (HardwareTier.C, 6.0),   # Tier C: smaller models
        (HardwareTier.B, 8.0),   # Tier B: medium models
        (HardwareTier.A, 15.0),  # Tier A: larger models
        (HardwareTier.S, 20.0),  # Tier S: largest models
    ])
    def test_tier_model_sizing(self, tier, max_primary_ram, backend_type, api_endpoint):
        """Test that each tier gets appropriately sized models."""
        hw_kwargs = {
            "ram_gb": 16.0 if tier == HardwareTier.C else (
                24.0 if tier == HardwareTier.B else (
                    32.0 if tier == HardwareTier.A else 64.0
                )
            ),
            "tier": tier,
            "usable_ram_gb": 9.6 if tier == HardwareTier.C else (
                15.6 if tier == HardwareTier.B else (
                    22.4 if tier == HardwareTier.A else 44.8
                )
            ),
            "has_apple_silicon": True,
        }
        if backend_type == "ollama":
            hw_kwargs["ollama_available"] = True
            hw_kwargs["ollama_api_endpoint"] = api_endpoint
        else:
            hw_kwargs["docker_model_runner_available"] = True
            hw_kwargs["dmr_api_endpoint"] = api_endpoint
        hw_info = HardwareInfo(**hw_kwargs)
        
        recommendation = model_selector.generate_best_recommendation(hw_info)
        
        # Primary model should be within size limits
        assert recommendation.primary.ram_gb <= max_primary_ram


# =============================================================================
# Model Selection → Config Generation Integration
# =============================================================================

class TestModelSelectionToConfig:
    """Tests for model selection → config generation flow."""
    
    def test_recommended_models_normalize_for_config(self, mock_recommended_models):
        """Test that recommended models can be normalized for config."""
        models = mock_recommended_models.all_models()
        
        for model in models:
            normalized = config._normalize_model(model)
            
            assert "name" in normalized
            assert "roles" in normalized
            assert isinstance(normalized["roles"], list)
    
    def test_all_roles_represented_in_config(self, mock_recommended_models):
        """Test that all model roles are represented."""
        models = mock_recommended_models.all_models()
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
    
    def test_fallback_models_are_valid(self, mock_hardware_tier_c):
        """Test that fallback models are valid RecommendedModel objects."""
        # Get a recommended model
        recommendation = model_selector.generate_best_recommendation(mock_hardware_tier_c)
        primary = recommendation.primary
        
        # Get fallback
        fallback = validator.get_fallback_model(primary, mock_hardware_tier_c.tier)
        
        if fallback:
            assert isinstance(fallback, RecommendedModel)
            # Use backend-appropriate attribute
            model_name_attr = "ollama_name" if _test_backend == "ollama" else "docker_name"
            assert getattr(fallback, model_name_attr) != getattr(primary, model_name_attr)
            assert fallback.role == primary.role
    
    def test_setup_result_tracks_models_correctly(self, mock_recommended_models):
        """Test that SetupResult correctly tracks model status."""
        result = validator.SetupResult()
        models = mock_recommended_models.all_models()
        
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
    def test_verify_running_uses_api(self, mock_urlopen):
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
        if _test_backend == 'docker':
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
        self, mock_run, mock_exists, mock_system
    ):
        """Test that auto-start status checks launchctl."""
        mock_system.return_value = "Darwin"
        mock_exists.return_value = True
        mock_run.return_value = (0, "com.ollama.server", "")
        
        if _test_backend == 'docker':
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
        self, mock_run, mock_urlopen, mock_hardware_tier_c
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
        
        # Get recommendations
        recommendation = model_selector.generate_best_recommendation(mock_hardware_tier_c)
        models = recommendation.all_models()
        
        # Validate
        # Docker backend may not have run_preflight parameter
        try:
            is_valid, warnings = validator.validate_pre_install(
                models, mock_hardware_tier_c, run_preflight=False
            )
        except TypeError:
            # Docker backend doesn't have run_preflight parameter
            is_valid, warnings = validator.validate_pre_install(
                models, mock_hardware_tier_c
            )
        
        # Should be valid with no critical warnings
        assert is_valid is True
        # May have RAM warnings but shouldn't block
    
    def test_model_recommendation_matches_tier_reservation(self, mock_hardware_tier_c):
        """Test that model recommendations respect tier RAM reservation."""
        recommendation = model_selector.generate_best_recommendation(mock_hardware_tier_c)
        
        # Calculate expected usable RAM for Tier C (60% of total)
        expected_usable = mock_hardware_tier_c.ram_gb * 0.6
        
        # Total model RAM should be within usable
        total_model_ram = recommendation.total_ram()
        
        assert total_model_ram <= expected_usable, (
            f"Models ({total_model_ram}GB) exceed Tier C usable RAM ({expected_usable}GB)"
        )


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
    
    def test_models_normalize_for_manifest(self, mock_recommended_models):
        """Test that models can be normalized for manifest."""
        models = mock_recommended_models.all_models()
        
        for model in models:
            normalized = config._normalize_model(model)
            
            # Manifest needs these fields
            assert "name" in normalized
            assert "ram_gb" in normalized or normalized.get("ram_gb") is not None
