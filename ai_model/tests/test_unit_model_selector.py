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
    ModelRole, RecommendedModel, ModelRecommendation,
    get_usable_ram, generate_best_recommendation,
    generate_conservative_recommendation,
)
# generate_multi_model_recommendation may not exist in Docker backend
try:
    from lib.model_selector import generate_multi_model_recommendation
except ImportError:
    generate_multi_model_recommendation = None
from lib.model_selector import (
    get_alternatives_for_role, EMBED_MODEL, AUTOCOMPLETE_MODELS, PRIMARY_MODELS
)
from lib import hardware
from lib.hardware import HardwareTier, HardwareInfo

# Determine backend from environment for model name attribute
import os
_test_backend = os.environ.get('TEST_BACKEND', 'ollama').lower()
model_name_attr = "docker_name" if _test_backend == "docker" else "ollama_name"


def create_hw_info(ram_gb: float, tier: HardwareTier) -> HardwareInfo:
    """Create a real HardwareInfo object for testing."""
    return HardwareInfo(ram_gb=ram_gb, tier=tier)


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
    
    def test_model_with_fallback(self):
        """Test model with fallback_name."""
        model_kwargs = {
            "name": "Primary Model",
            "ram_gb": 8.0,
            "role": ModelRole.CHAT,
            "roles": ["chat"],
            "fallback_name": "fallback:latest"
        }
        model_kwargs[model_name_attr] = "primary:latest"
        model = RecommendedModel(**model_kwargs)
        
        assert model.fallback_name == "fallback:latest"


class TestModelRecommendation:
    """Tests for ModelRecommendation dataclass."""
    
    def test_all_models_returns_list(self):
        """Test all_models() returns all non-None models."""
        rec = ModelRecommendation(
            primary=RecommendedModel("P", "p:v", 5.0, ModelRole.CHAT, ["chat"]),
            autocomplete=RecommendedModel("A", "a:v", 2.0, ModelRole.AUTOCOMPLETE, ["autocomplete"]),
            embeddings=RecommendedModel("E", "e:v", 0.3, ModelRole.EMBED, ["embed"]),
        )
        
        models = rec.all_models()
        assert len(models) == 3
    
    def test_all_models_excludes_none(self):
        """Test all_models() excludes None models."""
        rec = ModelRecommendation(
            primary=RecommendedModel("P", "p:v", 5.0, ModelRole.CHAT, ["chat"]),
            autocomplete=None,
            embeddings=RecommendedModel("E", "e:v", 0.3, ModelRole.EMBED, ["embed"]),
        )
        
        models = rec.all_models()
        assert len(models) == 2
    
    def test_total_ram(self):
        """Test total_ram method calculates correctly."""
        rec = ModelRecommendation(
            primary=RecommendedModel("P", "p:v", 5.0, ModelRole.CHAT, ["chat"]),
            autocomplete=RecommendedModel("A", "a:v", 2.0, ModelRole.AUTOCOMPLETE, ["autocomplete"]),
            embeddings=RecommendedModel("E", "e:v", 0.3, ModelRole.EMBED, ["embed"]),
        )
        
        assert rec.total_ram() == pytest.approx(7.3, abs=0.01)
    
    def test_total_ram_primary_only(self):
        """Test total_ram with only primary model."""
        rec = ModelRecommendation(
            primary=RecommendedModel("P", "p:v", 5.0, ModelRole.CHAT, ["chat"]),
            autocomplete=None,
            embeddings=None,
        )
        
        assert rec.total_ram() == pytest.approx(5.0, abs=0.01)


class TestGetUsableRam:
    """Tests for get_usable_ram function."""
    
    def test_tier_c_reservation(self):
        """Test Tier C uses 40% reservation (60% usable)."""
        hw_info = create_hw_info(16, HardwareTier.C)
        
        usable = get_usable_ram(hw_info)
        expected = 16 * 0.60  # 9.6 GB
        assert usable == pytest.approx(expected, abs=0.1)
    
    def test_tier_b_reservation(self):
        """Test Tier B uses 35% reservation (65% usable)."""
        hw_info = create_hw_info(24, HardwareTier.B)
        
        usable = get_usable_ram(hw_info)
        expected = 24 * 0.65  # 15.6 GB
        assert usable == pytest.approx(expected, abs=0.1)
    
    def test_tier_a_reservation(self):
        """Test Tier A uses 30% reservation (70% usable)."""
        hw_info = create_hw_info(32, HardwareTier.A)
        
        usable = get_usable_ram(hw_info)
        expected = 32 * 0.70  # 22.4 GB
        assert usable == pytest.approx(expected, abs=0.1)
    
    def test_tier_s_reservation(self):
        """Test Tier S uses 30% reservation (70% usable)."""
        hw_info = create_hw_info(64, HardwareTier.S)
        
        usable = get_usable_ram(hw_info)
        expected = 64 * 0.70  # 44.8 GB
        assert usable == pytest.approx(expected, abs=0.1)


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


class TestAutocompleteModels:
    """Tests for AUTOCOMPLETE_MODELS dictionary."""
    
    def test_all_tiers_have_models(self):
        """Test all hardware tiers have autocomplete models."""
        for tier in [HardwareTier.C, HardwareTier.B, HardwareTier.A, HardwareTier.S]:
            assert tier in AUTOCOMPLETE_MODELS
            model = AUTOCOMPLETE_MODELS[tier]
            assert model is not None
    
    def test_autocomplete_models_have_correct_role(self):
        """Test autocomplete models have autocomplete role."""
        for tier, model in AUTOCOMPLETE_MODELS.items():
            assert model.role == ModelRole.AUTOCOMPLETE
            assert "autocomplete" in model.roles


class TestPrimaryModels:
    """Tests for PRIMARY_MODELS dictionary."""
    
    def test_all_tiers_have_models(self):
        """Test all hardware tiers have primary models."""
        for tier in [HardwareTier.C, HardwareTier.B, HardwareTier.A, HardwareTier.S]:
            assert tier in PRIMARY_MODELS
            assert len(PRIMARY_MODELS[tier]) > 0
    
    def test_primary_models_have_chat_role(self):
        """Test primary models have chat role."""
        for tier, models in PRIMARY_MODELS.items():
            for model in models:
                assert model.role == ModelRole.CHAT
                assert "chat" in model.roles


class TestGenerateBestRecommendation:
    """Tests for generate_best_recommendation function."""
    
    def test_returns_recommendation(self):
        """Test function returns ModelRecommendation."""
        hw_info = create_hw_info(24, HardwareTier.B)
        
        rec = generate_best_recommendation(hw_info)
        
        assert isinstance(rec, ModelRecommendation)
    
    def test_includes_primary_model(self):
        """Test recommendation includes primary model."""
        hw_info = create_hw_info(32, HardwareTier.A)
        
        rec = generate_best_recommendation(hw_info)
        
        assert rec.primary is not None
        assert rec.primary.role == ModelRole.CHAT
    
    def test_includes_embed_model(self):
        """Test recommendation includes embedding model."""
        hw_info = create_hw_info(32, HardwareTier.A)
        
        rec = generate_best_recommendation(hw_info)
        
        assert rec.embeddings is not None
        assert rec.embeddings.role == ModelRole.EMBED
    
    def test_fits_within_ram_budget(self):
        """Test total RAM fits within budget."""
        hw_info = create_hw_info(16, HardwareTier.C)
        
        rec = generate_best_recommendation(hw_info)
        usable = get_usable_ram(hw_info)
        
        # Total should fit within usable RAM
        assert rec.total_ram() <= usable


class TestGenerateMultiModelRecommendation:
    """Tests for generate_multi_model_recommendation function."""
    
    def test_returns_recommendation_or_none(self, backend_type):
        """Test returns ModelRecommendation or None."""
        if generate_multi_model_recommendation is None:
            pytest.skip("generate_multi_model_recommendation not available in Docker backend")
        hw_info = create_hw_info(24, HardwareTier.B)
        
        result = generate_multi_model_recommendation(hw_info)
        
        assert result is None or isinstance(result, ModelRecommendation)


class TestGenerateConservativeRecommendation:
    """Tests for generate_conservative_recommendation function."""
    
    def test_returns_recommendation(self):
        """Test always returns a recommendation."""
        hw_info = create_hw_info(16, HardwareTier.C)
        
        rec = generate_conservative_recommendation(hw_info)
        
        assert isinstance(rec, ModelRecommendation)
        assert rec.primary is not None
    
    def test_conservative_fits_limited_ram(self):
        """Test conservative recommendation fits in limited RAM."""
        hw_info = create_hw_info(16, HardwareTier.C)
        
        rec = generate_conservative_recommendation(hw_info)
        usable = get_usable_ram(hw_info)
        
        # Should fit comfortably
        assert rec.total_ram() <= usable


class TestGetAlternativesForRole:
    """Tests for get_alternatives_for_role function."""
    
    def test_returns_list(self):
        """Test returns list of alternatives."""
        hw_info = create_hw_info(32, HardwareTier.A)
        
        current = RecommendedModel("Current", "current:v", 5.0, ModelRole.CHAT, ["chat"])
        
        alternatives = get_alternatives_for_role(current, hw_info)
        
        assert isinstance(alternatives, list)
    
    def test_excludes_current_model(self):
        """Test current model is not in alternatives."""
        hw_info = create_hw_info(24, HardwareTier.B)
        
        current = PRIMARY_MODELS[HardwareTier.B][0]
        
        alternatives = get_alternatives_for_role(current, hw_info)
        
        # Current model should not be in alternatives
        for alt in alternatives:
            assert alt.ollama_name != current.ollama_name
    
    def test_alternatives_fit_ram(self):
        """Test alternatives fit within RAM budget."""
        hw_info = create_hw_info(16, HardwareTier.C)
        
        current = PRIMARY_MODELS[HardwareTier.C][0]
        usable = get_usable_ram(hw_info)
        
        alternatives = get_alternatives_for_role(current, hw_info)
        
        # All alternatives should fit
        for alt in alternatives:
            assert alt.ram_gb <= usable


class TestModelRamSanity:
    """Sanity tests for model RAM values across all catalogs."""
    
    def test_embed_model_smallest(self):
        """Test embedding model is smallest."""
        # Embedding should be much smaller than chat models
        for tier, models in PRIMARY_MODELS.items():
            for model in models:
                assert EMBED_MODEL.ram_gb < model.ram_gb
    
    def test_autocomplete_smaller_than_primary(self):
        """Test autocomplete models are generally smaller than primary."""
        for tier in [HardwareTier.C, HardwareTier.B]:
            auto = AUTOCOMPLETE_MODELS[tier]  # Single model, not list
            primary = PRIMARY_MODELS[tier][0]
            # Autocomplete should be smaller or equal
            assert auto.ram_gb <= primary.ram_gb + 1.0
    
    def test_higher_tiers_have_larger_models(self):
        """Test higher tiers have access to larger models."""
        tier_c_max = max(m.ram_gb for m in PRIMARY_MODELS[HardwareTier.C])
        tier_s_max = max(m.ram_gb for m in PRIMARY_MODELS[HardwareTier.S])
        
        assert tier_s_max >= tier_c_max
