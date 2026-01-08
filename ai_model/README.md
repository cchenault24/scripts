# VS Code + Continue.dev Local LLM Setup

Production-grade local AI coding environment optimized for VS Code with Continue.dev integration. Fully local inference, no cloud APIs, enterprise-safe.

## Overview

This setup provides a seamless "zero to productive" local AI coding experience in VS Code where the assistant can:
- Understand entire repositories (multi-file context)
- Perform semantic code search
- Refactor across files with accurate diffs
- Follow best practices for React + TypeScript + Redux-Saga + MUI + AG Grid + OpenLayers stack

### Key Features

- **Hardware-Aware Auto-Tuning**: Automatically configures models based on your system's RAM tier
- **Approved Models Only**: Curated list of trusted open-weight models (no DeepSeek)
- **Continue.dev Integration**: Auto-generated profiles for coding, review, documentation, and deep analysis
- **VS Code Optimized**: Settings, extensions, and prompts tailored for your stack
- **Production-Grade**: Idempotent, resumable, with comprehensive error handling
- **Fully Local**: No cloud APIs, no telemetry, works offline after setup

## Prerequisites

- **macOS Apple Silicon** (M1/M2/M3/M4)
- **Homebrew** ([install](https://brew.sh))
- **Xcode Command Line Tools** (`xcode-select --install`)
- **VS Code** (optional but recommended)
- **Internet connection** (only for initial setup and model downloads)

## Quick Start

1. **Run the setup script:**
   ```bash
   cd ai_model
   chmod +x setup-local-llm.sh
   ./setup-local-llm.sh
   ```

2. **Follow the interactive prompts:**
   - Hardware will be auto-detected
   - Select models from the approved list
   - Models will be auto-tuned for your hardware tier
   - Continue.dev config will be generated automatically

3. **Install Continue.dev in VS Code:**
   - Open VS Code
   - Install the [Continue.dev extension](https://marketplace.visualstudio.com/items?itemName=Continue.continue)
   - Restart VS Code
   - Continue.dev will automatically use the generated config at `~/.continue/config.json`

4. **Start coding with AI:**
   - Use `Cmd+L` to open Continue.dev chat
   - Use `Cmd+K` for inline edits
   - Try the starter prompts from `prompts/starter-prompts.md`

## Hardware Tiers and Model Selection

The setup automatically detects your hardware and classifies it into tiers:

### Tier S (≥49GB RAM)
- **All models available**
- **Recommended**: qwen2.5-coder:14b + codestral:22b (or llama3.1:70b for maximum quality)
- Keep-alive (1h) - models unload after 1 hour of inactivity
- High context window (32K tokens)
- Best for: Complex refactoring, architecture work, multi-model workflows

### Tier A (33-48GB RAM)
- **Excludes**: llama3.1:70b
- **Recommended**: qwen2.5-coder:14b + codestral:22b
- Keep-alive (1h) - models unload after 1 hour of inactivity
- Medium context window (16K tokens)
- Best for: General development, code review, complex coding tasks

### Tier B (17-32GB RAM)
- **Excludes**: llama3.1:70b, codestral:22b
- Conservative keep-alive (5m)
- Smaller context window (8K tokens)
- Best for: Lightweight development, autocomplete

### Tier C (<17GB RAM)
- **Only**: qwen2.5-coder:7b, llama3.1:8b
- Minimal keep-alive (5m)
- Small context window (4K tokens)
- Best for: Simple edits, fast autocomplete

### Approved Models

All models are automatically optimized by Ollama with optimal quantization (Q4_K_M/Q5_K_M) for Apple Silicon when downloaded. Ollama selects the best quantization automatically, reducing RAM usage by 15-25% while maintaining quality.

1. **qwen2.5-coder:14b** (Recommended Primary)
   - Best balance of quality and speed for React/TypeScript development
   - ~7.5GB RAM (Q4_K_M quantized)
   - Excellent TypeScript, React, and Redux-Saga understanding
   - Optimized for coding tasks

2. **codestral:22b** (Recommended Secondary for Tier A/S)
   - Excellent code generation and explanation capabilities
   - ~11.5GB RAM (Q4_K_M quantized)
   - Best for complex coding tasks and code review
   - Superior to general-purpose models for development work

3. **llama3.1:8b** (Fast Alternative)
   - Fast, general-purpose coding assistant
   - ~4.2GB RAM (Q5_K_M quantized)
   - Good TypeScript support
   - Best for autocomplete and quick edits

4. **llama3.1:70b** (Tier S only)
   - Highest quality for complex refactoring and architecture
   - ~35GB RAM (Q4_K_M quantized)
   - Best for multi-file refactoring and deep analysis

5. **qwen2.5-coder:7b** (Lightweight)
   - Lightweight, fast autocomplete and simple edits
   - ~3.5GB RAM (Q5_K_M quantized)
   - Perfect for quick suggestions and small changes

## Continue.dev Setup and Usage

### Configuration

The setup script automatically generates a Continue.dev config at `~/.continue/config.json` with four profiles:

1. **Coding Assistant** (Primary)
   - Model: qwen2.5-coder:14b (or your selected primary)
   - Temperature: 0.7
   - Best for: General development, code generation

2. **Code Review**
   - Model: llama3.1:8b (or alternative)
   - Temperature: 0.3
   - Best for: Code review, correctness checks

3. **Documentation**
   - Model: llama3.1:8b
   - Temperature: 0.5
   - Best for: Generating documentation

4. **Deep Analysis**
   - Model: qwen2.5-coder:14b or llama3.1:70b
   - Temperature: 0.6
   - Best for: Complex refactoring, architecture

### Using Continue.dev

- **Chat**: `Cmd+L` - Ask questions, get explanations
- **Inline Edit**: `Cmd+K` - Select code and request changes
- **Tab Autocomplete**: Automatic suggestions as you type
- **Context**: Continue.dev automatically indexes your workspace

### Switching Profiles

In Continue.dev chat, you can switch between profiles:
- Use the profile selector in the chat interface
- Or mention the profile name in your prompt: "Using Code Review profile, review this code..."

## VS Code Integration

### Settings

The setup generates optimized VS Code settings at `vscode/settings.json`. To use:

1. Copy to your workspace:
   ```bash
   cp vscode/settings.json .vscode/settings.json
   ```

2. Or merge with existing settings manually

Key optimizations:
- TypeScript strict mode enforcement
- React/Redux navigation support
- Import organization
- Safer refactoring defaults
- MUI theme token awareness
- AG Grid type hints

### Extensions

Recommended extensions are listed in `vscode/extensions.json`. The setup script can optionally install them:

- **ESLint** - Code quality
- **Prettier** - Code formatting
- **TypeScript** - Enhanced TS support
- **React snippets** - Productivity
- **Path IntelliSense** - Import assistance
- **GitLens** - Git integration

To install manually:
```bash
code --install-extension <extension-id>
```

## Tool Usage

### Diagnose

Check the health of your setup:
```bash
./tools/diagnose.sh
```

Checks:
- Ollama daemon health
- Installed models
- Continue.dev config validity
- VS Code integration
- System resources
- Loaded models and memory usage
- Model response test

### Benchmark

Test model performance:
```bash
./tools/benchmark.sh
```

Measures:
- Time to first token
- Tokens per second
- Memory usage
- Response quality

### Update

Update Ollama and models:
```bash
./tools/update.sh
```

Updates:
- Ollama to latest version
- All installed models
- Refreshes Continue.dev config (optional)

### Cleanup

Unload models from memory to free up RAM:
```bash
./tools/cleanup.sh
```

Features:
- List all loaded models with memory usage
- Unload all models at once
- Unload specific models
- Show memory before/after cleanup
- Prevents memory warnings by freeing unused model memory

**When to use:**
- Seeing low memory warnings
- Multiple models loaded and not in use
- Need to free up RAM for other applications
- After running benchmarks or validations

### Uninstall

Remove components:
```bash
./tools/uninstall.sh
```

Options:
- Remove models
- Clean Continue.dev config
- Remove VS Code settings
- Clean state files
- Remove Ollama (optional)

## Tuning and Optimization

### Apple Silicon Optimizations

The setup script automatically optimizes models for Apple Silicon MacBook Pros:

#### Metal GPU Acceleration

- **Automatic Detection**: Metal GPU acceleration is automatically configured and verified
- **Environment Variables**: Optimal settings are configured in `~/.ollama/ollama.env`:
  - `OLLAMA_NUM_GPU=1` - Enables Metal GPU acceleration
  - `OLLAMA_NUM_THREAD` - Optimized CPU thread count (cores - 2)
  - `OLLAMA_KEEP_ALIVE` - Model keep-alive based on hardware tier
  - `OLLAMA_MAX_LOADED_MODELS` - Maximum concurrent models based on RAM

#### Automatic Quantization

Ollama automatically selects optimal quantization (Q4_K_M/Q5_K_M) for Apple Silicon when downloading models. You don't need to specify quantization - Ollama handles it automatically based on:
- Your hardware (Apple Silicon)
- Model size
- Available memory

Quantization benefits:
- **Q4_K_M**: 4-bit quantization, ~25% faster, minimal quality loss (used for larger models)
- **Q5_K_M**: 5-bit quantization, ~15% faster, excellent quality retention (used for smaller models)

The script uses standard model names (e.g., `qwen2.5-coder:14b`) and Ollama automatically downloads the best quantized variant for your system.

#### Performance Verification

During installation, the script:
- Verifies Metal GPU acceleration is active
- Benchmarks model performance (tokens/second)
- Validates model responses
- Logs performance metrics

### Auto-Tuning

Models are automatically tuned based on your hardware tier. Parameters include:
- Context window size
- Max tokens
- Temperature (role-specific)
- Top-p
- Keep-alive duration
- GPU acceleration (Metal)
- CPU thread optimization

### Manual Tuning

To adjust tuning, edit `~/.continue/config.json`:

```json
{
  "models": [
    {
      "title": "Coding Assistant",
      "contextLength": 16384,  // Adjust based on needs
      "temperature": 0.7,       // Lower = more focused
      ...
    }
  ]
}
```

### Performance Tips

1. **Metal GPU Acceleration**: Automatically enabled on Apple Silicon - verify with `curl http://localhost:11434/api/ps`
2. **Quantized Models**: Use Q4_K_M or Q5_K_M variants for best performance (automatically selected)
3. **Keep-alive settings**: Models stay loaded for 1h (Tier S/A) or 5m (Tier B/C) after use for fast responses, then automatically unload
4. **Smaller context** for faster responses
5. **Multiple models** - use smaller for autocomplete, larger for complex tasks
6. **Monitor memory** - use `ollama ps` or `./tools/diagnose.sh` to see loaded models
7. **Cleanup utility** - use `./tools/cleanup.sh` to unload models and free memory when needed
8. **Environment Variables**: Check `~/.ollama/ollama.env` for optimization settings

### Re-running Tuning

To re-run auto-tuning:
```bash
./setup-local-llm.sh
```

The script is idempotent - safe to re-run. It will:
- Detect existing installation
- Offer to resume or start fresh
- Preserve your customizations where possible

### Advanced Optimizations

The setup includes advanced optimizations for enhanced performance and resource management:

#### Multi-Model Orchestration

Intelligent model routing automatically selects the optimal model for each task type:

- **Autocomplete/Simple tasks**: Routes to smallest, fastest models (qwen2.5-coder:7b, llama3.1:8b)
- **Coding/Generation**: Routes to balanced models (qwen2.5-coder:14b, codestral:22b)
- **Refactoring/Complex tasks**: Routes to largest available models (llama3.1:70b, codestral:22b)
- **Code Review/Testing**: Routes to models with strong reasoning capabilities

**Usage:**
```bash
# Route a task to the optimal model
route_task_to_model "autocomplete" 0 "$HARDWARE_TIER"

# Execute a task with automatic routing
execute_task_with_routing "refactoring" "Refactor this code..." "coding"
```

#### GPU Layer Optimization

Automatically tests and optimizes GPU layer allocation for maximum performance:

- Benchmarks different GPU layer configurations
- Finds optimal balance between GPU and CPU layers
- Stores performance metrics for future reference

**Usage:**
```bash
# Benchmark specific GPU layer configuration
benchmark_gpu_layers "qwen2.5-coder:14b" "40"

# Find optimal GPU layers for a model
optimize_gpu_layers "qwen2.5-coder:14b"
```

#### Smart Request Queuing

Intelligent request queuing system with prioritization and batch processing:

- Priority-based queue (1 = highest, 10 = lowest)
- Automatic batch processing for efficiency
- Prevents request overload
- Supports task type and role routing

**Usage:**
```bash
# Queue a request
queue_request "Write a function..." "coding" 5 "coding"

# Process queued requests
process_request_queue 5 10  # Process 5 requests, wait up to 10s for batch

# Check queue status
get_queue_status
```

#### Performance Profiling

Continuous performance monitoring and metrics tracking:

- Tracks response times, tokens/second, success rates
- Model-specific and task-specific metrics
- Automatic performance report generation
- Historical performance data

**Usage:**
```bash
# Track performance for a request
track_performance "qwen2.5-coder:14b" "coding" 2.5 500 1

# Get performance statistics
get_performance_stats "qwen2.5-coder:14b" "coding"

# Generate performance report
generate_performance_report
```

**Performance Metrics Storage:**
- Metrics stored in: `~/.local-llm-setup/performance_metrics.json`
- Reports saved to: `~/.local-llm-setup/performance_report.txt`

#### Integration

Optimizations work seamlessly together:

- **Smart Loading** + **Orchestration**: Automatically loads optimal models for tasks
- **Memory Monitoring** + **Queuing**: Prevents memory pressure by queuing requests
- **Dynamic Context** + **Routing**: Adjusts context based on task type and selected model
- **Adaptive Temperature** + **Profiling**: Tracks which temperature settings perform best

All optimization functions are automatically available when you source `lib/optimization.sh` (which is done automatically by `setup-local-llm.sh`).

### Enabling Optimizations with Continue.dev

To get optimizations working automatically with Continue.dev:

#### Quick Start (Recommended)

1. **Start optimization services:**
   ```bash
   cd ai_model
   ./tools/start-optimizations.sh
   ```

2. **Regenerate Continue.dev config:**
   ```bash
   ./setup-local-llm.sh
   ```
   The config will automatically detect and use the proxy if running.

3. **Restart VS Code** completely (Cmd+Q, then reopen)

#### What Gets Enabled

**Core Optimizations:**
- **Automatic Model Routing**: Requests are routed to optimal models based on task type
- **Smart Request Queuing**: Requests are queued and processed efficiently
- **Memory Pressure Monitoring**: Automatically unloads models when memory is low
- **Performance Tracking**: All requests are tracked for optimization insights
- **Dynamic Context Sizing**: Context windows adjusted based on task complexity
- **Adaptive Temperature**: Temperature adjusted based on task type

**Advanced Optimizations:**
- **Prompt Optimization**: Automatically improves prompts for better responses (ENABLED by default)
- **Context Compression**: Compresses large contexts to prevent overflow (ENABLED by default)
- **Model Ensemble**: Combines multiple models for higher quality (DISABLED by default, enable for complex tasks)
- **Enhanced Batch Processing**: Efficiently processes multiple requests together

#### Management

```bash
# Check status
./tools/status-optimizations.sh

# Stop services
./tools/stop-optimizations.sh

# Start specific services
./tools/start-optimizations.sh --proxy    # Just proxy
./tools/start-optimizations.sh --monitor # Just memory monitor
./tools/start-optimizations.sh --queue   # Just queue processor
```

#### Manual Proxy Setup

If you prefer manual control:

1. **Start proxy:**
   ```bash
   ./tools/ollama-proxy.sh
   ```

2. **Update Continue.dev config:**
   Edit `~/.continue/config.yaml` and change `apiBase` to:
   ```yaml
   apiBase: http://localhost:11435  # Changed from 11434
   ```

3. **Restart VS Code**

#### Advanced Optimization Configuration

Advanced optimizations can be configured via environment variables:

```bash
# Enable model ensemble for complex tasks (slower but higher quality)
export ENABLE_ENSEMBLE=1

# Disable prompt optimization (faster, but less optimized prompts)
export ENABLE_PROMPT_OPTIMIZATION=0

# Disable context compression (may cause context overflow errors)
export ENABLE_CONTEXT_COMPRESSION=0

# Start with custom settings
./tools/start-optimizations.sh
```

**Recommended Settings:**
- **Default (Balanced)**: All advanced features enabled except ensemble
- **High Quality**: Enable ensemble for complex refactoring tasks
- **Maximum Speed**: Disable all advanced features for fastest responses

See `docs/ADVANCED_OPTIMIZATIONS.md` for detailed documentation.

## Troubleshooting

### Ollama Service Not Running

```bash
# Check status
brew services list | grep ollama

# Start service
brew services start ollama

# Or start manually
ollama serve
```

### Models Not Responding

1. **Check Ollama is running:**
   ```bash
   curl http://localhost:11434/api/tags
   ```

2. **Test model directly:**
   ```bash
   ollama run <model-name> "test"
   ```

3. **Check memory:**
   ```bash
   ollama ps
   ```

4. **Restart Ollama:**
   ```bash
   brew services restart ollama
   ```

### Continue.dev Not Connecting

1. **Verify config exists:**
   ```bash
   cat ~/.continue/config.json
   ```

2. **Check JSON validity:**
   ```bash
   jq empty ~/.continue/config.json
   ```

3. **Verify Ollama endpoint:**
   - Config should have: `"apiBase": "http://localhost:11434"`
   - Test: `curl http://localhost:11434/api/tags`

4. **Restart VS Code**

### Model Too Slow

1. **Use a smaller model** for autocomplete
2. **Reduce context window** in Continue.dev config
3. **Check system resources:**
   ```bash
   ollama ps
   top
   ```

4. **Pre-load model** with keep-alive:
   ```bash
   ollama run <model-name>
   # Keep terminal open
   ```

### Out of Memory / Low Memory Warnings

1. **Unload models using cleanup utility:**
   ```bash
   ./tools/cleanup.sh
   ```
   This will show loaded models and allow you to unload them to free memory.

2. **Check loaded models manually:**
   ```bash
   ollama ps
   ```

3. **Unload specific model:**
   ```bash
   curl -X POST http://localhost:11434/api/generate \
     -H "Content-Type: application/json" \
     -d '{"model": "model-name", "prompt": "", "keep_alive": 0}'
   ```

4. **Use smaller models** for your tier
5. **Keep-alive settings**: Models automatically unload after inactivity (1h for Tier S/A, 5m for Tier B/C)
6. **Close other applications** to free up RAM
7. **Use quantized variants** - Q4_K_M uses less memory than base models
8. **Restart Ollama** if models won't unload:
   ```bash
   brew services restart ollama
   ```

### Metal GPU Not Working

1. **Verify Metal is available:**
   ```bash
   system_profiler SPDisplaysDataType | grep -i metal
   ```

2. **Check environment variables:**
   ```bash
   cat ~/.ollama/ollama.env
   # Should show OLLAMA_NUM_GPU=1
   ```

3. **Restart Ollama with environment:**
   ```bash
   source ~/.ollama/ollama.env
   brew services restart ollama
   ```

4. **Verify GPU usage:**
   ```bash
   curl http://localhost:11434/api/ps
   # Should show GPU-related information
   ```

5. **Check Ollama version** - ensure you have the latest version:
   ```bash
   brew upgrade ollama
   ```

6. **Manual verification** - run a model and check Activity Monitor for GPU usage

### TypeScript/React Issues

1. **Check VS Code settings** - ensure TypeScript settings are applied
2. **Verify extensions** - ESLint, Prettier, TypeScript
3. **Check workspace** - ensure `.vscode/settings.json` is in workspace root
4. **Restart VS Code**

## Stack-Specific Best Practices

### TypeScript

- **Strict typing**: No `any`, use generics and discriminated unions
- **Type safety**: Enable all strict checks in `tsconfig.json`
- **Typed selectors**: Use typed Redux selectors

### Redux + Redux-Saga

- **Side effects in sagas**: Never in components
- **Typed selectors**: Use TypeScript for all selectors
- **Saga patterns**: Use takeLatest/takeEvery appropriately
- **Cancellation**: Always handle saga cancellation
- **Error handling**: Comprehensive error handling in sagas

### Material UI (MUI)

- **Theme-first**: Use sx prop with theme tokens
- **No inline styles**: Avoid ad-hoc inline styles
- **Accessibility**: Proper ARIA labels, keyboard navigation
- **Responsive**: Use MUI breakpoints

### AG Grid

- **Typed column defs**: Use TypeScript for column definitions
- **Memoized renderers**: Memoize cell renderers for performance
- **Performance**: Use virtualization, row grouping appropriately

### OpenLayers

- **Lifecycle management**: Clean up on component unmount
- **Event listeners**: Properly remove all event listeners
- **Map state**: Isolate map state, don't mix with component state
- **Memory leaks**: Check for proper cleanup

## Security and Privacy

### Local-First

- **No cloud APIs**: All inference is local
- **No telemetry**: Continue.dev telemetry disabled
- **No external calls**: Only initial installs and model downloads require internet
- **Offline capable**: Works fully offline after setup

### Enterprise-Safe

- **No data leaves your machine**: Code never sent to external services
- **Auditable**: All code is open-source and inspectable
- **Restricted environments**: Works in air-gapped networks (after initial setup)
- **Clearance-friendly**: No external dependencies during operation

### Data Storage

- **Models**: Stored in `~/.ollama/models/`
- **Config**: `~/.continue/config.json`
- **State**: `~/.local-llm-setup/`
- **Logs**: `~/.local-llm-setup/*.log`

All data stays on your local machine.

## Advanced Usage

### Custom Model Configuration

Edit `~/.continue/config.json` to add custom models or adjust parameters:

```json
{
  "models": [
    {
      "title": "Custom Model",
      "provider": "ollama",
      "model": "your-model:tag",
      "apiBase": "http://localhost:11434",
      "contextLength": 16384,
      "temperature": 0.7,
      "systemMessage": "Your custom system prompt"
    }
  ]
}
```

### Workspace-Specific Configs

Continue.dev supports workspace-specific configs. Create `.continue/config.json` in your workspace root to override global config.

### Local Embeddings

For better codebase understanding, you can enable local embeddings in Continue.dev config:

```json
{
  "embeddingsProvider": {
    "provider": "ollama",
    "model": "qwen2.5-coder:14b",
    "apiBase": "http://localhost:11434"
  }
}
```

Note: This uses more resources but provides better semantic search.

## Getting Help

### Diagnostic Report

Generate a full diagnostic report:
```bash
./tools/diagnose.sh
```

This creates a detailed report with all system information.

### Logs

Check logs for detailed information:
- Setup: `~/.local-llm-setup/setup.log`
- Diagnose: `~/.local-llm-setup/diagnose.log`
- Benchmark: `~/.local-llm-setup/benchmark.log`
- Update: `~/.local-llm-setup/update.log`

### Common Issues

See the [Troubleshooting](#troubleshooting) section above for common issues and solutions.

### Resources

- [Ollama Documentation](https://github.com/ollama/ollama/blob/main/docs)
- [Continue.dev Documentation](https://docs.continue.dev)
- [VS Code Settings](https://code.visualstudio.com/docs/getstarted/settings)

## File Structure

```
ai_model/
├── setup-local-llm.sh          # Main setup script
├── tools/
│   ├── diagnose.sh              # Health checks and diagnostics
│   ├── benchmark.sh             # Model performance testing
│   ├── cleanup.sh               # Memory cleanup utility
│   ├── update.sh                # Update Ollama and models
│   └── uninstall.sh             # Cleanup and removal
├── .continue/
│   └── config.json              # Continue.dev configuration template
├── vscode/
│   ├── settings.json            # VS Code settings snippet
│   └── extensions.json          # Extension recommendations
├── prompts/
│   └── starter-prompts.md       # Stack-optimized prompt templates
└── README.md                    # This file
```

## License

MIT License - See LICENSE file for details.

## Contributing

This is a production setup script. For improvements:
1. Test thoroughly on your hardware tier
2. Ensure idempotency (safe to re-run)
3. Maintain backward compatibility
4. Update documentation

---

**Setup completed?** Start coding with AI! Use `Cmd+L` in VS Code to open Continue.dev and try the starter prompts.
