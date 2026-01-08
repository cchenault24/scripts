# Model Recommendations Based on Continue.dev

This document outlines the model recommendations integrated from [Continue.dev's official model recommendations](https://docs.continue.dev/customize/models#recommended-models).

## Overview

Models are categorized by their role in the AI coding workflow:
- **Agent Plan / Chat / Edit**: Models for complex coding tasks, refactoring, and agent planning
- **Autocomplete**: Fast, lightweight models for real-time code suggestions
- **Embed**: Models for code indexing and semantic search
- **Rerank**: Models for improving search relevance
- **Next Edit**: Models specialized for predicting the next edit

## Best Models by Role

### Agent Plan / Chat / Edit

These models excel at complex coding tasks, refactoring, and agent planning:

| Model | RAM | Tier | Notes |
|-------|-----|------|-------|
| **devstral:27b** | ~14GB | A/S | Excellent for agent planning and reasoning |
| **gpt-oss:20b** | ~10GB | A/S | Strong coding capabilities |
| **codestral** | ~5GB | All | Excellent code generation, great for autocomplete |
| **llama3.1:70b** | ~35GB | S | Highest quality for complex refactoring |

**Recommendation**: 
- **Tier S**: Use `devstral:27b` for primary, `codestral` for secondary/autocomplete
- **Tier A**: Use `devstral:27b` or `gpt-oss:20b` for primary, `codestral` for secondary/autocomplete
- **Tier B**: Use `codestral` for primary, `llama3.1:8b` for secondary
- **Tier C**: Use `codestral` or `gemma2:9b` for primary, `llama3.1:8b` for secondary

### Autocomplete

Fast, lightweight models optimized for real-time code suggestions:

| Model | RAM | Tier | Notes |
|-------|-----|------|-------|
| **codestral** | ~5GB | All | Excellent for autocomplete (recommended by Continue.dev) |
| **gemma2:9b** | ~5.5GB | All | Fast, efficient model for autocomplete |
| **llama3.1:8b** | ~4.2GB | All | General-purpose fast model |

**Recommendation**: Use `codestral` for best autocomplete quality, or `gemma2:9b`/`llama3.1:8b` for faster suggestions.

### Embed (Code Indexing)

Models for semantic code search and indexing:

| Model | RAM | Tier | Notes |
|-------|-----|------|-------|
| **nomic-embed-text** | ~0.3GB | All | Best open embedding model |

**Recommendation**: `nomic-embed-text` is automatically installed and used for Continue.dev code indexing.

### Rerank (Search Relevance)

Models for improving search result relevance:

| Model | RAM | Tier | Notes |
|-------|-----|------|-------|
| **zerank-1** | ~0.4GB | All | Best open reranker |
| **zerank-1-small** | ~0.2GB | All | Smaller, faster reranker |

**Recommendation**: Use `zerank-1` for best quality, or `zerank-1-small` for faster processing.

### Next Edit

Models specialized for predicting the next edit:

| Model | RAM | Tier | Notes |
|-------|-----|------|-------|
| **instinct** | ~8GB | A/B/S | Best open model for next edit |

**Recommendation**: Use `instinct` for next edit predictions when available.

## Hardware Tier Recommendations

### Tier S (≥49GB RAM)
- **Primary**: `devstral:27b`
- **Secondary**: `codestral` (excellent for autocomplete)
- **Autocomplete**: `codestral` (recommended by Continue.dev)
- **All embedding/rerank models available**

### Tier A (33-48GB RAM)
- **Primary**: `devstral:27b` or `gpt-oss:20b`
- **Secondary**: `codestral` (excellent for autocomplete)
- **Autocomplete**: `codestral` (recommended by Continue.dev)
- **All embedding/rerank models available**

### Tier B (17-32GB RAM)
- **Primary**: `codestral`
- **Secondary**: `llama3.1:8b`
- **Autocomplete**: `codestral` or `llama3.1:8b`
- **All embedding/rerank models available**

### Tier C (<17GB RAM)
- **Primary**: `codestral` or `gemma2:9b`
- **Secondary**: `llama3.1:8b`
- **Autocomplete**: `codestral`, `gemma2:9b`, or `llama3.1:8b`
- **All embedding/rerank models available**

## Model Selection in Setup

The setup script automatically:
1. Detects your hardware tier
2. Recommends optimal models based on Continue.dev's recommendations
3. Filters models by hardware eligibility
4. Installs selected models with optimal quantization

## References

- [Continue.dev Model Recommendations](https://docs.continue.dev/customize/models#recommended-models)
- [Continue.dev Model Roles](https://docs.continue.dev/customize/models#model-roles)
- [Ollama Model Library](https://ollama.com/library)

## Notes

- All RAM estimates are for quantized models (Q4_K_M/Q5_K_M) optimized for Apple Silicon
- Models are automatically quantized by Ollama during download
- Embedding and rerank models are small and available for all tiers
- The setup script automatically installs `nomic-embed-text` for code indexing
