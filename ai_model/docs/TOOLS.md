# Tool Usage

## Diagnose

Check the health of your setup:
```bash
./tools/diagnose.sh
```

**Checks:**
- Ollama daemon health
- Installed models
- Continue.dev config validity
- VS Code integration
- System resources
- Loaded models and memory usage
- Model response test

## Benchmark

Test model performance:
```bash
./tools/benchmark.sh
```

**Measures:**
- Time to first token
- Tokens per second
- Memory usage
- Response quality

## Update

Update Ollama and models:
```bash
./tools/update.sh
```

**Updates:**
- Ollama to latest version
- All installed models
- Refreshes Continue.dev config (optional)

## Cleanup

Unload models from memory to free up RAM:
```bash
./tools/cleanup.sh
```

**Features:**
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

## Uninstall

Remove components:
```bash
./tools/uninstall.sh
```

**Options:**
- Remove models
- Clean Continue.dev config
- Remove VS Code settings
- Clean state files
- Remove Ollama (optional)

## Optimization Tools

### Start Optimizations

Start optimization services:
```bash
./tools/start-optimizations.sh
```

Options:
- `--proxy` - Just proxy
- `--monitor` - Just memory monitor
- `--queue` - Just queue processor

### Status

Check optimization status:
```bash
./tools/status-optimizations.sh
```

### Stop

Stop optimization services:
```bash
./tools/stop-optimizations.sh
```

### Enable/Ensure

Enable or ensure optimizations are configured:
```bash
./tools/enable-optimizations.sh
./tools/ensure-optimizations.sh
```

See [Optimization](OPTIMIZATION.md) for detailed information about these tools.
