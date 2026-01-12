"""
Unit tests for lib/utils.py.

Tests utility functions including command execution and SSL context.
Runs against both ollama and docker backends.
"""

import ssl
import subprocess
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

from lib import utils


# =============================================================================
# SSL Context Tests
# =============================================================================

class TestSSLContext:
    """Tests for SSL context creation and caching."""
    
    def test_get_unverified_ssl_context_returns_context(self):
        """Test that get_unverified_ssl_context returns an SSL context."""
        ctx = utils.get_unverified_ssl_context()
        
        assert ctx is not None
        assert isinstance(ctx, ssl.SSLContext)
    
    def test_ssl_context_verification_disabled(self):
        """Test that SSL context has verification disabled."""
        ctx = utils.get_unverified_ssl_context()
        
        assert ctx.check_hostname is False
        assert ctx.verify_mode == ssl.CERT_NONE
    
    def test_ssl_context_is_cached(self):
        """Test that SSL context is cached (singleton pattern)."""
        # Reset the cache
        utils._UNVERIFIED_SSL_CONTEXT = None
        
        ctx1 = utils.get_unverified_ssl_context()
        ctx2 = utils.get_unverified_ssl_context()
        
        # Should return the same object
        assert ctx1 is ctx2
    
    def test_ssl_context_reset_works(self):
        """Test that resetting the cache creates new context."""
        ctx1 = utils.get_unverified_ssl_context()
        
        # Reset cache
        utils._UNVERIFIED_SSL_CONTEXT = None
        
        ctx2 = utils.get_unverified_ssl_context()
        
        # Should be different objects (though equivalent)
        assert ctx1 is not ctx2


# =============================================================================
# Command Execution Tests
# =============================================================================

class TestRunCommand:
    """Tests for run_command function."""
    
    @patch('subprocess.run')
    def test_run_command_success(self, mock_run):
        """Test successful command execution."""
        mock_run.return_value = Mock(
            returncode=0,
            stdout="output",
            stderr=""
        )
        
        code, stdout, stderr = utils.run_command(["echo", "hello"])
        
        assert code == 0
        assert stdout == "output"
        assert stderr == ""
    
    @patch('subprocess.run')
    def test_run_command_failure(self, mock_run):
        """Test failed command execution."""
        mock_run.return_value = Mock(
            returncode=1,
            stdout="",
            stderr="error message"
        )
        
        code, stdout, stderr = utils.run_command(["false"])
        
        assert code == 1
        assert "error" in stderr.lower()
    
    @patch('subprocess.run')
    def test_run_command_timeout(self, mock_run):
        """Test command timeout handling."""
        mock_run.side_effect = subprocess.TimeoutExpired(cmd=["sleep"], timeout=1)
        
        code, stdout, stderr = utils.run_command(["sleep", "100"], timeout=1)
        
        assert code == -1
        assert "timed out" in stderr.lower()
    
    @patch('subprocess.run')
    def test_run_command_not_found(self, mock_run):
        """Test handling of command not found."""
        mock_run.side_effect = FileNotFoundError()
        
        code, stdout, stderr = utils.run_command(["nonexistent_command"])
        
        assert code == -1
        assert "not found" in stderr.lower()
    
    @patch('subprocess.run')
    def test_run_command_with_stderr(self, mock_run):
        """Test command that produces stderr output."""
        mock_run.return_value = Mock(
            returncode=0,
            stdout="",
            stderr="warning: something"
        )
        
        code, stdout, stderr = utils.run_command(["cmd"])
        
        assert code == 0
        assert "warning" in stderr.lower()
    
    @patch('subprocess.run')
    def test_run_command_default_timeout(self, mock_run):
        """Test that default timeout is applied."""
        mock_run.return_value = Mock(
            returncode=0,
            stdout="",
            stderr=""
        )
        
        utils.run_command(["echo", "test"])
        
        # Check that subprocess.run was called with a timeout
        call_kwargs = mock_run.call_args[1]
        assert "timeout" in call_kwargs
        assert call_kwargs["timeout"] == 300  # Default timeout
    
    @patch('subprocess.run')
    def test_run_command_custom_timeout(self, mock_run):
        """Test command with custom timeout."""
        mock_run.return_value = Mock(
            returncode=0,
            stdout="",
            stderr=""
        )
        
        utils.run_command(["echo", "test"], timeout=60)
        
        call_kwargs = mock_run.call_args[1]
        assert call_kwargs["timeout"] == 60
    
    @patch('subprocess.run')
    def test_run_command_captures_output(self, mock_run):
        """Test that output is captured by default."""
        mock_run.return_value = Mock(
            returncode=0,
            stdout="captured output",
            stderr=""
        )
        
        utils.run_command(["echo", "test"])
        
        call_kwargs = mock_run.call_args[1]
        assert call_kwargs.get("capture_output") is True
    
    @patch('subprocess.run')
    def test_run_command_text_mode(self, mock_run):
        """Test that command runs in text mode."""
        mock_run.return_value = Mock(
            returncode=0,
            stdout="text output",
            stderr=""
        )
        
        utils.run_command(["echo", "test"])
        
        call_kwargs = mock_run.call_args[1]
        assert call_kwargs.get("text") is True


# =============================================================================
# Edge Case Tests
# =============================================================================

class TestEdgeCases:
    """Tests for edge cases and error conditions."""
    
    @patch('subprocess.run')
    def test_run_command_empty_output(self, mock_run):
        """Test handling of empty output."""
        mock_run.return_value = Mock(
            returncode=0,
            stdout=None,  # None instead of empty string
            stderr=None
        )
        
        code, stdout, stderr = utils.run_command(["true"])
        
        assert code == 0
        assert stdout == ""
        assert stderr == ""
    
    @patch('subprocess.run')
    def test_run_command_generic_exception(self, mock_run):
        """Test handling of generic exceptions."""
        mock_run.side_effect = Exception("Unexpected error")
        
        code, stdout, stderr = utils.run_command(["cmd"])
        
        assert code == -1
        assert "Unexpected error" in stderr
    
    def test_ssl_context_fallback(self):
        """Test SSL context creation fallback."""
        # Even if _create_unverified_context fails, we should get a context
        with patch('ssl._create_unverified_context', side_effect=AttributeError()):
            utils._UNVERIFIED_SSL_CONTEXT = None
            ctx = utils.get_unverified_ssl_context()
            
            assert ctx is not None
            assert isinstance(ctx, ssl.SSLContext)


# =============================================================================
# Integration-like Tests (Backend-Aware)
# =============================================================================

class TestCommandPatterns:
    """Tests for common command patterns."""
    
    @patch('subprocess.run')
    def test_list_command(self, mock_run, backend_type):
        """Test list command pattern for both backends."""
        if backend_type == "ollama":
            mock_run.return_value = Mock(
                returncode=0,
                stdout="NAME\nqwen2.5-coder:7b\nnomic-embed-text\n",
                stderr=""
            )
            code, stdout, stderr = utils.run_command(["ollama", "list"])
            assert "qwen2.5-coder:7b" in stdout
        else:  # docker
            mock_run.return_value = Mock(
                returncode=0,
                stdout="NAME\nai/qwen2.5-coder:7b\nai/nomic-embed-text-v1.5\n",
                stderr=""
            )
            code, stdout, stderr = utils.run_command(["docker", "model", "list"])
            assert "ai/qwen2.5-coder:7b" in stdout
        assert code == 0
    
    @patch('subprocess.run')
    def test_version_command(self, mock_run, backend_type):
        """Test version command pattern for both backends."""
        if backend_type == "ollama":
            mock_run.return_value = Mock(
                returncode=0,
                stdout="ollama version 0.13.5",
                stderr=""
            )
            code, stdout, stderr = utils.run_command(["ollama", "--version"])
            assert "0.13.5" in stdout
        else:  # docker
            mock_run.return_value = Mock(
                returncode=0,
                stdout="Docker version 27.0.3, build abc123",
                stderr=""
            )
            code, stdout, stderr = utils.run_command(["docker", "--version"])
            assert "27.0.3" in stdout
        assert code == 0
    
    @patch('subprocess.run')
    def test_launchctl_load_command(self, mock_run, backend_type):
        """Test launchctl load command pattern (ollama-specific)."""
        if backend_type == "ollama":
            mock_run.return_value = Mock(
                returncode=0,
                stdout="",
                stderr=""
            )
            code, stdout, stderr = utils.run_command(
                ["launchctl", "load", "/path/to/plist"],
                timeout=10
            )
            assert code == 0
        else:
            # Docker doesn't use launchctl
            pytest.skip("launchctl is ollama-specific")
    
    @patch('subprocess.run')
    def test_pgrep_command(self, mock_run, backend_type):
        """Test pgrep command pattern."""
        mock_run.return_value = Mock(
            returncode=0,
            stdout="12345",
            stderr=""
        )
        if backend_type == "ollama":
            code, stdout, stderr = utils.run_command(["pgrep", "-f", "ollama serve"])
        else:  # docker
            code, stdout, stderr = utils.run_command(["pgrep", "-f", "docker"])
        assert code == 0
        assert "12345" in stdout
