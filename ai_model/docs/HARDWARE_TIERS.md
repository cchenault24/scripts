# Hardware Tiers and Model Selection

The setup automatically detects your hardware and classifies it into tiers:

## Hardware Tiers

### Tier S (≥49GB RAM)
- **All models available**
- **Recommended**: llama3.3:70b or llama3.1:70b + codestral:22b
- Keep-alive (24h) - models unload after 24 hours of inactivity
- High context window (32K tokens)
- Best for: Complex refactoring, architecture work, multi-model workflows, agent planning

### Tier A (33-48GB RAM)
- **Excludes**: llama3.1:70b, llama3.3:70b
- **Recommended**: codestral:22b + phi4:14b or granite-code:20b
- Keep-alive (12h) - models unload after 12 hours of inactivity
- Medium context window (16K tokens)
- Best for: General development, code review, complex coding tasks, agent planning

### Tier B (17-32GB RAM)
- **Excludes**: llama3.1:70b, llama3.3:70b, codestral:22b
- **Recommended**: granite-code:20b or starcoder2:15b + llama3.1:8b
- Conservative keep-alive (5m)
- Smaller context window (8K tokens)
- Best for: Lightweight development, autocomplete

### Tier C (<17GB RAM)
- **Only**: Models 8B and below (llama3.1:8b, codegemma:7b, starcoder2:7b, granite-code:8b, starcoder2:3b, llama3.2:3b)
- **Recommended**: llama3.1:8b or starcoder2:3b
- Minimal keep-alive (5m)
- Small context window (4K tokens)
- Best for: Simple edits, fast autocomplete

## Model Quantization

All models are automatically optimized by Ollama with optimal quantization (Q4_K_M/Q5_K_M) for Apple Silicon when downloaded. Ollama selects the best quantization automatically, reducing RAM usage by 15-25% while maintaining quality.

**Model Selection**: Models are selected based on [Continue.dev's recommended models](https://docs.continue.dev/customize/models#recommended-models) for each role (Agent Plan, Chat, Edit, Autocomplete, Embed, Rerank, Next Edit). This ensures you're using the best-performing open models for each specific task type.

## Model Categories

### Agent Plan / Chat / Edit Models (Best for coding tasks)

1. **llama3.3:70b** (Tier S only - Highest quality)
   - Similar to Llama 3.1 405B, highest quality for complex refactoring
   - ~35GB RAM (Q4_K_M quantized)
   - Best for multi-file refactoring and deep analysis

2. **llama3.1:70b** (Tier S only - Highest quality)
   - Highest quality for complex refactoring and architecture
   - ~35GB RAM (Q4_K_M quantized)
   - Best for multi-file refactoring and deep analysis

3. **codestral:22b** (Tier A/S - Excellent code generation)
   - Excellent code generation and reasoning
   - ~11GB RAM (Q4_K_M quantized)
   - Strong coding capabilities with good balance

4. **granite-code:20b** (Tier A/B/S - IBM Granite code model)
   - IBM Granite code model with strong coding capabilities
   - ~10GB RAM (Q4_K_M quantized)
   - Good alternative for coding tasks

5. **starcoder2:15b** (Tier A/B/S - StarCoder2 code model)
   - StarCoder2 code model with good performance
   - ~7.5GB RAM (Q4_K_M quantized)
   - Solid coding capabilities

6. **phi4:14b** (Tier A/B/S - State-of-the-art open model)
   - State-of-the-art open model with excellent reasoning
   - ~7GB RAM (Q4_K_M quantized)
   - Strong for agent planning and reasoning tasks

7. **llama3.1:8b** (All tiers - Fast general-purpose)
   - Fast, general-purpose coding assistant
   - ~4.2GB RAM (Q5_K_M quantized)
   - Good TypeScript support
   - Best for autocomplete and quick edits

8. **codegemma:7b** (All tiers - CodeGemma code model)
   - CodeGemma code model for fast coding tasks
   - ~3.5GB RAM (Q4_K_M quantized)
   - Good for autocomplete and quick edits

### Autocomplete Models (Fast, lightweight)

1. **codestral:22b** (Tier A/S - Designed for code generation)
   - Excellent code generation and autocomplete capabilities
   - ~11GB RAM (Q4_K_M quantized)
   - Best for autocomplete, complex coding tasks, and code review
   - Recommended by Continue.dev for autocomplete role

2. **starcoder2:7b** (All tiers - StarCoder2 for autocomplete)
   - StarCoder2 optimized for autocomplete
   - ~3.5GB RAM (Q4_K_M quantized)
   - Fast autocomplete suggestions

3. **codegemma:7b** (All tiers - CodeGemma for autocomplete)
   - CodeGemma optimized for autocomplete
   - ~3.5GB RAM (Q4_K_M quantized)
   - Fast code suggestions

4. **granite-code:8b** (All tiers - IBM Granite code model)
   - IBM Granite code model for autocomplete
   - ~4GB RAM (Q4_K_M quantized)
   - Good autocomplete performance

5. **llama3.1:8b** (All tiers - Fast general-purpose)
   - Fast, general-purpose coding assistant
   - ~4.2GB RAM (Q5_K_M quantized)
   - Good TypeScript support
   - Best for autocomplete and quick edits

6. **starcoder2:3b** (All tiers - Small StarCoder2)
   - Small StarCoder2 for very fast autocomplete
   - ~1.5GB RAM (Q4_K_M quantized)
   - Fastest autocomplete option

7. **llama3.2:3b** (All tiers - Small and fast)
   - Small and fast for autocomplete
   - ~1.5GB RAM (Q4_K_M quantized)
   - Very fast suggestions

8. **phi4:14b** (Tier A/B/S - State-of-the-art open model)
   - State-of-the-art open model
   - ~7GB RAM (Q4_K_M quantized)
   - Good for autocomplete with higher quality

### Embedding Models (For code indexing)

1. **nomic-embed-text** (Best open embedding)
   - Best open embedding model for code indexing
   - ~0.3GB RAM
   - Large token context window
   - Automatically installed for Continue.dev code indexing

2. **mxbai-embed-large** (State-of-the-art large embedding)
   - State-of-the-art large embedding from mixedbread.ai
   - ~0.2GB RAM
   - Excellent for code indexing

3. **snowflake-arctic-embed2** (Frontier embedding)
   - Frontier embedding with multilingual support
   - ~0.3GB RAM
   - Strong multilingual capabilities

4. **granite-embedding** (IBM Granite, multilingual)
   - IBM Granite embedding with multilingual support
   - ~0.17GB RAM
   - Good multilingual performance

5. **all-minilm** (Very small, sentence-level)
   - Very small embedding model
   - ~0.02GB RAM
   - Fast but limited context

### Rerank Models (For search relevance)

Currently, no rerank models are included in the approved list. Rerank functionality can be added in the future as new open rerank models become available.

### Next Edit Models (For predicting the next edit)

1. **llama3.3:70b** (Tier S only - Similar to Llama 3.1 405B)
   - Best for next edit predictions on Tier S systems
   - ~35GB RAM (Q4_K_M quantized)

2. **granite-code:20b** (Tier A/B/S - IBM Granite code model)
   - IBM Granite code model for next edit
   - ~10GB RAM (Q4_K_M quantized)

3. **starcoder2:15b** (Tier A/B/S - StarCoder2 code model)
   - StarCoder2 code model for next edit
   - ~7.5GB RAM (Q4_K_M quantized)

4. **phi4:14b** (Tier A/B/S - State-of-the-art open model)
   - State-of-the-art open model for next edit
   - ~7GB RAM (Q4_K_M quantized)

5. **codestral:22b** (Tier A/S - Code generation)
   - Excellent for next edit predictions
   - ~11GB RAM (Q4_K_M quantized)

6. **llama3.1:8b** (All tiers - Fast general-purpose)
   - Fast general-purpose for next edit
   - ~4.2GB RAM (Q5_K_M quantized)

7. **codegemma:7b** (All tiers - CodeGemma code model)
   - CodeGemma code model for next edit
   - ~3.5GB RAM (Q4_K_M quantized)

8. **starcoder2:7b** (All tiers - StarCoder2 code model)
   - StarCoder2 code model for next edit
   - ~3.5GB RAM (Q4_K_M quantized)

## Model Roles

Models are automatically assigned to roles based on their capabilities. A single model can serve multiple roles (e.g., `llama3.1:8b` can be used for both Agent Plan/Chat/Edit and Autocomplete), which saves RAM and improves efficiency.

See also: [MODEL_RECOMMENDATIONS.md](MODEL_RECOMMENDATIONS.md)
