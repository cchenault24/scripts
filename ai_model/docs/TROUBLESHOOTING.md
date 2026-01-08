# Troubleshooting

## Ollama Service Not Running

```bash
# Check status
brew services list | grep ollama

# Start service
brew services start ollama

# Or start manually
ollama serve
```

## Models Not Responding

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

## Continue.dev Not Connecting

1. **Verify config exists:**
   ```bash
   cat ~/.continue/config.yaml
   ```

2. **Check YAML validity:**
   ```bash
   # Basic YAML structure check
   grep -q "models:" ~/.continue/config.yaml && echo "Config structure OK" || echo "Config may be invalid"
   ```

3. **Verify Ollama endpoint:**
   - Config should have: `apiBase: http://localhost:11434` (or `http://localhost:11435` if using proxy)
   - Test: `curl http://localhost:11434/api/tags`

4. **Restart VS Code**

## Model Too Slow

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

## Out of Memory / Low Memory Warnings

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
5. **Keep-alive settings**: Models automatically unload after inactivity (24h for Tier S, 12h for Tier A, 5m for Tier B/C)
6. **Close other applications** to free up RAM
7. **Use quantized variants** - Q4_K_M uses less memory than base models
8. **Restart Ollama** if models won't unload:
   ```bash
   brew services restart ollama
   ```

## Metal GPU Not Working

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

## TypeScript/React Issues

1. **Check VS Code settings** - ensure TypeScript settings are applied
2. **Verify extensions** - ESLint, Prettier, TypeScript
3. **Check workspace** - ensure `.vscode/settings.json` is in workspace root
4. **Restart VS Code**

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

### Resources

- [Ollama Documentation](https://github.com/ollama/ollama/blob/main/docs)
- [Continue.dev Documentation](https://docs.continue.dev)
- [VS Code Settings](https://code.visualstudio.com/docs/getstarted/settings)
