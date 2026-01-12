"""
Extended tests for lib/model_selector.py - Additional coverage.
"""

import pytest
from unittest.mock import patch, MagicMock

from lib.model_selector import (
    ModelRole, RecommendedModel,
    EMBED_MODEL, PRIMARY_MODEL, select_models
)
from lib.hardware import HardwareInfo


class TestSelectModels:
    """Tests for select_models function - returns fixed models."""
    
    def test_returns_fixed_models(self, backend_type):
        """Test select_models returns PRIMARY_MODEL and EMBED_MODEL for all users."""
        hw_info = HardwareInfo(ram_gb=32.0, has_apple_silicon=True, apple_chip_model="M4")
        
        models = select_models(hw_info)
        
        assert len(models) == 2
        assert models[0] == PRIMARY_MODEL
        assert models[1] == EMBED_MODEL
    
    def test_primary_model_is_gpt_oss(self, backend_type):
        """Test primary model is GPT-OSS 20B."""
        hw_info = HardwareInfo(ram_gb=32.0, has_apple_silicon=True, apple_chip_model="M4")
        
        models = select_models(hw_info)
        
        model_name_attr = "docker_name" if backend_type == "docker" else "ollama_name"
        assert "gpt-oss" in getattr(models[0], model_name_attr).lower()
        assert models[0].ram_gb == 16.0
    
    def test_embed_model_is_nomic(self, backend_type):
        """Test embedding model is nomic-embed-text."""
        hw_info = HardwareInfo(ram_gb=32.0, has_apple_silicon=True, apple_chip_model="M4")
        
        models = select_models(hw_info)
        
        model_name_attr = "docker_name" if backend_type == "docker" else "ollama_name"
        assert "nomic" in getattr(models[1], model_name_attr).lower()
        assert models[1].ram_gb == 0.3


class TestRecommendedModelDataclass:
    """Tests for RecommendedModel dataclass."""
    
    def test_model_with_all_fields(self, backend_type, model_name_attr):
        """Test creating model with all fields."""
        model_kwargs = {
            "name": "Test Model",
            "ram_gb": 5.0,
            "role": ModelRole.CHAT,
            "roles": ["chat", "edit"],
            "description": "A test model",
        }
        model_kwargs[model_name_attr] = "test:v1"
        model = RecommendedModel(**model_kwargs)
        
        assert model.name == "Test Model"
        assert model.description == "A test model"
    
    def test_model_without_optional_fields(self, backend_type, model_name_attr):
        """Test creating model without optional fields."""
        model_kwargs = {
            "name": "Minimal",
            "ram_gb": 3.0,
            "role": ModelRole.AUTOCOMPLETE,
            "roles": ["autocomplete"]
        }
        model_kwargs[model_name_attr] = "minimal:v1"
        model = RecommendedModel(**model_kwargs)
        
        assert model.description == ""
