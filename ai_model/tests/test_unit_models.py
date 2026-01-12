"""
Unit tests for lib/models.py - Model catalog and legacy support.

Tests cover:
- ModelInfo dataclass
- MODEL_CATALOG validation
"""

import pytest
from lib import hardware
from lib.models import ModelInfo, MODEL_CATALOG

# Determine backend type
import os
_test_backend = os.environ.get('TEST_BACKEND', 'ollama').lower()
if _test_backend == 'docker':
    model_name_attr = "docker_name"
else:
    model_name_attr = "ollama_name"


class TestModelInfo:
    """Tests for ModelInfo dataclass."""
    
    def test_model_info_creation(self, backend_type):
        """Test creating a ModelInfo instance with all fields."""
        model_kwargs = {
            "name": "Test Model",
            "description": "A test model",
            "ram_gb": 5.0,
            "context_length": 32768,
            "roles": ["chat", "edit"],
            "tiers": [hardware.HardwareTier.A, hardware.HardwareTier.B],
            "recommended_for": ["Testing"],
            "base_model_name": "test"
        }
        model_kwargs[model_name_attr] = "test:latest"
        model = ModelInfo(**model_kwargs)
        assert model.name == "Test Model"
        assert getattr(model, model_name_attr) == "test:latest"
        assert model.ram_gb == 5.0
        assert "chat" in model.roles
    
    def test_model_info_default_values(self, backend_type):
        """Test ModelInfo with default field values."""
        model_kwargs = {
            "name": "Minimal Model",
            "description": "A minimal model",
            "ram_gb": 1.0,
            "context_length": 4096,
            "roles": ["chat"]
        }
        model_kwargs[model_name_attr] = "minimal:latest"
        model = ModelInfo(**model_kwargs)
        # Default values should be set
        assert model.recommended_for == []
        assert model.base_model_name is None
        assert model.selected_variant is None
    
    def test_model_info_with_selected_variant(self, backend_type):
        """Test ModelInfo with a selected variant."""
        model_kwargs = {
            "name": "Test Model",
            "description": "Test model with variant",
            "ram_gb": 5.0,
            "context_length": 32768,
            "roles": ["chat"],
            "selected_variant": "7b-q4_k_m"
        }
        model_kwargs[model_name_attr] = "test:7b"
        model = ModelInfo(**model_kwargs)
        assert model.selected_variant == "7b-q4_k_m"


class TestModelCatalog:
    """Tests for MODEL_CATALOG."""
    
    def test_catalog_not_empty(self):
        """Verify MODEL_CATALOG has models."""
        assert len(MODEL_CATALOG) > 0
    
    def test_all_models_have_required_fields(self):
        """Verify all models have required fields populated."""
        for model in MODEL_CATALOG:
            assert model.name, f"Model missing name"
            assert getattr(model, model_name_attr), f"{model.name} missing {model_name_attr}"
            assert model.description, f"{model.name} missing description"
            assert model.ram_gb > 0, f"{model.name} has invalid ram_gb"
            assert model.context_length > 0, f"{model.name} has invalid context_length"
            assert len(model.roles) > 0, f"{model.name} has no roles"
    
    def test_catalog_has_embedding_model(self):
        """Verify catalog includes at least one embedding model."""
        embed_models = [m for m in MODEL_CATALOG if "embed" in m.roles]
        assert len(embed_models) > 0, "No embedding model in catalog"
    
    def test_catalog_has_chat_model(self):
        """Verify catalog includes at least one chat model."""
        chat_models = [m for m in MODEL_CATALOG if "chat" in m.roles]
        assert len(chat_models) > 0, "No chat model in catalog"
    
    def test_catalog_has_autocomplete_model(self):
        """Verify catalog includes at least one autocomplete model."""
        auto_models = [m for m in MODEL_CATALOG if "autocomplete" in m.roles]
        assert len(auto_models) > 0, "No autocomplete model in catalog"
    
    def test_ram_values_reasonable(self):
        """Verify RAM values are reasonable (0.1 - 100 GB)."""
        for model in MODEL_CATALOG:
            assert 0.1 <= model.ram_gb <= 100, f"{model.name} has unreasonable ram_gb: {model.ram_gb}"
    
    def test_context_length_reasonable(self):
        """Verify context lengths are reasonable."""
        for model in MODEL_CATALOG:
            # Some embedding models have smaller context lengths (e.g., 512)
            # Allow context_length >= 512 for embedding models
            min_context = 512 if "embed" in " ".join(model.roles).lower() else 1024
            assert min_context <= model.context_length <= 1000000, \
                f"{model.name} has unreasonable context_length: {model.context_length}"
class TestModelCompatibility:
    """Tests for model compatibility across system."""
    
    def test_model_roles_are_valid(self):
        """Verify all model roles are valid Continue.dev roles."""
        valid_roles = {"chat", "edit", "autocomplete", "embed", "apply", "rerank", "summarize", "agent"}
        for model in MODEL_CATALOG:
            for role in model.roles:
                assert role in valid_roles, f"{model.name} has invalid role: {role}"
    
