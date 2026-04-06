# Migrating from Docker Model Runner to Ollama

## Overview

As of **v4.1.0 (April 2026)**, the ai_model project has simplified to use **Ollama exclusively**. The Docker Model Runner backend has been removed to:

- Reduce code duplication (60-70% of codebase was duplicated)
- Lower maintenance burden (-6,759 lines of code)
- Provide a clearer, more focused user experience
- Eliminate architectural complexity

This guide helps existing Docker Model Runner users migrate to Ollama.

## Why the Change?

### Technical Reasons
- **Code Duplication**: Docker and Ollama backends shared 10 modules with 60-70% identical code
- **Maintenance Overhead**: Bug fixes and features had to be implemented twice
- **Architectural Drift**: Backends were diverging over time (Ollama had more features)
- **Testing Complexity**: Parametrized test fixtures for dual backends added complexity

### Strategic Reasons
- **Ollama is More Mature**: Better model ecosystem, more active development
- **Simpler Installation**: No Docker Desktop requirement
- **Better Performance**: Dedicated LLM runtime optimized for inference
- **Easier Troubleshooting**: Single code path means clearer error messages

## What You're Losing

### Docker-Specific Features Removed

**1. AI Fine-Tuning Profiles** (`tuning.py` - 213 lines)
- **What it did**: Hardware-aware LLM parameter presets (performance/balanced/quality)
- **Auto-detected tier** based on RAM and Apple Silicon generation
- **Customized parameters**: temperature, top_p, top_k, max_tokens, context_length, etc.
- **Why dropped**: Continue.dev has built-in UI controls for these same parameters

**Example (Lost Feature):**
```python
# Docker backend auto-detected performance tier
tier = detect_performance_tier(hw_info)  # Returns "performance", "balanced", or "quality"
profile = create_preset_profile(tier, hw_info)
# profile.temperature = 0.7, profile.context_length = 32768, etc.
```

**Workaround**: Manually adjust parameters in Continue.dev settings:
- Open Continue.dev chat panel
- Click settings icon → Model Settings
- Adjust temperature, top_p, max_tokens manually

**2. Docker Model Runner API Endpoint**
- **Old**: `http://127.0.0.1:12434/v1`
- **New**: `http://127.0.0.1:11434/v1` (Ollama)

## Migration Steps

### Prerequisites

**System Requirements:**
- macOS with Apple Silicon (M1/M2/M3/M4)
- 16GB+ RAM
- 20GB+ free disk space

**Note**: If you're on Linux/Windows/Intel Mac, the current code **will not work** - it requires Apple Silicon detection. See "Platform Support" section below.

### Step 1: Uninstall Docker Setup

```bash
cd ai_model

# If you still have the old structure
python3 docker/docker-llm-uninstall.py

# This will:
# - Remove Docker-pulled models
# - Restore backed-up Continue.dev configs
# - Clean up generated files
```

**Manual Cleanup** (if uninstaller unavailable):
```bash
# Remove Docker Model Runner models
docker model rm gpt-oss:20b
docker model rm nomic-embed-text

# Remove Continue.dev configs (will be regenerated)
rm ~/.continue/config.yaml
rm ~/.continue/config.json
rm ~/.continue/rules/global-rule.md

# Backup any custom rules you want to keep!
cp ~/.continue/rules/global-rule.md ~/global-rule-backup.md
```

### Step 2: Update Repository

```bash
# Pull latest changes
git pull origin master

# Or checkout the refactored branch
git checkout refactor/ollama-only

# Verify new structure
ls -la
# Should see: lib/, tests/, setup.py, uninstall.py, README.md
```

### Step 3: Install Ollama

Ollama will be installed automatically during setup, but you can install manually:

```bash
# Install via Homebrew
brew install ollama

# Or download from https://ollama.com

# Verify installation
ollama --version
```

### Step 4: Run Ollama Setup

```bash
cd ai_model

# Run the new unified setup script
python3 setup.py

# This will:
# 1. Detect Apple Silicon hardware
# 2. Install/update Ollama if needed
# 3. Pull GPT-OSS 20B and nomic-embed-text
# 4. Configure Ollama service (LaunchAgent for auto-start)
# 5. Generate Continue.dev configuration
# 6. Create installation manifest
```

**Expected Output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Hardware Detection
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Detected: Apple M3 Pro
✓ RAM: 16.0 GB
✓ Available for models: 9.6 GB (60%)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Model Selection
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Selected models:
  • GPT-OSS 20B (16GB) - chat, edit, autocomplete
  • Nomic Embed Text (0.3GB) - embed

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Pulling Models
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Pulling gpt-oss:20b...
[████████████████████████████████████] 100% 16.2GB/16.2GB 25MB/s ETA: 0s
✓ Model pulled and verified

Setup Complete! 🎉
```

### Step 5: Verify Installation

```bash
# Check Ollama models
ollama list
# Should show:
# NAME                 ID              SIZE    MODIFIED
# gpt-oss:20b          abc123def       16 GB   2 minutes ago
# nomic-embed-text     xyz789uvw       274 MB  2 minutes ago

# Test model inference
ollama run gpt-oss:20b "Write hello world in Python"

# Check API endpoint
curl http://127.0.0.1:11434/api/tags
# Should return JSON with model list
```

### Step 6: Test Continue.dev Integration

1. Open VS Code/Cursor/IntelliJ IDEA
2. Reload window (if Continue was already installed)
3. Open Continue chat panel
4. Verify status bar shows: **"● Ollama"** (connected)
5. Send a test message - should respond using GPT-OSS 20B

**Troubleshooting Connection Issues:**
```bash
# Ensure Ollama is running
ollama serve  # Should say "already running" if LaunchAgent is active

# Check config points to correct endpoint
cat ~/.continue/config.yaml | grep apiBase
# Should show: apiBase: http://127.0.0.1:11434/v1

# Restart Ollama if needed
pkill ollama
ollama serve
```

## Comparing Docker vs Ollama

### API Endpoints

| Backend | Endpoint | Port | Format |
|---------|----------|------|--------|
| **Docker Model Runner** | `http://127.0.0.1:12434/v1` | 12434 | OpenAI-compatible |
| **Ollama** | `http://127.0.0.1:11434/v1` | 11434 | OpenAI-compatible |

### Model Storage

| Backend | Storage Location | Size |
|---------|------------------|------|
| **Docker** | Docker volumes | ~16GB+ |
| **Ollama** | `~/.ollama/models/` | ~16GB+ |

### Commands

| Task | Docker Command | Ollama Command |
|------|----------------|----------------|
| List models | `docker model ls` | `ollama list` |
| Pull model | `docker model pull gpt-oss:20b` | `ollama pull gpt-oss:20b` |
| Remove model | `docker model rm gpt-oss:20b` | `ollama rm gpt-oss:20b` |
| Run inference | `docker model run ...` | `ollama run gpt-oss:20b "prompt"` |

### Configuration Differences

**Docker (`docker/lib/config.py`):**
```python
def generate_continue_config(
    model_list: List[Any],
    hw_info: hardware.HardwareInfo,
    tuning_profile: tuning.TuningProfile,  # Has tuning!
    target_ide: List[str],
    output_path: Optional[Path] = None
) -> Path:
```

**Ollama (`lib/config.py`):**
```python
def generate_continue_config(
    model_list: List[Any],
    hw_info: hardware.HardwareInfo,
    output_path: Optional[Path] = None,
    target_ide: Optional[List[str]] = None  # No tuning profile
) -> Path:
```

## Platform Support

### Current Limitations

The current code **requires Apple Silicon**:

```python
# lib/model_selector.py:92-99
is_supported, error_msg = hardware.validate_apple_silicon_support(hw_info)
if not is_supported:
    ui.print_error(error_msg or "This setup only supports Apple Silicon Macs")
    raise SystemExit("Hardware requirements not met: Apple Silicon required")
```

### If You Need Multi-Platform Support

**Option 1: Use Older Version**
- Checkout `v4.0.0` (before Ollama-only refactoring)
- Docker backend supported Linux/Windows with NVIDIA GPUs

```bash
git checkout v4.0.0
cd ai_model/docker
python3 docker-llm-setup.py
```

**Option 2: Modify Code** (remove Apple Silicon check)
```python
# lib/model_selector.py - REMOVE lines 92-99
# Comment out or delete the Apple Silicon validation

# This will allow setup to run on Intel/Linux/Windows
# But model performance may vary without Metal GPU acceleration
```

**Option 3: Use Ollama Directly**
- Install Ollama manually: https://ollama.com
- Pull models: `ollama pull gpt-oss:20b`
- Configure Continue.dev manually with endpoint `http://localhost:11434/v1`

## Frequently Asked Questions

### Q: Can I use both Docker and Ollama?
**A**: Technically yes, but they use different ports (12434 vs 11434). However, the setup script only supports Ollama as of v4.1.

### Q: What if I have custom Docker models?
**A**: Pull them to Ollama:
```bash
# List Docker models
docker model ls

# Pull equivalent in Ollama
ollama pull <model-name>

# Example: If you had custom finetuned model
# You'll need to re-import it to Ollama's format
```

### Q: Can I restore the AI tuning feature?
**A**: The `tuning.py` module (213 lines) is available in git history. You could:
1. Restore `tuning.py` from `git show v4.0.0:docker/lib/tuning.py`
2. Modify `lib/config.py` to accept tuning profiles
3. Update `setup.py` to call tuning functions

However, Continue.dev's UI provides equivalent manual controls.

### Q: Will my Continue.dev configs be preserved?
**A**: The uninstaller creates backups:
- `config.yaml` → `config.yaml.backup`
- Restoration happens automatically if setup detects backups

### Q: What about my custom global rules?
**A**: Save them before migration:
```bash
cp ~/.continue/rules/global-rule.md ~/my-custom-rules.md
```

After setup, merge your rules back:
```bash
cat ~/my-custom-rules.md >> ~/.continue/rules/global-rule.md
```

### Q: Is performance the same?
**A**: Ollama is generally **faster**:
- Dedicated LLM runtime (not Docker overhead)
- Optimized for Metal GPU on Apple Silicon
- Better memory management

### Q: Can I go back to Docker?
**A**: Yes, checkout `v4.0.0`:
```bash
git checkout v4.0.0
cd ai_model/docker
python3 docker-llm-setup.py
```

## Getting Help

### Check Status
```bash
# Ollama service status
ollama ps

# Ollama logs
tail -f ~/.ollama/logs/server.log

# Continue.dev config
cat ~/.continue/config.yaml

# Test API
curl http://127.0.0.1:11434/api/tags
```

### Common Issues

**"Apple Silicon required" error:**
- Current code only supports M1/M2/M3/M4 Macs
- See "Platform Support" section for workarounds

**Ollama models not pulling:**
- Check disk space: `df -h` (need 20GB+)
- Check internet connection
- Try manual pull: `ollama pull gpt-oss:20b`

**Continue.dev not connecting:**
- Verify endpoint in `~/.continue/config.yaml`
- Should be `http://127.0.0.1:11434/v1` (not 12434)
- Restart Ollama: `pkill ollama && ollama serve`

### Support Channels

- **GitHub Issues**: [Repository Issues](https://github.com/[your-repo]/issues)
- **Ollama Docs**: https://ollama.com/docs
- **Continue.dev Docs**: https://continue.dev/docs

## Summary

**Migration Checklist:**
- [ ] Uninstall Docker setup (`python3 docker/docker-llm-uninstall.py`)
- [ ] Backup custom Continue.dev rules
- [ ] Pull latest code (`git pull` or `git checkout refactor/ollama-only`)
- [ ] Run Ollama setup (`python3 setup.py`)
- [ ] Verify models installed (`ollama list`)
- [ ] Test Continue.dev connection
- [ ] Restore custom rules if needed

**Key Changes:**
- ✅ Simpler codebase (-40% lines of code)
- ✅ Single backend (Ollama)
- ✅ Faster installation
- ✅ Better maintainability
- ❌ Lost AI tuning presets (use Continue.dev UI instead)
- ❌ Docker Model Runner no longer supported

**Migration Time**: ~15 minutes

---

**Questions?** Open an issue or see README.md for detailed documentation.
