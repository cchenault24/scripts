# Gemma4 + OpenCode Setup for Teams

Production-ready scripts for deploying Google's Gemma4 models with OpenCode via Ollama on macOS.

## Features

✨ **Hardware-Optimized** - Automatically detects your Mac's capabilities and configures optimal settings  
🎯 **Model Recommendations** - Suggests the best Gemma4 variant for your RAM  
🔧 **Complete Integration** - Sets up Ollama, OpenCode, and LaunchAgent  
🔄 **Idempotent** - Safe to run multiple times  
🗑️ **Clean Uninstall** - Comprehensive removal with backup support  

## Quick Start

### Installation

```bash
# Interactive setup (recommended for first-time users)
./setup-gemma4-opencode.sh

# Auto-detect and install (CI/CD friendly)
./setup-gemma4-opencode.sh --auto

# Force specific model
./setup-gemma4-opencode.sh --model gemma4:26b
```

### Uninstallation

```bash
# Interactive removal (choose what to keep)
./uninstall-gemma4-opencode.sh

# Complete removal with confirmation
./uninstall-gemma4-opencode.sh --complete

# Preview what would be removed
./uninstall-gemma4-opencode.sh --dry-run
```

## Available Models

| Model | Size | Context | RAM Required | Best For |
|-------|------|---------|--------------|----------|
| **gemma4:e2b** | 7.2GB | 128K | 12GB+ | Minimal RAM systems |
| **gemma4:latest** | 9.6GB | 128K | 16GB+ | Balanced performance |
| **gemma4:26b** | 17GB | 256K | 32GB+ | Large context needs |
| **gemma4:31b** | 19GB | 256K | 48GB+ | Maximum quality |

*Source: https://ollama.com/library/gemma4/tags*

## Requirements

- macOS (Apple Silicon recommended)
- Homebrew installed
- Minimum 12GB RAM (16GB+ recommended)
- 50GB+ free disk space

## What Gets Installed

### Applications (via Homebrew)
- **Ollama** - Local LLM runtime
- **OpenCode** - AI coding assistant CLI

### Configuration
- **LaunchAgent** - Auto-starts Ollama on boot with optimized settings
- **OpenCode Config** - Pre-configured for your hardware
- **Custom Model** - Hardware-optimized variant (e.g., gemma4-optimized-31b) with tuned context window

### Optimizations (Hardware-Dependent)
- Metal GPU memory allocation (70-75% of total RAM)
- Parallel request handling (1-6 concurrent)
- Context window (128K-256K tokens based on model and RAM)
- Flash attention, GPU layers, keep-alive

## Usage Examples

### Setup Script

```bash
# View help and available options
./setup-gemma4-opencode.sh --help

# Interactive with hardware detection
./setup-gemma4-opencode.sh
# Shows detected hardware and recommends optimal model

# Automated setup (no prompts)
./setup-gemma4-opencode.sh --auto

# Override recommended model
./setup-gemma4-opencode.sh --model gemma4:e2b
./setup-gemma4-opencode.sh --model gemma4:latest
./setup-gemma4-opencode.sh --model gemma4:26b
./setup-gemma4-opencode.sh --model gemma4:31b
```

### Uninstall Script

```bash
# Interactive mode - choose what to remove
./uninstall-gemma4-opencode.sh

# Complete removal (everything)
./uninstall-gemma4-opencode.sh --complete

# Keep models but remove everything else
./uninstall-gemma4-opencode.sh --keep-models

# Keep configs but remove apps and models
./uninstall-gemma4-opencode.sh --keep-configs

# Keep apps but remove configs and models
./uninstall-gemma4-opencode.sh --keep-apps

# Dry-run to preview changes
./uninstall-gemma4-opencode.sh --dry-run

# Non-interactive complete removal (CI/CD)
./uninstall-gemma4-opencode.sh --complete --yes
```

## Interactive Setup Example

```
$ ./setup-gemma4-opencode.sh

========================================
Hardware Detection & Model Recommendation
========================================

Detected Hardware:
  • Chip:      M3
  • RAM:       64GB
  • CPU Cores: 12

Recommended Model: gemma4:31b

Available Gemma4 models:
  1. gemma4:31b    (19GB model, 256K context, requires 48GB+ RAM)
  2. gemma4:26b    (17GB model, 256K context, requires 32GB+ RAM)
  3. gemma4:latest (9.6GB model, 128K context, requires 16GB+ RAM)
  4. gemma4:e2b    (7.2GB model, 128K context, smallest)

Use recommended model gemma4:31b? (Y/n)
```

## Interactive Uninstall Example

```
$ ./uninstall-gemma4-opencode.sh

========================================
Detecting Installed Components
========================================

ℹ ✓ Ollama installed: ollama version 0.1.26
ℹ ✓ OpenCode installed: 0.2.4
ℹ ✓ LaunchAgent configured: /Users/you/Library/LaunchAgents/com.ollama.custom.plist
ℹ   Status: Loaded and running
ℹ ✓ OpenCode config exists: /Users/you/.config/opencode
ℹ ✓ Ollama models directory: /Users/you/.ollama
ℹ   Files: 487, Size: 18GB

========================================
Uninstallation Options
========================================

What would you like to remove?

1. Complete removal (everything)
2. Applications only (Ollama + OpenCode)
3. Configurations only (keep apps and models)
4. Models only (keep apps and configs)
5. LaunchAgent only (keep everything else)
6. Custom selection (choose each component)
7. Cancel

Enter your choice (1-7):
```

## After Installation

### Launch OpenCode
```bash
opencode
```

### Test the Model
```bash
# Custom model name includes the base model variant
ollama run gemma4-optimized-31b  # Or gemma4-optimized-26b, gemma4-optimized-latest, etc.
```

### Check Status
```bash
# Server health
curl http://localhost:11434/api/tags

# View logs
tail -f ~/.local/var/log/ollama.stdout.log

# List models
ollama list
```

### Manage Server
```bash
# Restart
launchctl unload ~/Library/LaunchAgents/com.ollama.custom.plist
launchctl load ~/Library/LaunchAgents/com.ollama.custom.plist

# Stop
launchctl unload ~/Library/LaunchAgents/com.ollama.custom.plist

# Start
launchctl load ~/Library/LaunchAgents/com.ollama.custom.plist
```

## Hardware Optimization Details

The setup script dynamically configures:

### Metal Memory
- Allocates 75% of available RAM
- Capped at 80GB max
- Leaves headroom for macOS

### Parallel Requests
| RAM | Parallel Requests |
|-----|-------------------|
| 16-23GB | 1 |
| 24-31GB | 2 |
| 32-47GB | 3-4 |
| 48-63GB | 4 |
| 64GB+ | 6 |

### Context Window
Respects model's native capabilities:
- **e2b, latest**: Up to 128K tokens
- **26b, 31b**: Up to 256K tokens

Reduced automatically if insufficient RAM.

## Backup and Restoration

### Automatic Backups
The uninstaller automatically backs up:
- LaunchAgent configuration
- OpenCode configs
- Model list (for reference)

Backup location: `~/gemma4-opencode-backup-<timestamp>/`

### Manual Restoration
```bash
# LaunchAgent
cp ~/gemma4-opencode-backup-*/LaunchAgent/com.ollama.custom.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.ollama.custom.plist

# OpenCode config
cp -R ~/gemma4-opencode-backup-*/configs/opencode ~/.config/

# Reinstall apps
brew install ollama anomalyco/tap/opencode

# Re-pull models (see models_list.txt in backup)
ollama pull gemma4:31b
```

## Troubleshooting

### OpenCode can't connect
```bash
# Check if Ollama is running
curl http://localhost:11434/api/tags

# Check LaunchAgent status
launchctl list | grep ollama

# View logs
tail -f ~/.local/var/log/ollama.stderr.log
```

### Out of memory errors
```bash
# Use a smaller model
./setup-gemma4-opencode.sh --model gemma4:e2b

# Or check current settings
cat ~/Library/LaunchAgents/com.ollama.custom.plist
```

### Model is slow
```bash
# Check GPU usage in Activity Monitor
# Should see high GPU utilization during inference

# Verify all GPU layers enabled
# Check OLLAMA_GPU_LAYERS=999 in LaunchAgent plist
```

### Re-run setup
```bash
# Safe to run again - it's idempotent
./setup-gemma4-opencode.sh
```

## Team Deployment

### Share with your team
```bash
# Clone or download these scripts
git clone <your-repo>
cd ai_model

# Each team member runs
./setup-gemma4-opencode.sh --auto
```

### CI/CD Integration
```bash
# Automated setup (no prompts)
./setup-gemma4-opencode.sh --auto --model gemma4:latest

# Automated teardown
./uninstall-gemma4-opencode.sh --complete --yes
```

## Documentation

- **Ollama**: https://docs.ollama.com/
- **OpenCode**: https://opencode.ai/docs/
- **Gemma**: https://ai.google.dev/gemma
- **Models**: https://ollama.com/library/gemma4/tags

## Files

```
ai_model/
├── setup-gemma4-opencode.sh      # Installation script
├── uninstall-gemma4-opencode.sh  # Uninstallation script
└── README.md                      # This file
```

## License

MIT License - See [LICENSE](../LICENSE) file for details.

## Support

For issues or questions:
1. Check the troubleshooting section above
2. View logs in `~/.local/var/log/ollama.*.log`
3. Run with `--help` flag for options

---

**Last Updated**: 2026-04-09  
**Version**: 1.0.0
