# Tuning and Optimization

## Apple Silicon Optimizations

The setup script automatically optimizes models for Apple Silicon MacBook Pros:

### Metal GPU Acceleration

- **Automatic Detection**: Metal GPU acceleration is automatically configured and verified
- **Environment Variables**: Optimal settings are configured in `~/.ollama/ollama.env`:
  - `OLLAMA_NUM_GPU=1` - Enables Metal GPU acceleration
  - `OLLAMA_NUM_THREAD` - Optimized CPU thread count (cores - 2)
  - `OLLAMA_KEEP_ALIVE` - Model keep-alive based on hardware tier
  - `OLLAMA_MAX_LOADED_MODELS` - Maximum concurrent models based on RAM

### Automatic Quantization

Ollama automatically selects optimal quantization (Q4_K_M/Q5_K_M) for Apple Silicon when downloading models. You don't need to specify quantization - Ollama handles it automatically based on:
- Your hardware (Apple Silicon)
- Model size
- Available memory

**Quantization benefits:**
- **Q4_K_M**: 4-bit quantization, ~25% faster, minimal quality loss (used for larger models)
- **Q5_K_M**: 5-bit quantization, ~15% faster, excellent quality retention (used for smaller models)

The script uses standard model names (e.g., `llama3.1:70b`, `codestral:22b`) and Ollama automatically downloads the best quantized variant for your system.

### Performance Verification

During installation, the script:
- Verifies Metal GPU acceleration is active
- Benchmarks model performance (tokens/second)
- Validates model responses
- Logs performance metrics

## Auto-Tuning

Models are automatically tuned based on your hardware tier. Parameters include:
- Context window size
- Max tokens
- Temperature (role-specific)
- Top-p
- Keep-alive duration
- GPU acceleration (Metal)
- CPU thread optimization

## Manual Tuning

To adjust tuning, edit `~/.continue/config.yaml`:

```yaml
models:
  - name: Llama 3.1 8B
    provider: ollama
    model: llama3.1:8b
    apiBase: http://localhost:11434
    contextLength: 16384  # Adjust based on needs
    temperature: 0.7       # Lower = more focused
    roles:
      - chat
      - edit
      - apply
```

## Performance Tips

1. **Metal GPU Acceleration**: Automatically enabled on Apple Silicon - verify with `curl http://localhost:11434/api/ps`
2. **Quantized Models**: Use Q4_K_M or Q5_K_M variants for best performance (automatically selected)
3. **Keep-alive settings**: Models stay loaded for 24h (Tier S), 12h (Tier A), or 5m (Tier B/C) after use for fast responses, then automatically unload
4. **Smaller context** for faster responses
5. **Multiple models** - use smaller for autocomplete, larger for complex tasks
6. **Monitor memory** - use `ollama ps` or `./tools/diagnose.sh` to see loaded models
7. **Cleanup utility** - use `./tools/cleanup.sh` to unload models and free memory when needed
8. **Environment Variables**: Check `~/.ollama/ollama.env` for optimization settings

## Advanced Optimizations

The setup includes advanced optimizations for enhanced performance and resource management:

### Multi-Model Orchestration

Intelligent model routing automatically selects the optimal model for each task type:

- **Autocomplete/Simple tasks**: Routes to smallest, fastest models (llama3.1:8b, starcoder2:3b)
- **Coding/Generation**: Routes to balanced models (codestral:22b, llama3.1:8b, granite-code:20b)
- **Refactoring/Complex tasks**: Routes to largest available models (llama3.3:70b, llama3.1:70b, codestral:22b)
- **Code Review/Testing**: Routes to models with strong reasoning capabilities (phi4:14b, codestral:22b)

**Usage:**
```bash
# Route a task to the optimal model
route_task_to_model "autocomplete" 0 "$HARDWARE_TIER"

# Execute a task with automatic routing
execute_task_with_routing "refactoring" "Refactor this code..." "coding"
```

### GPU Layer Optimization

Automatically tests and optimizes GPU layer allocation for maximum performance:

- Benchmarks different GPU layer configurations
- Finds optimal balance between GPU and CPU layers
- Stores performance metrics for future reference

**Usage:**
```bash
# Benchmark specific GPU layer configuration
benchmark_gpu_layers "codestral:22b" "40"

# Find optimal GPU layers for a model
optimize_gpu_layers "codestral:22b"
```

### Smart Request Queuing

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

### Performance Profiling

Continuous performance monitoring and metrics tracking:

- Tracks response times, tokens/second, success rates
- Model-specific and task-specific metrics
- Automatic performance report generation
- Historical performance data

**Usage:**
```bash
# Track performance for a request
track_performance "codestral:22b" "coding" 2.5 500 1

# Get performance statistics
get_performance_stats "codestral:22b" "coding"

# Generate performance report
generate_performance_report
```

**Performance Metrics Storage:**
- Metrics stored in: `~/.local-llm-setup/performance_metrics.json`
- Reports saved to: `~/.local-llm-setup/performance_report.txt`

### Integration

Optimizations work seamlessly together:

- **Smart Loading** + **Orchestration**: Automatically loads optimal models for tasks
- **Memory Monitoring** + **Queuing**: Prevents memory pressure by queuing requests
- **Dynamic Context** + **Routing**: Adjusts context based on task type and selected model
- **Adaptive Temperature** + **Profiling**: Tracks which temperature settings perform best

All optimization functions are automatically available when you source `lib/optimization.sh` (which is done automatically by `setup-local-llm.sh`).

## Enabling Optimizations with Continue.dev

### Quick Start (Recommended)

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

### What Gets Enabled

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

### Management

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

### Manual Proxy Setup

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

### Advanced Optimization Configuration

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
