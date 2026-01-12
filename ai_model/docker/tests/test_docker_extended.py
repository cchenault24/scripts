"""
Extended tests for lib/docker.py - Additional coverage for Docker and Docker Model Runner management.
"""

import pytest
from unittest.mock import patch, MagicMock
import urllib.error

from lib import docker
from lib.docker import (
    check_docker, check_docker_model_runner_status, fetch_available_models_from_api,
    check_docker_model_runner, DMR_API_BASE, DMR_API_HOST, DMR_API_PORT
)
from lib.hardware import HardwareInfo, HardwareTier


class TestCheckDocker:
    """Extended tests for check_docker function."""
    
    @patch('shutil.which', return_value='/usr/bin/docker')
    @patch('lib.docker.utils.run_command')
    def test_docker_found_with_version(self, mock_run, mock_which):
        """Test Docker found with version."""
        mock_run.side_effect = [
            (0, "Docker version 27.0.3, build abc123", ""),  # docker --version
            (0, "Server Version: 27.0.3", "")  # docker info
        ]
        
        found, version = check_docker()
        
        assert found is True
        assert "27.0.3" in version or version != ""
    
    def test_check_docker_returns_tuple(self):
        """Test check_docker returns tuple."""
        found, version = check_docker()
        
        assert isinstance(found, bool)
        assert isinstance(version, str)
    
    @patch('shutil.which')
    def test_docker_not_installed(self, mock_which):
        """Test Docker detection when not installed."""
        mock_which.return_value = None
        
        found, version = check_docker()
        
        assert found is False
    
    @patch('lib.docker.utils.run_command')
    @patch('shutil.which')
    def test_docker_daemon_not_running(self, mock_which, mock_run):
        """Test Docker detection when daemon not running."""
        mock_which.return_value = "/usr/bin/docker"
        mock_run.side_effect = [
            (0, "Docker version 27.0.3", ""),  # docker --version
            (1, "", "Cannot connect to Docker daemon")  # docker info
        ]
        
        found, version = check_docker()
        
        assert found is False


class TestCheckDockerModelRunnerStatus:
    """Tests for check_docker_model_runner_status function."""
    
    def test_status_returns_tuple(self):
        """Test check_docker_model_runner_status returns tuple."""
        available, msg = check_docker_model_runner_status()
        
        assert isinstance(available, bool)
        assert isinstance(msg, str)
    
    @patch('lib.docker.utils.run_command')
    @patch('shutil.which')
    def test_dmr_available(self, mock_which, mock_run):
        """Test DMR available."""
        mock_which.return_value = "/usr/bin/docker"
        mock_run.side_effect = [
            (0, "Server Version: 27.0.3", ""),  # docker info
            (0, "NAME\nai/model:7b\n", "")  # docker model list
        ]
        
        available, msg = check_docker_model_runner_status()
        
        assert available is True
        assert "available" in msg.lower()
    
    @patch('lib.docker.utils.run_command')
    @patch('shutil.which')
    def test_dmr_not_enabled(self, mock_which, mock_run):
        """Test DMR not enabled."""
        mock_which.return_value = "/usr/bin/docker"
        mock_run.side_effect = [
            (0, "Server Version: 27.0.3", ""),  # docker info
            (1, "", "unknown command")  # docker model list
        ]
        
        available, msg = check_docker_model_runner_status()
        
        assert available is False
        assert "not enabled" in msg.lower() or "not found" in msg.lower()


class TestFetchAvailableModelsFromApi:
    """Tests for fetch_available_models_from_api function."""
    
    @patch('urllib.request.urlopen')
    def test_fetch_models_success(self, mock_urlopen):
        """Test fetching models from API successfully."""
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.read.return_value = b'{"data": [{"id": "ai/model1:7b"}, {"id": "ai/model2:3b"}]}'
        mock_response.__enter__ = MagicMock(return_value=mock_response)
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        models = fetch_available_models_from_api(DMR_API_BASE)
        
        assert len(models) == 2
        assert "ai/model1:7b" in models
        assert "ai/model2:3b" in models
    
    @patch('urllib.request.urlopen')
    def test_fetch_models_failure(self, mock_urlopen):
        """Test fetching models when API fails."""
        mock_urlopen.side_effect = urllib.error.URLError("Connection refused")
        
        models = fetch_available_models_from_api(DMR_API_BASE)
        
        assert len(models) == 0
    
    @patch('urllib.request.urlopen')
    def test_fetch_models_empty_response(self, mock_urlopen):
        """Test fetching models with empty response."""
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.read.return_value = b'{"data": []}'
        mock_response.__enter__ = MagicMock(return_value=mock_response)
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        models = fetch_available_models_from_api(DMR_API_BASE)
        
        assert len(models) == 0


class TestCheckDockerModelRunner:
    """Tests for check_docker_model_runner function."""
    
    def test_requires_hardware_info(self):
        """Test that check_docker_model_runner requires hardware info."""
        with pytest.raises(ValueError, match="hw_info is required"):
            check_docker_model_runner(None)
    
    @patch('lib.docker.utils.run_command')
    @patch('lib.docker.models.fetch_available_models_from_docker_hub', return_value=[])
    @patch('lib.docker.ui.print_subheader')
    @patch('lib.docker.ui.print_success')
    @patch('lib.docker.ui.print_info')
    def test_dmr_available_with_hw_info(self, mock_info, mock_success, mock_subheader, mock_fetch, mock_run):
        """Test check_docker_model_runner when DMR is available."""
        hw_info = HardwareInfo(
            ram_gb=32.0,
            tier=HardwareTier.A,
            has_apple_silicon=True
        )
        
        mock_run.return_value = (0, "NAME\nai/model:7b\n", "")
        
        # Mock API call
        with patch('urllib.request.urlopen') as mock_urlopen:
            mock_response = MagicMock()
            mock_response.status = 200
            mock_response.read.return_value = b'{"data": [{"id": "ai/model:7b"}]}'
            mock_response.__enter__ = MagicMock(return_value=mock_response)
            mock_response.__exit__ = MagicMock(return_value=False)
            mock_urlopen.return_value = mock_response
            
            result = check_docker_model_runner(hw_info)
        
        assert result is True
        assert hw_info.docker_model_runner_available is True
        assert hw_info.dmr_api_endpoint == DMR_API_BASE


class TestApiConfiguration:
    """Tests for API configuration constants."""
    
    def test_api_host_configured(self):
        """Test API host is configured."""
        assert DMR_API_HOST == "localhost"
    
    def test_api_port_configured(self):
        """Test API port is configured."""
        assert DMR_API_PORT == 12434
    
    def test_api_base_url(self):
        """Test API base URL format."""
        expected = "http://localhost:12434/v1"
        assert DMR_API_BASE == expected
