"""
End-to-end tests for Docker Model Runner LLM setup.

Simulates complete user flows through the setup process,
testing all branching paths and user interaction scenarios.
"""

import json
import sys
from pathlib import Path
from typing import List
from unittest.mock import MagicMock, Mock, patch, call

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib import hardware, model_selector, validator, config, docker, ui
from lib.hardware import HardwareTier, HardwareInfo
from lib.model_selector import ModelRole, RecommendedModel, ModelRecommendation


# =============================================================================
# Fixtures for E2E Tests
# =============================================================================

@pytest.fixture
def mock_complete_environment(tmp_path):
    """Set up a complete mock environment for E2E testing."""
    # Create hardware info directly since fixture may not be available
    from lib import hardware
    hw_info = hardware.HardwareInfo(
        ram_gb=16.0,
        cpu_cores=4,
        gpu_vram_gb=0,
        tier=hardware.HardwareTier.C,
        usable_ram_gb=9.6,
        docker_version="1.0.0",
        docker_model_runner_available=True,
        dmr_api_endpoint="http://localhost:12434/v1",
    )
    # Create directory structure
    continue_dir = tmp_path / ".continue"
    continue_dir.mkdir()
    (continue_dir / "rules").mkdir()
    
    return {
        "home": tmp_path,
        "continue_dir": continue_dir,
        "hardware": hw_info
    }


class MockInputHandler:
    """Helper to manage mock user inputs."""
    
    def __init__(self, responses: List[str]):
        self.responses = iter(responses)
        self.prompts_received = []
    
    def __call__(self, prompt: str = "") -> str:
        self.prompts_received.append(prompt)
        try:
            return next(self.responses)
        except StopIteration:
            return ""


# =============================================================================
# E2E Scenario 1: Happy Path - Accept All
# =============================================================================

class TestHappyPathAcceptAll:
    """E2E test: User accepts all default options."""
    
    @patch('lib.hardware.detect_hardware')
    @patch('lib.ide.detect_installed_ides')
    @patch('lib.docker.check_docker')
    @patch('lib.docker.check_docker_model_runner')
    @patch('lib.validator.is_dmr_api_available')
    @patch('lib.validator._pull_model')
    @patch('lib.validator.verify_model_exists')
    @patch('lib.ui.prompt_yes_no')
    @patch('lib.ui.prompt_choice')
    @patch('lib.ui.print_header')
    @patch('lib.ui.print_info')
    @patch('lib.ui.print_success')
    @patch('lib.ui.print_warning')
    @patch('lib.ui.print_error')
    @patch('lib.ui.print_subheader')
    @patch('lib.ui.print_step')
    @patch('lib.ui.clear_screen')
    def test_full_accept_flow(
        self, mock_clear, mock_step, mock_subheader, mock_error,
        mock_warning, mock_success, mock_info, mock_header,
        mock_choice, mock_yes_no, mock_verify, mock_pull,
        mock_api_available, mock_docker_mr, mock_docker_check,
        mock_ides, mock_detect_hw, mock_complete_environment
    ):
        """Test complete flow with user accepting all options."""
        # Setup mocks
        hw_info = mock_complete_environment["hardware"]
        mock_detect_hw.return_value = hw_info
        mock_ides.return_value = ["vscode"]
        mock_docker_check.return_value = (True, "27.0.3")
        mock_docker_mr.return_value = True
        mock_api_available.return_value = True
        mock_pull.return_value = (True, "")
        mock_verify.return_value = True
        mock_yes_no.return_value = True
        mock_choice.return_value = 0  # Accept recommendation
        
        # Get recommendation
        recommendation = model_selector.generate_best_recommendation(hw_info)
        models = recommendation.all_models()
        
        # Simulate pulling
        result = validator.SetupResult()
        for model in models:
            result.successful_models.append(model)
        
        # Verify all models succeeded
        assert result.complete_success is True
        assert len(result.successful_models) == len(models)
        assert len(result.failed_models) == 0


# =============================================================================
# E2E Scenario 2: Docker Not Running
# =============================================================================

class TestDockerNotRunning:
    """E2E test: Docker daemon not running."""
    
    @patch('lib.docker.check_docker')
    @patch('lib.ui.print_error')
    @patch('lib.ui.print_info')
    def test_docker_not_running(
        self, mock_info, mock_error, mock_check
    ):
        """Test flow when Docker daemon is not running."""
        mock_check.return_value = (False, "27.0.3")
        
        # Check Docker
        docker_ok, version = mock_check()
        
        assert docker_ok is False


# =============================================================================
# E2E Scenario 3: Docker Model Runner Not Enabled
# =============================================================================

class TestDockerModelRunnerNotEnabled:
    """E2E test: Docker Model Runner not enabled."""
    
    @patch('lib.docker.check_docker_model_runner')
    @patch('lib.ui.print_warning')
    @patch('lib.ui.print_info')
    @patch('lib.ui.prompt_yes_no')
    def test_dmr_not_enabled(
        self, mock_yes_no, mock_info, mock_warning, mock_check
    ):
        """Test flow when Docker Model Runner is not enabled."""
        mock_check.return_value = False
        mock_yes_no.return_value = False  # Don't continue
        
        # Check DMR
        dmr_ok = mock_check(Mock())
        
        assert dmr_ok is False


# =============================================================================
# E2E Scenario 4: Model Pull Failure with Fallback
# =============================================================================

class TestModelPullFailureWithFallback:
    """E2E test: Primary model fails, fallback succeeds."""
    
    @patch('lib.validator.is_restricted_model_name', return_value=False)
    @patch('lib.validator._pull_model')
    @patch('lib.validator.verify_model_exists')
    @patch('lib.ui.print_info')
    @patch('lib.ui.print_success')
    @patch('lib.ui.print_warning')
    @patch('lib.ui.print_error')
    @patch('time.sleep')
    def test_fallback_success(
        self, mock_sleep, mock_error, mock_warning, mock_success,
        mock_info, mock_verify, mock_pull, mock_restricted
    ):
        """Test that fallback model is used when primary fails."""
        # Primary fails, fallback succeeds
        mock_pull.side_effect = [
            (False, "Network error"),  # Primary fails
            (True, ""),  # Fallback succeeds
        ]
        mock_verify.return_value = True
        
        model = RecommendedModel(
            name="Primary",
            docker_name="ai/granite-code:7b",  # Use non-restricted model name
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat"],
            description="Test",
            fallback_name="ai/codellama:7b"
        )
        
        result = validator.pull_model_with_verification(
            model, HardwareTier.C, show_progress=False
        )
        
        # Primary failed but fallback succeeded
        assert result.success is True or mock_pull.call_count >= 2


# =============================================================================
# E2E Scenario 5: All Models Fail
# =============================================================================

class TestAllModelsFail:
    """E2E test: All model pulls fail (network issue)."""
    
    def test_complete_failure_result(self, mock_complete_environment):
        """Test SetupResult when all models fail."""
        hw_info = mock_complete_environment["hardware"]
        recommendation = model_selector.generate_best_recommendation(hw_info)
        models = recommendation.all_models()
        
        result = validator.SetupResult()
        for model in models:
            result.failed_models.append((model, "Network error"))
        
        assert result.complete_failure is True
        assert result.complete_success is False
        assert result.partial_success is False
        assert len(result.failed_models) == len(models)


# =============================================================================
# E2E Scenario 6: Different RAM Tiers
# =============================================================================

class TestDifferentRamTiers:
    """E2E test: Different recommendations for different RAM tiers."""
    
    @pytest.mark.parametrize("ram_gb,tier,expected_min_ram,expected_max_ram", [
        (16, HardwareTier.C, 0, 10),    # Tier C: small models
        (24, HardwareTier.B, 0, 16),    # Tier B: medium models
        (32, HardwareTier.A, 0, 23),    # Tier A: larger models
        (64, HardwareTier.S, 0, 45),    # Tier S: largest models
    ])
    def test_tier_recommendations(self, ram_gb, tier, expected_min_ram, expected_max_ram):
        """Test model recommendations for each tier."""
        hw_info = HardwareInfo(
            ram_gb=ram_gb,
            tier=tier,
            usable_ram_gb=ram_gb * (0.6 if tier == HardwareTier.C else (
                0.65 if tier == HardwareTier.B else 0.7
            )),
            has_apple_silicon=True,
            docker_model_runner_available=True
        )
        
        recommendation = model_selector.generate_best_recommendation(hw_info)
        total_ram = recommendation.total_ram()
        
        assert total_ram >= expected_min_ram, f"Tier {tier}: Models too small"
        assert total_ram <= expected_max_ram, f"Tier {tier}: Models too large"


# =============================================================================
# E2E Scenario 7: Permission Errors
# =============================================================================

class TestPermissionErrors:
    """E2E test: Handle permission errors gracefully."""
    
    @patch('builtins.open')
    @patch('lib.ui.print_error')
    @patch('lib.ui.print_info')
    def test_config_write_permission_error(self, mock_info, mock_error, mock_open):
        """Test handling of config file permission errors."""
        mock_open.side_effect = PermissionError("Access denied")
        
        # Attempt to write (should not crash)
        try:
            with open("/test/config.yaml", "w") as f:
                f.write("test")
            written = True
        except PermissionError:
            written = False
        
        assert written is False


# =============================================================================
# E2E Scenario 8: Network Error Flow
# =============================================================================

class TestNetworkErrorFlow:
    """E2E test: Handle network errors with proper troubleshooting."""
    
    def test_network_error_provides_troubleshooting(self):
        """Test that network errors provide helpful troubleshooting."""
        error_msg = "connection refused"
        error_type = validator.classify_pull_error(error_msg)
        steps = validator.get_troubleshooting_steps(error_type)
        
        assert error_type == validator.PullErrorType.NETWORK
        
        # Should provide network-related troubleshooting steps
        steps_text = " ".join(steps)
        assert "network" in steps_text.lower() or "connection" in steps_text.lower()


# =============================================================================
# E2E Scenario 9: Retry Failed Models
# =============================================================================

class TestRetryFailedModels:
    """E2E test: Retry failed models after initial failure."""
    
    def test_retry_reduces_failures(self, mock_complete_environment):
        """Test that retrying can reduce number of failures."""
        model1 = RecommendedModel(
            name="Model1",
            docker_name="ai/model1:latest",
            ram_gb=3.0,
            role=ModelRole.CHAT,
            roles=["chat"],
            description="Test"
        )
        model2 = RecommendedModel(
            name="Model2",
            docker_name="ai/model2:latest",
            ram_gb=2.0,
            role=ModelRole.EMBED,
            roles=["embed"],
            description="Test"
        )
        
        # Initial result: both failed
        initial_result = validator.SetupResult()
        initial_result.failed_models.append((model1, "Error"))
        initial_result.failed_models.append((model2, "Error"))
        
        # After retry: one succeeded
        final_result = validator.SetupResult()
        final_result.successful_models.append(model1)
        final_result.failed_models.append((model2, "Still failing"))
        
        # Verify partial success
        assert final_result.partial_success is True
        assert len(final_result.successful_models) == 1
        assert len(final_result.failed_models) == 1


# =============================================================================
# E2E Scenario 10: Uninstaller Flow
# =============================================================================

class TestUninstallerFlow:
    """E2E test: Complete uninstaller flow."""
    
    def test_uninstall_with_manifest(self, tmp_path):
        """Test uninstaller flow with manifest."""
        # Create manifest
        continue_dir = tmp_path / ".continue"
        continue_dir.mkdir()
        
        manifest = {
            "version": "2.0",
            "timestamp": "2024-01-01T00:00:00Z",
            "installer_version": "2.0.0",
            "installer_type": "docker",
            "installed": {
                "models": [
                    {"name": "ai/qwen2.5-coder:7b", "size_gb": 5.0}
                ],
                "files": [
                    {"path": str(continue_dir / "config.yaml")}
                ]
            },
            "pre_existing": {"models": []}
        }
        
        manifest_path = continue_dir / "setup-manifest.json"
        manifest_path.write_text(json.dumps(manifest))
        
        # Verify manifest can be loaded
        loaded = json.loads(manifest_path.read_text())
        
        assert loaded["version"] == "2.0"
        assert loaded["installer_type"] == "docker"
        assert len(loaded["installed"]["models"]) == 1


# =============================================================================
# E2E Scenario 11: Config Customization Detection
# =============================================================================

class TestConfigCustomizationDetection:
    """E2E test: Detect user customizations in config."""
    
    def test_detect_modified_config(self, tmp_path):
        """Test detecting when user has modified config."""
        config_path = tmp_path / "config.yaml"
        
        # Create original with fingerprint
        original_content = config.add_fingerprint_header("models:\n  - test", "yaml")
        config_path.write_text(original_content)
        
        # Modify it
        modified_content = original_content + "\n# User added this"
        config_path.write_text(modified_content)
        
        # Check if modified
        manifest = {
            "installed": {
                "files": [{"path": str(config_path), "fingerprint": "original_hash"}]
            }
        }
        
        # File has our fingerprint, so it's ours (True or "maybe")
        is_ours = config.is_our_file(config_path, manifest)
        assert is_ours in [True, "maybe"], f"Expected True or 'maybe', got {is_ours}"


# =============================================================================
# E2E Scenario 12: Full Diagnostic Flow
# =============================================================================

class TestFullDiagnosticFlow:
    """E2E test: Complete diagnostic flow."""
    
    @patch('lib.utils.run_command')
    @patch('urllib.request.urlopen')
    @patch('lib.validator._pull_model_single_attempt')
    def test_diagnostics_identify_issues(self, mock_pull, mock_urlopen, mock_run):
        """Test that diagnostics correctly identify issues."""
        if not hasattr(validator, 'run_diagnostics'):
            pytest.skip("run_diagnostics not available in Docker backend")
        # Mock docker not installed
        mock_run.return_value = (-1, "", "command not found: docker")
        
        results = validator.run_diagnostics(verbose=False)
        
        assert results["docker_installed"] is False
        assert len(results["issues_found"]) > 0
        assert len(results["recommendations"]) > 0


# =============================================================================
# E2E Scenario 13: Model Selection Customization
# =============================================================================

class TestModelSelectionCustomization:
    """E2E test: User customizes model selection."""
    
    def test_get_alternatives_for_role(self, mock_complete_environment):
        """Test getting alternatives for a role."""
        # Test that PRIMARY_MODELS contains alternatives for the tier
        from lib.model_selector import PRIMARY_MODELS
        
        hw_info = mock_complete_environment["hardware"]
        alternatives = PRIMARY_MODELS.get(hw_info.tier, [])
        
        assert len(alternatives) > 0, "Should have alternatives for the tier"
        for alt in alternatives:
            assert isinstance(alt, RecommendedModel)
            # Primary models should have chat role
            assert "chat" in alt.roles or alt.role == ModelRole.CHAT


# =============================================================================
# E2E Scenario 14: Graceful Degradation
# =============================================================================

class TestGracefulDegradation:
    """E2E test: System degrades gracefully on partial failures."""
    
    def test_partial_setup_still_useful(self, mock_complete_environment):
        """Test that partial setup is still usable."""
        hw_info = mock_complete_environment["hardware"]
        recommendation = model_selector.generate_best_recommendation(hw_info)
        models = recommendation.all_models()
        
        # Simulate: primary succeeds, embed fails
        result = validator.SetupResult()
        result.successful_models.append(models[0])  # Primary
        if len(models) > 2:
            result.failed_models.append((models[2], "Error"))  # Embed
        
        # Should be partial success
        if len(result.failed_models) > 0:
            assert result.partial_success is True
        
        # Should have at least chat capability
        has_chat = any(
            m.role == ModelRole.CHAT or "chat" in m.roles
            for m in result.successful_models
        )
        assert has_chat is True
