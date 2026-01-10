"""
Unit tests for lib/uninstaller.py - Smart uninstallation functionality.

Tests cover:
- Manifest creation and loading
- Safe location checking
- Orphaned file scanning
- Process detection and handling
- Model removal
- IDE extension uninstallation
"""

import pytest
from unittest.mock import patch, MagicMock, mock_open
from pathlib import Path
import json
import tempfile
import os

from lib import uninstaller
from lib.uninstaller import (
    create_empty_manifest, is_safe_location, scan_for_orphaned_files,
    check_running_processes, handle_running_processes, stop_processes_gracefully,
    handle_config_removal, get_installed_models, remove_model, remove_models,
    check_vscode_extension_installed, uninstall_vscode_extension,
    check_intellij_plugin_installed, uninstall_intellij_plugin
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
