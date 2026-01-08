# Installation Guide

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
   - Continue.dev will automatically use the generated config at `~/.continue/config.yaml`

4. **Start coding with AI:**
   - Use `Cmd+L` to open Continue.dev chat
   - Use `Cmd+K` for inline edits
   - Try the starter prompts from `prompts/starter-prompts.md`

## Re-running Setup

The setup script is idempotent - safe to re-run. It will:
- Detect existing installation
- Offer to resume or start fresh
- Preserve your customizations where possible

To re-run auto-tuning:
```bash
./setup-local-llm.sh
```

## Next Steps

- See [Hardware Tiers](HARDWARE_TIERS.md) for model selection guidance
- See [Continue.dev Setup](CONTINUE_SETUP.md) for configuration details
- See [VS Code Integration](VSCODE_INTEGRATION.md) for editor setup
- See [Tools](TOOLS.md) for available utilities
