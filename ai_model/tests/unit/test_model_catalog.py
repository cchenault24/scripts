"""
Comprehensive unit tests for lib/model_catalog.py

Tests the unified backend abstraction for model selection.
"""

from pathlib import Path
from unittest.mock import MagicMock
import pytest

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from lib import model_catalog, hardware


class TestBackendEnum:
    """Test Backend enum."""

    def test_backend_values(self):
        """Test backend enum values."""
        assert model_catalog.Backend.OLLAMA.value == "ollama"
        assert model_catalog.Backend.LLAMACPP.value == "llamacpp"

    def test_backend_comparison(self):
        """Test backend enum comparison."""
        assert model_catalog.Backend.OLLAMA == model_catalog.Backend.OLLAMA
        assert model_catalog.Backend.OLLAMA != model_catalog.Backend.LLAMACPP


class TestModelSize:
    """Test ModelSize enum."""

    def test_model_sizes(self):
        """Test model size categories."""
        assert model_catalog.ModelSize.SMALL.value == "2b"
        assert model_catalog.ModelSize.MEDIUM.value == "4b"
        assert model_catalog.ModelSize.LARGE.value == "26b"
        assert model_catalog.ModelSize.XLARGE.value == "31b"


class TestContextOption:
    """Test ContextOption dataclass."""

    def test_context_option_creation(self):
        """Test creating context options."""
        ctx = model_catalog.ContextOption(
            size=32768,
            description="32K context (~17GB RAM)",
            ram_gb=17.0
        )

        assert ctx.size == 32768
        assert "32K" in ctx.description
        assert ctx.ram_gb == 17.0


class TestLlamaCppModel:
    """Test LlamaCppModel implementation."""

    def test_model_creation(self):
        """Test creating llama.cpp model."""
        model = model_catalog.LlamaCppModel(
            name="Test Model",
            size=model_catalog.ModelSize.LARGE,
            hf_repo="org/repo:file.gguf",
            ram_gb=16.0,
            min_ram=16,
            max_ram=32,
            description="Test description"
        )

        assert model.name == "Test Model"
        assert model.size == model_catalog.ModelSize.LARGE
        assert model.hf_repo == "org/repo:file.gguf"
        assert model.ram_gb == 16.0

    def test_get_identifier(self):
        """Test get_identifier returns HF repo."""
        model = model_catalog.LlamaCppModel(
            name="Test",
            size=model_catalog.ModelSize.LARGE,
            hf_repo="org/repo:file.gguf",
            ram_gb=16.0,
            min_ram=16,
            max_ram=32,
            description="Test"
        )

        assert model.get_identifier() == "org/repo:file.gguf"

    def test_get_backend(self):
        """Test get_backend returns LLAMACPP."""
        model = model_catalog.LlamaCppModel(
            name="Test",
            size=model_catalog.ModelSize.LARGE,
            hf_repo="org/repo:file.gguf",
            ram_gb=16.0,
            min_ram=16,
            max_ram=32,
            description="Test"
        )

        assert model.get_backend() == model_catalog.Backend.LLAMACPP

    def test_get_repo_and_file(self):
        """Test splitting HF repo into repo_id and filename."""
        model = model_catalog.LlamaCppModel(
            name="Test",
            size=model_catalog.ModelSize.LARGE,
            hf_repo="ggml-org/gemma-4-26B-it-GGUF:Q4_K_M",
            ram_gb=16.0,
            min_ram=16,
            max_ram=32,
            description="Test"
        )

        repo_id, filename = model.get_repo_and_file()

        assert repo_id == "ggml-org/gemma-4-26B-it-GGUF"
        assert filename == "Q4_K_M.gguf"

    def test_get_repo_and_file_with_extension(self):
        """Test repo/file split when filename already has .gguf."""
        model = model_catalog.LlamaCppModel(
            name="Test",
            size=model_catalog.ModelSize.LARGE,
            hf_repo="org/repo:model.gguf",
            ram_gb=16.0,
            min_ram=16,
            max_ram=32,
            description="Test"
        )

        repo_id, filename = model.get_repo_and_file()

        assert repo_id == "org/repo"
        assert filename == "model.gguf"

    def test_get_repo_and_file_invalid_format(self):
        """Test error on invalid repo format."""
        model = model_catalog.LlamaCppModel(
            name="Test",
            size=model_catalog.ModelSize.LARGE,
            hf_repo="invalid-format",  # No colon separator
            ram_gb=16.0,
            min_ram=16,
            max_ram=32,
            description="Test"
        )

        with pytest.raises(ValueError, match="Invalid hf_repo format"):
            model.get_repo_and_file()

    def test_supports_ram(self):
        """Test RAM support checking."""
        model = model_catalog.LlamaCppModel(
            name="Test",
            size=model_catalog.ModelSize.LARGE,
            hf_repo="org/repo:file",
            ram_gb=16.0,
            min_ram=16,
            max_ram=32,
            description="Test"
        )

        assert model.supports_ram(16.0) is True
        assert model.supports_ram(24.0) is True
        assert model.supports_ram(32.0) is True
        assert model.supports_ram(15.0) is False
        assert model.supports_ram(33.0) is False

    def test_get_default_context(self):
        """Test default context retrieval."""
        # Model with contexts defined
        model = model_catalog.LlamaCppModel(
            name="Test",
            size=model_catalog.ModelSize.LARGE,
            hf_repo="org/repo:file",
            ram_gb=16.0,
            min_ram=16,
            max_ram=32,
            description="Test",
            contexts=[
                model_catalog.ContextOption(32768, "32K", 17.0),
                model_catalog.ContextOption(65536, "64K", 20.0),
            ]
        )

        ctx = model.get_default_context()
        assert ctx.size == 32768

        # Model without contexts
        model_no_ctx = model_catalog.LlamaCppModel(
            name="Test",
            size=model_catalog.ModelSize.LARGE,
            hf_repo="org/repo:file",
            ram_gb=16.0,
            min_ram=16,
            max_ram=32,
            description="Test"
        )

        ctx = model_no_ctx.get_default_context()
        assert ctx.size == 32768  # Fallback


class TestOllamaModel:
    """Test OllamaModel implementation."""

    def test_model_creation(self):
        """Test creating Ollama model."""
        model = model_catalog.OllamaModel(
            name="Test Model",
            size=model_catalog.ModelSize.LARGE,
            ollama_name="gemma4:26b",
            ram_gb=16.0,
            min_ram=16,
            max_ram=32,
            description="Test description"
        )

        assert model.name == "Test Model"
        assert model.ollama_name == "gemma4:26b"

    def test_get_identifier(self):
        """Test get_identifier returns Ollama name."""
        model = model_catalog.OllamaModel(
            name="Test",
            size=model_catalog.ModelSize.LARGE,
            ollama_name="gemma4:26b",
            ram_gb=16.0,
            min_ram=16,
            max_ram=32,
            description="Test"
        )

        assert model.get_identifier() == "gemma4:26b"

    def test_get_backend(self):
        """Test get_backend returns OLLAMA."""
        model = model_catalog.OllamaModel(
            name="Test",
            size=model_catalog.ModelSize.LARGE,
            ollama_name="gemma4:26b",
            ram_gb=16.0,
            min_ram=16,
            max_ram=32,
            description="Test"
        )

        assert model.get_backend() == model_catalog.Backend.OLLAMA


class TestModelCatalog:
    """Test model catalog functions."""

    def test_get_llamacpp_catalog(self):
        """Test getting llama.cpp model catalog."""
        catalog = model_catalog.get_model_catalog(model_catalog.Backend.LLAMACPP)

        assert isinstance(catalog, dict)
        assert len(catalog) > 0
        assert "2b" in catalog
        assert "4b" in catalog
        assert "26b" in catalog
        assert "31b" in catalog

        # Verify all are LlamaCppModel instances
        for key, model in catalog.items():
            assert isinstance(model, model_catalog.LlamaCppModel)
            assert model.get_backend() == model_catalog.Backend.LLAMACPP

    def test_get_ollama_catalog(self):
        """Test getting Ollama model catalog."""
        catalog = model_catalog.get_model_catalog(model_catalog.Backend.OLLAMA)

        assert isinstance(catalog, dict)
        assert len(catalog) > 0
        assert "2b" in catalog
        assert "4b" in catalog
        assert "26b" in catalog or "26b-optimized" in catalog
        assert "31b" in catalog

        # Verify all are OllamaModel instances
        for key, model in catalog.items():
            assert isinstance(model, model_catalog.OllamaModel)
            assert model.get_backend() == model_catalog.Backend.OLLAMA

    def test_get_catalog_invalid_backend(self):
        """Test error on invalid backend."""
        class FakeBackend:
            value = "fake"

        with pytest.raises(ValueError, match="Unknown backend"):
            model_catalog.get_model_catalog(FakeBackend())

    def test_llamacpp_models_have_hf_repo(self):
        """Test all llama.cpp models have HF repo."""
        catalog = model_catalog.get_model_catalog(model_catalog.Backend.LLAMACPP)

        for key, model in catalog.items():
            assert model.hf_repo, f"Model {key} missing hf_repo"
            assert ":" in model.hf_repo, f"Model {key} has invalid hf_repo format"

    def test_ollama_models_have_ollama_name(self):
        """Test all Ollama models have Ollama name."""
        catalog = model_catalog.get_model_catalog(model_catalog.Backend.OLLAMA)

        for key, model in catalog.items():
            assert model.ollama_name, f"Model {key} missing ollama_name"


class TestRecommendedModel:
    """Test recommended model selection."""

    def test_recommended_model_low_ram(self):
        """Test recommendation for low RAM system (8GB)."""
        hw_info = MagicMock()
        hw_info.ram_gb = 8.0

        recommended = model_catalog.get_recommended_model(
            model_catalog.Backend.LLAMACPP,
            hw_info
        )

        assert recommended is not None
        assert recommended.supports_ram(8.0)
        # Should recommend 2b or 4b for 8GB
        assert recommended.size in [model_catalog.ModelSize.SMALL, model_catalog.ModelSize.MEDIUM]

    def test_recommended_model_medium_ram(self):
        """Test recommendation for medium RAM system (16GB)."""
        hw_info = MagicMock()
        hw_info.ram_gb = 16.0

        recommended = model_catalog.get_recommended_model(
            model_catalog.Backend.LLAMACPP,
            hw_info
        )

        assert recommended is not None
        assert recommended.supports_ram(16.0)

    def test_recommended_model_high_ram(self):
        """Test recommendation for high RAM system (48GB)."""
        hw_info = MagicMock()
        hw_info.ram_gb = 48.0

        recommended = model_catalog.get_recommended_model(
            model_catalog.Backend.LLAMACPP,
            hw_info
        )

        assert recommended is not None
        assert recommended.supports_ram(48.0)
        # Should recommend 31b for 48GB
        assert recommended.size == model_catalog.ModelSize.XLARGE

    def test_recommended_model_insufficient_ram(self):
        """Test recommendation when RAM is too low."""
        hw_info = MagicMock()
        hw_info.ram_gb = 2.0

        recommended = model_catalog.get_recommended_model(
            model_catalog.Backend.LLAMACPP,
            hw_info
        )

        # Should return None or smallest model
        if recommended:
            assert recommended.min_ram <= 4  # Smallest model requirement

    def test_recommended_model_prefers_marked_recommended(self):
        """Test that marked recommended models are preferred."""
        hw_info = MagicMock()
        hw_info.ram_gb = 24.0

        # Get catalog and check for recommended flag
        catalog = model_catalog.get_model_catalog(model_catalog.Backend.LLAMACPP)

        # Find models with recommended flag
        recommended_models = [m for m in catalog.values() if m.recommended and m.supports_ram(24.0)]

        if recommended_models:
            # If there are recommended models, get_recommended_model should return one
            result = model_catalog.get_recommended_model(
                model_catalog.Backend.LLAMACPP,
                hw_info
            )

            assert result is not None
            # Should match one of the recommended models
            assert result in recommended_models


class TestFilterModelsByRAM:
    """Test RAM-based model filtering."""

    def test_filter_models_8gb(self):
        """Test filtering for 8GB RAM."""
        catalog = model_catalog.get_model_catalog(model_catalog.Backend.LLAMACPP)
        filtered = model_catalog.filter_models_by_ram(catalog, 8.0)

        # Should include 2b and 4b, exclude 26b and 31b
        assert "2b" in filtered
        assert "4b" in filtered

        # Verify all returned models support 8GB
        for model in filtered.values():
            assert model.supports_ram(8.0)

    def test_filter_models_16gb(self):
        """Test filtering for 16GB RAM."""
        catalog = model_catalog.get_model_catalog(model_catalog.Backend.LLAMACPP)
        filtered = model_catalog.filter_models_by_ram(catalog, 16.0)

        # Should include 2b, 4b, and 26b
        assert "2b" in filtered
        assert "4b" in filtered
        assert "26b" in filtered

        # Verify all returned models support 16GB
        for model in filtered.values():
            assert model.supports_ram(16.0)

    def test_filter_models_48gb(self):
        """Test filtering for 48GB RAM."""
        catalog = model_catalog.get_model_catalog(model_catalog.Backend.LLAMACPP)
        filtered = model_catalog.filter_models_by_ram(catalog, 48.0)

        # Should include 31b (but not others since 48GB exceeds their max_ram)
        assert "31b" in filtered

        # Verify all returned models support 48GB
        for model in filtered.values():
            assert model.supports_ram(48.0)

    def test_filter_models_insufficient_ram(self):
        """Test filtering with insufficient RAM."""
        catalog = model_catalog.get_model_catalog(model_catalog.Backend.LLAMACPP)
        filtered = model_catalog.filter_models_by_ram(catalog, 2.0)

        # Should return empty or very limited results
        assert len(filtered) < len(catalog)

    def test_filter_preserves_model_properties(self):
        """Test that filtering preserves all model properties."""
        catalog = model_catalog.get_model_catalog(model_catalog.Backend.LLAMACPP)
        filtered = model_catalog.filter_models_by_ram(catalog, 16.0)

        for key, model in filtered.items():
            # Verify model is complete
            assert model.name
            assert model.get_identifier()
            assert model.ram_gb > 0
            assert model.min_ram > 0
            assert model.max_ram >= model.min_ram
            assert model.description


class TestContextOptions:
    """Test context option handling in models."""

    def test_models_have_context_options(self):
        """Test that models have context options defined."""
        catalog = model_catalog.get_model_catalog(model_catalog.Backend.LLAMACPP)

        # Check 26b model has multiple context options
        model_26b = catalog.get("26b")
        assert model_26b is not None
        assert len(model_26b.contexts) > 0

        # Verify context options are valid
        for ctx in model_26b.contexts:
            assert ctx.size > 0
            assert ctx.description
            assert ctx.ram_gb >= model_26b.ram_gb

    def test_context_sizes_are_powers_of_two(self):
        """Test that context sizes are valid powers of two."""
        import math

        catalog = model_catalog.get_model_catalog(model_catalog.Backend.LLAMACPP)

        for model in catalog.values():
            for ctx in model.contexts:
                # Context size should be a power of 2
                log2 = math.log2(ctx.size)
                assert log2 == int(log2), f"Context size {ctx.size} is not a power of 2"

    def test_larger_contexts_need_more_ram(self):
        """Test that larger contexts require more RAM."""
        catalog = model_catalog.get_model_catalog(model_catalog.Backend.LLAMACPP)

        # Check 26b model context RAM progression
        model_26b = catalog.get("26b")
        if model_26b and len(model_26b.contexts) > 1:
            for i in range(len(model_26b.contexts) - 1):
                ctx_small = model_26b.contexts[i]
                ctx_large = model_26b.contexts[i + 1]

                # Larger context should need more RAM
                assert ctx_large.size > ctx_small.size
                assert ctx_large.ram_gb > ctx_small.ram_gb


class TestModelMetadata:
    """Test model metadata consistency."""

    def test_all_models_have_required_fields(self):
        """Test all models have complete metadata."""
        for backend in [model_catalog.Backend.LLAMACPP, model_catalog.Backend.OLLAMA]:
            catalog = model_catalog.get_model_catalog(backend)

            for key, model in catalog.items():
                assert model.name, f"{key}: missing name"
                assert model.size, f"{key}: missing size"
                assert model.description, f"{key}: missing description"
                assert model.ram_gb > 0, f"{key}: invalid ram_gb"
                assert model.min_ram > 0, f"{key}: invalid min_ram"
                assert model.max_ram >= model.min_ram, f"{key}: max_ram < min_ram"
                assert model.performance_tier, f"{key}: missing performance_tier"

    def test_performance_tiers_are_valid(self):
        """Test performance tiers are valid values."""
        valid_tiers = {"fast", "balanced", "quality"}

        for backend in [model_catalog.Backend.LLAMACPP, model_catalog.Backend.OLLAMA]:
            catalog = model_catalog.get_model_catalog(backend)

            for key, model in catalog.items():
                assert model.performance_tier in valid_tiers, \
                    f"{key}: invalid tier '{model.performance_tier}'"

    def test_model_sizes_match_names(self):
        """Test that model sizes match their category names."""
        size_map = {
            "2b": model_catalog.ModelSize.SMALL,
            "4b": model_catalog.ModelSize.MEDIUM,
            "26b": model_catalog.ModelSize.LARGE,
            "31b": model_catalog.ModelSize.XLARGE,
        }

        catalog = model_catalog.get_model_catalog(model_catalog.Backend.LLAMACPP)

        for key, model in catalog.items():
            if key in size_map:
                assert model.size == size_map[key], \
                    f"{key}: size mismatch (expected {size_map[key]}, got {model.size})"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
