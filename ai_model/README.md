# Gemma4 + OpenCode Setup for IntelliJ IDEA

Automated setup for **Gemma4 models** with **OpenCode plugin** in IntelliJ IDEA. Optimized for Apple Silicon Macs (M1/M2/M3/M4) using Ollama.

## 🎯 Overview

This project provides an interactive setup for running Gemma4 LLMs locally with OpenCode in IntelliJ IDEA. It:

- **Detects** your Apple Silicon Mac hardware (CPU, RAM, Metal GPU)
- **Presents** 5 Gemma4 model options with hardware-based recommendations
- **Pulls** your selected model + optional embedding model
- **Optimizes** model parameters for Mac Silicon performance
- **Guides** you through OpenCode plugin configuration

**Version 5.0**: Focused on single-model selection with Gemma4 family and OpenCode plugin for IntelliJ IDEA.

## ✨ Features

### Core Functionality
- **Interactive Model Selection**: Choose from 5 Gemma4 variants (2B to 31B)
- **Hardware-Based Recommendations**: Suggests optimal model for your RAM
- **Mac Silicon Optimization**: Tuned parameters (temperature, context length, top-k)
- **Optional Embedding Model**: nomic-embed-text for semantic code search
- **OpenCode Integration**: Step-by-step configuration guide

### Available Gemma4 Models
| Model | Size | RAM Required | Best For |
|-------|------|-------------|----------|
| **gemma4:e2b** | 2B | 4GB+ | Low RAM systems, fast responses |
| **gemma4:e4b** | 4B | 8GB+ | Balanced performance |
| **VladimirGav/gemma4-26b-16GB-VRAM:latest** | 26B | 16GB+ | **Recommended for 16GB+ Mac** ⭐ |
| **gemma4:26b** | 26B | 16GB+ | Standard 26B variant |
| **gemma4:31b** | 31B | 24GB+ | Maximum quality for high-RAM systems |

### Mac Silicon Optimization
Parameters are automatically optimized based on your chip and RAM:

**M4/M3 with 24GB+ RAM:**
- Temperature: 0.8
- Context Length: 16,384 tokens
- Top-K: 50

**M4/M3 with 16GB RAM:**
- Temperature: 0.75
- Context Length: 12,288 tokens
- Top-K: 45

**M2/M1 with 24GB+ RAM:**
- Temperature: 0.75
- Context Length: 12,288 tokens

**M2/M1 with 16GB RAM:**
- Temperature: 0.7
- Context Length: 8,192 tokens

## 📦 Requirements

### System Requirements
- **macOS**: Apple Silicon (M1/M2/M3/M4) required
- **RAM**: 16GB minimum (24GB+ recommended for 26B+ models)
- **Python**: 3.8 or higher
- **IntelliJ IDEA**: Community or Ultimate Edition
- **Ollama**: Installed automatically if not present

### Platform Support
- ✅ **macOS (Apple Silicon)**: Full support with Metal GPU acceleration
- ❌ **Linux/Windows/Intel Mac**: Not currently supported

## 🚀 Quick Start

```bash
# Navigate to project directory
cd ai_model

# Run interactive setup
python3 setup.py

# Follow the prompts to:
# 1. Select your Gemma4 model (recommended model will be highlighted)
# 2. Choose whether to install embedding model (recommended)
# 3. Wait for model download
# 4. Follow OpenCode configuration instructions
```

### Example Setup Flow

```
🚀 Ollama + OpenCode Setup v5.0
Gemma4 models for IntelliJ IDEA
Optimized for Mac Silicon

Ready to begin setup? [Y/n]: y

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Hardware Detection
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Detected: Apple M4
  CPU: Apple M4 (10 cores: 4P+6E)
  RAM: 16.0 GB
  GPU: Apple M4 (10 GPU cores)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  📦 Model Selection
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Detected: Apple M4
  Total RAM:       16 GB
  Available RAM:   ~9 GB (for AI models)

Available Gemma4 models:

  1. Gemma4 2B (Efficient)
     gemma4:e2b
     ✓ RAM: 2.5 GB (requires 4+ GB system RAM)
     Fast, efficient model for basic coding tasks.

  2. Gemma4 4B (Balanced)
     gemma4:e4b
     ✓ RAM: 4.5 GB (requires 8+ GB system RAM)
     Balanced performance and quality.

  3. Gemma4 26B (Optimized for 16GB VRAM) ★ RECOMMENDED
     VladimirGav/gemma4-26b-16GB-VRAM:latest
     ✓ RAM: 16.0 GB (requires 16+ GB system RAM)
     Optimized 26B model for Mac Silicon with 16GB+ RAM.

  4. Gemma4 26B (Standard)
     gemma4:26b
     ✓ RAM: 16.0 GB (requires 16+ GB system RAM)
     Standard 26B model, high quality code generation.

  5. Gemma4 31B (Maximum Quality)
     gemma4:31b
     ✗ RAM: 20.0 GB (requires 24+ GB system RAM)
     Largest model, best quality for high-RAM systems.

Recommended: Option 3 (Gemma4 26B (Optimized for 16GB VRAM))

Select model (1-5) or press Enter for recommended [3]: ⏎

✓ Selected: Gemma4 26B (Optimized for 16GB VRAM)
  Model: VladimirGav/gemma4-26b-16GB-VRAM:latest
  Size: 26B
  RAM Usage: ~16.0 GB

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Embedding Model (Optional)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

An embedding model enables semantic code search:
  • Ask 'how does authentication work?' → finds relevant files
  • Understands code meaning, not just keywords
  • Model: nomic-embed-text (274 MB)

Install embedding model for code search? [Y/n]: y

📥 Downloading Models

[1/2] Pulling VladimirGav/gemma4-26b-16GB-VRAM:latest...
⠋ Pulling VladimirGav/gemma4-26b-16GB-VRAM:latest ▕████████████▏ 45% 8.2GB/16GB 25MB/s 5m12s

✓ Downloaded VladimirGav/gemma4-26b-16GB-VRAM:latest

[2/2] Pulling nomic-embed-text...
✓ Downloaded nomic-embed-text

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ⚙️ Configuration
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✓ Generated reference config: ~/.opencode/opencode-config.json
✓ Created manifest: ~/.opencode/setup-manifest.json

🔧 OpenCode Configuration

OpenCode is configured through IntelliJ IDEA settings.
Follow these steps to complete setup:

1. Install OpenCode Plugin:
   • Open IntelliJ IDEA
   • Go to: Preferences → Plugins (Cmd+,)
   • Click 'Marketplace' tab
   • Search for 'OpenCode'
   • Click 'Install' and restart IntelliJ
   • Plugin URL: https://plugins.jetbrains.com/plugin/30681-opencode

2. Configure Ollama Connection:
   • In IntelliJ, open OpenCode settings
   • Set Ollama API endpoint:
     http://127.0.0.1:11434

3. Select Gemma4 Model:
   • In OpenCode settings, choose model:
     VladimirGav/gemma4-26b-16GB-VRAM:latest

4. Optimize Model Parameters:
   • Temperature: 0.75
   • Context Length: 12288 tokens
   • Top-K: 45
   • Top-P: 0.9

   (Optimized for Apple M4 with 16GB RAM)

5. Configure Embedding Model (Optional):
   • For semantic code search, configure:
     nomic-embed-text
   • Temperature: 0.0 (deterministic)

6. Verify Setup:
   • Open any code file in IntelliJ
   • Activate OpenCode (check plugin toolbar/menu)
   • Ask a coding question to test the connection

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Setup Complete!

Next steps:
  1. Open IntelliJ IDEA
  2. Install OpenCode plugin (if not already)
  3. Configure OpenCode using the instructions above
  4. Start coding with AI assistance!
```

## 📖 Detailed Usage

### Setup Script
```bash
python3 setup.py
```

**Interactive Steps:**
1. **Hardware Detection**: Detects your Mac Silicon chip and RAM
2. **IDE Detection**: Checks for IntelliJ IDEA and OpenCode plugin
3. **Model Selection**: Shows 5 Gemma4 models with recommendations
4. **Embedding Model**: Optional semantic search capability
5. **Pre-flight Checks**: Verifies Ollama is installed and running
6. **Model Download**: Pulls selected models with progress bars
7. **Configuration**: Generates reference config and setup instructions
8. **Completion**: Provides step-by-step OpenCode configuration guide

### Uninstall Script
```bash
python3 uninstall.py
```

**What it does:**
1. Loads installation manifest from `~/.opencode/setup-manifest.json`
2. Removes installed Gemma4 models
3. Removes embedding model (if installed)
4. Cleans up configuration files
5. Optionally uninstalls Ollama completely

### Check Status
```bash
# List installed models
ollama list

# Test Gemma4 model
ollama run VladimirGav/gemma4-26b-16GB-VRAM:latest "Write hello world in Python"

# Test embedding model
ollama run nomic-embed-text "test embedding"

# Check Ollama service
curl http://127.0.0.1:11434/api/tags
```

## 🔧 Configuration

### Reference Config File
Setup creates `~/.opencode/opencode-config.json` with your optimized settings:

```json
{
  "version": "1.0",
  "ollama": {
    "api_base": "http://127.0.0.1:11434",
    "models": {
      "chat": {
        "name": "VladimirGav/gemma4-26b-16GB-VRAM:latest",
        "parameters": {
          "temperature": 0.75,
          "top_p": 0.9,
          "top_k": 45,
          "num_ctx": 12288,
          "repeat_penalty": 1.1
        }
      },
      "embedding": {
        "name": "nomic-embed-text",
        "parameters": {
          "temperature": 0.0,
          "top_k": 1
        }
      }
    }
  },
  "hardware": {
    "chip": "M4",
    "ram_gb": 16,
    "optimized": true
  }
}
```

**Note**: This file is for reference only. OpenCode is configured through IntelliJ IDEA's settings UI, not by reading this file.

### OpenCode Settings Location

OpenCode stores settings in IntelliJ IDEA's configuration:
- **macOS**: `~/Library/Application Support/JetBrains/IntelliJIdea<version>/`
- **Linux**: `~/.config/JetBrains/IntelliJIdea<version>/`
- **Windows**: `%APPDATA%\JetBrains\IntelliJIdea<version>\`

You configure OpenCode through: **Preferences/Settings → Tools → OpenCode**

## 🧪 Testing

### Manual Testing
```bash
# Test model inference
ollama run VladimirGav/gemma4-26b-16GB-VRAM:latest "Explain Python decorators"

# Verify Ollama API
curl http://127.0.0.1:11434/api/tags | python3 -m json.tool

# Check model parameters
ollama show VladimirGav/gemma4-26b-16GB-VRAM:latest
```

### In IntelliJ IDEA
1. Open any code file
2. Activate OpenCode (toolbar or menu)
3. Ask: "Explain this function"
4. Verify model responds correctly
5. Test semantic search: "Find authentication code"

## 🎓 Model Details

### Gemma4 26B (Optimized for 16GB VRAM)

**Source**: [VladimirGav/gemma4-26b-16GB-VRAM](https://ollama.com/VladimirGav/gemma4-26b-16GB-VRAM)

**Optimizations**:
- Quantized for 16GB Mac Silicon systems
- Optimized inference speed on Metal GPU
- Balanced quality/performance tradeoff

**Use Cases**:
- Code completion and generation
- Code explanation and documentation
- Refactoring suggestions
- Bug detection and fixes

### Nomic Embed Text

**Source**: [nomic-embed-text](https://ollama.com/library/nomic-embed-text)

**Purpose**: Converts code into semantic embeddings for:
- Semantic code search ("find authentication logic")
- Context-aware suggestions
- Related file discovery
- Documentation matching

**Size**: 274 MB (lightweight, recommended for all setups)

## 🛠️ Troubleshooting

### Model Not Found
```bash
# Verify model is pulled
ollama list

# Re-pull if needed
ollama pull VladimirGav/gemma4-26b-16GB-VRAM:latest
```

### OpenCode Not Connecting
1. Check Ollama is running:
   ```bash
   curl http://127.0.0.1:11434/api/tags
   ```

2. Verify OpenCode settings:
   - API endpoint: `http://127.0.0.1:11434`
   - Model name matches exactly

3. Restart IntelliJ IDEA

### Out of Memory
If the selected model runs out of RAM:
- Choose a smaller model (4B or 2B)
- Close other applications
- Reduce context length in parameters

### Slow Performance
- **M1/M2 users**: Stick with 26B or smaller
- **Reduce context**: Lower `num_ctx` to 8192 or 4096
- **Disable embedding**: Skip nomic-embed-text if not needed

## 📂 Project Structure

```
ai_model/
├── lib/                      # Core library modules
│   ├── __init__.py
│   ├── config.py            # OpenCode configuration
│   ├── hardware.py          # Mac Silicon detection
│   ├── ide.py               # IntelliJ/OpenCode detection
│   ├── model_selector.py    # Gemma4 catalog & selection
│   ├── models.py            # Model definitions
│   ├── ollama.py            # Ollama service management
│   ├── ui.py                # Terminal UI utilities
│   ├── uninstaller.py       # Uninstall logic
│   ├── utils.py             # Shared utilities
│   └── validator.py         # Model pulling & verification
├── setup.py                 # Main setup script (230 lines)
├── uninstall.py             # Uninstall script
├── run_tests.py             # Test runner
├── tests/                   # Test suite
├── .gitignore
├── README.md                # This file
└── OPENCODE_REFACTORING_PLAN.md  # Development notes
```

## 🔄 Version History

### v5.0.0 (2026-04-06) - OpenCode & Gemma4
- **Breaking**: Complete pivot from Continue.dev to OpenCode
- **Added**: Interactive Gemma4 model selection (5 variants)
- **Added**: Mac Silicon parameter optimization
- **Added**: IntelliJ IDEA + OpenCode plugin support
- **Removed**: Continue.dev YAML/JSON generation
- **Removed**: Multi-model automatic selection
- **Changed**: User choice with hardware recommendations

### v4.1.0 (2026-04-05) - Ollama Only
- **Breaking**: Removed Docker Model Runner backend
- **Changed**: Fixed GPT-OSS 20B + nomic-embed-text for all users
- **Simplified**: Single backend architecture (-40% code)
- **Improved**: Validator refactoring (-343 lines, complexity 71 → 5)

### v4.0.0 (2026-04-04) - Dual Backend
- Supported both Docker Model Runner and Ollama
- Hardware-based tiering
- Continue.dev integration

## 🤝 Contributing

This is a personal project optimized for Mac Silicon + Gemma4 + OpenCode. If you want to:

- **Add Linux/Windows support**: Remove Apple Silicon validation in `model_selector.py`
- **Add other models**: Extend `GEMMA4_MODELS` catalog in `model_selector.py`
- **Support other IDEs**: Extend `ide.py` detection logic

## 📝 License

MIT License - See LICENSE file for details.

## 🔗 Resources

- **Ollama**: https://ollama.com
- **Gemma4 Models**: https://ollama.com/library/gemma4
- **VladimirGav Optimized 26B**: https://ollama.com/VladimirGav/gemma4-26b-16GB-VRAM
- **OpenCode Plugin**: https://plugins.jetbrains.com/plugin/30681-opencode
- **IntelliJ IDEA**: https://www.jetbrains.com/idea/
- **Nomic Embed Text**: https://ollama.com/library/nomic-embed-text

## 🙏 Acknowledgments

- **Google**: Gemma4 model family
- **VladimirGav**: Optimized 26B variant for 16GB systems
- **Ollama**: Local LLM runtime with Metal GPU support
- **JetBrains**: IntelliJ IDEA and plugin ecosystem
- **Nomic AI**: nomic-embed-text embedding model

---

**Ready to start?** Run `python3 setup.py` and choose your Gemma4 model! 🚀
