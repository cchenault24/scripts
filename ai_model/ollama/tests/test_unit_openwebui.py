"""
Unit tests for Open WebUI integration.

Tests the openwebui module functions for Docker-based Open WebUI setup.
"""

import json
import platform
import subprocess
import unittest
from pathlib import Path
from typing import Any, Dict
from unittest.mock import MagicMock, patch

# Add parent directory to path for imports
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from lib import openwebui


class TestDockerDetection(unittest.TestCase):
    """Test Docker detection functions."""
    
    @patch('shutil.which')
    def test_is_docker_installed_true(self, mock_which):
        """Test Docker installed detection."""
        mock_which.return_value = "/usr/local/bin/docker"
        self.assertTrue(openwebui.is_docker_installed())
        mock_which.assert_called_once_with("docker")
    
    @patch('shutil.which')
    def test_is_docker_installed_false(self, mock_which):
        """Test Docker not installed detection."""
        mock_which.return_value = None
        self.assertFalse(openwebui.is_docker_installed())
    
    @patch('lib.openwebui.is_docker_installed')
    @patch('lib.utils.run_command')
    def test_is_docker_running_true(self, mock_run, mock_installed):
        """Test Docker daemon running detection."""
        mock_installed.return_value = True
        mock_run.return_value = (0, "OK", "")
        self.assertTrue(openwebui.is_docker_running())
    
    @patch('lib.openwebui.is_docker_installed')
    def test_is_docker_running_not_installed(self, mock_installed):
        """Test Docker running check when not installed."""
        mock_installed.return_value = False
        self.assertFalse(openwebui.is_docker_running())
    
    @patch('lib.openwebui.is_docker_installed')
    @patch('lib.utils.run_command')
    def test_get_docker_version(self, mock_run, mock_installed):
        """Test getting Docker version."""
        mock_installed.return_value = True
        mock_run.return_value = (0, "Docker version 24.0.7, build afdd53b", "")
        version = openwebui.get_docker_version()
        self.assertIn("Docker version", version)


class TestContainerManagement(unittest.TestCase):
    """Test container management functions."""
    
    @patch('lib.openwebui.is_docker_running')
    @patch('lib.utils.run_command')
    def test_is_openwebui_container_exists_true(self, mock_run, mock_running):
        """Test container exists detection."""
        mock_running.return_value = True
        mock_run.return_value = (0, "open-webui-local\n", "")
        self.assertTrue(openwebui.is_openwebui_container_exists())
    
    @patch('lib.openwebui.is_docker_running')
    @patch('lib.utils.run_command')
    def test_is_openwebui_container_exists_false(self, mock_run, mock_running):
        """Test container does not exist."""
        mock_running.return_value = True
        mock_run.return_value = (0, "", "")
        self.assertFalse(openwebui.is_openwebui_container_exists())
    
    @patch('lib.openwebui.is_docker_running')
    def test_is_openwebui_container_exists_docker_not_running(self, mock_running):
        """Test container check when Docker not running."""
        mock_running.return_value = False
        self.assertFalse(openwebui.is_openwebui_container_exists())
    
    @patch('lib.openwebui.is_docker_running')
    @patch('lib.utils.run_command')
    def test_is_openwebui_running_true(self, mock_run, mock_docker_running):
        """Test container running detection."""
        mock_docker_running.return_value = True
        mock_run.return_value = (0, "open-webui-local\n", "")
        self.assertTrue(openwebui.is_openwebui_running())
    
    @patch('lib.openwebui.is_docker_running')
    @patch('lib.utils.run_command')
    def test_is_openwebui_running_false(self, mock_run, mock_docker_running):
        """Test container not running."""
        mock_docker_running.return_value = True
        mock_run.return_value = (0, "", "")
        self.assertFalse(openwebui.is_openwebui_running())


class TestOpenWebUIStatus(unittest.TestCase):
    """Test status retrieval functions."""
    
    @patch('lib.openwebui.is_docker_installed')
    def test_get_status_docker_not_installed(self, mock_installed):
        """Test status when Docker not installed."""
        mock_installed.return_value = False
        status = openwebui.get_openwebui_status()
        self.assertFalse(status["docker_installed"])
        self.assertFalse(status["docker_running"])
        self.assertFalse(status["container_exists"])
    
    @patch('lib.openwebui.is_docker_installed')
    @patch('lib.openwebui.is_docker_running')
    def test_get_status_docker_not_running(self, mock_running, mock_installed):
        """Test status when Docker not running."""
        mock_installed.return_value = True
        mock_running.return_value = False
        status = openwebui.get_openwebui_status()
        self.assertTrue(status["docker_installed"])
        self.assertFalse(status["docker_running"])
        self.assertFalse(status["container_exists"])
    
    @patch('lib.openwebui.is_docker_installed')
    @patch('lib.openwebui.is_docker_running')
    @patch('lib.openwebui.is_openwebui_container_exists')
    @patch('lib.openwebui.is_openwebui_running')
    @patch('lib.utils.run_command')
    @patch('lib.openwebui.verify_openwebui_accessible')
    def test_get_status_full(self, mock_verify, mock_run, mock_container_running, 
                              mock_container_exists, mock_docker_running, mock_docker_installed):
        """Test full status retrieval."""
        mock_docker_installed.return_value = True
        mock_docker_running.return_value = True
        mock_container_exists.return_value = True
        mock_container_running.return_value = True
        mock_run.return_value = (0, "0.0.0.0:3000", "")
        mock_verify.return_value = True
        
        status = openwebui.get_openwebui_status()
        
        self.assertTrue(status["docker_installed"])
        self.assertTrue(status["docker_running"])
        self.assertTrue(status["container_exists"])
        self.assertTrue(status["container_running"])
        self.assertEqual(status["container_port"], 3000)
        self.assertTrue(status["web_accessible"])


class TestConfiguration(unittest.TestCase):
    """Test configuration constants."""
    
    def test_container_name(self):
        """Test container name is set."""
        self.assertEqual(openwebui.OPENWEBUI_CONTAINER_NAME, "open-webui-local")
    
    def test_default_port(self):
        """Test default port is set."""
        self.assertEqual(openwebui.OPENWEBUI_PORT, 3000)
    
    def test_env_vars_privacy(self):
        """Test environment variables disable telemetry."""
        self.assertEqual(openwebui.OPENWEBUI_ENV["DO_NOT_TRACK"], "true")
        self.assertEqual(openwebui.OPENWEBUI_ENV["SCARF_NO_ANALYTICS"], "true")
    
    def test_env_vars_local_only(self):
        """Test environment variables configure local operation."""
        self.assertIn("host.docker.internal", openwebui.OPENWEBUI_ENV["OLLAMA_BASE_URL"])
        self.assertEqual(openwebui.OPENWEBUI_ENV["ENABLE_RAG_WEB_SEARCH"], "false")
        self.assertEqual(openwebui.OPENWEBUI_ENV["ENABLE_IMAGE_GENERATION"], "false")
    
    def test_env_vars_rag_config(self):
        """Test RAG uses local embedding model."""
        self.assertEqual(openwebui.OPENWEBUI_ENV["RAG_EMBEDDING_ENGINE"], "ollama")
        self.assertEqual(openwebui.OPENWEBUI_ENV["RAG_EMBEDDING_MODEL"], "nomic-embed-text")
    
    def test_linux_env_uses_localhost(self):
        """Test Linux environment uses localhost instead of host.docker.internal."""
        self.assertIn("127.0.0.1", openwebui.LINUX_OPENWEBUI_ENV["OLLAMA_BASE_URL"])


class TestManifestEntry(unittest.TestCase):
    """Test manifest entry generation."""
    
    @patch('lib.openwebui.get_openwebui_status')
    def test_manifest_entry_installed(self, mock_status):
        """Test manifest entry when container exists."""
        mock_status.return_value = {
            "container_exists": True,
            "container_running": True,
            "container_port": 3000,
            "url": "http://localhost:3000"
        }
        
        entry = openwebui.get_openwebui_manifest_entry()
        
        self.assertEqual(entry["type"], "openwebui")
        self.assertTrue(entry["installed"])
        self.assertTrue(entry["running"])
        self.assertEqual(entry["container_name"], "open-webui-local")
        self.assertEqual(entry["port"], 3000)
        self.assertIsNotNone(entry["installed_at"])
    
    @patch('lib.openwebui.get_openwebui_status')
    def test_manifest_entry_not_installed(self, mock_status):
        """Test manifest entry when not installed."""
        mock_status.return_value = {
            "container_exists": False,
            "container_running": False,
            "container_port": None,
            "url": None
        }
        
        entry = openwebui.get_openwebui_manifest_entry()
        
        self.assertEqual(entry["type"], "openwebui")
        self.assertFalse(entry["installed"])
        self.assertFalse(entry["running"])
        self.assertIsNone(entry["installed_at"])


class TestContainerOperations(unittest.TestCase):
    """Test container start/stop/remove operations."""
    
    @patch('lib.openwebui.is_openwebui_running')
    @patch('lib.utils.run_command')
    def test_stop_container_success(self, mock_run, mock_running):
        """Test stopping container successfully."""
        mock_running.return_value = True
        mock_run.return_value = (0, "", "")
        
        result = openwebui.stop_openwebui_container()
        self.assertTrue(result)
    
    @patch('lib.openwebui.is_openwebui_running')
    def test_stop_container_not_running(self, mock_running):
        """Test stopping container when already stopped."""
        mock_running.return_value = False
        
        result = openwebui.stop_openwebui_container()
        self.assertTrue(result)
    
    @patch('lib.openwebui.is_openwebui_running')
    @patch('lib.openwebui.stop_openwebui_container')
    @patch('lib.openwebui.is_openwebui_container_exists')
    @patch('lib.utils.run_command')
    def test_remove_container(self, mock_run, mock_exists, mock_stop, mock_running):
        """Test removing container."""
        mock_running.return_value = False
        mock_exists.return_value = True
        mock_run.return_value = (0, "", "")
        mock_stop.return_value = True
        
        result = openwebui.remove_openwebui_container(remove_data=False)
        self.assertTrue(result)


class TestUninstall(unittest.TestCase):
    """Test uninstall functions."""
    
    @patch('lib.openwebui.is_docker_installed')
    def test_uninstall_docker_not_installed(self, mock_installed):
        """Test uninstall when Docker not installed."""
        mock_installed.return_value = False
        
        results = openwebui.uninstall_openwebui()
        
        self.assertFalse(results["container_removed"])
        self.assertFalse(results["data_removed"])
        self.assertFalse(results["image_removed"])
    
    @patch('lib.openwebui.is_docker_installed')
    @patch('lib.openwebui.is_docker_running')
    def test_uninstall_docker_not_running(self, mock_running, mock_installed):
        """Test uninstall when Docker not running."""
        mock_installed.return_value = True
        mock_running.return_value = False
        
        results = openwebui.uninstall_openwebui()
        
        self.assertFalse(results["container_removed"])


class TestImagePull(unittest.TestCase):
    """Test Docker image pulling."""
    
    @patch('lib.utils.run_command')
    def test_pull_image_success(self, mock_run):
        """Test successful image pull."""
        mock_run.return_value = (0, "Pull complete", "")
        
        result = openwebui.pull_openwebui_image()
        self.assertTrue(result)
    
    @patch('lib.utils.run_command')
    def test_pull_image_failure(self, mock_run):
        """Test failed image pull."""
        mock_run.return_value = (1, "", "Network error")
        
        result = openwebui.pull_openwebui_image()
        self.assertFalse(result)


if __name__ == "__main__":
    unittest.main()
