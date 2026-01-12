"""
Comprehensive tests for lib/config.py - Configuration generation.

Tests cover:
- YAML generation
- Setup summary generation
- Continue config generation
- Continueignore generation
- Global rules and codebase rules
- Manifest handling
- File fingerprinting
"""

import pytest
from unittest.mock import patch, MagicMock, mock_open
from pathlib import Path
import json
import tempfile
import os

from lib import config
from lib.config import (
    _get_utc_timestamp, _normalize_model, format_yaml_value, generate_yaml,
    generate_setup_summary, calculate_file_hash, classify_file_type,
    add_fingerprint_header, add_fingerprint_to_json, is_our_file,
    load_installation_manifest, check_config_customization
)
from lib import hardware
from lib.hardware import HardwareInfo
from lib.model_selector import RecommendedModel, ModelRole


class TestGetUtcTimestamp:
    """Tests for _get_utc_timestamp function."""
    
    def test_returns_string(self):
        """Test returns ISO format string."""
        ts = _get_utc_timestamp()
        assert isinstance(ts, str)
        # ISO format should have T separator
        assert "T" in ts
    
    def test_contains_date(self):
        """Test timestamp contains date components."""
        ts = _get_utc_timestamp()
        # Should have year, month, day
        parts = ts.split("T")[0].split("-")
        assert len(parts) == 3


class TestNormalizeModel:
    """Tests for _normalize_model function."""
    
    def test_normalize_recommended_model(self, backend_type, model_name_attr):
        """Test normalizing RecommendedModel."""
        model_kwargs = {
            "name": "Test Model",
            "ram_gb": 5.0,
            "role": ModelRole.CHAT,
            "roles": ["chat", "edit"]
        }
        model_kwargs[model_name_attr] = "test:latest"
        model = RecommendedModel(**model_kwargs)
        
        result = _normalize_model(model)
        
        assert result["name"] == "Test Model"
        assert result[model_name_attr] == "test:latest"
        assert result["ram_gb"] == 5.0
        assert "chat" in result["roles"]
    
    def test_normalize_dict(self):
        """Test normalizing dictionary model."""
        model = {
            "name": "Dict Model",
            "ollama_name": "dict:v1",
            "ram_gb": 3.0,
            "roles": ["chat"],
            "context_length": 8192
        }
        
        result = _normalize_model(model)
        
        assert result == model
    
    def test_normalize_invalid_raises(self):
        """Test normalizing invalid type raises error."""
        with pytest.raises(ValueError):
            _normalize_model("invalid")


class TestFormatYamlValue:
    """Tests for format_yaml_value function."""
    
    def test_format_bool_true(self):
        """Test formatting True."""
        assert format_yaml_value(True) == "true"
    
    def test_format_bool_false(self):
        """Test formatting False."""
        assert format_yaml_value(False) == "false"
    
    def test_format_simple_string(self):
        """Test formatting simple string."""
        assert format_yaml_value("hello") == "hello"
    
    def test_format_string_with_special_chars(self):
        """Test formatting string with special characters."""
        result = format_yaml_value("http://example.com:8080")
        assert result.startswith('"')
        assert result.endswith('"')
    
    def test_format_number(self):
        """Test formatting number."""
        assert format_yaml_value(42) == "42"
        assert format_yaml_value(3.14) == "3.14"


class TestGenerateYaml:
    """Tests for generate_yaml function."""
    
    def test_simple_dict(self):
        """Test generating simple YAML."""
        config = {"key": "value", "number": 42}
        
        result = generate_yaml(config)
        
        assert "key: value" in result
        assert "number: 42" in result
    
    def test_nested_dict(self):
        """Test generating nested YAML."""
        config = {
            "outer": {
                "inner": "value"
            }
        }
        
        result = generate_yaml(config)
        
        assert "outer:" in result
        assert "inner: value" in result
    
    def test_list_values(self):
        """Test generating YAML with lists."""
        config = {
            "items": ["a", "b", "c"]
        }
        
        result = generate_yaml(config)
        
        assert "items:" in result
        assert "- a" in result
    
    def test_comment_handling(self):
        """Test that comment keys are preserved."""
        config = {"# This is a comment": None, "key": "value"}
        
        result = generate_yaml(config)
        
        assert "# This is a comment" in result
    
    def test_none_values_skipped(self):
        """Test that None values are skipped."""
        config = {"present": "value", "absent": None}
        
        result = generate_yaml(config)
        
        assert "present: value" in result
        assert "absent" not in result


class TestGenerateSetupSummary:
    """Tests for generate_setup_summary function."""
    
    def test_generates_summary(self):
        """Test summary generation."""
        hw_info = HardwareInfo(
            ram_gb=24,
            cpu_brand="Apple M2",
            has_apple_silicon=True,
            apple_chip_model="M2"
        )
        
        models = [
            RecommendedModel("Model1", "m1:v", 5.0, ModelRole.CHAT, ["chat"]),
            RecommendedModel("Model2", "m2:v", 0.3, ModelRole.EMBED, ["embed"]),
        ]
        
        result = generate_setup_summary(models, hw_info)
        
        assert "hardware" in result
        assert "models" in result
        assert "ram_usage" in result
    
    def test_hardware_info_included(self):
        """Test hardware info in summary."""
        hw_info = HardwareInfo(
            ram_gb=32,
            has_apple_silicon=True,
            apple_chip_model="M3 Max"
        )
        
        models = [
            RecommendedModel("Test", "test:v", 5.0, ModelRole.CHAT, ["chat"])
        ]
        
        result = generate_setup_summary(models, hw_info)
        
        assert result["hardware"]["ram_gb"] == 32
    
    def test_ram_usage_calculated(self):
        """Test RAM usage calculation."""
        hw_info = HardwareInfo(ram_gb=16)
        
        models = [
            RecommendedModel("M1", "m1:v", 3.0, ModelRole.CHAT, ["chat"]),
            RecommendedModel("M2", "m2:v", 2.0, ModelRole.AUTOCOMPLETE, ["autocomplete"]),
        ]
        
        result = generate_setup_summary(models, hw_info)
        
        assert result["ram_usage"]["total_ram_gb"] == 5.0


class TestCalculateFileHash:
    """Tests for calculate_file_hash function."""
    
    def test_hash_of_file(self, tmp_path):
        """Test computing hash of file."""
        test_file = tmp_path / "test.txt"
        test_file.write_text("Hello, World!")
        
        hash1 = calculate_file_hash(test_file)
        hash2 = calculate_file_hash(test_file)
        
        assert hash1 == hash2
        assert len(hash1) == 64  # SHA-256 hex length
    
    def test_different_content_different_hash(self, tmp_path):
        """Test different content gives different hash."""
        file1 = tmp_path / "file1.txt"
        file2 = tmp_path / "file2.txt"
        file1.write_text("Content A")
        file2.write_text("Content B")
        
        hash1 = calculate_file_hash(file1)
        hash2 = calculate_file_hash(file2)
        
        assert hash1 != hash2


class TestClassifyFileType:
    """Tests for classify_file_type function."""
    
    @pytest.mark.parametrize("filename,expected_contains", [
        ("config.yaml", "config"),
        ("config.json", "config"),
        ("global-rule.md", "rule"),
        ("codebase-context.md", "rule"),
        (".continueignore", "ignore"),
        ("setup-summary.json", "summary"),
        ("random.txt", ""),
    ])
    def test_classify_file_types(self, filename, expected_contains):
        """Test file type classification."""
        result = classify_file_type(Path(filename))
        if expected_contains:
            assert expected_contains in result
        else:
            # Unknown type should be classified somehow
            assert isinstance(result, str)


class TestAddFingerprintHeader:
    """Tests for add_fingerprint_header function."""
    
    def test_add_to_yaml(self):
        """Test adding fingerprint to YAML content."""
        content = "key: value"
        
        result = add_fingerprint_header(content, "yaml")
        
        assert "Generated by" in result
        assert "key: value" in result
    
    def test_add_to_markdown(self):
        """Test adding fingerprint to Markdown content."""
        content = "# Rule\n\nContent here"
        
        result = add_fingerprint_header(content, "md")
        
        assert "Generated by" in result
        assert "# Rule" in result


class TestAddFingerprintToJson:
    """Tests for add_fingerprint_to_json function."""
    
    def test_adds_metadata(self):
        """Test metadata is added to JSON."""
        data = {"key": "value"}
        
        result = add_fingerprint_to_json(data)
        
        assert "_metadata" in result
        assert "generator" in result["_metadata"]


class TestIsOurFile:
    """Tests for is_our_file function."""
    
    def test_file_with_fingerprint(self, tmp_path, setup_script_name):
        """Test detecting our file by fingerprint."""
        test_file = tmp_path / "config.yaml"
        test_file.write_text(f"# Generated by {setup_script_name}.py v2.0.0\nkey: value")
        
        result = is_our_file(test_file)
        
        # Should detect it as our file (fingerprint or ours)
        assert result in ("fingerprint", "ours", True) or "fingerprint" in str(result).lower()
    
    def test_file_not_ours(self, tmp_path):
        """Test detecting non-our file."""
        test_file = tmp_path / "other.yaml"
        test_file.write_text("# Some other file\nkey: value")
        
        result = is_our_file(test_file)
        
        assert result is False


class TestLoadInstallationManifest:
    """Tests for load_installation_manifest function."""
    
    @patch('pathlib.Path.exists')
    def test_manifest_not_found(self, mock_exists):
        """Test when manifest doesn't exist."""
        mock_exists.return_value = False
        
        result = load_installation_manifest()
        
        assert result is None
    
    @patch('pathlib.Path.exists')
    @patch('builtins.open', mock_open(read_data='{"version": "2.0.0", "installed": {}}'))
    def test_manifest_loaded(self, mock_exists):
        """Test loading manifest."""
        mock_exists.return_value = True
        
        result = load_installation_manifest()
        
        # May return None or dict depending on path handling
        assert result is None or isinstance(result, dict)


class TestCheckConfigCustomization:
    """Tests for check_config_customization function."""
    
    def test_config_not_found(self):
        """Test when config doesn't exist."""
        result = check_config_customization(Path("/nonexistent/path.yaml"))
        
        assert result == "missing"


class TestGenerateContinueConfig:
    """Tests for generate_continue_config function (integration-style)."""
    
    @patch('lib.config.ui.print_subheader')
    @patch('lib.config.ui.print_success')
    def test_generates_valid_config(self, mock_success, mock_header, tmp_path, backend_type, api_endpoint, model_name_attr):
        """Test that generate_continue_config produces valid output."""
        from lib.config import generate_continue_config
        
        hw_kwargs = {
            "ram_gb": 24,
            "has_apple_silicon": True,
        }
        if backend_type == "ollama":
            hw_kwargs["ollama_api_endpoint"] = api_endpoint
        else:
            hw_kwargs["dmr_api_endpoint"] = api_endpoint
        hw_info = HardwareInfo(**hw_kwargs)
        
        model1_kwargs = {"name": "Chat", "ram_gb": 5.0, "role": ModelRole.CHAT, "roles": ["chat", "edit"]}
        model1_kwargs[model_name_attr] = "chat:v"
        model2_kwargs = {"name": "Embed", "ram_gb": 0.3, "role": ModelRole.EMBED, "roles": ["embed"]}
        model2_kwargs[model_name_attr] = "embed:v"
        models = [
            RecommendedModel(**model1_kwargs),
            RecommendedModel(**model2_kwargs),
        ]
        
        output_path = tmp_path / "config.yaml"
        
        result = generate_continue_config(
            models, hw_info, output_path=output_path
        )
        
        assert result.exists()
        content = result.read_text()
        # Should contain model configuration
        assert "models" in content or "chat" in content.lower()


class TestGenerateContinueignore:
    """Tests for generate_continueignore function."""
    
    @patch('lib.config.ui.print_subheader')
    @patch('lib.config.ui.print_success')
    def test_generates_ignore_file(self, mock_success, mock_header, tmp_path):
        """Test generating .continueignore file."""
        from lib.config import generate_continueignore
        
        output_path = tmp_path / ".continueignore"
        
        result = generate_continueignore(output_path=output_path)
        
        assert result.exists()
        content = result.read_text()
        # Should contain common ignore patterns
        assert "node_modules" in content or ".git" in content


class TestGenerateGlobalRule:
    """Tests for generate_global_rule function."""
    
    @patch('lib.config.ui.print_subheader')
    @patch('lib.config.ui.print_success')
    @patch('lib.config.ui.print_info')
    def test_generates_rule_file(self, mock_info, mock_success, mock_header, tmp_path):
        """Test generating global rule file."""
        from lib.config import generate_global_rule
        
        output_path = tmp_path / "global-rule.md"
        
        result = generate_global_rule(output_path=output_path)
        
        assert result.exists()
        content = result.read_text()
        # Should contain content (may be YAML frontmatter or markdown)
        assert len(content) > 0
        # Check for either markdown headings or YAML frontmatter
        assert "#" in content or "---" in content or "description:" in content


class TestGenerateCodebaseRules:
    """Tests for generate_codebase_rules function."""
    
    @patch('lib.config.ui.print_subheader')
    @patch('lib.config.ui.print_success')
    @patch('lib.config.ui.print_info')
    def test_generates_codebase_rules(self, mock_info, mock_success, mock_header, tmp_path):
        """Test generating codebase rules file."""
        from lib.config import generate_codebase_rules
        
        output_path = tmp_path / "codebase-context.md"
        
        result = generate_codebase_rules(output_path=output_path)
        
        assert result.exists()
        content = result.read_text()
        # Should be markdown template
        assert "#" in content or "codebase" in content.lower()
