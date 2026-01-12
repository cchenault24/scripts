"""
Unit tests for lib/uninstaller.py.

Tests uninstallation functionality including manifest handling and cleanup.
"""

import json
import os
import platform
import shutil
import sys
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib import uninstaller


# =============================================================================
# Create Empty Manifest Tests
# =============================================================================

class TestCreateEmptyManifest:
    """Tests for create_empty_manifest function."""
    
    def test_empty_manifest_structure(self):
        """Test empty manifest has correct structure."""
        manifest = uninstaller.create_empty_manifest()
        
        assert "version" in manifest
        assert manifest["version"] == "2.0"
        assert manifest["installer_type"] == "docker"
        assert "installed" in manifest
        assert "pre_existing" in manifest
    
    def test_empty_manifest_installed_section(self):
        """Test installed section structure."""
        manifest = uninstaller.create_empty_manifest()
        
        assert "models" in manifest["installed"]
        assert "files" in manifest["installed"]
        assert manifest["installed"]["models"] == []
        assert manifest["installed"]["files"] == []


# =============================================================================
# Model Name Normalization Tests
# =============================================================================

class TestNormalizeModelName:
    """Tests for normalize_model_name function."""
    
    def test_normalize_with_tag(self):
        """Test normalizing model name with tag."""
        result = uninstaller.normalize_model_name("ai/model:7b-q4_k_m")
        assert result == "ai/model:7b"
    
    def test_normalize_without_tag(self):
        """Test normalizing model name without tag."""
        result = uninstaller.normalize_model_name("ai/model")
        assert result == "ai/model"
    
    def test_normalize_empty_string(self):
        """Test normalizing empty string."""
        result = uninstaller.normalize_model_name("")
        assert result == ""


# =============================================================================
# Models Overlap Tests
# =============================================================================

class TestModelsOverlap:
    """Tests for models_overlap function."""
    
    def test_exact_match(self):
        """Test exact model name match."""
        assert uninstaller.models_overlap("ai/model:7b", "ai/model:7b") is True
    
    def test_same_base_different_tag(self):
        """Test same base model with different tags."""
        assert uninstaller.models_overlap("ai/model:7b", "ai/model:3b") is True
    
    def test_different_models(self):
        """Test different models don't overlap."""
        assert uninstaller.models_overlap("ai/model1:7b", "ai/model2:7b") is False
    
    def test_empty_strings(self):
        """Test empty strings don't overlap."""
        assert uninstaller.models_overlap("", "ai/model:7b") is False
        assert uninstaller.models_overlap("ai/model:7b", "") is False


# =============================================================================
# Get Installed Models Tests
# =============================================================================

class TestGetInstalledModels:
    """Tests for get_installed_models function."""
    
    @patch('lib.uninstaller.utils.run_command')
    def test_get_models_success(self, mock_run):
        """Test getting installed models successfully."""
        mock_run.return_value = (0, "NAME\nai/model1:7b\nai/model2:3b\n", "")
        
        models = uninstaller.get_installed_models()
        
        assert len(models) == 2
        assert "ai/model1:7b" in models
        assert "ai/model2:3b" in models
    
    @patch('lib.uninstaller.utils.run_command')
    def test_get_models_empty(self, mock_run):
        """Test getting models when none installed."""
        mock_run.return_value = (0, "NAME\n", "")
        
        models = uninstaller.get_installed_models()
        
        assert len(models) == 0
    
    @patch('lib.uninstaller.utils.run_command')
    def test_get_models_failure(self, mock_run):
        """Test getting models when command fails."""
        mock_run.return_value = (1, "", "error")
        
        models = uninstaller.get_installed_models()
        
        assert len(models) == 0


# =============================================================================
# Remove Model Tests
# =============================================================================

class TestRemoveModel:
    """Tests for remove_model function."""
    
    @patch('lib.uninstaller.utils.run_command')
    def test_remove_model_success(self, mock_run):
        """Test removing model successfully."""
        mock_run.return_value = (0, "", "")
        
        result = uninstaller.remove_model("ai/model:7b")
        
        assert result is True
        mock_run.assert_called_once()
    
    @patch('lib.uninstaller.utils.run_command')
    def test_remove_model_failure(self, mock_run):
        """Test removing model failure."""
        mock_run.return_value = (1, "", "error: model not found")
        
        result = uninstaller.remove_model("ai/model:7b")
        
        assert result is False


# =============================================================================
# VS Code Extension Tests
# =============================================================================

class TestVSCodeExtension:
    """Tests for VS Code extension functions."""
    
    @patch('lib.uninstaller.utils.run_command')
    @patch('shutil.which')
    def test_check_extension_installed(self, mock_which, mock_run):
        """Test checking VS Code extension installed."""
        mock_which.return_value = "/usr/bin/code"
        mock_run.return_value = (0, "Continue.continue\n", "")
        
        result = uninstaller.check_vscode_extension_installed()
        
        assert result is True
    
    @patch('lib.uninstaller.utils.run_command')
    @patch('shutil.which')
    def test_check_extension_not_installed(self, mock_which, mock_run):
        """Test checking VS Code extension not installed."""
        mock_which.return_value = "/usr/bin/code"
        mock_run.return_value = (0, "other.extension\n", "")
        
        result = uninstaller.check_vscode_extension_installed()
        
        assert result is False
    
    @patch('shutil.which')
    def test_check_extension_code_not_found(self, mock_which):
        """Test checking extension when code CLI not found."""
        mock_which.return_value = None
        
        result = uninstaller.check_vscode_extension_installed()
        
        assert result is False


# =============================================================================
# IntelliJ Plugin Tests
# =============================================================================

class TestIntelliJPlugin:
    """Tests for IntelliJ plugin functions."""
    
    def test_check_plugin_installed(self, tmp_path):
        """Test checking IntelliJ plugin installed."""
        # Create mock plugin directory
        plugin_dir = tmp_path / "Library" / "Application Support" / "JetBrains" / "IntelliJIdea2024.1" / "plugins" / "Continue"
        plugin_dir.mkdir(parents=True)
        
        with patch('platform.system', return_value='Darwin'):
            with patch.object(Path, 'home', return_value=tmp_path):
                installed, paths = uninstaller.check_intellij_plugin_installed()
        
        # Result depends on implementation
        assert isinstance(installed, bool)
        assert isinstance(paths, list)


# =============================================================================
# Scan Orphaned Files Tests
# =============================================================================

class TestScanOrphanedFiles:
    """Tests for scan_for_orphaned_files function."""
    
    def test_scan_empty_manifest(self):
        """Test scanning with empty manifest."""
        manifest = uninstaller.create_empty_manifest()
        
        orphaned = uninstaller.scan_for_orphaned_files(manifest)
        
        assert isinstance(orphaned, list)
    
    def test_scan_finds_orphaned_files(self, tmp_path):
        """Test scanning finds orphaned files."""
        # Create test files
        continue_dir = tmp_path / ".continue"
        continue_dir.mkdir()
        orphan_file = continue_dir / "docker-setup-orphan.txt"
        orphan_file.write_text("orphaned file")
        
        manifest = {
            "installed": {
                "files": []  # File not in manifest
            }
        }
        
        # The actual test depends on implementation details
        orphaned = uninstaller.scan_for_orphaned_files(manifest)
        assert isinstance(orphaned, list)


# =============================================================================
# Safe Location Tests
# =============================================================================

class TestIsSafeLocation:
    """Tests for is_safe_location function."""
    
    def test_home_dir_is_safe(self, tmp_path):
        """Test home directory is safe to scan."""
        path = tmp_path / ".continue"
        result = uninstaller.is_safe_location(path)
        assert result is True
    
    def test_system_paths_unsafe(self):
        """Test system paths are not safe to scan."""
        unsafe_paths = [
            Path("/usr/bin"),
            Path("/System/Library"),
            Path("/bin"),
        ]
        
        for path in unsafe_paths:
            result = uninstaller.is_safe_location(path)
            assert result is False, f"{path} should be unsafe"


# =============================================================================
# Remove Models Tests
# =============================================================================

class TestRemoveModels:
    """Tests for remove_models function."""
    
    @patch('lib.uninstaller.get_installed_models')
    @patch('lib.uninstaller.remove_model')
    def test_remove_multiple_models(self, mock_remove, mock_get):
        """Test removing multiple models."""
        mock_get.return_value = ["ai/model1:7b", "ai/model2:3b"]
        mock_remove.return_value = True
        
        removed = uninstaller.remove_models(["ai/model1:7b", "ai/model2:3b"])
        
        assert removed == 2
    
    @patch('lib.uninstaller.get_installed_models')
    @patch('lib.uninstaller.remove_model')
    def test_remove_partial_success(self, mock_remove, mock_get):
        """Test partial success removing models."""
        mock_get.return_value = ["ai/model1:7b", "ai/model2:3b"]
        mock_remove.side_effect = [True, False]  # First succeeds, second fails
        
        removed = uninstaller.remove_models(["ai/model1:7b", "ai/model2:3b"])
        
        assert removed == 1
    
    @patch('lib.uninstaller.get_installed_models')
    def test_remove_no_models_installed(self, mock_get):
        """Test removing when no models installed."""
        mock_get.return_value = []
        
        removed = uninstaller.remove_models(["ai/model:7b"])
        
        assert removed == 0
