"""
Unit tests for lib/model_selector.py.

Tests model selection logic, tier-based recommendations, and customization.
"""

import sys
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib import hardware
from lib import model_selector
from lib.model_selector import (
    ModelRole,
    RecommendedModel,
    ModelRecommendation,
    EMBED_MODEL,
    AUTOCOMPLETE_MODELS,
    PRIMARY_MODELS,
    generate_best_recommendation,
    generate_conservative_recommendation,
    get_usable_ram,
    get_alternatives_for_role,
)


# =============================================================================
# Model Catalog Tests
# =============================================================================

class TestModelCatalog:
    """Tests for the hardcoded model catalog."""
    
    def test_embed_model_exists(self):
        """Test that embed model is defined."""
        assert EMBED_MODEL is not None
        assert EMBED_MODEL.docker_name.startswith("ai/")
        assert "embed" in EMBED_MODEL.roles
    
    def test_autocomplete_models_per_tier(self):
        """Test that autocomplete models are defined for each tier."""
        for tier in [hardware.HardwareTier.S, hardware.HardwareTier.A, 
                     hardware.HardwareTier.B, hardware.HardwareTier.C]:
            assert tier in AUTOCOMPLETE_MODELS, f"Missing autocomplete model for {tier}"
            model = AUTOCOMPLETE_MODELS[tier]
            assert "autocomplete" in model.roles
    
    def test_primary_models_per_tier(self):
        """Test that primary models are defined for each tier."""
        for tier in [hardware.HardwareTier.S, hardware.HardwareTier.A, 
                     hardware.HardwareTier.B, hardware.HardwareTier.C]:
            assert tier in PRIMARY_MODELS, f"Missing primary model for {tier}"
            models = PRIMARY_MODELS[tier]
            assert isinstance(models, list), f"PRIMARY_MODELS[{tier}] should be a list"
            assert len(models) > 0, f"PRIMARY_MODELS[{tier}] should not be empty"
            # Check first model has chat role
            assert "chat" in models[0].roles
    
    def test_docker_name_format(self):
        """Test that all model docker_names follow ai/ format."""
        # Test embed model
        assert EMBED_MODEL.docker_name.startswith("ai/"), \
            f"Embed model docker_name should start with ai/: {EMBED_MODEL.docker_name}"
        
        # Test autocomplete models
        for tier, model in AUTOCOMPLETE_MODELS.items():
            assert model.docker_name.startswith("ai/"), \
                f"Autocomplete {tier} docker_name should start with ai/: {model.docker_name}"
        
        # Test primary models (each tier has a list of models)
        for tier, models in PRIMARY_MODELS.items():
            for model in models:
                assert model.docker_name.startswith("ai/"), \
                    f"Primary {tier} docker_name should start with ai/: {model.docker_name}"


# =============================================================================
# RecommendedModel Tests
# =============================================================================

class TestRecommendedModel:
    """Tests for RecommendedModel dataclass."""
    
    def test_model_creation(self):
        """Test creating a RecommendedModel."""
        model = RecommendedModel(
            name="Test Model",
            docker_name="ai/test-model:7b",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat", "edit"],
            description="Test description"
        )
        assert model.name == "Test Model"
        assert model.docker_name == "ai/test-model:7b"
        assert model.ram_gb == 5.0
    
    def test_model_with_fallback(self):
        """Test model with fallback defined."""
        model = RecommendedModel(
            name="Primary Model",
            docker_name="ai/primary:7b",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat"],
            fallback_name="ai/fallback:7b"
        )
        assert model.fallback_name == "ai/fallback:7b"


# =============================================================================
# ModelRecommendation Tests
# =============================================================================

class TestModelRecommendation:
    """Tests for ModelRecommendation dataclass."""
    
    def test_all_models(self, mock_recommended_models):
        """Test all_models() returns all non-None models."""
        all_models = mock_recommended_models.all_models()
        assert len(all_models) == 3  # primary, autocomplete, embeddings
    
    def test_total_ram(self, mock_recommended_models):
        """Test total_ram() calculation."""
        total = mock_recommended_models.total_ram()
        expected = 5.0 + 2.0 + 0.3  # 7.3 GB
        assert abs(total - expected) < 0.01
    
    def test_recommendation_with_only_primary(self):
        """Test recommendation with only primary model."""
        primary = RecommendedModel(
            name="Primary",
            docker_name="ai/primary:7b",
            ram_gb=5.0,
            role=ModelRole.CHAT,
            roles=["chat"]
        )
        rec = ModelRecommendation(primary=primary)
        assert len(rec.all_models()) == 1
        assert rec.total_ram() == 5.0


# =============================================================================
# Get Usable RAM Tests
# =============================================================================

class TestGetUsableRam:
    """Tests for get_usable_ram function."""
    
    def test_tier_c_usable_ram(self, mock_hardware_tier_c):
        """Test usable RAM for Tier C."""
        usable = get_usable_ram(mock_hardware_tier_c)
        # Tier C: 16GB * 0.60 = 9.6 GB
        assert abs(usable - 9.6) < 0.1
    
    def test_tier_a_usable_ram(self, mock_hardware_tier_a):
        """Test usable RAM for Tier A."""
        usable = get_usable_ram(mock_hardware_tier_a)
        # Tier A: 32GB * 0.70 = 22.4 GB
        assert abs(usable - 22.4) < 0.1
    
    def test_tier_s_usable_ram(self, mock_hardware_tier_s):
        """Test usable RAM for Tier S."""
        usable = get_usable_ram(mock_hardware_tier_s)
        # Tier S: 64GB * 0.70 = 44.8 GB
        assert abs(usable - 44.8) < 0.1


# =============================================================================
# Generate Recommendation Tests
# =============================================================================

class TestGenerateRecommendation:
    """Tests for recommendation generation functions."""
    
    def test_best_recommendation_tier_c(self, mock_hardware_tier_c):
        """Test best recommendation for Tier C."""
        rec = generate_best_recommendation(mock_hardware_tier_c)
        
        assert rec is not None
        assert rec.primary is not None
        # Total RAM should fit within usable
        assert rec.total_ram() <= get_usable_ram(mock_hardware_tier_c) + 1.0
    
    def test_best_recommendation_tier_a(self, mock_hardware_tier_a):
        """Test best recommendation for Tier A."""
        rec = generate_best_recommendation(mock_hardware_tier_a)
        
        assert rec is not None
        assert rec.primary is not None
        assert rec.embeddings is not None  # Should have embeddings
    
    def test_best_recommendation_tier_s(self, mock_hardware_tier_s):
        """Test best recommendation for Tier S."""
        rec = generate_best_recommendation(mock_hardware_tier_s)
        
        assert rec is not None
        assert rec.primary is not None
        # Tier S should get the best models
        assert "chat" in rec.primary.roles
    
    def test_best_recommendation_has_embeddings(self, mock_hardware_tier_a):
        """Test best recommendation includes embeddings."""
        rec = generate_best_recommendation(mock_hardware_tier_a)
        
        assert rec is not None
        assert rec.primary is not None
        assert rec.embeddings is not None
    
    def test_conservative_recommendation(self, mock_hardware_tier_c):
        """Test conservative recommendation."""
        rec = generate_conservative_recommendation(mock_hardware_tier_c)
        
        assert rec is not None
        assert rec.primary is not None
        # Conservative should use less RAM
        total = rec.total_ram()
        usable = get_usable_ram(mock_hardware_tier_c)
        assert total < usable


# =============================================================================
# Get Alternatives Tests
# =============================================================================

class TestGetAlternatives:
    """Tests for get_alternatives_for_role function."""
    
    def test_get_chat_alternatives(self, mock_hardware_tier_a):
        """Test getting alternative chat models."""
        usable = get_usable_ram(mock_hardware_tier_a)
        alts = get_alternatives_for_role(ModelRole.CHAT, usable)
        
        # May return empty list if no alternatives fit
        assert isinstance(alts, list)
        for model in alts:
            assert "chat" in model.roles
    
    def test_get_autocomplete_alternatives(self, mock_hardware_tier_a):
        """Test getting alternative autocomplete models."""
        usable = get_usable_ram(mock_hardware_tier_a)
        alts = get_alternatives_for_role(ModelRole.AUTOCOMPLETE, usable)
        
        assert len(alts) > 0
        for model in alts:
            assert "autocomplete" in model.roles
    
    def test_alternatives_fit_in_ram(self, mock_hardware_tier_c):
        """Test that alternatives fit within available RAM."""
        usable = get_usable_ram(mock_hardware_tier_c)
        alts = get_alternatives_for_role(ModelRole.CHAT, usable)
        
        for model in alts:
            assert model.ram_gb <= usable, \
                f"Alternative {model.name} ({model.ram_gb}GB) exceeds usable RAM ({usable}GB)"


# =============================================================================
# Model Role Tests
# =============================================================================

class TestModelRole:
    """Tests for ModelRole enum."""
    
    def test_all_roles_defined(self):
        """Test that all expected roles are defined."""
        expected_roles = {"CHAT", "EDIT", "AUTOCOMPLETE", "EMBED", "APPLY", "RERANK"}
        actual_roles = {role.name for role in ModelRole}
        assert expected_roles.issubset(actual_roles)
    
    def test_role_values(self):
        """Test role enum values."""
        assert ModelRole.CHAT.value == "chat"
        assert ModelRole.AUTOCOMPLETE.value == "autocomplete"
        assert ModelRole.EMBED.value == "embed"


# =============================================================================
# RAM Constraint Tests
# =============================================================================

class TestRamConstraints:
    """Tests for RAM constraint handling."""
    
    @pytest.mark.parametrize("tier_fixture,expected_max_primary", [
        ("mock_hardware_tier_c", 8.0),   # Tier C: ~9.6 GB usable, primary should be < 8
        ("mock_hardware_tier_b", 12.0),  # Tier B: ~15.6 GB usable
        ("mock_hardware_tier_a", 18.0),  # Tier A: ~22.4 GB usable
        ("mock_hardware_tier_s", 35.0),  # Tier S: ~44.8 GB usable
    ])
    def test_primary_model_fits_tier(self, tier_fixture, expected_max_primary, request):
        """Test that primary model recommendation fits within tier's RAM."""
        hw_info = request.getfixturevalue(tier_fixture)
        rec = generate_best_recommendation(hw_info)
        
        if rec and rec.primary:
            assert rec.primary.ram_gb <= expected_max_primary, \
                f"Primary model {rec.primary.name} ({rec.primary.ram_gb}GB) exceeds expected max ({expected_max_primary}GB)"
    
    def test_total_recommendation_fits_usable_ram(self, mock_hardware_tier_a):
        """Test that total recommendation fits within usable RAM with buffer."""
        rec = generate_best_recommendation(mock_hardware_tier_a)
        usable = get_usable_ram(mock_hardware_tier_a)
        
        # Allow 2GB buffer for runtime overhead
        assert rec.total_ram() <= usable + 2.0, \
            f"Total recommendation ({rec.total_ram()}GB) exceeds usable RAM + buffer ({usable + 2.0}GB)"
