"""
Unit tests for lib/docker.py.

Tests Docker and Docker Model Runner detection and API interactions.
"""

import json
import sys
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch
import urllib.error

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib import docker
from lib import hardware


# =============================================================================
# Check Docker Tests
# =============================================================================

class TestCheckDocker:
    """Tests for check_docker function."""
    
    @patch('lib.docker.utils.run_command')
    @patch('shutil.which')
    def test_docker_installed_and_running(self, mock_which, mock_run):
        """Test Docker detection when installed and running."""
        mock_which.return_value = "/usr/bin/docker"
        mock_run.side_effect = [
            (0, "Docker version 27.0.3, build abc123", ""),  # docker --version
            (0, "Server Version: 27.0.3", "")  # docker info
        ]
        
        success, version = docker.check_docker()
        
        assert success is True
        assert "27.0.3" in version
    
    @patch('shutil.which')
    def test_docker_not_installed(self, mock_which):
        """Test Docker detection when not installed."""
        mock_which.return_value = None
        
        success, version = docker.check_docker()
        
        assert success is False
    
    @patch('lib.docker.utils.run_command')
    @patch('shutil.which')
    def test_docker_daemon_not_running(self, mock_which, mock_run):
        """Test Docker detection when daemon not running."""
        mock_which.return_value = "/usr/bin/docker"
        mock_run.side_effect = [
            (0, "Docker version 27.0.3", ""),  # docker --version
            (1, "", "Cannot connect to Docker daemon")  # docker info
        ]
        
        success, version = docker.check_docker()
        
        assert success is False


# =============================================================================
# Check Docker Model Runner Status Tests
# =============================================================================

class TestCheckDmrStatus:
    """Tests for check_docker_model_runner_status function."""
    
    @patch('lib.docker.utils.run_command')
    @patch('shutil.which')
    def test_dmr_available(self, mock_which, mock_run):
        """Test DMR available."""
        mock_which.return_value = "/usr/bin/docker"
        mock_run.side_effect = [
            (0, "Server Version: 27.0.3", ""),  # docker info
            (0, "NAME\nai/model:7b\n", "")  # docker model list
        ]
        
        available, msg = docker.check_docker_model_runner_status()
        
        assert available is True
    
    @patch('lib.docker.utils.run_command')
    @patch('shutil.which')
    def test_dmr_not_enabled(self, mock_which, mock_run):
        """Test DMR not enabled."""
        mock_which.return_value = "/usr/bin/docker"
        mock_run.side_effect = [
            (0, "Server Version: 27.0.3", ""),  # docker info
            (1, "", "unknown command")  # docker model list
        ]
        
        available, msg = docker.check_docker_model_runner_status()
        
        assert available is False
        assert "not enabled" in msg.lower()


# =============================================================================
# Fetch Models from API Tests
# =============================================================================

class TestFetchModelsFromApi:
    """Tests for fetch_available_models_from_api function."""
    
    @patch('urllib.request.urlopen')
    def test_fetch_models_success(self, mock_urlopen):
        """Test fetching models from API successfully."""
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.read.return_value = json.dumps({
            "data": [
                {"id": "ai/model1:7b"},
                {"id": "ai/model2:3b"}
            ]
        }).encode()
        mock_response.__enter__ = Mock(return_value=mock_response)
        mock_response.__exit__ = Mock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        models = docker.fetch_available_models_from_api("http://localhost:12434/v1")
        
        assert len(models) == 2
        assert "ai/model1:7b" in models
    
    @patch('urllib.request.urlopen')
    def test_fetch_models_failure(self, mock_urlopen):
        """Test fetching models when API fails."""
        mock_urlopen.side_effect = urllib.error.URLError("Connection refused")
        
        models = docker.fetch_available_models_from_api("http://localhost:12434/v1")
        
        assert len(models) == 0


# =============================================================================
# API Configuration Tests
# =============================================================================

class TestApiConfiguration:
    """Tests for API configuration constants."""
    
    def test_api_host_configured(self):
        """Test API host is configured."""
        assert docker.DMR_API_HOST == "localhost"
    
    def test_api_port_configured(self):
        """Test API port is configured."""
        assert docker.DMR_API_PORT == 12434
    
    def test_api_base_url(self):
        """Test API base URL format."""
        expected = "http://localhost:12434/v1"
        assert docker.DMR_API_BASE == expected
