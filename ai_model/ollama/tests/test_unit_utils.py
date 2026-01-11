"""
Unit tests for lib/utils.py.

Tests utility functions including command execution and SSL context.
"""

import ssl
import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

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
# Integration-like Tests
# =============================================================================

class TestCommandPatterns:
    """Tests for common command patterns."""
    
    @patch('subprocess.run')
    def test_ollama_list_command(self, mock_run):
        """Test ollama list command pattern."""
        mock_run.return_value = Mock(
            returncode=0,
            stdout="NAME\nqwen2.5-coder:7b\nnomic-embed-text\n",
            stderr=""
        )
        
        code, stdout, stderr = utils.run_command(["ollama", "list"])
        
        assert code == 0
        assert "qwen2.5-coder:7b" in stdout
    
    @patch('subprocess.run')
    def test_ollama_version_command(self, mock_run):
        """Test ollama version command pattern."""
        mock_run.return_value = Mock(
            returncode=0,
            stdout="ollama version 0.13.5",
            stderr=""
        )
        
        code, stdout, stderr = utils.run_command(["ollama", "--version"])
        
        assert code == 0
        assert "0.13.5" in stdout
    
    @patch('subprocess.run')
    def test_launchctl_load_command(self, mock_run):
        """Test launchctl load command pattern."""
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
    
    @patch('subprocess.run')
    def test_pgrep_command(self, mock_run):
        """Test pgrep command pattern."""
        mock_run.return_value = Mock(
            returncode=0,
            stdout="12345",
            stderr=""
        )
        
        code, stdout, stderr = utils.run_command(["pgrep", "-f", "ollama serve"])
        
        assert code == 0
        assert "12345" in stdout
