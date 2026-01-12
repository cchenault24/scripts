"""
Unit tests for lib/model_selector.py - Smart model recommendation engine.

Tests cover:
- ModelRole enum
- RecommendedModel dataclass
- ModelRecommendation dataclass
- get_usable_ram function
- Model recommendation generation
- Alternative model selection
- Customization functions

Runs against both ollama and docker backends.
"""

import sys
from pathlib import Path
import pytest
from unittest.mock import patch, MagicMock

# Add backend directories to path
_ollama_path = str(Path(__file__).parent.parent / "ollama")
_docker_path = str(Path(__file__).parent.parent / "docker")
if _ollama_path not in sys.path:
    sys.path.insert(0, _ollama_path)
if _docker_path not in sys.path:
    sys.path.insert(0, _docker_path)

from lib import model_selector
from lib.model_selector import (
    ModelRole, RecommendedModel,
    EMBED_MODEL, PRIMARY_MODEL, select_models
)
# generate_multi_model_recommendation may not exist in Docker backend
try:
    from lib.model_selector import generate_multi_model_recommendation
except ImportError:
    generate_multi_model_recommendation = None
from lib import hardware
from lib.hardware import HardwareInfo

# Determine backend from environment for model name attribute
import os
_test_backend = os.environ.get('TEST_BACKEND', 'ollama').lower()
model_name_attr = "docker_name" if _test_backend == "docker" else "ollama_name"


def create_hw_info(ram_gb: float) -> HardwareInfo:
    """Create a real HardwareInfo object for testing."""
    return HardwareInfo(ram_gb=ram_gb)


class TestModelRole:
    """Tests for ModelRole enum."""
    
    def test_model_role_values(self):
        """Test ModelRole has expected values."""
        assert ModelRole.CHAT.value == "chat"
        assert ModelRole.AUTOCOMPLETE.value == "autocomplete"
        assert ModelRole.EMBED.value == "embed"
    
    def test_all_roles_defined(self):
        """Test all expected roles are defined."""
        roles = [r.value for r in ModelRole]
        assert "chat" in roles
        assert "autocomplete" in roles
        assert "embed" in roles


class TestRecommendedModel:
    """Tests for RecommendedModel dataclass."""
    
    def test_create_model(self):
        """Test creating a RecommendedModel instance."""
        model_kwargs = {
            "name": "Test Model",
            "ram_gb": 5.0,
            "role": ModelRole.CHAT,
            "roles": ["chat", "edit"]
        }
        model_kwargs[model_name_attr] = "test:latest"
        model = RecommendedModel(**model_kwargs)
        
        assert model.name == "Test Model"
        assert getattr(model, model_name_attr) == "test:latest"
        assert model.ram_gb == 5.0
        assert model.role == ModelRole.CHAT
        assert "chat" in model.roles
    
    def test_model_with_description(self):
        """Test model with description."""
        model_kwargs = {
            "name": "Primary Model",
            "ram_gb": 8.0,
            "role": ModelRole.CHAT,
            "roles": ["chat"],
            "description": "A primary model for testing"
        }
        model_kwargs[model_name_attr] = "primary:latest"
        model = RecommendedModel(**model_kwargs)
        
        assert model.description == "A primary model for testing"




class TestEmbedModel:
    """Tests for EMBED_MODEL constant."""
    
    def test_embed_model_exists(self):
        """Test embed model is defined."""
        assert EMBED_MODEL is not None
        assert isinstance(EMBED_MODEL, RecommendedModel)
    
    def test_embed_model_has_embed_role(self):
        """Test embed model has embed role."""
        assert EMBED_MODEL.role == ModelRole.EMBED
        assert "embed" in EMBED_MODEL.roles
    
    def test_embed_model_low_ram(self):
        """Test embed model has low RAM requirement."""
        # Embedding models should be lightweight
        assert EMBED_MODEL.ram_gb < 1.0


class TestSelectModels:
    """Tests for select_models function - returns fixed models for all users."""
    
    def test_returns_fixed_models(self, backend_type):
        """Test select_models returns PRIMARY_MODEL and EMBED_MODEL."""
        hw_info = create_hw_info(32.0)
        hw_info.has_apple_silicon = True
        hw_info.apple_chip_model = "M4"
        
        models = select_models(hw_info)
        
        assert len(models) == 2
        assert models[0] == PRIMARY_MODEL
        assert models[1] == EMBED_MODEL
    
    def test_primary_model_is_gpt_oss(self, backend_type):
        """Test primary model is GPT-OSS 20B."""
        hw_info = create_hw_info(32.0)
        hw_info.has_apple_silicon = True
        hw_info.apple_chip_model = "M4"
        
        models = select_models(hw_info)
        
        assert "gpt-oss" in models[0].name.lower() or "gpt-oss" in getattr(models[0], model_name_attr).lower()
        assert models[0].ram_gb == 16.0
    
    def test_embed_model_is_nomic(self, backend_type):
        """Test embedding model is nomic-embed-text."""
        hw_info = create_hw_info(32.0)
        hw_info.has_apple_silicon = True
        hw_info.apple_chip_model = "M4"
        
        models = select_models(hw_info)
        
        assert "nomic" in models[1].name.lower() or "nomic" in getattr(models[1], model_name_attr).lower()
        assert models[1].ram_gb == 0.3
