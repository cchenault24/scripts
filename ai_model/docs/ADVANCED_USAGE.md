# Advanced Usage

## Custom Model Configuration

Edit `~/.continue/config.yaml` to add custom models or adjust parameters:

```yaml
models:
  - name: Custom Model
    provider: ollama
    model: your-model:tag
    apiBase: http://localhost:11434
    contextLength: 16384
    temperature: 0.7
    roles:
      - chat
      - edit
      - apply
```

## Workspace-Specific Configs

Continue.dev supports workspace-specific configs. Create `.continue/config.yaml` in your workspace root to override global config.

## Local Embeddings

For better codebase understanding, you can enable local embeddings in Continue.dev config:

```yaml
embeddingsProvider:
  provider: ollama
  model: nomic-embed-text
  apiBase: http://localhost:11434
```

Note: This uses more resources but provides better semantic search. The setup script automatically configures embeddings if you select an embedding model during installation.

## Performance Optimization

See [Optimization](OPTIMIZATION.md) for detailed information on:
- Metal GPU acceleration
- Model quantization
- Auto-tuning
- Advanced optimizations
- Performance profiling

## Custom Scripts

You can extend the setup with custom scripts. All library functions are available when you source the appropriate files:

```bash
# Source optimization functions
source lib/optimization.sh

# Source model functions
source lib/models.sh

# Source hardware detection
source lib/hardware.sh
```

See the `lib/` directory for available functions and utilities.
