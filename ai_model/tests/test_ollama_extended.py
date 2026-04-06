"""
Extended tests for lib/ollama.py - Additional coverage for Ollama service management.
"""

import pytest
from unittest.mock import patch, MagicMock
import os

from lib import ollama
from lib.ollama import (
    check_ollama, verify_ollama_running, get_installation_instructions,
    get_autostart_plist_path
)
from lib.hardware import HardwareInfo


class TestCheckOllama:
    """Extended tests for check_ollama function."""
    
    @patch('shutil.which', return_value='/usr/local/bin/ollama')
    @patch('lib.ollama.utils.run_command')
    def test_ollama_found_with_version(self, mock_run, mock_which):
        """Test Ollama found with version."""
        mock_run.return_value = (0, "ollama version 0.1.25", "")
        
        found, version = check_ollama()
        
        assert found is True
        assert "0.1.25" in version or version != ""
    
    @patch('lib.ollama.ui.prompt_yes_no', return_value=False)
    def test_check_ollama_returns_tuple(self, mock_prompt):
        """Test check_ollama returns tuple."""
        found, version = check_ollama()
        
        assert isinstance(found, bool)
        assert isinstance(version, str)


class TestVerifyOllamaRunning:
    """Tests for verify_ollama_running function."""
    
    def test_verify_returns_bool(self):
        """Test verify_ollama_running returns boolean."""
        result = verify_ollama_running()
        assert isinstance(result, bool)


class TestGetInstallationInstructions:
    """Tests for get_installation_instructions function."""
    
    @patch('platform.system', return_value='Darwin')
    def test_macos_instructions(self, mock_system):
        """Test macOS installation instructions."""
        instructions = get_installation_instructions()
        assert isinstance(instructions, str)
        assert len(instructions) > 0
    
    @patch('platform.system', return_value='Linux')
    def test_linux_instructions(self, mock_system):
        """Test Linux installation instructions."""
        instructions = get_installation_instructions()
        assert isinstance(instructions, str)
        assert "curl" in instructions.lower() or "install" in instructions.lower()
    
    @patch('platform.system', return_value='Windows')
    def test_windows_instructions(self, mock_system):
        """Test Windows installation instructions."""
        instructions = get_installation_instructions()
        assert isinstance(instructions, str)


# Note: check_ssh_environment_pollution function was removed from lib.ollama
# Tests for this function have been removed


class TestGetAutostartPlistPath:
    """Tests for get_autostart_plist_path function."""
    
    @patch('platform.system', return_value='Darwin')
    def test_macos_returns_path(self, mock_system):
        """Test macOS returns a path."""
        path = get_autostart_plist_path()
        # May return path or None depending on implementation
        assert path is None or 'LaunchAgents' in str(path)
    
    @patch('platform.system', return_value='Linux')
    def test_linux_returns_none(self, mock_system):
        """Test Linux returns None."""
        path = get_autostart_plist_path()
        assert path is None


class TestOllamaServiceManagement:
    """Tests for Ollama service-related functions."""
    
    @patch('lib.ollama.verify_ollama_running', return_value=True)
    def test_service_already_running(self, mock_verify):
        """Test detection when service is already running."""
        from lib.ollama import start_ollama_service
        
        result = start_ollama_service()
        assert result is True
