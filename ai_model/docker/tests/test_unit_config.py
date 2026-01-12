"""
Unit tests for lib/config.py.

Tests configuration generation, manifest creation, and file fingerprinting.
"""

import json
import sys
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch
import tempfile

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib import config
from lib import hardware
from lib.model_selector import RecommendedModel, ModelRole


# =============================================================================
# YAML Generation Tests
# =============================================================================

class TestYamlGeneration:
    """Tests for YAML generation functions."""
    
    def test_format_yaml_value_string(self):
        """Test formatting string values."""
        assert config.format_yaml_value("test") == "test"
        assert config.format_yaml_value("test:value") == '"test:value"'
    
    def test_format_yaml_value_bool(self):
        """Test formatting boolean values."""
        assert config.format_yaml_value(True) == "true"
        assert config.format_yaml_value(False) == "false"
    
    def test_format_yaml_value_number(self):
        """Test formatting numeric values."""
        assert config.format_yaml_value(42) == "42"
        assert config.format_yaml_value(3.14) == "3.14"


# =============================================================================
# File Fingerprinting Tests
# =============================================================================

class TestFileFingerprinting:
    """Tests for file fingerprinting functions."""
    
    def test_calculate_file_hash(self, tmp_path):
        """Test calculating file hash."""
        test_file = tmp_path / "test.txt"
        test_file.write_text("test content")
        
        hash1 = config.calculate_file_hash(test_file)
        hash2 = config.calculate_file_hash(test_file)
        
        assert hash1 == hash2
        assert len(hash1) == 64
    
    def test_calculate_file_hash_different_content(self, tmp_path):
        """Test different content produces different hashes."""
        file1 = tmp_path / "file1.txt"
        file2 = tmp_path / "file2.txt"
        file1.write_text("content 1")
        file2.write_text("content 2")
        
        hash1 = config.calculate_file_hash(file1)
        hash2 = config.calculate_file_hash(file2)
        
        assert hash1 != hash2


# =============================================================================
# Manifest Creation Tests
# =============================================================================

class TestManifestCreation:
    """Tests for installation manifest creation."""
    
    def test_manifest_version(self, tmp_path, mock_hardware_tier_a):
        """Test manifest has correct version."""
        model = RecommendedModel(
            name="Test Model",
            docker_name="ai/test:7b",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat"]
        )
        
        test_file = tmp_path / ".continue" / "config.yaml"
        test_file.parent.mkdir(parents=True)
        test_file.write_text("test: config")
        
        with patch.object(Path, 'home', return_value=tmp_path):
            manifest_path = config.create_installation_manifest(
                installed_models=[model],
                created_files=[test_file],
                hw_info=mock_hardware_tier_a,
                target_ide=["vscode"],
                pre_existing_models=[]
            )
        
        manifest = json.loads(manifest_path.read_text())
        assert manifest["version"] == "2.0"
        assert manifest["installer_type"] == "docker"


# =============================================================================
# Config Customization Tests
# =============================================================================

class TestConfigCustomization:
    """Tests for config customization detection."""
    
    def test_check_config_modified(self, tmp_path):
        """Test detecting modified config."""
        test_file = tmp_path / "config.yaml"
        test_file.write_text("original: value")
        original_hash = config.calculate_file_hash(test_file)
        
        manifest = {
            "installed": {
                "files": [{
                    "path": str(test_file),
                    "fingerprint": original_hash
                }]
            }
        }
        
        test_file.write_text("modified: value")
        
        status = config.check_config_customization(test_file, manifest)
        assert status == "modified"
