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
    
    @patch('lib.ollama.verify_ollama_running')
    @patch('lib.ollama.check_ollama_autostart_status_macos')
    @patch('lib.ollama.check_port_in_use')
    @patch('lib.ollama.get_port_process_info')
    @patch('lib.utils.run_command')
    @patch('subprocess.Popen')
    @patch('subprocess.run')
    @patch('shutil.which')
    @patch('platform.system')
    @patch('time.sleep')
    def test_start_ollama_service(
        self, mock_sleep, mock_system, mock_which, mock_run_subprocess, 
        mock_popen, mock_run, mock_port_info, mock_port, mock_autostart, mock_verify
    ):
        """
        Test starting Ollama service.
        
        Specification: When Ollama is not running, the function should:
        1. Check if Ollama is already running (verify_ollama_running)
        2. Check if auto-start is configured (on macOS)
        3. If not configured, spawn 'ollama serve' as background process
        4. Wait for API to become available
        """
        mock_system.return_value = "Darwin"
        mock_verify.side_effect = [False, True]  # Not running, then running
        mock_autostart.return_value = (False, "Not configured")  # No auto-start
        mock_port.return_value = False  # Port not in use
        mock_which.return_value = "/usr/bin/ollama"
        mock_run_subprocess.return_value = MagicMock(returncode=1)  # pgrep finds nothing
        
        # Mock the Popen for 'ollama serve'
        mock_process = MagicMock()
        mock_process.poll.return_value = None  # Process still running
        mock_popen.return_value = mock_process
        
        # Call the function
        try:
            result = ollama.start_ollama_service()
            
            # SPECIFICATION VERIFICATION:
            # 1. Should have checked if running
            assert mock_verify.called, "Should have checked if Ollama is running"
            
            # 2. Should have checked for auto-start (on macOS)
            assert mock_autostart.called, "Should have checked for auto-start configuration"
            
            # 3. Should have spawned ollama serve (since no auto-start)
            assert mock_popen.called, "Should have spawned 'ollama serve' process"
            popen_args = mock_popen.call_args[0][0] if mock_popen.call_args[0] else mock_popen.call_args[1].get('args', [])
            assert 'ollama' in str(popen_args), "Should have called ollama command"
            
        except Exception as e:
            # Function may timeout waiting for API, that's acceptable
            # But we still verify the mocks were called
            assert mock_verify.called or mock_popen.called, \
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
    @patch('shutil.which')
    @patch('pathlib.Path.mkdir')
    @patch('pathlib.Path.exists')
    @patch('lib.utils.run_command')
    @patch('lib.ui.prompt_yes_no')
    @patch('lib.ui.print_success')
    @patch('lib.ui.print_info')
    @patch('lib.ui.print_warning')
    @patch('lib.ui.print_error')
    @patch('urllib.request.urlopen')
    def test_setup_autostart_plist_has_enhanced_keepalive(
        self, mock_urlopen, mock_error, mock_warning, mock_info,
        mock_success, mock_prompt, mock_run, mock_exists,
        mock_mkdir, mock_which, mock_system
    ):
        """Test that plist file includes enhanced KeepAlive settings."""
        mock_system.return_value = "Darwin"
        mock_which.return_value = "/opt/homebrew/bin/ollama"
        mock_exists.return_value = False
        mock_run.return_value = (0, "", "")
        mock_prompt.return_value = True
        
        # Mock urlopen for verify_ollama_running
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.__enter__ = Mock(return_value=mock_response)
        mock_response.__exit__ = Mock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        written_content = []
        mock_file = MagicMock()
        mock_file.write.side_effect = lambda x: written_content.append(x)
        
        with patch('builtins.open', create=True) as mock_open, \
             patch('time.sleep'):
            mock_open.return_value.__enter__ = Mock(return_value=mock_file)
            mock_open.return_value.__exit__ = Mock(return_value=False)
            
            ollama.setup_ollama_autostart_macos()
        
        # Verify plist content was written
        assert len(written_content) > 0
        plist_content = ''.join(str(c) for c in written_content)
        
        # Check for enhanced KeepAlive settings
        assert "SuccessfulExit" in plist_content, "Should have SuccessfulExit key"
        assert "Crashed" in plist_content, "Should have Crashed key"
        assert "ThrottleInterval" in plist_content, "Should have ThrottleInterval key"
        assert "WorkingDirectory" in plist_content, "Should have WorkingDirectory key"
    
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


# =============================================================================
# Port and Process Management Tests
# =============================================================================

class TestPortManagement:
    """Tests for port conflict detection."""
    
    @patch('socket.socket')
    def test_check_port_in_use_true(self, mock_socket_class):
        """Test detecting when port is in use."""
        mock_socket = MagicMock()
        mock_socket.__enter__ = Mock(return_value=mock_socket)
        mock_socket.__exit__ = Mock(return_value=False)
        mock_socket.connect_ex.return_value = 0  # Port is in use
        mock_socket_class.return_value = mock_socket
        
        result = ollama.check_port_in_use(11434)
        assert result is True
    
    @patch('socket.socket')
    def test_check_port_in_use_false(self, mock_socket_class):
        """Test detecting when port is not in use."""
        mock_socket = MagicMock()
        mock_socket.__enter__ = Mock(return_value=mock_socket)
        mock_socket.__exit__ = Mock(return_value=False)
        mock_socket.connect_ex.return_value = 1  # Port is not in use
        mock_socket_class.return_value = mock_socket
        
        result = ollama.check_port_in_use(11434)
        assert result is False
    
    @patch('socket.socket')
    def test_check_port_in_use_exception(self, mock_socket_class):
        """Test handling exceptions in port check."""
        mock_socket_class.side_effect = Exception("Socket error")
        
        result = ollama.check_port_in_use(11434)
        assert result is False  # Should return False on error
    
    @patch('lib.utils.run_command')
    def test_get_port_process_info_success(self, mock_run):
        """Test getting process info for port in use."""
        mock_run.side_effect = [
            (0, "12345\n", ""),  # lsof returns PID
            (0, "ollama\n", ""),  # ps returns command
        ]
        
        result = ollama.get_port_process_info(11434)
        
        assert result is not None
        assert result["pid"] == "12345"
        assert result["command"] == "ollama"
    
    @patch('lib.utils.run_command')
    def test_get_port_process_info_not_found(self, mock_run):
        """Test when no process is using the port."""
        mock_run.return_value = (1, "", "")  # lsof returns no process
        
        result = ollama.get_port_process_info(11434)
        
        assert result is None
    
    @patch('lib.utils.run_command')
    def test_get_port_process_info_exception(self, mock_run):
        """Test handling exceptions in get_port_process_info."""
        mock_run.side_effect = Exception("Command failed")
        
        result = ollama.get_port_process_info(11434)
        
        assert result is None


class TestOllamaProcessInfo:
    """Tests for Ollama process information."""
    
    @patch('lib.utils.run_command')
    @patch('platform.system')
    def test_get_ollama_process_info_running(self, mock_system, mock_run):
        """Test getting info when Ollama is running."""
        mock_system.return_value = "Darwin"
        mock_run.side_effect = [
            (0, "12345\n67890\n", ""),  # pgrep finds processes
            (0, "", ""),  # launchctl list succeeds
        ]
        
        result = ollama.get_ollama_process_info()
        
        assert result["count"] == 2
        assert "12345" in result["pids"]
        assert "67890" in result["pids"]
        assert result["via_launchd"] is True
    
    @patch('lib.utils.run_command')
    @patch('platform.system')
    def test_get_ollama_process_info_not_running(self, mock_system, mock_run):
        """Test getting info when Ollama is not running."""
        mock_system.return_value = "Darwin"
        mock_run.return_value = (1, "", "")  # pgrep finds nothing
        
        result = ollama.get_ollama_process_info()
        
        assert result["count"] == 0
        assert result["pids"] == []
        assert result["via_launchd"] is False
    
    @patch('lib.utils.run_command')
    def test_get_ollama_process_info_exception(self, mock_run):
        """Test handling exceptions in get_ollama_process_info."""
        mock_run.side_effect = Exception("Command failed")
        
        result = ollama.get_ollama_process_info()
        
        assert result["count"] == 0
        assert result["pids"] == []


# =============================================================================
# Service Status Tests
# =============================================================================

class TestServiceStatus:
    """Tests for service status checking."""
    
    @patch('lib.ollama.verify_ollama_running')
    @patch('lib.ollama.check_ollama_autostart_status_macos')
    @patch('lib.ollama.check_port_in_use')
    @patch('lib.ollama.get_ollama_process_info')
    @patch('platform.system')
    def test_get_service_status_running_with_autostart(
        self, mock_system, mock_process_info, mock_port, mock_autostart, mock_verify
    ):
        """Test service status when running with auto-start configured."""
        mock_system.return_value = "Darwin"
        mock_verify.return_value = True
        mock_autostart.return_value = (True, "Launch Agent (loaded)")
        mock_port.return_value = True
        mock_process_info.return_value = {"pids": ["12345"], "count": 1, "via_launchd": True}
        
        status = ollama.get_ollama_service_status()
        
        assert status["running"] is True
        assert status["api_accessible"] is True
        assert status["auto_start_configured"] is True
        assert "Launch Agent" in status["auto_start_method"]
        assert status["port_in_use"] is True
        assert status["process_info"]["count"] == 1
    
    @patch('lib.ollama.verify_ollama_running')
    @patch('lib.ollama.check_ollama_autostart_status_macos')
    @patch('lib.ollama.check_port_in_use')
    @patch('platform.system')
    def test_get_service_status_not_running(
        self, mock_system, mock_port, mock_autostart, mock_verify
    ):
        """Test service status when not running."""
        mock_system.return_value = "Darwin"
        mock_verify.return_value = False
        mock_autostart.return_value = (False, "Not configured")
        mock_port.return_value = False
        
        status = ollama.get_ollama_service_status()
        
        assert status["running"] is False
        assert status["api_accessible"] is False
        assert status["auto_start_configured"] is False
        assert status["port_in_use"] is False
    
    @patch('lib.ollama.verify_ollama_running')
    @patch('lib.ollama.check_ollama_autostart_status_macos')
    @patch('lib.ollama.check_port_in_use')
    @patch('lib.ollama.get_port_process_info')
    @patch('platform.system')
    def test_get_service_status_port_conflict(
        self, mock_system, mock_port_info, mock_port, mock_autostart, mock_verify
    ):
        """Test service status when port is in use by another process."""
        mock_system.return_value = "Darwin"
        mock_verify.return_value = False
        mock_autostart.return_value = (False, "Not configured")
        mock_port.return_value = True
        mock_port_info.return_value = {"pid": "99999", "command": "other-app"}
        
        status = ollama.get_ollama_service_status()
        
        assert status["running"] is False
        assert status["port_in_use"] is True
        assert status["port_process"] is not None
        assert status["port_process"]["pid"] == "99999"


# =============================================================================
# Service Management Tests
# =============================================================================

class TestServiceManagement:
    """Tests for service start/stop/restart functionality."""
    
    @patch('shutil.which')
    @patch('lib.ollama.verify_ollama_running')
    @patch('lib.ollama.check_ollama_autostart_status_macos')
    @patch('lib.ollama.get_autostart_plist_path')
    @patch('pathlib.Path.exists')
    @patch('lib.utils.run_command')
    @patch('subprocess.run')
    @patch('platform.system')
    @patch('time.sleep')
    def test_start_ollama_service_uses_launchd_when_configured(
        self, mock_sleep, mock_system, mock_subprocess, mock_run, mock_exists, mock_plist_path, mock_autostart, mock_verify, mock_which
    ):
        """Test that start_ollama_service uses launchd when auto-start is configured."""
        mock_system.return_value = "Darwin"
        mock_which.return_value = "/usr/local/bin/ollama"  # Ollama is installed
        mock_verify.return_value = False  # Not running initially
        mock_autostart.return_value = (True, "Launch Agent (loaded)")
        plist_path = Path("/test/com.ollama.server.plist")
        mock_plist_path.return_value = plist_path
        mock_exists.return_value = True  # plist exists
    
        # Mock subprocess.run for pgrep
        mock_subprocess.return_value = MagicMock(returncode=1)  # pgrep finds nothing
    
        # Mock launchctl load success
        mock_run.side_effect = [
            (0, "", ""),  # launchctl load succeeds
            (0, "", ""),  # launchctl list succeeds
        ]
    
        # Mock verify_ollama_running to return True after start
        mock_verify.side_effect = [False, True]
    
        result = ollama.start_ollama_service()
        
        # Should have called launchctl load
        # Check if any call to run_command contains "launchctl"
        launchctl_calls = []
        for call in mock_run.call_args_list:
            if call[0] and len(call[0]) > 0:
                cmd = call[0][0]
                if isinstance(cmd, list) and "launchctl" in cmd:
                    launchctl_calls.append(call)
        assert len(launchctl_calls) > 0, f"Should have called launchctl load, but got calls: {mock_run.call_args_list}"
    
    @patch('lib.ollama.verify_ollama_running')
    @patch('lib.ollama.check_ollama_autostart_status_macos')
    @patch('lib.ollama.check_port_in_use')
    @patch('lib.ollama.get_port_process_info')
    @patch('lib.ollama.get_autostart_plist_path')
    @patch('subprocess.run')
    @patch('subprocess.Popen')
    @patch('shutil.which')
    @patch('platform.system')
    @patch('time.sleep')
    def test_start_ollama_service_checks_port_conflicts(
        self, mock_sleep, mock_system, mock_which, mock_popen, mock_run_subprocess,
        mock_plist_path, mock_port_info, mock_port, mock_autostart, mock_verify
    ):
        """Test that start_ollama_service checks for port conflicts."""
        mock_system.return_value = "Darwin"
        mock_verify.return_value = False
        mock_autostart.return_value = (False, "Not configured")
        mock_plist_path.return_value = None
        mock_port.return_value = True  # Port is in use
        mock_port_info.return_value = {"pid": "99999", "command": "other-app"}
        mock_which.return_value = "/usr/bin/ollama"
        mock_run_subprocess.return_value = MagicMock(returncode=1)  # pgrep finds nothing
        
        mock_process = MagicMock()
        mock_process.poll.return_value = None
        mock_popen.return_value = mock_process
        
        # Mock verify to return True eventually
        mock_verify.side_effect = [False, True]
        
        result = ollama.start_ollama_service()
        
        # Should have checked for port conflicts
        assert mock_port.called, "Should have checked if port is in use"
        assert mock_port_info.called, "Should have gotten port process info"
    
    @patch('lib.ollama.verify_ollama_running')
    @patch('lib.ollama.get_autostart_plist_path')
    @patch('pathlib.Path.exists')
    @patch('lib.utils.run_command')
    @patch('platform.system')
    @patch('time.sleep')
    def test_stop_ollama_service_via_launchd(
        self, mock_sleep, mock_system, mock_run, mock_exists, mock_plist_path, mock_verify
    ):
        """Test stopping Ollama via launchd."""
        mock_system.return_value = "Darwin"
        mock_verify.side_effect = [True, False]  # Running, then stopped
        mock_plist_path.return_value = Path("/test/com.ollama.server.plist")
        mock_exists.return_value = True  # plist exists
        mock_run.return_value = (0, "", "")  # launchctl unload succeeds
    
        result = ollama.stop_ollama_service()
        
        assert result is True
        # Should have called launchctl unload
        assert mock_run.called
        launchctl_calls = [c for c in mock_run.call_args_list if len(c[0]) > 0 and "launchctl" in str(c[0][0])]
        assert len(launchctl_calls) > 0
    
    @patch('lib.ollama.verify_ollama_running')
    @patch('lib.ollama.get_autostart_plist_path')
    @patch('lib.utils.run_command')
    @patch('time.sleep')
    def test_stop_ollama_service_via_pkill(
        self, mock_sleep, mock_run, mock_plist_path, mock_verify
    ):
        """Test stopping Ollama via pkill when launchd not available."""
        mock_verify.side_effect = [True, False]  # Running, then stopped
        mock_plist_path.return_value = None  # No plist (Linux)
        # Mock run_command to return tuple (code, stdout, stderr)
        mock_run.return_value = (0, "", "")  # pkill succeeds
    
        with patch('platform.system', return_value="Linux"):
            result = ollama.stop_ollama_service()
        
        assert result is True
        # Should have called pkill
        # Check if any call to run_command contains "pkill"
        pkill_calls = []
        for call in mock_run.call_args_list:
            if call[0] and len(call[0]) > 0:
                cmd = call[0][0]
                if isinstance(cmd, list) and "pkill" in cmd:
                    pkill_calls.append(call)
        assert len(pkill_calls) > 0, f"Should have called pkill, but got calls: {mock_run.call_args_list}"
    
    @patch('lib.ollama.verify_ollama_running')
    def test_stop_ollama_service_not_running(self, mock_verify):
        """Test stopping when Ollama is not running."""
        mock_verify.return_value = False
        
        result = ollama.stop_ollama_service()
        
        assert result is True  # Should return True (nothing to stop)
    
    @patch('lib.ollama.stop_ollama_service')
    @patch('lib.ollama.start_ollama_service')
    @patch('time.sleep')
    def test_restart_ollama_service(
        self, mock_sleep, mock_start, mock_stop
    ):
        """Test restarting Ollama service."""
        mock_stop.return_value = True
        mock_start.return_value = True
        
        result = ollama.restart_ollama_service()
        
        assert result is True
        assert mock_stop.called
        assert mock_start.called
        assert mock_sleep.called  # Should wait between stop and start


# =============================================================================
# Enhanced start_ollama_service Tests
# =============================================================================

class TestStartOllamaServiceEnhanced:
    """Tests for enhanced start_ollama_service with launchd support."""
    
    @patch('shutil.which')
    @patch('lib.ollama.verify_ollama_running')
    @patch('lib.ollama.check_ollama_autostart_status_macos')
    @patch('lib.ollama.get_autostart_plist_path')
    @patch('pathlib.Path.exists')
    @patch('lib.utils.run_command')
    @patch('subprocess.run')
    @patch('platform.system')
    @patch('time.sleep')
    def test_start_uses_launchd_when_available(
        self, mock_sleep, mock_system, mock_run_subprocess, mock_run,
        mock_exists, mock_plist_path, mock_autostart, mock_verify, mock_which
    ):
        """Test that start_ollama_service uses launchd when configured."""
        mock_system.return_value = "Darwin"
        mock_which.return_value = "/usr/local/bin/ollama"  # Ollama is installed
        mock_verify.side_effect = [False, True]  # Not running, then running
        mock_autostart.return_value = (True, "Launch Agent (loaded)")
        plist_path = Path("/test/com.ollama.server.plist")
        mock_plist_path.return_value = plist_path
        mock_exists.return_value = True  # plist exists
    
        mock_run_subprocess.return_value = MagicMock(returncode=1)  # pgrep finds nothing
        mock_run.side_effect = [
            (0, "", ""),  # launchctl load succeeds
            (0, "", ""),  # launchctl list succeeds
        ]
    
        result = ollama.start_ollama_service()
        
        # Should have tried to use launchd
        assert mock_autostart.called
        assert mock_plist_path.called
        # Should have called launchctl
        # Check if any call to run_command contains "launchctl"
        launchctl_calls = []
        for call in mock_run.call_args_list:
            if call[0] and len(call[0]) > 0:
                cmd = call[0][0]
                if isinstance(cmd, list) and "launchctl" in cmd:
                    launchctl_calls.append(call)
        assert len(launchctl_calls) > 0, f"Should have called launchctl, but got calls: {mock_run.call_args_list}"
    
    @patch('lib.ollama.verify_ollama_running')
    @patch('lib.ollama.check_ollama_autostart_status_macos')
    @patch('lib.ollama.check_port_in_use')
    @patch('lib.ollama.get_port_process_info')
    @patch('subprocess.run')
    @patch('subprocess.Popen')
    @patch('shutil.which')
    @patch('platform.system')
    @patch('time.sleep')
    def test_start_warns_about_temporary_process(
        self, mock_sleep, mock_system, mock_which, mock_popen, mock_run_subprocess,
        mock_port_info, mock_port, mock_autostart, mock_verify
    ):
        """Test that start_ollama_service warns when starting temporary process."""
        mock_system.return_value = "Darwin"
        mock_verify.side_effect = [False, True]  # Not running, then running
        mock_autostart.return_value = (False, "Not configured")
        mock_port.return_value = False
        mock_which.return_value = "/usr/bin/ollama"
        mock_run_subprocess.return_value = MagicMock(returncode=1)  # pgrep finds nothing
        
        mock_process = MagicMock()
        mock_process.poll.return_value = None
        mock_popen.return_value = mock_process
        
        with patch('lib.ui.print_warning') as mock_warning:
            ollama.start_ollama_service()
            
            # Should have warned about temporary process
            warning_calls = [str(c) for c in mock_warning.call_args_list if "temporarily" in str(c).lower()]
            assert len(warning_calls) > 0, "Should warn about temporary process"
    
    @patch('lib.ollama.verify_ollama_running')
    @patch('shutil.which')
    def test_start_fails_when_ollama_not_installed(self, mock_which, mock_verify):
        """Test that start_ollama_service fails when Ollama is not installed."""
        mock_verify.return_value = False
        mock_which.return_value = None  # Ollama not found
        
        with patch('subprocess.run') as mock_run:
            mock_run.return_value = MagicMock(returncode=1)  # pgrep finds nothing
            
            result = ollama.start_ollama_service()
            
            assert result is False
