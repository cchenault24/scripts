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
- **Continue.dev Integration**: Auto-generated role-based configuration for agent planning, chat, edit, autocomplete, and embeddings
- **VS Code Optimized**: Settings, extensions, and prompts tailored for your stack
- **Production-Grade**: Idempotent, resumable, with comprehensive error handling
- **Fully Local**: No cloud APIs, no telemetry, works offline after setup

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

## Documentation

### Getting Started
- **[Installation Guide](docs/INSTALLATION.md)** - Prerequisites and installation steps
- **[Hardware Tiers](docs/HARDWARE_TIERS.md)** - Hardware tiers and model selection guide
- **[Continue.dev Setup](docs/CONTINUE_SETUP.md)** - Continue.dev configuration and usage
- **[VS Code Integration](docs/VSCODE_INTEGRATION.md)** - VS Code settings and extensions

### Usage & Tools
- **[Tools](docs/TOOLS.md)** - Available utilities (diagnose, benchmark, cleanup, etc.)
- **[Optimization](docs/OPTIMIZATION.md)** - Tuning, performance tips, and advanced optimizations
- **[Best Practices](docs/BEST_PRACTICES.md)** - Stack-specific coding best practices

### Reference
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[Security](docs/SECURITY.md)** - Security and privacy information
- **[Advanced Usage](docs/ADVANCED_USAGE.md)** - Custom configuration and advanced features
- **[Model Recommendations](docs/MODEL_RECOMMENDATIONS.md)** - Detailed model recommendations

## File Structure

```
ai_model/
├── setup-local-llm.sh          # Main setup script
├── tools/                      # Utility scripts
│   ├── diagnose.sh             # Health checks and diagnostics
│   ├── benchmark.sh           # Model performance testing
│   ├── cleanup.sh              # Memory cleanup utility
│   ├── update.sh               # Update Ollama and models
│   └── uninstall.sh            # Cleanup and removal
├── docs/                       # Documentation
│   ├── INSTALLATION.md         # Installation guide
│   ├── HARDWARE_TIERS.md       # Hardware tiers and models
│   ├── CONTINUE_SETUP.md       # Continue.dev setup
│   ├── VSCODE_INTEGRATION.md   # VS Code integration
│   ├── TOOLS.md                # Tool usage
│   ├── OPTIMIZATION.md         # Optimization guide
│   ├── TROUBLESHOOTING.md      # Troubleshooting
│   ├── BEST_PRACTICES.md       # Best practices
│   ├── SECURITY.md             # Security info
│   ├── ADVANCED_USAGE.md       # Advanced usage
│   └── MODEL_RECOMMENDATIONS.md # Model recommendations
├── lib/                        # Library functions
├── vscode/                     # VS Code configuration
│   ├── settings.json           # VS Code settings
│   └── extensions.json         # Extension recommendations
├── prompts/                    # Prompt templates
│   └── starter-prompts.md      # Stack-optimized prompts
└── README.md                   # This file
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
