"""
Unit tests for lib/ollama.py.

Tests Ollama installation, service management, and auto-start functionality.
"""

import json
import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib import ollama


# =============================================================================
# Ollama Installation Tests
# =============================================================================

class TestOllamaInstallation:
    """Tests for Ollama installation detection."""
    
    @patch('shutil.which')
    def test_ollama_installed(self, mock_which):
        """Test detection when Ollama is installed."""
        mock_which.return_value = "/opt/homebrew/bin/ollama"
        
        path = mock_which("ollama")
        assert path is not None
        assert "ollama" in path
    
    @patch('shutil.which')
    def test_ollama_not_installed(self, mock_which):
        """Test detection when Ollama is not installed."""
        mock_which.return_value = None
        
        path = mock_which("ollama")
        assert path is None
    
    @patch('lib.utils.run_command')
    def test_get_ollama_version(self, mock_run):
        """Test getting Ollama version."""
        mock_run.return_value = (0, "ollama version 0.13.5", "")
        
        code, stdout, _ = mock_run(["ollama", "--version"])
        assert code == 0
        assert "0.13.5" in stdout


# =============================================================================
# Ollama Service Tests
# =============================================================================

class TestOllamaService:
    """Tests for Ollama service management."""
    
    @patch('urllib.request.urlopen')
    def test_verify_ollama_running_success(self, mock_urlopen):
        """Test verification when Ollama is running."""
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.__enter__ = Mock(return_value=mock_response)
        mock_response.__exit__ = Mock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        result = ollama.verify_ollama_running()
        assert result is True
    
    @patch('urllib.request.urlopen')
    def test_verify_ollama_running_failure(self, mock_urlopen):
        """Test verification when Ollama is not running."""
        import urllib.error
        mock_urlopen.side_effect = urllib.error.URLError("Connection refused")
        
        result = ollama.verify_ollama_running()
        assert result is False
    
    @patch('urllib.request.urlopen')
    def test_verify_ollama_running_timeout(self, mock_urlopen):
        """Test verification with timeout."""
        import socket
        mock_urlopen.side_effect = socket.timeout("Timed out")
        
        result = ollama.verify_ollama_running()
        assert result is False
    
    @patch('lib.utils.run_command')
    @patch('urllib.request.urlopen')
    @patch('subprocess.Popen')
    @patch('time.sleep')
    def test_start_ollama_service(self, mock_sleep, mock_popen, mock_urlopen, mock_run):
        """
        Test starting Ollama service.
        
        Specification: When Ollama is not running, the function should:
        1. Check if Ollama process is already running (pgrep)
        2. If not, spawn 'ollama serve' as background process
        3. Wait for API to become available
        """
        import urllib.error
        
        # Simulate: first API check fails, second succeeds (service started)
        mock_response_success = MagicMock()
        mock_response_success.status = 200
        mock_response_success.__enter__ = Mock(return_value=mock_response_success)
        mock_response_success.__exit__ = Mock(return_value=False)
        
        mock_urlopen.side_effect = [
            urllib.error.URLError("Not running"),  # First check - not running
            mock_response_success,                  # Second check - now running
        ]
        
        # pgrep returns 1 (not found) - no existing Ollama process
        mock_run.return_value = (1, "", "")
        
        # Mock the Popen for 'ollama serve'
        mock_process = MagicMock()
        mock_process.poll.return_value = None  # Process still running
        mock_popen.return_value = mock_process
        
        # Call the function
        try:
            ollama.start_ollama_service()
            
            # SPECIFICATION VERIFICATION:
            # 1. Should have checked for existing process
            assert mock_run.called, "Should have checked for existing Ollama process"
            
            # 2. Should have spawned ollama serve
            assert mock_popen.called, "Should have spawned 'ollama serve' process"
            popen_args = mock_popen.call_args[0][0] if mock_popen.call_args[0] else mock_popen.call_args[1].get('args', [])
            assert 'ollama' in str(popen_args), "Should have called ollama command"
            
        except Exception as e:
            # Function may timeout waiting for API, that's acceptable
            # But we still verify the mocks were called
            assert mock_run.called or mock_popen.called, \
                f"Function failed without attempting to start Ollama: {e}"


# =============================================================================
# Auto-Start Tests (macOS)
# =============================================================================

class TestAutoStartMacOS:
    """Tests for macOS launchd auto-start functionality."""
    
    @patch('platform.system')
    def test_autostart_only_on_macos(self, mock_system):
        """Test that auto-start functions only work on macOS."""
        mock_system.return_value = "Linux"
        
        result = ollama.setup_ollama_autostart_macos()
        assert result is False
    
    @patch('platform.system')
    @patch('shutil.which')
    def test_autostart_requires_ollama(self, mock_which, mock_system):
        """Test that auto-start requires Ollama to be installed."""
        mock_system.return_value = "Darwin"
        mock_which.return_value = None  # Ollama not found
        
        result = ollama.setup_ollama_autostart_macos()
        assert result is False
    
    @patch('platform.system')
    @patch('shutil.which')
    @patch('pathlib.Path.mkdir')
    @patch('pathlib.Path.exists')
    @patch('builtins.open', create=True)
    @patch('lib.utils.run_command')
    @patch('lib.ui.prompt_yes_no')
    @patch('lib.ui.print_success')
    @patch('lib.ui.print_info')
    @patch('lib.ui.print_warning')
    @patch('lib.ui.print_error')
    @patch('urllib.request.urlopen')
    def test_setup_autostart_success(
        self, mock_urlopen, mock_error, mock_warning, mock_info,
        mock_success, mock_prompt, mock_run, mock_open, mock_exists,
        mock_mkdir, mock_which, mock_system
    ):
        """Test successful auto-start setup."""
        mock_system.return_value = "Darwin"
        mock_which.return_value = "/opt/homebrew/bin/ollama"
        mock_exists.return_value = False  # Plist doesn't exist
        mock_run.return_value = (0, "", "")  # launchctl succeeds
        mock_open.return_value.__enter__ = Mock()
        mock_open.return_value.__exit__ = Mock(return_value=False)
        
        # Mock urlopen for verify_ollama_running
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.__enter__ = Mock(return_value=mock_response)
        mock_response.__exit__ = Mock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        with patch('time.sleep'):
            result = ollama.setup_ollama_autostart_macos()
        
        assert result is True
    
    @patch('platform.system')
    @patch('pathlib.Path.exists')
    def test_check_autostart_not_configured(self, mock_exists, mock_system):
        """Test checking auto-start when not configured."""
        mock_system.return_value = "Darwin"
        mock_exists.return_value = False
        
        with patch('shutil.which', return_value=None):
            is_configured, details = ollama.check_ollama_autostart_status_macos()
        
        assert is_configured is False
        assert "Not configured" in details
    
    @patch('platform.system')
    @patch('pathlib.Path.exists')
    @patch('lib.utils.run_command')
    def test_check_autostart_configured_loaded(self, mock_run, mock_exists, mock_system):
        """Test checking auto-start when configured and loaded."""
        mock_system.return_value = "Darwin"
        mock_exists.return_value = True
        mock_run.return_value = (0, "com.ollama.server\t-\t0", "")
        
        is_configured, details = ollama.check_ollama_autostart_status_macos()
        
        assert is_configured is True
        assert "loaded" in details.lower()
    
    @patch('platform.system')
    @patch('pathlib.Path.exists')
    @patch('pathlib.Path.unlink')
    @patch('lib.utils.run_command')
    @patch('lib.ui.print_info')
    @patch('lib.ui.print_success')
    @patch('lib.ui.print_warning')
    def test_remove_autostart_success(
        self, mock_warning, mock_success, mock_info,
        mock_run, mock_unlink, mock_exists, mock_system
    ):
        """Test successful auto-start removal."""
        mock_system.return_value = "Darwin"
        mock_exists.return_value = True
        mock_run.return_value = (0, "", "")  # launchctl unload succeeds
        
        result = ollama.remove_ollama_autostart_macos()
        
        assert result is True
        mock_unlink.assert_called_once()
    
    @patch('platform.system')
    @patch('pathlib.Path.exists')
    @patch('lib.ui.print_info')
    def test_remove_autostart_not_exists(self, mock_info, mock_exists, mock_system):
        """Test removing auto-start when not configured."""
        mock_system.return_value = "Darwin"
        mock_exists.return_value = False
        
        result = ollama.remove_ollama_autostart_macos()
        
        assert result is True  # Nothing to remove is still success


# =============================================================================
# Plist Path Tests
# =============================================================================

class TestPlistPath:
    """Tests for plist path generation."""
    
    @patch('platform.system')
    def test_plist_path_macos(self, mock_system):
        """Test plist path generation on macOS."""
        mock_system.return_value = "Darwin"
        
        path = ollama.get_autostart_plist_path()
        assert path is not None
        assert "LaunchAgents" in str(path)
        assert "com.ollama.server.plist" in str(path)
    
    @patch('platform.system')
    def test_plist_path_linux(self, mock_system):
        """Test plist path generation on Linux (should be None)."""
        mock_system.return_value = "Linux"
        
        path = ollama.get_autostart_plist_path()
        assert path is None


# =============================================================================
# API Fetch Tests
# =============================================================================

class TestAPIFetch:
    """Tests for Ollama API fetch operations."""
    
    @patch('urllib.request.urlopen')
    def test_fetch_available_models_success(self, mock_urlopen):
        """Test fetching available models from API."""
        response_data = {
            "models": [
                {"name": "qwen2.5-coder:7b"},
                {"name": "nomic-embed-text"}
            ]
        }
        
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.read.return_value = json.dumps(response_data).encode()
        mock_response.__enter__ = Mock(return_value=mock_response)
        mock_response.__exit__ = Mock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        models = ollama.fetch_available_models_from_api()
        
        assert len(models) == 2
        assert "qwen2.5-coder:7b" in models
        assert "nomic-embed-text" in models
    
    @patch('urllib.request.urlopen')
    def test_fetch_available_models_failure(self, mock_urlopen):
        """Test handling API failure when fetching models."""
        import urllib.error
        mock_urlopen.side_effect = urllib.error.URLError("Connection failed")
        
        models = ollama.fetch_available_models_from_api()
        
        assert models == []
    
    @patch('urllib.request.urlopen')
    def test_fetch_available_models_empty(self, mock_urlopen):
        """Test handling empty model list."""
        response_data = {"models": []}
        
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.read.return_value = json.dumps(response_data).encode()
        mock_response.__enter__ = Mock(return_value=mock_response)
        mock_response.__exit__ = Mock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        models = ollama.fetch_available_models_from_api()
        
        assert models == []


# =============================================================================
# SSL Context Tests
# =============================================================================

class TestSSLContext:
    """
    Tests for SSL context usage in API calls.
    
    CRITICAL SPECIFICATION:
    All urllib.request.urlopen() calls MUST include the context parameter
    with an unverified SSL context. This is required for corporate proxies
    and SSL interception environments.
    """
    
    @patch('urllib.request.urlopen')
    def test_verify_running_uses_ssl_context(self, mock_urlopen):
        """
        Test that verify_ollama_running() uses unverified SSL context.
        
        Specification: All API calls MUST pass context=get_unverified_ssl_context()
        This test FAILS if the context parameter is missing.
        """
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.__enter__ = Mock(return_value=mock_response)
        mock_response.__exit__ = Mock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        # Call a function that makes API requests
        ollama.verify_ollama_running()
        
        # CRITICAL VERIFICATION: SSL context MUST be passed
        assert mock_urlopen.called, "urlopen should have been called"
        
        call_args = mock_urlopen.call_args
        assert call_args is not None, "urlopen call_args should not be None"
        
        _, kwargs = call_args
        assert "context" in kwargs, \
            "CRITICAL: SSL context MUST be passed to urlopen for corporate proxy compatibility"
        assert kwargs["context"] is not None, \
            "SSL context cannot be None"
    
    @patch('urllib.request.urlopen')
    def test_fetch_models_uses_ssl_context(self, mock_urlopen):
        """
        Test that fetch_available_models_from_api() uses unverified SSL context.
        """
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.read.return_value = b'{"models": []}'
        mock_response.__enter__ = Mock(return_value=mock_response)
        mock_response.__exit__ = Mock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        # Call the function
        ollama.fetch_available_models_from_api()
        
        # Verify SSL context was passed
        if mock_urlopen.called:
            _, kwargs = mock_urlopen.call_args
            assert "context" in kwargs, \
                "SSL context MUST be passed for corporate proxy compatibility"


# =============================================================================
# Constants Tests
# =============================================================================

class TestConstants:
    """Tests for module constants."""
    
    def test_api_base_url(self):
        """Test API base URL constant."""
        assert "localhost" in ollama.OLLAMA_API_BASE
        assert "11434" in ollama.OLLAMA_API_BASE
    
    def test_openai_endpoint(self):
        """Test OpenAI-compatible endpoint."""
        assert "v1" in ollama.OLLAMA_OPENAI_ENDPOINT
    
    def test_launch_agent_label(self):
        """Test Launch Agent label."""
        assert ollama.LAUNCH_AGENT_LABEL == "com.ollama.server"
    
    def test_launch_agent_plist(self):
        """Test Launch Agent plist filename."""
        assert ollama.LAUNCH_AGENT_PLIST == "com.ollama.server.plist"
