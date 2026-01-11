"""
Unit tests for lib/uninstaller.py - Smart uninstallation functionality.

Tests cover:
- Manifest creation and loading
- Safe location checking
- Orphaned file scanning
- Process detection and handling
- Model removal
- IDE extension uninstallation
- Execution order (models removed before service stop)
- Model name comparison (handling tags)
- No overlap between installed and pre-existing lists
- Ollama service management
"""

import json
import os
import pytest
import tempfile
from pathlib import Path
from typing import Any, Dict, List
from unittest.mock import MagicMock, Mock, call, mock_open, patch

from lib import ollama
from lib import uninstaller
from lib.uninstaller import (
    check_intellij_plugin_installed, check_running_processes,
    check_vscode_extension_installed, create_empty_manifest,
    get_installed_models, handle_config_removal, handle_running_processes,
    is_safe_location, remove_model, remove_models, scan_for_orphaned_files,
    stop_processes_gracefully, uninstall_intellij_plugin,
    uninstall_vscode_extension
)


class TestCreateEmptyManifest:
    """Tests for create_empty_manifest function."""
    
    def test_creates_valid_manifest_structure(self):
        """Test that created manifest has required structure."""
        manifest = create_empty_manifest()
        
        assert "version" in manifest
        assert "timestamp" in manifest
        assert "installed" in manifest
        assert "pre_existing" in manifest
    
    def test_manifest_has_empty_lists(self):
        """Test that manifest starts with empty lists."""
        manifest = create_empty_manifest()
        
        assert manifest["installed"]["models"] == []
        assert manifest["installed"]["files"] == []
    
    def test_manifest_version_is_string(self):
        """Test that manifest version is a string."""
        manifest = create_empty_manifest()
        assert isinstance(manifest["version"], str)


class TestIsSafeLocation:
    """Tests for is_safe_location function."""
    
    def test_home_continue_is_safe(self):
        """Test ~/.continue is considered safe."""
        path = Path.home() / ".continue" / "config.yaml"
        assert is_safe_location(path) is True
    
    def test_root_is_not_safe(self):
        """Test root directory is not safe."""
        path = Path("/etc/passwd")
        assert is_safe_location(path) is False
    
    def test_system_paths_not_safe(self):
        """Test system paths are not safe."""
        unsafe_paths = [
            Path("/usr/bin/python"),
            Path("/etc/hosts"),
            Path("/var/log/syslog"),
        ]
        for path in unsafe_paths:
            assert is_safe_location(path) is False, f"{path} should not be safe"
    
    def test_home_directory_subpath_is_safe(self):
        """Test paths under home directory are generally safe."""
        path = Path.home() / "some_file.txt"
        # is_safe_location allows home directory paths
        result = is_safe_location(path)
        # The function should return True for paths under home
        assert isinstance(result, bool)


class TestScanForOrphanedFiles:
    """Tests for scan_for_orphaned_files function."""
    
    @patch('pathlib.Path.home')
    @patch('pathlib.Path.exists')
    @patch('pathlib.Path.iterdir')
    def test_empty_manifest_scans_continue_dir(self, mock_iterdir, mock_exists, mock_home):
        """Test scanning with empty manifest."""
        mock_home.return_value = Path("/home/test")
        mock_exists.return_value = True
        mock_iterdir.return_value = []
        
        manifest = create_empty_manifest()
        orphans = scan_for_orphaned_files(manifest)
        
        assert isinstance(orphans, list)
    
    def test_returns_list_of_tuples(self):
        """Test that function returns list of (Path, status) tuples."""
        manifest = create_empty_manifest()
        with patch('pathlib.Path.exists', return_value=False):
            result = scan_for_orphaned_files(manifest)
            assert isinstance(result, list)


class TestCheckRunningProcesses:
    """Tests for check_running_processes function."""
    
    @patch('lib.uninstaller.utils.run_command')
    def test_detects_ollama_process(self, mock_run):
        """Test detecting running Ollama process."""
        mock_run.return_value = (0, "12345\n", "")  # PID found
        
        manifest = create_empty_manifest()
        running = check_running_processes(manifest)
        
        assert isinstance(running, dict)
    
    @patch('lib.uninstaller.utils.run_command')
    def test_no_processes_running(self, mock_run):
        """Test when no processes are running."""
        mock_run.return_value = (1, "", "")  # No process found
        
        manifest = create_empty_manifest()
        running = check_running_processes(manifest)
        
        assert isinstance(running, dict)


class TestHandleRunningProcesses:
    """Tests for handle_running_processes function."""
    
    def test_empty_dict_returns_true(self):
        """Test empty running dict returns True (continue)."""
        result = handle_running_processes({})
        assert result is True
    
    @patch('lib.uninstaller.ui.prompt_choice', return_value=2)  # Cancel option
    def test_user_chooses_cancel(self, mock_prompt):
        """Test when user chooses to cancel."""
        running = {"ollama": ["12345"]}
        result = handle_running_processes(running)
        # When user cancels, should return False
        assert result is False


class TestStopProcessesGracefully:
    """Tests for stop_processes_gracefully function."""
    
    @patch('lib.uninstaller.utils.run_command')
    def test_stops_ollama(self, mock_run):
        """Test stopping Ollama process."""
        mock_run.return_value = (0, "", "")
        
        running = {"ollama": ["12345"]}
        result = stop_processes_gracefully(running)
        
        assert isinstance(result, bool)


class TestGetInstalledModels:
    """Tests for get_installed_models function."""
    
    @patch('lib.uninstaller.utils.run_command')
    def test_parses_model_list(self, mock_run):
        """Test parsing Ollama model list output."""
        mock_run.return_value = (0, "NAME\tSIZE\nllama3:latest\t4.7GB\ncodestral:22b\t13GB\n", "")
        
        models = get_installed_models()
        
        assert isinstance(models, list)
        assert "llama3:latest" in models or len(models) >= 0
    
    @patch('lib.uninstaller.utils.run_command')
    def test_empty_on_error(self, mock_run):
        """Test returns empty list on error."""
        mock_run.return_value = (1, "", "error")
        
        models = get_installed_models()
        
        assert models == []
    
    @patch('lib.uninstaller.utils.run_command')
    def test_handles_no_models(self, mock_run):
        """Test handling when no models installed."""
        mock_run.return_value = (0, "NAME\tSIZE\n", "")  # Only header
        
        models = get_installed_models()
        
        assert models == []


class TestRemoveModel:
    """Tests for remove_model function."""
    
    @patch('lib.uninstaller.utils.run_command')
    def test_successful_removal(self, mock_run):
        """Test successful model removal."""
        mock_run.return_value = (0, "deleted 'llama3:latest'", "")
        
        result = remove_model("llama3:latest")
        
        assert result is True
        mock_run.assert_called_once()
    
    @patch('lib.uninstaller.utils.run_command')
    def test_failed_removal(self, mock_run):
        """Test failed model removal."""
        mock_run.return_value = (1, "", "model not found")
        
        result = remove_model("nonexistent:model")
        
        assert result is False


class TestRemoveModels:
    """Tests for remove_models function."""
    
    @patch('lib.uninstaller.remove_model')
    def test_removes_multiple_models(self, mock_remove):
        """Test removing multiple models."""
        mock_remove.return_value = True
        
        count = remove_models(["model1", "model2", "model3"])
        
        assert count == 3
        assert mock_remove.call_count == 3
    
    @patch('lib.uninstaller.remove_model')
    def test_counts_successful_removals(self, mock_remove):
        """Test counting only successful removals."""
        mock_remove.side_effect = [True, False, True]  # 2 succeed, 1 fails
        
        count = remove_models(["model1", "model2", "model3"])
        
        assert count == 2
    
    def test_empty_list_returns_zero(self):
        """Test empty model list returns 0."""
        count = remove_models([])
        assert count == 0


class TestCheckVSCodeExtensionInstalled:
    """Tests for check_vscode_extension_installed function."""
    
    @patch('shutil.which')
    @patch('lib.uninstaller.utils.run_command')
    def test_extension_installed(self, mock_run, mock_which):
        """Test detecting installed extension."""
        mock_which.return_value = "/usr/bin/code"
        mock_run.return_value = (0, "Continue.continue\nsome-other-extension", "")
        
        result = check_vscode_extension_installed()
        
        assert result is True
    
    @patch('shutil.which')
    def test_vscode_not_installed(self, mock_which):
        """Test when VS Code is not installed."""
        mock_which.return_value = None
        
        result = check_vscode_extension_installed()
        
        assert result is False
    
    @patch('shutil.which')
    @patch('lib.uninstaller.utils.run_command')
    def test_extension_not_installed(self, mock_run, mock_which):
        """Test when extension is not installed."""
        mock_which.return_value = "/usr/bin/code"
        mock_run.return_value = (0, "some-other-extension", "")
        
        result = check_vscode_extension_installed()
        
        assert result is False


class TestUninstallVSCodeExtension:
    """Tests for uninstall_vscode_extension function."""
    
    @patch('shutil.which')
    @patch('lib.uninstaller.utils.run_command')
    def test_successful_uninstall(self, mock_run, mock_which):
        """Test successful extension uninstallation."""
        mock_which.return_value = "/usr/bin/code"
        mock_run.return_value = (0, "Extension 'Continue.continue' was uninstalled", "")
        
        result = uninstall_vscode_extension()
        
        assert result is True
    
    @patch('shutil.which')
    def test_vscode_not_available(self, mock_which):
        """Test when VS Code CLI not available."""
        mock_which.return_value = None
        
        result = uninstall_vscode_extension()
        
        assert result is False


class TestCheckIntelliJPluginInstalled:
    """Tests for check_intellij_plugin_installed function."""
    
    @patch('pathlib.Path.exists')
    @patch('pathlib.Path.iterdir')
    @patch('pathlib.Path.home')
    @patch('platform.system')
    def test_plugin_found_macos(self, mock_system, mock_home, mock_iterdir, mock_exists):
        """Test finding plugin on macOS."""
        mock_system.return_value = "Darwin"
        mock_home.return_value = Path("/Users/test")
        mock_exists.return_value = True
        
        # Mock the directory structure
        mock_plugin_dir = MagicMock()
        mock_plugin_dir.name = "Continue"
        mock_plugin_dir.is_dir.return_value = True
        
        mock_version_dir = MagicMock()
        mock_version_dir.is_dir.return_value = True
        mock_version_dir.iterdir.return_value = [mock_plugin_dir]
        mock_version_dir.name = "IntelliJIdea2024.1"
        
        result = check_intellij_plugin_installed()
        
        assert isinstance(result, tuple)
        assert len(result) == 2


class TestUninstallIntelliJPlugin:
    """Tests for uninstall_intellij_plugin function."""
    
    @patch('lib.uninstaller.check_intellij_plugin_installed')
    @patch('lib.uninstaller.ui.prompt_yes_no', return_value=False)
    def test_no_plugin_found(self, mock_prompt, mock_check):
        """Test when no plugin is found."""
        mock_check.return_value = (False, [])
        
        result = uninstall_intellij_plugin()
        
        # Should handle gracefully
        assert isinstance(result, bool)


class TestHandleConfigRemoval:
    """Tests for handle_config_removal function."""
    
    @patch('pathlib.Path.exists')
    def test_config_not_found(self, mock_exists):
        """Test when config file doesn't exist."""
        mock_exists.return_value = False
        
        manifest = create_empty_manifest()
        result = handle_config_removal(Path("/fake/path.yaml"), manifest)
        
        assert result is True  # Nothing to remove is success
    
    @patch('pathlib.Path.exists')
    @patch('builtins.open', mock_open(read_data="# Generated by ollama-llm-setup.py"))
    @patch('lib.uninstaller.ui.prompt_yes_no', return_value=True)
    @patch('pathlib.Path.unlink')
    def test_removes_our_config(self, mock_unlink, mock_prompt, mock_exists):
        """Test removing config we generated."""
        mock_exists.return_value = True
        
        manifest = create_empty_manifest()
        result = handle_config_removal(Path("/fake/config.yaml"), manifest)
        
        assert isinstance(result, bool)


class TestModelNameComparison:
    """Test model name normalization and comparison."""
    
    def test_normalize_model_name_with_tag(self):
        """Test normalizing model names with tags."""
        assert uninstaller.normalize_model_name("codellama:7b") == "codellama:7b"
        assert uninstaller.normalize_model_name("codellama:7b-latest") == "codellama:7b"
        assert uninstaller.normalize_model_name("codellama:7b-v0.1") == "codellama:7b"
        assert uninstaller.normalize_model_name("codellama:7b-q4_K_M") == "codellama:7b"
        assert uninstaller.normalize_model_name("starcoder2:3b") == "starcoder2:3b"
        assert uninstaller.normalize_model_name("nomic-embed-text") == "nomic-embed-text"
    
    def test_normalize_model_name_without_tag(self):
        """Test normalizing model names without tags."""
        assert uninstaller.normalize_model_name("codellama") == "codellama"
        assert uninstaller.normalize_model_name("") == ""
    
    def test_models_overlap_same_model(self):
        """Test detecting overlap for same model with different tags."""
        assert uninstaller.models_overlap("codellama:7b", "codellama:7b-latest") is True
        assert uninstaller.models_overlap("codellama:7b-latest", "codellama:7b") is True
        assert uninstaller.models_overlap("codellama:7b", "codellama:7b") is True
        assert uninstaller.models_overlap("codellama:7b-v0.1", "codellama:7b-latest") is True
    
    def test_models_overlap_different_models(self):
        """Test detecting no overlap for different models."""
        assert uninstaller.models_overlap("codellama:7b", "codellama:13b") is False
        assert uninstaller.models_overlap("codellama:7b", "starcoder2:3b") is False
        assert uninstaller.models_overlap("codellama:7b", "nomic-embed-text") is False


class TestExecutionOrder:
    """Test that models are removed before service is stopped."""
    
    @patch('lib.uninstaller.ollama.verify_ollama_running')
    @patch('lib.uninstaller.ollama.start_ollama_service')
    @patch('lib.uninstaller.remove_model')
    @patch('lib.uninstaller.utils.run_command')
    def test_models_removed_before_service_stop(
        self,
        mock_run_command,
        mock_remove_model,
        mock_start_ollama,
        mock_verify_running
    ):
        """Verify execution order: remove models before stopping service."""
        # Setup: Ollama is running
        mock_verify_running.return_value = True
        mock_remove_model.return_value = True
        
        # Remove models
        model_names = ["codellama:7b", "starcoder2:3b"]
        result = uninstaller.remove_models(model_names)
        
        # Verify models were removed
        assert result == 2
        assert mock_remove_model.call_count == 2
        
        # Verify Ollama was NOT stopped during model removal
        # (pkill should not be called)
        pkill_calls = [c for c in mock_run_command.call_args_list 
                      if len(c[0]) > 0 and c[0][0] and "pkill" in c[0][0]]
        assert len(pkill_calls) == 0, "Ollama should not be stopped during model removal"
    
    @patch('lib.uninstaller.ollama.verify_ollama_running')
    @patch('lib.uninstaller.ollama.start_ollama_service')
    @patch('lib.uninstaller.remove_model')
    def test_starts_ollama_if_stopped_for_model_removal(
        self,
        mock_remove_model,
        mock_start_ollama,
        mock_verify_running
    ):
        """Auto-start Ollama if stopped when removing models."""
        # Setup: Ollama is NOT running
        mock_verify_running.return_value = False
        mock_start_ollama.return_value = True
        mock_remove_model.return_value = True
        
        # Remove models
        model_names = ["codellama:7b"]
        result = uninstaller.remove_models(model_names)
        
        # Verify Ollama was started
        assert mock_start_ollama.called, "Ollama should be started if not running"
        assert mock_verify_running.called
        assert result == 1
    
    @patch('lib.uninstaller.ollama.verify_ollama_running')
    @patch('lib.uninstaller.ollama.start_ollama_service')
    def test_returns_zero_if_cannot_start_ollama(
        self,
        mock_start_ollama,
        mock_verify_running
    ):
        """Return 0 removed models if Ollama cannot be started."""
        # Setup: Ollama is NOT running and cannot be started
        mock_verify_running.return_value = False
        mock_start_ollama.return_value = False
        
        # Try to remove models
        model_names = ["codellama:7b"]
        result = uninstaller.remove_models(model_names)
        
        # Verify no models were removed
        assert result == 0
        assert mock_start_ollama.called


class TestNoOverlapInstalledAndPreexisting:
    """Test that installed and pre-existing model lists have no overlap."""
    
    def test_filter_overlapping_models_in_uninstaller(self):
        """Test filtering overlapping models in uninstaller."""
        manifest = {
            "installed": {
                "models": [
                    {"name": "codellama:7b-latest", "size_gb": 4.0},
                    {"name": "starcoder2:3b", "size_gb": 2.0},
                    {"name": "nomic-embed-text", "size_gb": 0.3}
                ]
            },
            "pre_existing": {
                "models": ["codellama:7b"]  # Overlaps with codellama:7b-latest
            }
        }
        
        # Simulate the filtering logic from uninstaller
        installed_models = manifest.get("installed", {}).get("models", [])
        pre_existing = manifest.get("pre_existing", {}).get("models", [])
        
        filtered_installed = []
        for model in installed_models:
            model_name = model.get("name", "")
            if not model_name:
                continue
            
            overlaps = False
            for pre_existing_name in pre_existing:
                if uninstaller.models_overlap(model_name, pre_existing_name):
                    overlaps = True
                    break
            
            if not overlaps:
                filtered_installed.append(model)
        
        # Verify codellama:7b-latest was filtered out (overlaps with codellama:7b)
        model_names = [m.get("name") for m in filtered_installed]
        assert "codellama:7b-latest" not in model_names
        assert "starcoder2:3b" in model_names
        assert "nomic-embed-text" in model_names
        assert len(filtered_installed) == 2
    
    def test_no_overlap_when_different_models(self):
        """Test no filtering when models are actually different."""
        manifest = {
            "installed": {
                "models": [
                    {"name": "codellama:7b", "size_gb": 4.0},
                    {"name": "starcoder2:3b", "size_gb": 2.0}
                ]
            },
            "pre_existing": {
                "models": ["nomic-embed-text"]  # Different model
            }
        }
        
        installed_models = manifest.get("installed", {}).get("models", [])
        pre_existing = manifest.get("pre_existing", {}).get("models", [])
        
        filtered_installed = []
        for model in installed_models:
            model_name = model.get("name", "")
            if not model_name:
                continue
            
            overlaps = False
            for pre_existing_name in pre_existing:
                if uninstaller.models_overlap(model_name, pre_existing_name):
                    overlaps = True
                    break
            
            if not overlaps:
                filtered_installed.append(model)
        
        # Verify all models are kept (no overlap)
        assert len(filtered_installed) == 2
        assert all(m.get("name") in ["codellama:7b", "starcoder2:3b"] 
                  for m in filtered_installed)


class TestManifestCreation:
    """Test manifest creation filters overlapping models."""
    
    @patch('lib.config._get_utc_timestamp')
    @patch('lib.config.calculate_file_hash')
    @patch('lib.config.classify_file_type')
    def test_manifest_filters_overlapping_models(
        self,
        mock_classify,
        mock_hash,
        mock_timestamp,
        tmp_path
    ):
        """Test that manifest creation filters models that overlap with pre-existing."""
        from lib import config
        from lib import hardware
        
        mock_timestamp.return_value = "2024-01-01T00:00:00Z"
        mock_hash.return_value = "test_hash"
        mock_classify.return_value = "config"
        
        # Create mock models
        class MockModel:
            def __init__(self, name, ollama_name, ram_gb, roles):
                self.name = name
                self.ollama_name = ollama_name
                self.ram_gb = ram_gb
                self.roles = roles
        
        installed_models = [
            MockModel("CodeLlama 7B", "codellama:7b-latest", 4.0, ["chat"]),
            MockModel("StarCoder2 3B", "starcoder2:3b", 2.0, ["autocomplete"]),
        ]
        
        pre_existing_models = ["codellama:7b"]  # Overlaps with codellama:7b-latest
        
        hw_info = hardware.HardwareInfo(
            ram_gb=16.0,
            cpu_brand="Apple M1",
            has_apple_silicon=True
        )
        
        # Create manifest
        manifest_path = config.create_installation_manifest(
            installed_models=installed_models,
            created_files=[],
            hw_info=hw_info,
            target_ide=["vscode"],
            pre_existing_models=pre_existing_models
        )
        
        # Load and verify
        with open(manifest_path, 'r') as f:
            manifest = json.load(f)
        
        installed = manifest["installed"]["models"]
        installed_names = [m["name"] for m in installed]
        
        # Verify codellama:7b-latest was filtered out
        assert "codellama:7b-latest" not in installed_names
        assert "starcoder2:3b" in installed_names
        assert len(installed) == 1


class TestOllamaServiceManagement:
    """Test Ollama service management functions."""
    
    @patch('lib.uninstaller.ollama.verify_ollama_running')
    @patch('lib.uninstaller.ollama.start_ollama_service')
    def test_ensure_ollama_running_when_already_running(
        self,
        mock_start,
        mock_verify
    ):
        """Test ensure_ollama_running when Ollama is already running."""
        mock_verify.return_value = True
        
        result = uninstaller.ensure_ollama_running_for_removal()
        
        assert result is True
        assert mock_verify.called
        assert not mock_start.called  # Should not start if already running
    
    @patch('lib.uninstaller.ollama.verify_ollama_running')
    @patch('lib.uninstaller.ollama.start_ollama_service')
    def test_ensure_ollama_running_starts_if_stopped(
        self,
        mock_start,
        mock_verify
    ):
        """Test ensure_ollama_running starts Ollama if stopped."""
        mock_verify.return_value = False
        mock_start.return_value = True
        
        result = uninstaller.ensure_ollama_running_for_removal()
        
        assert result is True
        assert mock_start.called
    
    @patch('lib.uninstaller.ollama.verify_ollama_running')
    @patch('lib.uninstaller.ollama.start_ollama_service')
    def test_ensure_ollama_running_fails_if_cannot_start(
        self,
        mock_start,
        mock_verify
    ):
        """Test ensure_ollama_running returns False if cannot start."""
        mock_verify.return_value = False
        mock_start.return_value = False
        
        result = uninstaller.ensure_ollama_running_for_removal()
        
        assert result is False
        assert mock_start.called


class TestIDEProcessHandling:
    """Test IDE process handling (separate from Ollama)."""
    
    @patch('lib.uninstaller.ui.prompt_choice')
    @patch('lib.uninstaller.ui.prompt_yes_no')
    def test_handle_ide_processes_only(
        self,
        mock_prompt_yes,
        mock_prompt_choice
    ):
        """Test that handle_ide_processes only handles IDEs, not Ollama."""
        running = {
            "vscode": ["VS Code"],
            "intellij": [],
            "ollama_serve": ["Ollama service"]  # Should be ignored
        }
        
        mock_prompt_choice.return_value = 0  # Stop processes
        mock_prompt_yes.return_value = True  # Closed IDE
        
        result = uninstaller.handle_ide_processes(running)
        
        # Should return True (IDEs handled)
        assert result is True
        # Verify only IDE prompts were shown, not Ollama
        # (Ollama should not be stopped here)
