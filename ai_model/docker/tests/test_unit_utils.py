"""
Unit tests for lib/utils.py.

Tests utility functions including run_command and SSL context.
"""

import os
import ssl
import sys
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch
import subprocess

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib import utils


# =============================================================================
# Run Command Tests
# =============================================================================

class TestRunCommand:
    """Tests for run_command function."""
    
    @patch('subprocess.run')
    def test_run_command_success(self, mock_run):
        """Test successful command execution."""
        mock_run.return_value = Mock(
            returncode=0,
            stdout="success output",
            stderr=""
        )
        
        code, stdout, stderr = utils.run_command(["echo", "test"])
        
        assert code == 0
        assert stdout == "success output"
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
        assert stderr == "error message"
    
    @patch('subprocess.run')
    def test_run_command_timeout(self, mock_run):
        """Test command timeout handling."""
        mock_run.side_effect = subprocess.TimeoutExpired(cmd=["test"], timeout=30)
        
        code, stdout, stderr = utils.run_command(["sleep", "100"])
        
        assert code == -1
        assert "timed out" in stderr.lower()
    
    @patch('subprocess.run')
    def test_run_command_not_found(self, mock_run):
        """Test handling of command not found."""
        mock_run.side_effect = FileNotFoundError("Command not found")
        
        code, stdout, stderr = utils.run_command(["nonexistent"])
        
        assert code == -1
        assert "not found" in stderr.lower()
    
    @patch('subprocess.run')
    def test_run_command_clean_env(self, mock_run):
        """Test command with clean_env removes SSH_AUTH_SOCK."""
        mock_run.return_value = Mock(returncode=0, stdout="", stderr="")
        
        # Set SSH_AUTH_SOCK in environment
        os.environ['SSH_AUTH_SOCK'] = '/tmp/test'
        
        try:
            utils.run_command(["echo", "test"], clean_env=True)
            
            # Verify subprocess was called with env that excludes SSH_AUTH_SOCK
            call_kwargs = mock_run.call_args.kwargs
            if 'env' in call_kwargs and call_kwargs['env'] is not None:
                assert 'SSH_AUTH_SOCK' not in call_kwargs['env']
        finally:
            # Cleanup
            if 'SSH_AUTH_SOCK' in os.environ:
                del os.environ['SSH_AUTH_SOCK']
    
    @patch('subprocess.run')
    def test_run_command_default_timeout(self, mock_run):
        """Test default timeout is applied."""
        mock_run.return_value = Mock(returncode=0, stdout="", stderr="")
        
        utils.run_command(["echo", "test"])
        
        # Default timeout should be 300 seconds
        mock_run.assert_called_once()
        assert mock_run.call_args.kwargs['timeout'] == 300


# =============================================================================
# SSL Context Tests
# =============================================================================

class TestSSLContext:
    """Tests for SSL context utility."""
    
    def test_get_unverified_ssl_context(self):
        """Test creating unverified SSL context."""
        ctx = utils.get_unverified_ssl_context()
        
        assert ctx is not None
        assert isinstance(ctx, ssl.SSLContext)
        assert ctx.verify_mode == ssl.CERT_NONE
    
    def test_ssl_context_singleton(self):
        """Test SSL context is reused (singleton pattern)."""
        # Reset singleton
        utils._UNVERIFIED_SSL_CONTEXT = None
        
        ctx1 = utils.get_unverified_ssl_context()
        ctx2 = utils.get_unverified_ssl_context()
        
        assert ctx1 is ctx2  # Same object
    
    def test_ssl_context_check_hostname_disabled(self):
        """Test hostname verification is disabled."""
        ctx = utils.get_unverified_ssl_context()
        
        assert ctx.check_hostname is False


# =============================================================================
# Edge Cases
# =============================================================================

class TestEdgeCases:
    """Edge case tests for utils module."""
    
    @patch('subprocess.run')
    def test_run_command_empty_output(self, mock_run):
        """Test handling of empty command output."""
        mock_run.return_value = Mock(
            returncode=0,
            stdout=None,
            stderr=None
        )
        
        code, stdout, stderr = utils.run_command(["echo"])
        
        assert stdout == ""
        assert stderr == ""
    
    @patch('subprocess.run')
    def test_run_command_custom_timeout(self, mock_run):
        """Test custom timeout value."""
        mock_run.return_value = Mock(returncode=0, stdout="", stderr="")
        
        utils.run_command(["echo", "test"], timeout=60)
        
        mock_run.assert_called_once()
        assert mock_run.call_args.kwargs['timeout'] == 60
