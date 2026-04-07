# Project Structure

Organized directory structure for the Comprehensive Local LLM Setup system.

## Directory Layout

```
ai_model/
├── 📄 README.md                    # Main documentation
├── 📄 STRUCTURE.md                 # This file
├── 📄 .gitignore                   # Git ignore rules
│
├── 🚀 Main Scripts (User-facing)
│   ├── setup.sh                   # Main installation script
│   ├── llama-control.sh           # Server management (start/stop/status/health/metrics)
│   ├── switch-model.sh            # Change active model + auto-update configs
│   ├── compare-models.sh          # Display installed models in table
│   ├── install-model-pack.sh      # Install preset model packs
│   ├── benchmark.sh               # Performance testing with 4 standard tests
│   ├── diagnose.sh                # Automated troubleshooting (8 checks)
│   └── uninstall.sh               # Comprehensive uninstaller
│
├── 📚 lib/ - Core Libraries
│   ├── common.sh                  # Hardware detection, utilities, print functions
│   ├── model-families.sh          # 13 models across 4 families, security filters
│   ├── model-selection.sh         # Intelligent 2-stage selection with RAM filtering
│   ├── ollama-setup.sh            # Build Ollama with Apple Silicon optimizations
│   ├── continue-setup.sh          # Configure Continue.dev for JetBrains/VS Code
│   ├── webui-setup.sh             # Setup Open WebUI Docker container
│   └── opencode-setup.sh          # Install and configure OpenCode CLI
│
├── 📖 docs/ - Documentation
│   ├── MODEL_GUIDE.md             # Model selection guide with decision trees
│   ├── CLIENT_SETUP.md            # Continue.dev, WebUI, OpenCode setup guides
│   ├── TROUBLESHOOTING.md         # 14 common issues with solutions
│   └── TEAM_DEPLOYMENT.md         # Enterprise deployment guide
│
├── ⚙️ presets/ - Configuration Presets
│   ├── README.md                  # Preset usage guide
│   ├── developer.env              # Codestral-focused for code generation
│   ├── researcher.env             # Llama 70B for quality
│   └── production.env             # Balanced Llama 11B
│
├── 🧪 tests/ - Testing Suite
│   ├── quality-checks.sh          # Shellcheck, security, optimizations (8 checks)
│   ├── integration-test.sh        # Full end-to-end testing
│   ├── test-ollama-setup.sh       # Ollama build/server tests
│   ├── test-compare-models.sh     # Model comparison utility tests
│   ├── test-switch-model.sh       # Model switching tests
│   ├── test-model-selection.sh    # Selection UI tests
│   ├── test-model-selection-comprehensive.sh  # Comprehensive selection tests
│   └── test-setup.sh              # Main setup script tests
│
├── 💡 examples/ - Example Scripts
│   └── demo-model-selection.sh    # Interactive demo of model selection
│
└── 📦 archive/ - Planning Documents
    ├── comprehensive-llm-setup.md  # Original planning doc
    └── multi-model-llm-setup.md    # Alternative planning approach
```

## File Categories

### Main Scripts (Root Level)
These are the scripts your team will use directly:
- **setup.sh** - Single command to install everything
- **llama-control.sh** - Manage the Ollama server
- **switch-model.sh** - Change models on the fly
- **compare-models.sh** - See what's installed
- **install-model-pack.sh** - Quick install with presets
- **benchmark.sh** - Test performance
- **diagnose.sh** - Fix problems automatically
- **uninstall.sh** - Clean removal

### Libraries (lib/)
Modular components sourced by main scripts:
- All `.sh` files can be sourced individually
- Follow common naming and style conventions
- Export functions for use in other scripts

### Documentation (docs/)
Comprehensive guides for different audiences:
- **MODEL_GUIDE.md** - Choose the right model
- **CLIENT_SETUP.md** - Configure your IDE/browser/CLI
- **TROUBLESHOOTING.md** - Solve common problems
- **TEAM_DEPLOYMENT.md** - Deploy to your team

### Presets (presets/)
Pre-configured setups for common use cases:
- **developer.env** - Code-focused (Codestral)
- **researcher.env** - Quality-focused (Llama 70B)
- **production.env** - Balanced (Llama 11B)

### Tests (tests/)
Quality assurance and validation:
- **quality-checks.sh** - Static analysis, security audits
- **integration-test.sh** - Full workflow testing
- **test-*.sh** - Individual component tests

### Examples (examples/)
Reference implementations and demos:
- **demo-model-selection.sh** - See selection in action

### Archive (archive/)
Historical planning documents:
- Kept for reference, not part of active codebase
- Ignored by git (.gitignore)

## Design Principles

1. **Modular Architecture**
   - Core functionality in `lib/` for reusability
   - Main scripts are thin orchestrators
   - Easy to maintain and extend

2. **User-Facing Scripts at Root**
   - Clear, discoverable entry points
   - Consistent naming conventions
   - Comprehensive help text

3. **Documentation First**
   - Every feature documented in `docs/`
   - README.md links to detailed guides
   - Self-service troubleshooting

4. **Testing Built-In**
   - All components have tests in `tests/`
   - Quality checks automated
   - Integration tests validate workflows

5. **Preset-Driven Deployment**
   - Common configurations in `presets/`
   - Easy team deployment
   - Consistent setups across machines

## Adding New Components

### New Main Script
```bash
# Create in root
touch new-utility.sh
chmod +x new-utility.sh

# Source common libraries
source "$(dirname "$0")/lib/common.sh"

# Add to README.md usage section
```

### New Library Function
```bash
# Add to appropriate lib/*.sh file
# Or create new lib file if needed

# Document in function comments
# Export for use by other scripts
```

### New Documentation
```bash
# Create in docs/
touch docs/NEW_GUIDE.md

# Link from README.md
# Cross-reference related docs
```

### New Preset
```bash
# Create in presets/
touch presets/custom.env

# Define: MODEL_FAMILY, MODEL, SETUP_CLIENTS
# Document in presets/README.md
```

### New Test
```bash
# Create in tests/
touch tests/test-new-feature.sh
chmod +x tests/test-new-feature.sh

# Add to integration-test.sh
# Run via ./tests/quality-checks.sh
```

## Maintenance

### Regular Updates
1. **Models** - Update `lib/model-families.sh` when new models released
2. **Documentation** - Keep docs/ in sync with features
3. **Tests** - Add tests for new functionality
4. **Presets** - Update presets/ for new best practices

### Version Control
- **Commit frequently** - Small, focused commits
- **Descriptive messages** - What and why
- **Co-authored** - Include Claude attribution
- **Branch strategy** - Feature branches for major changes

### Code Quality
- **Shellcheck** - Run `./tests/quality-checks.sh` before commit
- **Testing** - All tests pass before merge
- **Documentation** - Update relevant docs with code changes
- **Style** - Follow existing patterns and conventions

---

**Last Updated:** 2026-04-07
**Maintained By:** Development Team + Claude Sonnet 4.5
