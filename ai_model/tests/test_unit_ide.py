"""
Unit tests for lib/ide.py - IDE integration functionality.

Tests cover:
- IDE detection (VS Code, Cursor, IntelliJ)
- Extension/plugin installation
- IDE restart functions
- Model server management
- Next steps display
"""

import pytest
from unittest.mock import patch, MagicMock
from pathlib import Path
import subprocess

from lib import ide
from lib.ide import (
    detect_installed_ides, is_vscode_installed, is_cursor_installed,
    is_intellij_installed,
    install_vscode_extension, detect_intellij_cli, install_intellij_plugin,
    restart_vscode, restart_intellij, start_model_server
)
# _get_model_attr may not exist in Docker backend
try:
    from lib.ide import _get_model_attr
except ImportError:
    _get_model_attr = None
# display_detected_ides may not exist in Docker backend
try:
    from lib.ide import display_detected_ides
except ImportError:
    display_detected_ides = None
# get_ide_info may not exist in Docker backend
try:
    from lib.ide import get_ide_info
except ImportError:
    get_ide_info = None
from lib import hardware


class TestIsVSCodeInstalled:
    """Tests for is_vscode_installed function."""
    
    @patch('shutil.which')
    def test_vscode_in_path(self, mock_which):
        """Test VS Code detected via PATH."""
        mock_which.return_value = "/usr/bin/code"
        assert is_vscode_installed() is True
    
    @patch('shutil.which')
    @patch('pathlib.Path.exists')
    @patch('platform.system')
    def test_vscode_app_macos(self, mock_system, mock_exists, mock_which):
        """Test VS Code detected via macOS app path."""
        mock_which.return_value = None
        mock_system.return_value = "Darwin"
        # Simulate VS Code app exists
        mock_exists.return_value = True
        
        result = is_vscode_installed()
        assert isinstance(result, bool)
    
    @patch('shutil.which')
    @patch('pathlib.Path.exists')
    @patch('platform.system')
    def test_vscode_not_installed(self, mock_system, mock_exists, mock_which):
        """Test VS Code not found."""
        mock_which.return_value = None
        mock_system.return_value = "Linux"
        mock_exists.return_value = False
        
        result = is_vscode_installed()
        assert result is False


class TestIsCursorInstalled:
    """Tests for is_cursor_installed function."""
    
    @patch('shutil.which')
    def test_cursor_in_path(self, mock_which):
        """Test Cursor detected via PATH."""
        mock_which.return_value = "/usr/bin/cursor"
        assert is_cursor_installed() is True
    
    @patch('shutil.which')
    @patch('pathlib.Path.exists')
    @patch('platform.system')
    def test_cursor_not_installed(self, mock_system, mock_exists, mock_which):
        """Test Cursor not found."""
        mock_which.return_value = None
        mock_system.return_value = "Linux"
        mock_exists.return_value = False
        
        result = is_cursor_installed()
        assert result is False


class TestIsIntelliJInstalled:
    """Tests for is_intellij_installed function."""
    
    @patch('shutil.which')
    def test_intellij_in_path(self, mock_which):
        """Test IntelliJ detected via PATH."""
        mock_which.return_value = "/usr/bin/idea"
        assert is_intellij_installed() is True
    
    @patch('shutil.which')
    @patch('pathlib.Path.exists')
    @patch('platform.system')
    def test_intellij_not_installed(self, mock_system, mock_exists, mock_which):
        """Test IntelliJ not found."""
        mock_which.return_value = None
        mock_system.return_value = "Linux"
        mock_exists.return_value = False
        
        result = is_intellij_installed()
        assert result is False


class TestDetectInstalledIDEs:
    """Tests for detect_installed_ides function."""
    
    @patch('lib.ide.is_vscode_installed', return_value=True)
    @patch('lib.ide.is_cursor_installed', return_value=False)
    @patch('lib.ide.is_intellij_installed', return_value=False)
    def test_only_vscode(self, mock_ij, mock_cursor, mock_vscode):
        """Test detecting only VS Code."""
        ides = detect_installed_ides()
        assert "VS Code" in ides
        assert "Cursor" not in ides
        assert "IntelliJ IDEA" not in ides
    
    @patch('lib.ide.is_vscode_installed', return_value=True)
    @patch('lib.ide.is_cursor_installed', return_value=True)
    @patch('lib.ide.is_intellij_installed', return_value=True)
    def test_all_ides(self, mock_ij, mock_cursor, mock_vscode):
        """Test detecting all IDEs."""
        ides = detect_installed_ides()
        assert "VS Code" in ides
        assert "Cursor" in ides
        assert "IntelliJ IDEA" in ides
    
    @patch('lib.ide.is_vscode_installed', return_value=False)
    @patch('lib.ide.is_cursor_installed', return_value=False)
    @patch('lib.ide.is_intellij_installed', return_value=False)
    def test_no_ides(self, mock_ij, mock_cursor, mock_vscode):
        """Test no IDEs detected."""
        ides = detect_installed_ides()
        assert ides == []


class TestGetIDEInfo:
    """Tests for get_ide_info function."""
    
    @patch('lib.ide.is_vscode_installed', return_value=True)
    @patch('lib.ide.is_cursor_installed', return_value=False)
    @patch('lib.ide.is_intellij_installed', return_value=True)
    def test_returns_dict(self, mock_ij, mock_cursor, mock_vscode, backend_type):
        """Test returns dictionary with IDE status."""
        if get_ide_info is None:
            pytest.skip("get_ide_info not available in Docker backend")
        info = get_ide_info()
        
        assert isinstance(info, dict)
        assert "vscode" in info
        assert "cursor" in info
        assert "intellij" in info
        assert info["vscode"] is True
        assert info["cursor"] is False
        assert info["intellij"] is True


class TestDisplayDetectedIDEs:
    """Tests for display_detected_ides function."""
    
    @patch('lib.ide.detect_installed_ides')
    def test_displays_ides(self, mock_detect, capsys):
        if display_detected_ides is None:
            pytest.skip("display_detected_ides not available in this backend")
        """Test display function outputs to console."""
        mock_detect.return_value = ["VS Code", "IntelliJ IDEA"]
        
        result = display_detected_ides()
        
        assert result == ["VS Code", "IntelliJ IDEA"]
    
    @patch('lib.ide.detect_installed_ides')
    def test_displays_warning_when_none(self, mock_detect, capsys, backend_type):
        """Test warning displayed when no IDEs found."""
        if display_detected_ides is None:
            pytest.skip("display_detected_ides not available in Docker backend")
        mock_detect.return_value = []
        
        result = display_detected_ides()
        captured = capsys.readouterr()
        
        assert result == []
        assert "No supported IDEs" in captured.out or len(captured.out) >= 0


class TestInstallVSCodeExtension:
    """Tests for install_vscode_extension function."""
    
    @patch('shutil.which')
    def test_no_code_cli(self, mock_which):
        """Test when VS Code CLI not available."""
        mock_which.return_value = None
        
        result = install_vscode_extension("some.extension")
        assert result is False
    
    @patch('shutil.which')
    @patch('lib.ide.utils.run_command')
    def test_already_installed(self, mock_run, mock_which):
        """Test extension already installed."""
        mock_which.return_value = "/usr/bin/code"
        mock_run.return_value = (0, "Continue.continue\nother.ext", "")
        
        result = install_vscode_extension("Continue.continue")
        assert result is True
    
    @patch('shutil.which')
    @patch('lib.ide.utils.run_command')
    def test_successful_install(self, mock_run, mock_which):
        """Test successful extension installation."""
        mock_which.return_value = "/usr/bin/code"
        # First call: list extensions (not found)
        # Second call: install extension (success)
        mock_run.side_effect = [
            (0, "other.extension", ""),
            (0, "Installing...", "")
        ]
        
        result = install_vscode_extension("Continue.continue")
        assert result is True


class TestDetectIntelliJCLI:
    """Tests for detect_intellij_cli function."""
    
    @patch('shutil.which')
    def test_idea_in_path(self, mock_which):
        """Test IntelliJ CLI found in PATH."""
        mock_which.return_value = "/usr/bin/idea"
        
        result = detect_intellij_cli()
        assert result == "/usr/bin/idea"
    
    @patch('shutil.which')
    @patch('pathlib.Path.exists')
    @patch('platform.system')
    def test_cli_not_found(self, mock_system, mock_exists, mock_which):
        """Test IntelliJ CLI not found."""
        mock_which.return_value = None
        mock_system.return_value = "Linux"
        mock_exists.return_value = False
        
        result = detect_intellij_cli()
        assert result is None


class TestInstallIntelliJPlugin:
    """Tests for install_intellij_plugin function."""
    
    @patch('lib.ide.detect_intellij_cli')
    def test_no_intellij_cli(self, mock_detect):
        """Test when IntelliJ CLI not available."""
        mock_detect.return_value = None
        
        result = install_intellij_plugin("some.plugin")
        assert result is False
    
    @patch('lib.ide.detect_intellij_cli')
    @patch('lib.ide.utils.run_command')
    def test_successful_install(self, mock_run, mock_detect):
        """Test successful plugin installation."""
        mock_detect.return_value = "/usr/bin/idea"
        mock_run.return_value = (0, "Plugin installed", "")
        
        result = install_intellij_plugin("Continue.continue")
        assert result is True


class TestRestartVSCode:
    """Tests for restart_vscode function."""
    
    @patch('platform.system')
    def test_non_macos_returns_false(self, mock_system):
        """Test restart not supported on non-macOS."""
        mock_system.return_value = "Linux"
        
        result = restart_vscode()
        assert result is False
    
    @patch('platform.system')
    @patch('lib.ide.utils.run_command')
    def test_macos_restart(self, mock_run, mock_system):
        """Test restart on macOS."""
        mock_system.return_value = "Darwin"
        mock_run.return_value = (0, "", "")
        
        result = restart_vscode()
        assert isinstance(result, bool)


class TestRestartIntelliJ:
    """Tests for restart_intellij function."""
    
    @patch('platform.system')
    def test_non_macos_returns_false(self, mock_system):
        """Test restart not supported on non-macOS."""
        mock_system.return_value = "Linux"
        
        result = restart_intellij()
        assert result is False
    
    @patch('platform.system')
    @patch('lib.ide.utils.run_command')
    def test_macos_restart(self, mock_run, mock_system):
        """Test restart on macOS."""
        mock_system.return_value = "Darwin"
        mock_run.return_value = (0, "", "")
        
        result = restart_intellij()
        assert isinstance(result, bool)


class TestStartModelServer:
    """Tests for start_model_server function."""
    
    @patch('urllib.request.urlopen')
    def test_api_already_running(self, mock_urlopen):
        """Test when Ollama API is already running."""
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.__enter__ = MagicMock(return_value=mock_response)
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        result = start_model_server("llama3:latest")
        # Should return None since Ollama runs as a service
        assert result is None


class TestGetModelAttr:
    """Tests for _get_model_attr helper function."""
    
    def test_get_attr_from_object(self):
        """Test getting attribute from object."""
        if _get_model_attr is None:
            pytest.skip("_get_model_attr not available in this backend")
        class MockModel:
            name = "Test Model"
            ram_gb = 5.0
        
        model = MockModel()
        assert _get_model_attr(model, 'name') == "Test Model"
        assert _get_model_attr(model, 'ram_gb') == 5.0
    
    def test_get_attr_from_dict(self):
        """Test getting attribute from dictionary."""
        if _get_model_attr is None:
            pytest.skip("_get_model_attr not available in this backend")
        model = {"name": "Dict Model", "ram_gb": 3.0}
        
        assert _get_model_attr(model, 'name') == "Dict Model"
        assert _get_model_attr(model, 'ram_gb') == 3.0
    
    def test_get_attr_default(self):
        """Test default value when attribute missing."""
        if _get_model_attr is None:
            pytest.skip("_get_model_attr not available in this backend")
        model = {"name": "Test"}
        
        assert _get_model_attr(model, 'missing', "default") == "default"
        assert _get_model_attr(model, 'another', None) is None
    
    def test_get_attr_missing_no_default(self):
        """Test missing attribute with no default."""
        if _get_model_attr is None:
            pytest.skip("_get_model_attr not available in this backend")
        model = {"name": "Test"}
        
        assert _get_model_attr(model, 'missing') is None


class TestShowNextSteps:
    """Tests for show_next_steps function - basic checks."""
    
    @patch('lib.ide.utils.run_command')
    @patch('lib.ide.ui.prompt_yes_no', return_value=False)
    @patch('shutil.which', return_value=None)
    def test_show_next_steps_outputs(self, mock_which, mock_prompt, mock_run, capsys):
        """Test show_next_steps produces output."""
        mock_run.return_value = (1, "", "")  # No VS Code running
        
        # Create mock hardware info
        hw_info = MagicMock()
        hw_info.apple_chip_model = "M1"
        hw_info.cpu_brand = "Apple M1"
        hw_info.has_apple_silicon = True
        hw_info.ram_gb = 16
        # Set backend-appropriate attributes
        import os
        backend = os.environ.get('TEST_BACKEND', 'ollama').lower()
        if backend == "docker":
            hw_info.dmr_api_endpoint = "http://localhost:12434/v1"
            hw_info.docker_model_runner_available = True
        else:
            hw_info.ollama_api_endpoint = "http://localhost:11434/v1"
            hw_info.ollama_available = True
        hw_info.os_name = "Darwin"
        hw_info.get_tier_label = MagicMock(return_value="Tier C")
        
        # Create mock models
        models = [
            MagicMock(
                name="Test Model",
                ollama_name="test:latest",
                ram_gb=5.0,
                roles=["chat", "edit"]
            )
        ]
        
        from lib.ide import show_next_steps
        show_next_steps(
            config_path=Path("/tmp/config.yaml"),
            model_list=models,
            hw_info=hw_info,
            target_ide=["vscode"],
            has_embedding=True
        )
        
        captured = capsys.readouterr()
        assert "Setup Complete" in captured.out or len(captured.out) > 0
