# Troubleshooting Guide

This guide covers common issues you may encounter when using the AI model management scripts and their solutions.

## 1. Slow Inference Performance

**Problem:** Model responses are taking much longer than expected, with noticeable delays during generation.

**Cause:** Not all model layers are being loaded onto the GPU. By default, Ollama may only load a subset of layers to GPU memory, causing the CPU to handle remaining layers which is significantly slower.

**Solution:**
1. Set the GPU layers environment variable:
   ```bash
   export OLLAMA_NUM_GPU=999
   ```
2. Add this to your shell profile (~/.zshrc or ~/.bashrc) to make it permanent:
   ```bash
   echo 'export OLLAMA_NUM_GPU=999' >> ~/.zshrc
   source ~/.zshrc
   ```
3. Restart Ollama:
   ```bash
   ./llama-control.sh stop
   ./llama-control.sh start
   ```

**Verification:**
```bash
./llama-control.sh metrics
```
Check the output for GPU utilization. You should see high GPU usage during inference. You can also monitor GPU activity in Activity Monitor (macOS) under the "GPU History" tab.

---

## 2. Out of Memory Errors

**Problem:** System runs out of RAM or encounters memory errors when loading or running models.

**Cause:** The selected model is too large for available system RAM. Larger models and higher precision quantizations require more memory.

**Solution:**
1. Check current model size and available memory:
   ```bash
   ./compare-models.sh
   ```
2. Switch to a smaller model or lower quantization:
   ```bash
   # For smaller model
   ./switch-model.sh qwen2.5-coder:7b-instruct-q4_K_M

   # Or use Q4 quantization instead of Q8
   ./switch-model.sh gemma2:27b-instruct-q4_K_M
   ```
3. Close unnecessary applications to free up RAM

**Verification:**
```bash
./compare-models.sh
```
Review the memory requirements column and ensure your selected model fits within available RAM with headroom for the OS and other applications.

---

## 3. Model Not Found Error

**Problem:** Ollama returns "model not found" error when trying to use a model.

**Cause:** Either the model name contains a typo, uses incorrect syntax (dashes instead of colons), or the model hasn't been pulled from the registry.

**Solution:**
1. List all available models:
   ```bash
   ollama list
   ```
2. Verify the correct model name format (use colons, not dashes):
   - Correct: `qwen2.5-coder:7b-instruct-q4_K_M`
   - Incorrect: `qwen2.5-coder-7b-instruct-q4_K_M`
3. If model is missing, pull it:
   ```bash
   ollama pull qwen2.5-coder:7b-instruct-q4_K_M
   ```

**Verification:**
```bash
ollama list | grep <model-name>
```
The model should appear in the list with its size and modification date.

---

## 4. Port Already in Use

**Problem:** Server fails to start with "address already in use" or "port conflict" error.

**Cause:** Another process is already using port 3456, or a previous Ollama instance is still running.

**Solution:**
1. Check what's using the port:
   ```bash
   lsof -i :11434
   ```
2. Stop any conflicting process:
   ```bash
   ./llama-control.sh stop
   ```
3. If the port is needed for another service, change the port in configuration:
   ```bash
   # Edit lib/common.sh
   # Change: export PORT=3456
   # To: export PORT=3457
   ```
4. Update all client configurations to use the new port

**Verification:**
```bash
lsof -i :11434
```
Should show only your Ollama instance, or nothing if you changed the port. Then verify connectivity:
```bash
curl http://127.0.0.1:11434/api/tags
```

---

## 5. Server Won't Start

**Problem:** Ollama server fails to start or immediately crashes after starting.

**Cause:** A previous Ollama instance may still be running, or there are conflicting environment variables/configurations.

**Solution:**
1. Stop all running instances:
   ```bash
   ./llama-control.sh stop
   ```
2. Verify all processes are terminated:
   ```bash
   ps aux | grep ollama
   ```
3. Kill any remaining processes manually if needed:
   ```bash
   killall ollama
   ```
4. Check for conflicting OLLAMA_HOST settings:
   ```bash
   env | grep OLLAMA
   ```
5. Start the server fresh:
   ```bash
   ./llama-control.sh start
   ```

**Verification:**
```bash
./llama-control.sh status
```
Should show "Server is running" with the PID. Also test API access:
```bash
curl http://127.0.0.1:11434/api/tags
```

---

## 6. Context Truncation Issues

**Problem:** Long prompts or conversations are being truncated, losing important context.

**Cause:** Input exceeds the model's context window limit. Different models have different maximum context lengths.

**Solution:**
1. Check your current model's context window:
   ```bash
   ollama show <model-name>
   ```
2. Switch to a model with larger context window:
   ```bash
   # Gemma2 27B supports up to 256K context
   ./switch-model.sh gemma2:27b-instruct-q4_K_M
   ```
3. Alternatively, break down your prompt into smaller chunks
4. Use conversation history summarization for long chats

**Verification:**
Test with increasingly longer prompts to find the practical limit. Check model specifications:
```bash
ollama show gemma2:27b-instruct-q4_K_M | grep -i context
```

---

## 7. GPU Not Being Used

**Problem:** Activity Monitor shows no GPU usage during model inference, all processing appears to be on CPU.

**Cause:** Metal framework is not properly configured, or Ollama was built without GPU acceleration support.

**Solution:**
1. Check if Ollama was built with Metal support:
   ```bash
   ollama --version
   ```
2. Set GPU layers environment variable:
   ```bash
   export OLLAMA_NUM_GPU=999
   ```
3. If Metal support is missing, reinstall Ollama:
   ```bash
   brew uninstall ollama
   brew install ollama
   ```
4. Verify Metal framework is available:
   ```bash
   system_profiler SPDisplaysDataType | grep Metal
   ```

**Verification:**
Open Activity Monitor, go to the "Window" menu and select "GPU History". Run a query and observe GPU utilization during inference. You should see significant GPU activity on the graph.

---

## 8. Continue.dev Not Connecting

**Problem:** Continue.dev extension shows connection errors or fails to communicate with the local model.

**Cause:** The API URL in Continue.dev configuration doesn't match the actual Ollama server address.

**Solution:**
1. Open Continue.dev configuration:
   ```bash
   code ~/.continue/config.json
   ```
2. Verify the configuration has the correct endpoint:
   ```json
   {
     "models": [
       {
         "title": "Local Ollama",
         "provider": "ollama",
         "model": "qwen2.5-coder:7b-instruct-q4_K_M",
         "apiBase": "http://127.0.0.1:11434"
       }
     ]
   }
   ```
3. Ensure the server is running:
   ```bash
   ./llama-control.sh status
   ```
4. Restart VS Code after configuration changes

**Verification:**
Test the connection in Continue.dev chat interface. Send a simple query like "Hello" and verify you receive a response. Check the Continue.dev output panel for any error messages.

---

## 9. Open WebUI Cannot Reach Ollama

**Problem:** Open WebUI running in Docker cannot connect to the Ollama server running on the host machine.

**Cause:** Docker network isolation prevents the container from accessing localhost on the host. Using "localhost" or "127.0.0.1" in Docker refers to the container itself, not the host.

**Solution:**
1. Update Open WebUI environment variable to use Docker's host gateway:
   ```bash
   docker run -d -p 3000:8080 \
     -e OLLAMA_API_BASE_URL=http://host.docker.internal:11434 \
     --name open-webui \
     ghcr.io/open-webui/open-webui:main
   ```
2. For existing containers, update the environment variable:
   ```bash
   docker stop open-webui
   docker rm open-webui
   # Then run the command above
   ```
3. Verify Ollama is accessible from host:
   ```bash
   curl http://127.0.0.1:11434/api/tags
   ```

**Verification:**
Check container logs:
```bash
docker logs open-webui
```
Look for successful connection messages. Open WebUI in browser and verify models appear in the selection dropdown.

---

## 10. Model Switches But Clients Don't Update

**Problem:** After switching models manually with `ollama run`, client applications (Continue.dev, Open WebUI) still use the old model.

**Cause:** Client configuration files are not automatically updated when you switch models manually. Each client maintains its own configuration that specifies which model to use.

**Solution:**
1. Always use the provided switch script instead of manual switching:
   ```bash
   ./switch-model.sh qwen2.5-coder:7b-instruct-q4_K_M
   ```
2. The script automatically updates:
   - Continue.dev config (~/.continue/config.json)
   - Open WebUI settings (if running)
   - Environment variables
3. If you did switch manually, update configs manually:
   ```bash
   # Edit Continue.dev config
   code ~/.continue/config.json

   # Change the "model" field to your new model
   ```

**Verification:**
Check all client configurations:
```bash
# Continue.dev
cat ~/.continue/config.json | grep "model"

# Verify active model in Ollama
curl http://127.0.0.1:11434/api/tags
```
Test inference in each client to confirm they're using the new model.

---

## 11. Duplicate Model Listings

**Problem:** Running `ollama list` shows multiple copies of the same model with different names or tags.

**Cause:** Models have been pulled multiple times with different tag specifications, or remain from previous experiments.

**Solution:**
1. List all models to identify duplicates:
   ```bash
   ollama list
   ```
2. Remove unwanted duplicates:
   ```bash
   ollama rm <model-name:tag>
   ```
3. Use the cleanup script if available:
   ```bash
   ./cleanup-models.sh
   ```
4. Keep only the models you actively use

**Verification:**
```bash
ollama list
```
Should show a clean list with only the models you need, each appearing once with the correct tag.

---

## 12. Metrics Not Available

**Problem:** Running `./llama-control.sh metrics` returns no data or shows "metrics not available".

**Cause:** Metrics endpoint may not be enabled, or the server is not properly exposing the metrics interface.

**Solution:**
1. Verify the server is running:
   ```bash
   ./llama-control.sh status
   ```
2. Check if the metrics endpoint responds:
   ```bash
   curl http://127.0.0.1:11434/api/metrics
   ```
3. If unavailable, restart the server:
   ```bash
   ./llama-control.sh stop
   ./llama-control.sh start
   ```
4. Use alternative monitoring:
   ```bash
   # Monitor system resources
   top -pid $(pgrep ollama)
   ```

**Verification:**
```bash
./llama-control.sh metrics
```
Should display current performance statistics including request counts, latency, and resource usage.

---

## 13. Script Permission Denied

**Problem:** Attempting to run scripts results in "Permission denied" errors.

**Cause:** Script files don't have execute permissions set.

**Solution:**
1. Add execute permissions to all scripts:
   ```bash
   chmod +x *.sh
   ```
2. For scripts in subdirectories:
   ```bash
   find . -name "*.sh" -type f -exec chmod +x {} \;
   ```
3. Verify permissions:
   ```bash
   ls -la *.sh
   ```

**Verification:**
```bash
./llama-control.sh status
```
Should execute without permission errors. All scripts should show `rwxr-xr-x` permissions in `ls -la` output.

---

## 14. Environment Variables Not Persisting

**Problem:** Environment variables like `OLLAMA_NUM_GPU` need to be set every time you open a new terminal session.

**Cause:** Variables are only set for the current shell session and not saved to your shell profile.

**Solution:**
1. Add variables to your shell profile:
   ```bash
   # For zsh (macOS default)
   echo 'export OLLAMA_NUM_GPU=999' >> ~/.zshrc
   echo 'export OLLAMA_HOST=http://127.0.0.1:11434' >> ~/.zshrc

   # For bash
   echo 'export OLLAMA_NUM_GPU=999' >> ~/.bashrc
   echo 'export OLLAMA_HOST=http://127.0.0.1:11434' >> ~/.bashrc
   ```
2. Reload your profile:
   ```bash
   source ~/.zshrc  # or ~/.bashrc
   ```
3. Alternatively, use the provided setup script if available

**Verification:**
Open a new terminal window and run:
```bash
echo $OLLAMA_NUM_GPU
echo $OLLAMA_HOST
```
Should display the configured values without manually exporting them.

---

## Getting Additional Help

If you encounter issues not covered in this guide:

1. **Check Logs:**
   ```bash
   ./llama-control.sh logs
   ```

2. **System Information:**
   ```bash
   ./compare-models.sh  # Shows system specs and model compatibility
   ```

3. **Test Server Health:**
   ```bash
   curl http://127.0.0.1:11434/api/tags
   curl http://127.0.0.1:11434/api/version
   ```

4. **Ollama Documentation:** https://github.com/ollama/ollama/tree/main/docs

5. **Model Documentation:** Check model-specific documentation on Ollama's model library

6. **Community Support:** Visit the Ollama GitHub discussions for community help
