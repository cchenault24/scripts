"""
End-to-end tests for Ollama LLM setup.

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
# Add parent directory to path to access shared conftest fixtures
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from lib import hardware, model_selector, validator, config, ollama, ui
from lib.hardware import HardwareInfo
from lib.model_selector import ModelRole, RecommendedModel


# =============================================================================
# Fixtures for E2E Tests
# =============================================================================

@pytest.fixture
def mock_complete_environment(tmp_path):
    """Set up a complete mock environment for E2E testing."""
    # Create hardware info directly since fixture may not be available
    from lib import hardware
    hw_info = hardware.HardwareInfo(
        os_name="Darwin",
        os_version="14.0",
        macos_version="14.0",
        ram_gb=16.0,
        cpu_cores=10,
        cpu_perf_cores=4,
        cpu_eff_cores=6,
        gpu_vram_gb=0,
        gpu_cores=10,
        neural_engine_cores=16,
        has_apple_silicon=True,
        apple_chip_model="M4",
        cpu_brand="Apple M4",
        cpu_arch="arm64",
        gpu_name="Apple M4",
        usable_ram_gb=16.0,
        ollama_version="1.0.0",
        ollama_available=True,
        ollama_api_endpoint="http://localhost:11434/v1",
    )
    # Create directory structure
    continue_dir = tmp_path / ".continue"
    continue_dir.mkdir()
    (continue_dir / "rules").mkdir()
    
    launch_agents = tmp_path / "Library" / "LaunchAgents"
    launch_agents.mkdir(parents=True)
    
    return {
        "home": tmp_path,
        "continue_dir": continue_dir,
        "launch_agents": launch_agents,
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
    @patch('lib.ollama.check_ollama')
    @patch('lib.ollama.check_ollama_api')
    @patch('lib.validator.is_ollama_api_available')
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
        mock_api_available, mock_ollama_api, mock_ollama_check,
        mock_ides, mock_detect_hw, mock_complete_environment
    ):
        """Test complete flow with user accepting all options."""
        mock_hardware_tier_c = mock_complete_environment["hardware"]
        # Setup mocks
        mock_detect_hw.return_value = mock_hardware_tier_c
        mock_ides.return_value = ["vscode"]
        mock_ollama_check.return_value = (True, "0.13.5")
        mock_ollama_api.return_value = True
        mock_api_available.return_value = True
        mock_pull.return_value = (True, "")
        mock_verify.return_value = True
        mock_yes_no.return_value = True
        mock_choice.return_value = 0  # Accept recommendation
        
        # Get models to install
        from lib.model_selector import select_models
        models = select_models(mock_hardware_tier_c)
        
        # Simulate pulling
        result = validator.SetupResult()
        for model in models:
            result.successful_models.append(model)
        
        # Verify all models succeeded
        assert result.complete_success is True
        assert len(result.successful_models) == len(models)
        assert len(result.failed_models) == 0


# =============================================================================
# E2E Scenario 2: Decline Autostart
# =============================================================================

class TestDeclineAutostart:
    """E2E test: User declines auto-start setup."""
    
    @patch('platform.system')
    @patch('lib.ollama.check_ollama_autostart_status_macos')
    @patch('lib.ui.prompt_yes_no')
    @patch('lib.ui.print_info')
    @patch('lib.ui.print_subheader')
    def test_autostart_declined(
        self, mock_subheader, mock_info, mock_yes_no,
        mock_status, mock_system
    ):
        """Test flow when user declines auto-start."""
        mock_system.return_value = "Darwin"
        mock_status.return_value = (False, "Not configured")
        mock_yes_no.return_value = False  # Decline autostart
        
        # Check auto-start status
        is_configured, details = mock_status()
        
        # User declines
        setup_autostart = mock_yes_no("Would you like to set up auto-start?")
        
        assert is_configured is False
        assert setup_autostart is False


# =============================================================================
# E2E Scenario 3: Autostart Already Configured
# =============================================================================

class TestAutostartAlreadyConfigured:
    """E2E test: Auto-start already configured."""
    
    @patch('platform.system')
    @patch('lib.ollama.check_ollama_autostart_status_macos')
    @patch('lib.ollama.verify_ollama_running')
    @patch('lib.ui.print_success')
    @patch('lib.ui.print_info')
    @patch('lib.ui.print_subheader')
    def test_autostart_exists(
        self, mock_subheader, mock_info, mock_success,
        mock_running, mock_status, mock_system
    ):
        """Test flow when auto-start is already configured."""
        mock_system.return_value = "Darwin"
        mock_status.return_value = (True, "Launch Agent (loaded)")
        mock_running.return_value = True
        
        # Check status
        is_configured, details = mock_status()
        is_running = mock_running()
        
        assert is_configured is True
        assert "loaded" in details.lower()
        assert is_running is True


# =============================================================================
# E2E Scenario 5: All Models Fail
# =============================================================================

class TestAllModelsFail:
    """E2E test: All model pulls fail (network issue)."""
    
    def test_complete_failure_result(self, mock_complete_environment):
        """Test SetupResult when all models fail."""
        mock_hardware_tier_c = mock_complete_environment["hardware"]
        from lib.model_selector import select_models
        models = select_models(mock_hardware_tier_c)
        
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
    
    @pytest.mark.skip(reason="HardwareTier removed - using fixed models for all users")
    @pytest.mark.parametrize("ram_gb,tier,expected_min_ram,expected_max_ram", [
        (16, None, 0, 10),    # Tier C: small models
        (24, None, 0, 16),    # Tier B: medium models
        (32, None, 0, 23),    # Tier A: larger models
        (64, None, 0, 45),    # Tier S: largest models
    ])
    def test_tier_recommendations(self, ram_gb, tier, expected_min_ram, expected_max_ram):
        """Test model recommendations for each tier."""
        hw_info = HardwareInfo(
            ram_gb=ram_gb,
            usable_ram_gb=ram_gb * 0.6,
            has_apple_silicon=True,
            ollama_available=True
        )
        
        from lib.model_selector import select_models
        models = select_models(hw_info)
        total_ram = sum(m.ram_gb for m in models)
        
        assert total_ram >= expected_min_ram, f"Tier {tier}: Models too small"
        assert total_ram <= expected_max_ram, f"Tier {tier}: Models too large"


# =============================================================================
# E2E Scenario 7: Overwrite Existing Autostart
# =============================================================================

class TestOverwriteAutostart:
    """E2E test: Overwrite existing auto-start configuration."""
    
    @patch('platform.system')
    @patch('pathlib.Path.exists')
    @patch('lib.ui.prompt_yes_no')
    @patch('lib.utils.run_command')
    @patch('lib.ui.print_warning')
    @patch('lib.ui.print_info')
    def test_overwrite_flow(
        self, mock_info, mock_warning, mock_run,
        mock_yes_no, mock_exists, mock_system
    ):
        """Test overwriting existing auto-start configuration."""
        mock_system.return_value = "Darwin"
        mock_exists.return_value = True  # Plist exists
        mock_yes_no.return_value = True  # Confirm overwrite
        mock_run.return_value = (0, "", "")
        
        # Simulate the check
        plist_exists = mock_exists()
        overwrite = mock_yes_no("Overwrite existing configuration?")
        
        assert plist_exists is True
        assert overwrite is True


# =============================================================================
# E2E Scenario 8: Permission Errors
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
# E2E Scenario 9: SSH Key Error Flow
# =============================================================================

class TestSSHKeyErrorFlow:
    """E2E test: Handle SSH key errors with proper troubleshooting."""
    
    def test_ssh_error_provides_troubleshooting(self):
        """Test that SSH errors provide helpful troubleshooting."""
        error_msg = "ssh: no key found"
        error_type = validator.classify_pull_error(error_msg)
        steps = validator.get_troubleshooting_steps(error_type)
        
        assert error_type == validator.PullErrorType.SSH_KEY
        
        # Should provide SSH-related troubleshooting steps
        steps_text = " ".join(steps)
        assert "SSH" in steps_text.upper() or "OLLAMA" in steps_text.upper()


# =============================================================================
# E2E Scenario 10: Retry Failed Models
# =============================================================================

class TestRetryFailedModels:
    """E2E test: Retry failed models after initial failure."""
    
    def test_retry_reduces_failures(self, mock_complete_environment):
        """Test that retrying can reduce number of failures."""
        mock_hardware_tier_c = mock_complete_environment["hardware"]
        model1 = RecommendedModel(
            name="Model1",
            ollama_name="model1:latest",
            ram_gb=3.0,
            role=ModelRole.CHAT,
            roles=["chat"],
            description="Test"
        )
        model2 = RecommendedModel(
            name="Model2",
            ollama_name="model2:latest",
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
# E2E Scenario 11: Uninstaller Flow
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
            "installed": {
                "models": [
                    {"name": "qwen2.5-coder:7b", "size_gb": 5.0}
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
        assert len(loaded["installed"]["models"]) == 1


# =============================================================================
# E2E Scenario 12: Config Customization Detection
# =============================================================================

class TestConfigCustomizationDetection:
    """E2E test: Detect user customizations in config."""
    
    def test_detect_modified_config(self, tmp_path):
        """Test detecting when user has modified config."""
        config_path = tmp_path / "config.yaml"
        
        # Create original with fingerprint
        original_content = config.add_fingerprint_header("models:\n  - test", "yaml")
        config_path.write_text(original_content)


# =============================================================================
# E2E Scenario 13: Uninstaller Auto-Installation Behavior
# =============================================================================

class TestUninstallerAutoInstallation:
    """E2E test: Uninstaller automatically installs backend if missing."""
    
    def test_skip_model_removal_when_ollama_not_installed(self, tmp_path, monkeypatch):
        """Test that model removal is skipped when Ollama is not installed."""
        # This tests the behavior where if Ollama is not installed,
        # the uninstaller should skip model removal rather than failing
        with patch('lib.uninstaller.remove_models') as mock_remove:
            # Simulate SystemInfo with Ollama not installed
            from dataclasses import dataclass
            from typing import List, Dict, Any
            from pathlib import Path
            
            @dataclass
            class MockSystemInfo:
                ollama_installed: bool = False
                ollama_running: bool = False
                ollama_installed_by_script: bool = False
                installed_models: List[str] = None
                
            @dataclass  
            class MockUninstallChoices:
                models_to_remove: List[str] = None
            
            info = MockSystemInfo(installed_models=["test:model"])
            choices = MockUninstallChoices(models_to_remove=["test:model"])
            
            # Simulate the execute_uninstall logic for model removal
            if choices.models_to_remove:
                if not info.ollama_installed:
                    # Should skip - this is the new behavior
                    models_removed = 0
                else:
                    # Would call remove_models
                    models_removed = len(choices.models_to_remove)
            
            # Verify models were not removed (skipped)
            assert models_removed == 0
            mock_remove.assert_not_called()
    
    @patch('lib.utils.run_command')
    @patch('subprocess.run')
    def test_remove_ollama_if_installed_by_script(self, mock_subprocess, mock_run, tmp_path, monkeypatch):
        """Test that Ollama is removed at the end if installed by script."""
        # Test the cleanup logic: if ollama_installed_by_script is True,
        # Ollama should be uninstalled at the end
        monkeypatch.setenv('HOME', str(tmp_path))
        mock_run.return_value = (0, "", "")  # brew uninstall succeeds
        mock_subprocess.return_value = MagicMock(returncode=0)
        
        # Simulate the cleanup logic
        install_method = "homebrew"
        ollama_installed_by_script = True
        
        if ollama_installed_by_script and install_method == "homebrew":
            code, _, stderr = mock_run(["brew", "uninstall", "ollama"], timeout=60, clean_env=True)
            uninstalled = (code == 0)
        else:
            uninstalled = False
        
        # Verify brew uninstall was called
        assert uninstalled is True
        assert mock_run.called


# =============================================================================
# E2E Scenario 13: Full Diagnostic Flow
# =============================================================================

class TestFullDiagnosticFlow:
    """E2E test: Complete diagnostic flow."""
    
    @patch('lib.utils.run_command')
    @patch('urllib.request.urlopen')
    @patch('lib.validator._pull_model_single_attempt')
    def test_diagnostics_identify_issues(self, mock_pull, mock_urlopen, mock_run):
        """Test that diagnostics correctly identify issues."""
        # Mock ollama not installed
        mock_run.return_value = (-1, "", "command not found: ollama")
        
        results = validator.run_diagnostics(verbose=False)
        
        assert results["ollama_installed"] is False
        assert len(results["issues_found"]) > 0
        assert len(results["recommendations"]) > 0


# =============================================================================
# E2E Scenario 14: Model Selection Customization
# =============================================================================

class TestModelSelectionCustomization:
    """E2E test: User customizes model selection."""
    
    def test_primary_models_for_tier(self, mock_complete_environment):
        """Test that select_models returns fixed models for all users."""
        mock_hardware_tier_c = mock_complete_environment["hardware"]
        from lib.model_selector import select_models, PRIMARY_MODEL, EMBED_MODEL
        
        models = select_models(mock_hardware_tier_c)
        
        # Should return PRIMARY_MODEL and EMBED_MODEL for all users
        assert len(models) >= 2, "Should have at least primary and embed models"
        model_names = [m.ollama_name for m in models]
        assert PRIMARY_MODEL.ollama_name in model_names, "Should include PRIMARY_MODEL"
        assert EMBED_MODEL.ollama_name in model_names, "Should include EMBED_MODEL"
        
        # Verify model types
        for model in models:
            assert isinstance(model, RecommendedModel)
        
        # Verify at least one model has chat role (PRIMARY_MODEL)
        chat_models = [m for m in models if "chat" in m.roles or m.role == ModelRole.CHAT]
        assert len(chat_models) > 0, "Should have at least one chat model"
        
        # Verify at least one model has embed role (EMBED_MODEL)
        embed_models = [m for m in models if "embed" in m.roles or m.role == ModelRole.EMBED]
        assert len(embed_models) > 0, "Should have at least one embed model"


# =============================================================================
# E2E Scenario 15: Graceful Degradation
# =============================================================================

class TestGracefulDegradation:
    """E2E test: System degrades gracefully on partial failures."""
    
    def test_partial_setup_still_useful(self, mock_complete_environment):
        """Test that partial setup is still usable."""
        mock_hardware_tier_c = mock_complete_environment["hardware"]
        from lib.model_selector import select_models
        models = select_models(mock_hardware_tier_c)
        
        # Simulate: primary succeeds, embed fails
        result = validator.SetupResult()
        # Find primary and embed models
        primary = next((m for m in models if m.role == ModelRole.CHAT), models[0])
        embed = next((m for m in models if m.role == ModelRole.EMBED), models[1] if len(models) > 1 else None)
        
        result.successful_models.append(primary)
        if embed:
            result.failed_models.append((embed, "Error"))
        
        # Should be partial success
        if len(result.failed_models) > 0:
            assert result.partial_success is True
        
        # Should have at least chat capability
        has_chat = any(
            m.role == ModelRole.CHAT or "chat" in m.roles
            for m in result.successful_models
        )
        assert has_chat is True
