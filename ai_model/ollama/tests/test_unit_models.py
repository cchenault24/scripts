"""
Unit tests for lib/models.py - Model catalog and legacy support.

Tests cover:
- ModelInfo dataclass
- MODEL_CATALOG validation
- get_models_for_tier function
- find_modelinfo_by_ollama_name function
"""

import pytest
from lib import hardware
from lib.models import ModelInfo, MODEL_CATALOG, get_models_for_tier, find_modelinfo_by_ollama_name


class TestModelInfo:
    """Tests for ModelInfo dataclass."""
    
    def test_model_info_creation(self):
        """Test creating a ModelInfo instance with all fields."""
        model = ModelInfo(
            name="Test Model",
            ollama_name="test:latest",
            description="A test model",
            ram_gb=5.0,
            context_length=32768,
            roles=["chat", "edit"],
            tiers=[hardware.HardwareTier.A, hardware.HardwareTier.B],
            recommended_for=["Testing"],
            base_model_name="test"
        )
        assert model.name == "Test Model"
        assert model.ollama_name == "test:latest"
        assert model.ram_gb == 5.0
        assert "chat" in model.roles
        assert hardware.HardwareTier.A in model.tiers
    
    def test_model_info_default_values(self):
        """Test ModelInfo with default field values."""
        model = ModelInfo(
            name="Minimal Model",
            ollama_name="minimal:latest",
            description="A minimal model",
            ram_gb=1.0,
            context_length=4096,
            roles=["chat"],
            tiers=[hardware.HardwareTier.C]
        )
        # Default values should be set
        assert model.recommended_for == []
        assert model.base_model_name is None
        assert model.selected_variant is None
    
    def test_model_info_with_selected_variant(self):
        """Test ModelInfo with a selected variant."""
        model = ModelInfo(
            name="Test Model",
            ollama_name="test:7b",
            description="Test model with variant",
            ram_gb=5.0,
            context_length=32768,
            roles=["chat"],
            tiers=[hardware.HardwareTier.B],
            selected_variant="7b-q4_k_m"
        )
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
            assert model.ollama_name, f"{model.name} missing ollama_name"
            assert model.description, f"{model.name} missing description"
            assert model.ram_gb > 0, f"{model.name} has invalid ram_gb"
            assert model.context_length > 0, f"{model.name} has invalid context_length"
            assert len(model.roles) > 0, f"{model.name} has no roles"
            assert len(model.tiers) > 0, f"{model.name} has no tiers"
    
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
    
    def test_all_tiers_have_models(self):
        """Verify each hardware tier has at least one model."""
        for tier in [hardware.HardwareTier.S, hardware.HardwareTier.A, 
                     hardware.HardwareTier.B, hardware.HardwareTier.C]:
            models = get_models_for_tier(tier)
            assert len(models) > 0, f"No models for {tier.name}"
    
    def test_ram_values_reasonable(self):
        """Verify RAM values are reasonable (0.1 - 100 GB)."""
        for model in MODEL_CATALOG:
            assert 0.1 <= model.ram_gb <= 100, f"{model.name} has unreasonable ram_gb: {model.ram_gb}"
    
    def test_context_length_reasonable(self):
        """Verify context lengths are reasonable."""
        for model in MODEL_CATALOG:
            assert 1024 <= model.context_length <= 1000000, \
                f"{model.name} has unreasonable context_length: {model.context_length}"


class TestGetModelsForTier:
    """Tests for get_models_for_tier function."""
    
    def test_tier_s_models(self):
        """Test getting models for Tier S."""
        models = get_models_for_tier(hardware.HardwareTier.S)
        assert isinstance(models, list)
        # Tier S should have access to all models
        assert len(models) >= 1
        for model in models:
            assert hardware.HardwareTier.S in model.tiers
    
    def test_tier_a_models(self):
        """Test getting models for Tier A."""
        models = get_models_for_tier(hardware.HardwareTier.A)
        assert isinstance(models, list)
        for model in models:
            assert hardware.HardwareTier.A in model.tiers
    
    def test_tier_b_models(self):
        """Test getting models for Tier B."""
        models = get_models_for_tier(hardware.HardwareTier.B)
        assert isinstance(models, list)
        for model in models:
            assert hardware.HardwareTier.B in model.tiers
    
    def test_tier_c_models(self):
        """Test getting models for Tier C - should have smaller models."""
        models = get_models_for_tier(hardware.HardwareTier.C)
        assert isinstance(models, list)
        for model in models:
            assert hardware.HardwareTier.C in model.tiers
            # Tier C models should have reasonable RAM requirements
            assert model.ram_gb <= 10, f"Tier C model {model.name} uses too much RAM"
    
    def test_tier_d_no_models(self):
        """Test Tier D (unsupported) returns no models."""
        models = get_models_for_tier(hardware.HardwareTier.D)
        # Tier D is unsupported, no models should be available
        assert len(models) == 0


class TestFindModelInfoByOllamaName:
    """Tests for find_modelinfo_by_ollama_name function."""
    
    def test_find_exact_match(self):
        """Test finding model by exact ollama_name."""
        # Use a known model from the catalog
        model = find_modelinfo_by_ollama_name("nomic-embed-text:latest")
        assert model is not None
        assert model.name == "Nomic Embed Text"
    
    def test_find_base_name_match(self):
        """Test finding model by base name (without tag)."""
        model = find_modelinfo_by_ollama_name("granite-code:some-variant")
        # Should match based on base name
        assert model is not None
        assert "granite-code" in model.ollama_name
    
    def test_not_found_returns_none(self):
        """Test that non-existent model returns None."""
        model = find_modelinfo_by_ollama_name("completely-fake-model:v99")
        assert model is None
    
    def test_find_with_different_tag(self):
        """Test finding model when searching with different tag."""
        # Search with a different tag than what's in catalog
        model = find_modelinfo_by_ollama_name("qwen2.5-coder:custom-tag")
        assert model is not None
        assert "qwen2.5-coder" in model.ollama_name


class TestModelCompatibility:
    """Tests for model compatibility across system."""
    
    def test_model_roles_are_valid(self):
        """Verify all model roles are valid Continue.dev roles."""
        valid_roles = {"chat", "edit", "autocomplete", "embed", "apply", "rerank", "summarize"}
        for model in MODEL_CATALOG:
            for role in model.roles:
                assert role in valid_roles, f"{model.name} has invalid role: {role}"
    
    def test_model_tiers_are_valid(self):
        """Verify all model tiers are valid HardwareTier values."""
        valid_tiers = {hardware.HardwareTier.S, hardware.HardwareTier.A, 
                       hardware.HardwareTier.B, hardware.HardwareTier.C, 
                       hardware.HardwareTier.D}
        for model in MODEL_CATALOG:
            for tier in model.tiers:
                assert tier in valid_tiers, f"{model.name} has invalid tier: {tier}"
