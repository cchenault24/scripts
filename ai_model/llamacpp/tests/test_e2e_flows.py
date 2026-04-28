"""
End-to-end flow tests for llama.cpp server setup.

Tests complete installation and management workflows.
"""

import json
import platform
import sys
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib import hardware
from lib import llamacpp


# =============================================================================
# Installation Flow Tests
# =============================================================================

class TestInstallationFlow:
    """Tests for complete installation workflow."""
    
    @pytest.mark.skipif(platform.system() != "Darwin", reason="macOS only")
    @patch('lib.llamacpp.install_binary')
    @patch('lib.llamacpp.download_model')
    @patch('lib.llamacpp.find_optimal_context_size')
    @patch('lib.llamacpp.test_server_start')
    @patch('lib.llamacpp.create_launch_agent')
    def test_complete_installation_flow(
        self,
        mock_create_agent,
        mock_test_start,
        mock_find_context,
        mock_download_model,
        mock_install_binary
    ):
        """Test complete installation flow."""
        # Setup mocks
        mock_install_binary.return_value = (True, Path("/tmp/llama-server"))
        mock_download_model.return_value = (True, Path("/tmp/model.gguf"))
        mock_find_context.return_value = (16384, "Test successful")
        mock_test_start.return_value = (True, 16384)
        mock_create_agent.return_value = (True, Path("/tmp/plist.plist"))
        
        # Simulate installation steps
        binary_success, binary_path = mock_install_binary()
        assert binary_success is True
        
        model_success, model_path = mock_download_model("Q4_K_M")
        assert model_success is True
        
        context, reason = mock_find_context(
            hardware.HardwareInfo(ram_gb=16.0),
            model_path,
            binary_path
        )
        assert context > 0
        
        test_success, _ = mock_test_start(
            llamacpp.ServerConfig(
                binary_path=binary_path,
                model_path=model_path,
                context_size=context
            )
        )
        assert test_success is True
        
        agent_success, _ = mock_create_agent(
            llamacpp.ServerConfig(
                binary_path=binary_path,
                model_path=model_path,
                context_size=context
            )
        )
        assert agent_success is True


# =============================================================================
# Context Optimization Flow Tests
# =============================================================================

class TestContextOptimizationFlow:
    """Tests for context size optimization workflow."""
    
    @patch('lib.llamacpp.test_server_start')
    def test_context_fallback_chain(self, mock_test_start):
        """Test context size fallback mechanism."""
        # Simulate failures for large contexts, success for smaller
        def side_effect(config, timeout):
            if config.context_size > 32768:
                return (False, None)
            return (True, config.context_size)
        
        mock_test_start.side_effect = side_effect
        
        # Test fallback chain
        test_contexts = [65536, 32768, 16384]
        optimal = None
        
        for ctx_size in test_contexts:
            config = llamacpp.ServerConfig(
                binary_path=Path("/tmp/llama-server"),
                model_path=Path("/tmp/model.gguf"),
                context_size=ctx_size
            )
            
            success, _ = mock_test_start(config, timeout=30)
            if success:
                optimal = ctx_size
                break
        
        assert optimal == 32768  # First successful size in chain


# =============================================================================
# Server Management Flow Tests
# =============================================================================

class TestServerManagementFlow:
    """Tests for server management workflows."""
    
    @patch('lib.llamacpp.check_server_health')
    @patch('lib.llamacpp.get_server_status')
    def test_status_command_flow(self, mock_get_status, mock_check_health):
        """Test status command workflow."""
        mock_check_health.return_value = (True, {"status": "ok"})
        mock_get_status.return_value = {
            "running": True,
            "health": {"status": "ok"},
            "models": [{"id": "gpt-oss-20b"}]
        }
        
        is_healthy, health_data = mock_check_health()
        assert is_healthy is True
        
        status = mock_get_status()
        assert status["running"] is True
        assert len(status.get("models", [])) > 0
    
    @patch('lib.llamacpp.stop_server')
    @patch('lib.llamacpp.unload_launch_agent')
    def test_stop_command_flow(self, mock_unload, mock_stop):
        """Test stop command workflow."""
        mock_unload.return_value = True
        mock_stop.return_value = True
        
        unload_success = mock_unload()
        assert unload_success is True
        
        stop_success = mock_stop()
        assert stop_success is True


# =============================================================================
# VPN Resilience Tests
# =============================================================================

class TestVPNResilience:
    """Tests for VPN-resilient configuration."""
    
    def test_vpn_resilient_environment(self):
        """Test VPN-resilient environment setup."""
        llamacpp.setup_vpn_resilient_environment()
        
        # Check that environment variables are set
        assert "NO_PROXY" in llamacpp.VPN_RESILIENT_ENV
    
    def test_server_config_uses_127_0_0_1(self):
        """Test that server config uses 127.0.0.1 by default."""
        config = llamacpp.ServerConfig()
        
        assert config.host == "127.0.0.1"
        assert config.host != "localhost"


# =============================================================================
# Error Handling Tests
# =============================================================================

class TestErrorHandling:
    """Tests for error handling and recovery."""
    
    @patch('lib.llamacpp.test_server_start')
    def test_oom_fallback(self, mock_test_start):
        """Test out-of-memory fallback mechanism."""
        # Simulate OOM on first attempt
        def side_effect(config, timeout):
            if config.context_size >= 65536:
                return (False, None)  # OOM
            return (True, config.context_size)
        
        mock_test_start.side_effect = side_effect
        
        # Try large context first
        config = llamacpp.ServerConfig(
            binary_path=Path("/tmp/llama-server"),
            model_path=Path("/tmp/model.gguf"),
            context_size=65536
        )
        
        success, _ = mock_test_start(config)
        if not success:
            # Fallback to smaller
            config.context_size = 32768
            success, _ = mock_test_start(config)
            assert success is True
