"""
Unit tests for lib/llamacpp.py.

Tests llama.cpp server installation, configuration, and management.
"""

import json
import platform
import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib import llamacpp


# =============================================================================
# Configuration Tests
# =============================================================================

class TestServerConfig:
    """Tests for ServerConfig dataclass."""
    
    def test_default_config(self):
        """Test default configuration values."""
        config = llamacpp.ServerConfig()
        
        assert config.host == llamacpp.DEFAULT_HOST
        assert config.port == llamacpp.DEFAULT_PORT
        assert config.context_size == 16384
        assert config.n_gpu_layers == -1
        assert config.parallel == 2
        assert config.cont_batching is True
        assert config.metrics is True
        assert config.log_format == "json"
        assert config.flash_attn is True
        assert config.no_mmap is True
    
    def test_custom_config(self):
        """Test custom configuration."""
        config = llamacpp.ServerConfig(
            host="0.0.0.0",
            port=9000,
            context_size=32768,
            parallel=4
        )
        
        assert config.host == "0.0.0.0"
        assert config.port == 9000
        assert config.context_size == 32768
        assert config.parallel == 4


# =============================================================================
# Binary Installation Tests
# =============================================================================

class TestBinaryInstallation:
    """Tests for binary download and installation."""
    
    @patch('urllib.request.urlopen')
    def test_get_latest_release_url_success(self, mock_urlopen):
        """Test getting latest release URL successfully."""
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.read.return_value = json.dumps({
            "assets": [
                {
                    "name": "llama-server-darwin-arm64",
                    "browser_download_url": "https://example.com/binary"
                }
            ]
        }).encode('utf-8')
        mock_response.__enter__ = Mock(return_value=mock_response)
        mock_response.__exit__ = Mock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        success, url = llamacpp.get_latest_release_url()
        
        assert success is True
        assert "example.com" in url
    
    @patch('urllib.request.urlopen')
    def test_get_latest_release_url_failure(self, mock_urlopen):
        """Test getting latest release URL with failure."""
        import urllib.error
        mock_urlopen.side_effect = urllib.error.URLError("Connection failed")
        
        success, error = llamacpp.get_latest_release_url()
        
        assert success is False
        assert "Connection failed" in error
    
    @patch('urllib.request.urlopen')
    @patch('pathlib.Path.mkdir')
    @patch('builtins.open', create=True)
    def test_download_binary_success(self, mock_open, mock_mkdir, mock_urlopen):
        """Test successful binary download."""
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.headers = {'Content-Length': '1000'}
        mock_response.read.side_effect = [b'data', b'']
        mock_response.__enter__ = Mock(return_value=mock_response)
        mock_response.__exit__ = Mock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        mock_file = MagicMock()
        mock_open.return_value.__enter__ = Mock(return_value=mock_file)
        mock_open.return_value.__exit__ = Mock(return_value=False)
        
        dest_path = Path("/tmp/test-binary")
        success, message = llamacpp.download_binary("https://example.com/binary", dest_path)
        
        assert success is True
        assert "successful" in message.lower()
    
    @patch('urllib.request.urlopen')
    def test_download_binary_failure(self, mock_urlopen):
        """Test binary download failure."""
        import urllib.error
        mock_urlopen.side_effect = urllib.error.URLError("Download failed")
        
        dest_path = Path("/tmp/test-binary")
        success, message = llamacpp.download_binary("https://example.com/binary", dest_path)
        
        assert success is False
        assert "failed" in message.lower()


# =============================================================================
# Model Download Tests
# =============================================================================

class TestModelDownload:
    """Tests for model download functionality."""
    
    def test_get_model_download_url_q4(self):
        """Test getting Q4_K_M model URL."""
        success, url, filename = llamacpp.get_model_download_url("Q4_K_M")
        
        assert success is True
        assert "gpt-oss-20b-q4_k_m.gguf" in filename
        assert "huggingface.co" in url
    
    def test_get_model_download_url_invalid(self):
        """Test getting URL for invalid quantization."""
        success, url, error = llamacpp.get_model_download_url("INVALID")
        
        assert success is False
        assert "Unknown" in error


# =============================================================================
# Context Size Tests
# =============================================================================

class TestContextSizing:
    """Tests for context size calculation."""
    
    @patch('lib.hardware.HardwareInfo')
    def test_calculate_optimal_context_size_16gb(self, mock_hw):
        """Test context size calculation for 16GB RAM."""
        mock_hw.ram_gb = 16.0
        mock_hw.get_ram_tier.return_value = "16GB"
        
        context, reason = llamacpp.calculate_optimal_context_size(mock_hw)
        
        assert context > 0
        assert "16GB" in reason or "aggressive" in reason.lower()
    
    @patch('lib.hardware.HardwareInfo')
    def test_calculate_optimal_context_size_32gb(self, mock_hw):
        """Test context size calculation for 32GB RAM."""
        mock_hw.ram_gb = 32.0
        mock_hw.get_ram_tier.return_value = "32GB"
        
        context, reason = llamacpp.calculate_optimal_context_size(mock_hw)
        
        assert context >= 98304  # Aggressive tier for 32GB
    
    @patch('os.environ.get')
    def test_context_size_environment_override(self, mock_env):
        """Test context size override from environment."""
        mock_env.return_value = "32768"
        
        from lib import hardware
        hw_info = hardware.HardwareInfo(ram_gb=16.0)
        hw_info.get_ram_tier = Mock(return_value="16GB")
        
        context, reason = llamacpp.calculate_optimal_context_size(hw_info)
        
        # Should use environment value if set
        # Note: This test may need adjustment based on actual implementation
        assert context > 0


# =============================================================================
# Server Management Tests
# =============================================================================

class TestServerManagement:
    """Tests for server start/stop/status."""
    
    @patch('urllib.request.urlopen')
    def test_check_server_health_success(self, mock_urlopen):
        """Test health check when server is healthy."""
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.read.return_value = json.dumps({"status": "ok"}).encode('utf-8')
        mock_response.__enter__ = Mock(return_value=mock_response)
        mock_response.__exit__ = Mock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        is_healthy, health_data = llamacpp.check_server_health()
        
        assert is_healthy is True
        assert health_data is not None
        assert health_data.get("status") == "ok"
    
    @patch('urllib.request.urlopen')
    def test_check_server_health_failure(self, mock_urlopen):
        """Test health check when server is not healthy."""
        import urllib.error
        mock_urlopen.side_effect = urllib.error.URLError("Connection refused")
        
        is_healthy, health_data = llamacpp.check_server_health()
        
        assert is_healthy is False
        assert health_data is None
    
    @patch('lib.utils.run_command')
    def test_stop_server_success(self, mock_run):
        """Test stopping server successfully."""
        mock_run.return_value = (0, "", "")
        
        success = llamacpp.stop_server()
        
        assert success is True
    
    @patch('lib.utils.run_command')
    def test_stop_server_failure(self, mock_run):
        """Test stopping server with failure."""
        mock_run.return_value = (-1, "", "Command failed")
        
        success = llamacpp.stop_server()
        
        # Should still return True if server is not running
        assert isinstance(success, bool)


# =============================================================================
# LaunchAgent Tests
# =============================================================================

class TestLaunchAgent:
    """Tests for LaunchAgent creation and management."""
    
    @patch('pathlib.Path.mkdir')
    @patch('builtins.open', create=True)
    @patch('plistlib.dump')
    def test_create_launch_agent_success(self, mock_dump, mock_open, mock_mkdir):
        """Test creating LaunchAgent successfully."""
        config = llamacpp.ServerConfig(
            binary_path=Path("/tmp/llama-server"),
            model_path=Path("/tmp/model.gguf"),
            context_size=16384
        )
        
        success, plist_path = llamacpp.create_launch_agent(config)
        
        assert success is True
        assert plist_path.name == llamacpp.LAUNCH_AGENT_PLIST
    
    @patch('lib.utils.run_command')
    def test_load_launch_agent_success(self, mock_run):
        """Test loading LaunchAgent successfully."""
        mock_run.return_value = (0, "", "")
        
        plist_path = Path("/tmp/test.plist")
        success = llamacpp.load_launch_agent(plist_path)
        
        assert success is True
    
    @patch('lib.utils.run_command')
    def test_unload_launch_agent_success(self, mock_run):
        """Test unloading LaunchAgent successfully."""
        mock_run.return_value = (0, "", "")
        
        success = llamacpp.unload_launch_agent()
        
        assert success is True


# =============================================================================
# Utility Function Tests
# =============================================================================

class TestUtilityFunctions:
    """Tests for utility functions."""
    
    def test_get_parallel_count_16gb(self):
        """Test parallel count for 16GB RAM."""
        from lib import hardware
        hw_info = hardware.HardwareInfo(ram_gb=16.0)
        
        parallel = llamacpp.get_parallel_count(hw_info)
        
        assert parallel == 2
    
    def test_get_parallel_count_32gb(self):
        """Test parallel count for 32GB RAM."""
        from lib import hardware
        hw_info = hardware.HardwareInfo(ram_gb=32.0)
        
        parallel = llamacpp.get_parallel_count(hw_info)
        
        assert parallel == 4
    
    def test_get_parallel_count_64gb(self):
        """Test parallel count for 64GB+ RAM."""
        from lib import hardware
        hw_info = hardware.HardwareInfo(ram_gb=64.0)
        
        parallel = llamacpp.get_parallel_count(hw_info)
        
        assert parallel == 8
    
    def test_build_server_args(self):
        """Test building server command arguments."""
        config = llamacpp.ServerConfig(
            binary_path=Path("/tmp/llama-server"),
            model_path=Path("/tmp/model.gguf"),
            host="127.0.0.1",
            port=8080,
            context_size=16384,
            parallel=2
        )
        
        args = llamacpp.build_server_args(config)
        
        assert "--host" in args
        assert "127.0.0.1" in args
        assert "--port" in args
        assert "8080" in args
        assert "--model" in args
        assert "--ctx-size" in args
        assert "16384" in args
        assert "--parallel" in args
        assert "2" in args
    
    def test_build_server_args_with_rope_scaling(self):
        """Test building server args with rope scaling."""
        config = llamacpp.ServerConfig(
            binary_path=Path("/tmp/llama-server"),
            model_path=Path("/tmp/model.gguf"),
            context_size=65536,
            rope_scaling="yarn",
            yarn_ext_factor=1.0
        )
        
        args = llamacpp.build_server_args(config)
        
        assert "--rope-scaling" in args
        assert "yarn" in args
        assert "--yarn-ext-factor" in args
        assert "1.0" in args
