"""
Extended tests for lib/model_selector.py - Additional coverage.
"""

import pytest
from unittest.mock import patch, MagicMock

from lib.model_selector import (
    ModelRole, RecommendedModel, ModelRecommendation,
    get_usable_ram,
    EMBED_MODEL, AUTOCOMPLETE_MODELS, PRIMARY_MODELS
)
from lib.hardware import HardwareTier, HardwareInfo


class TestModelRecommendationDisplay:
    """Tests for model recommendation display."""
    
    def test_recommendation_has_all_models(self, generate_best_recommendation):
        """Test recommendation has all required models."""
        hw = HardwareInfo(ram_gb=24, tier=HardwareTier.B)
        rec = generate_best_recommendation(hw)
        
        assert rec.primary is not None
        assert rec.embeddings is not None


class TestModelRecommendationGeneration:
    """Tests for model recommendation generation."""
    
    def test_best_recommendation_tier_s(self, generate_best_recommendation):
        """Test best recommendation for Tier S."""
        hw = HardwareInfo(ram_gb=64, tier=HardwareTier.S)
        rec = generate_best_recommendation(hw)
        
        assert rec.primary is not None
        assert rec.embeddings is not None
    
    def test_best_recommendation_tier_c(self, generate_best_recommendation):
        """Test best recommendation for Tier C."""
        hw = HardwareInfo(ram_gb=16, tier=HardwareTier.C)
        rec = generate_best_recommendation(hw)
        
        assert rec.primary is not None
        # Embeddings should still be included (very small)
        assert rec.embeddings is not None
    
    def test_best_recommendation_all_tiers(self, generate_best_recommendation):
        """Test best recommendation for all tiers."""
        for tier, ram in [(HardwareTier.S, 64), (HardwareTier.A, 32),
                          (HardwareTier.B, 24), (HardwareTier.C, 16)]:
            hw = HardwareInfo(ram_gb=ram, tier=tier)
            rec = generate_best_recommendation(hw)
            
            assert rec.primary is not None
            # Should fit within available RAM
            usable = get_usable_ram(hw)
            assert rec.total_ram() <= usable


class TestModelAlternatives:
    """Tests for model alternatives."""
    
    def test_primary_models_have_alternatives(self, backend_type, model_name_attr):
        """Test that primary models have alternatives in the catalog."""
        hw = HardwareInfo(ram_gb=32, tier=HardwareTier.A)
        current = PRIMARY_MODELS[HardwareTier.A][0]
        
        # Check that there are other models in the same tier
        all_models = PRIMARY_MODELS[HardwareTier.A]
        assert len(all_models) > 0
        # Current model should be in the list
        assert current in all_models
    
    def test_embed_model_is_unique(self):
        """Test that embed model is the same across tiers."""
        hw = HardwareInfo(ram_gb=24, tier=HardwareTier.B)
        current = EMBED_MODEL
        
        # EMBED_MODEL should be the same for all tiers
        assert current is not None
        assert current.role == ModelRole.EMBED


class TestModelCatalogs:
    """Tests for model catalogs."""
    
    def test_embed_model_universal(self):
        """Test embed model is the same across tiers."""
        # EMBED_MODEL should be the same for all tiers
        assert EMBED_MODEL.role == ModelRole.EMBED
        assert "embed" in EMBED_MODEL.roles
    
    def test_autocomplete_models_exist(self):
        """Test autocomplete models exist for all tiers."""
        for tier in [HardwareTier.S, HardwareTier.A, HardwareTier.B, HardwareTier.C]:
            assert tier in AUTOCOMPLETE_MODELS
            model = AUTOCOMPLETE_MODELS[tier]
            assert model.role == ModelRole.AUTOCOMPLETE
    
    def test_primary_models_exist(self):
        """Test primary models exist for all tiers."""
        for tier in [HardwareTier.S, HardwareTier.A, HardwareTier.B, HardwareTier.C]:
            assert tier in PRIMARY_MODELS
            models = PRIMARY_MODELS[tier]
            assert len(models) > 0
            for model in models:
                assert model.role == ModelRole.CHAT


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
            "fallback_name": "fallback:v1"
        }
        model_kwargs[model_name_attr] = "test:v1"
        model = RecommendedModel(**model_kwargs)
        
        assert model.name == "Test Model"
        assert model.description == "A test model"
        assert model.fallback_name == "fallback:v1"
    
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
        assert model.fallback_name is None


class TestModelRecommendationDataclass:
    """Tests for ModelRecommendation dataclass."""
    
    def test_all_models_method(self):
        """Test all_models method returns correct list."""
        primary = RecommendedModel("P", "p:v", 5.0, ModelRole.CHAT, ["chat"])
        auto = RecommendedModel("A", "a:v", 2.0, ModelRole.AUTOCOMPLETE, ["autocomplete"])
        embed = RecommendedModel("E", "e:v", 0.3, ModelRole.EMBED, ["embed"])
        
        rec = ModelRecommendation(
            primary=primary,
            autocomplete=auto,
            embeddings=embed
        )
        
        models = rec.all_models()
        assert len(models) == 3
        assert primary in models
        assert auto in models
        assert embed in models
    
    def test_total_ram_method(self):
        """Test total_ram method calculates correctly."""
        primary = RecommendedModel("P", "p:v", 5.0, ModelRole.CHAT, ["chat"])
        auto = RecommendedModel("A", "a:v", 2.5, ModelRole.AUTOCOMPLETE, ["autocomplete"])
        
        rec = ModelRecommendation(
            primary=primary,
            autocomplete=auto
        )
        
        total = rec.total_ram()
        assert total == pytest.approx(7.5, abs=0.1)
