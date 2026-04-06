# OpenCode Refactoring Plan

## Goal
Refactor ai_model from Continue.dev multi-model setup to OpenCode single-model setup with user choice.

## Current State (v4.1 - Ollama-only)
- **IDE**: Continue.dev (VS Code/Cursor/IntelliJ)
- **Models**: Fixed (GPT-OSS 20B + nomic-embed-text)
- **Selection**: Hardware-based automatic selection
- **Config**: `~/.continue/config.yaml` and `config.json`
- **Architecture**: Ollama backend only

## Target State (v5.0 - OpenCode)
- **IDE**: IntelliJ with OpenCode plugin
- **Models**: Gemma4 variants (user selects from list)
- **Selection**: Hardware recommendation + user choice
- **Config**: OpenCode plugin settings (IntelliJ)
- **Architecture**: Ollama backend (unchanged)
- **Platform**: Mac Silicon optimized

---

## Model Catalog

### Available Gemma4 Models
Based on user requirements:

| Model | Size | RAM Required | Use Case |
|-------|------|-------------|----------|
| `gemma4:e2b` | 2B | 4-8 GB | Low-end, fast responses |
| `gemma4:e4b` | 4B | 8-12 GB | Balanced performance |
| `VladimirGav/gemma4-26b-16GB-VRAM:latest` | 26B | 16+ GB | **Recommended for 16GB+ Mac** |
| `gemma4:26b` | 26B | 16+ GB | Standard 26B variant |
| `gemma4:31b` | 31B | 24+ GB | High-end, best quality |

**Default recommendation**: `VladimirGav/gemma4-26b-16GB-VRAM:latest` for systems with 16GB+ RAM

---

## Files to Modify

### 1. `lib/model_selector.py` - Complete rewrite
**Current**: Fixed models, hardware-based selection
**New**: Interactive menu with hardware recommendation

```python
GEMMA4_MODELS = [
    {
        "name": "Gemma4 2B (Efficient)",
        "ollama_name": "gemma4:e2b",
        "ram_gb": 2.5,
        "min_ram_required": 4,
        "max_ram_recommended": 12,
        "description": "Fast, efficient model for basic coding tasks"
    },
    {
        "name": "Gemma4 4B (Balanced)",
        "ollama_name": "gemma4:e4b",
        "ram_gb": 4.5,
        "min_ram_required": 8,
        "max_ram_recommended": 16,
        "description": "Balanced performance and quality"
    },
    {
        "name": "Gemma4 26B (Optimized for 16GB VRAM)",
        "ollama_name": "VladimirGav/gemma4-26b-16GB-VRAM:latest",
        "ram_gb": 16,
        "min_ram_required": 16,
        "max_ram_recommended": 32,
        "description": "Optimized 26B model for Mac Silicon with 16GB+ RAM",
        "recommended": True
    },
    {
        "name": "Gemma4 26B (Standard)",
        "ollama_name": "gemma4:26b",
        "ram_gb": 16,
        "min_ram_required": 16,
        "max_ram_recommended": 32,
        "description": "Standard 26B model, high quality"
    },
    {
        "name": "Gemma4 31B (Maximum Quality)",
        "ollama_name": "gemma4:31b",
        "ram_gb": 20,
        "min_ram_required": 24,
        "max_ram_recommended": 64,
        "description": "Largest model, best quality for high-RAM systems"
    }
]

def select_model_interactive(hw_info: HardwareInfo) -> dict:
    """Display model selection menu with hardware recommendation."""
    # Show available RAM
    # Highlight recommended model based on RAM
    # Let user choose from numbered list
    # Return selected model dict
    pass
```

### 2. `lib/config.py` - OpenCode configuration
**Current**: Generate Continue.dev YAML/JSON
**New**: Configure OpenCode plugin for IntelliJ

**OpenCode Config Location** (need to verify):
- Likely: `~/.config/JetBrains/IntelliJIdea*/opencode/` or
- IntelliJ settings: `Settings → Tools → OpenCode`
- Possibly uses Ollama API endpoint directly without separate config

**Implementation**:
```python
def configure_opencode(model_name: str, hw_info: HardwareInfo) -> Path:
    """
    Configure OpenCode plugin to use selected Ollama model.

    OpenCode likely uses:
    - Ollama API endpoint: http://localhost:11434
    - Model name: specified in plugin settings
    - May use IntelliJ's settings XML or a JSON config
    """
    # Generate OpenCode configuration
    # Set model name
    # Set endpoint
    # Set Mac Silicon optimizations
    pass
```

### 3. `lib/ide.py` - IntelliJ/OpenCode detection
**Current**: Detect Continue.dev, VS Code, Cursor
**New**: Detect IntelliJ IDEA, verify OpenCode plugin

```python
def detect_intellij() -> Tuple[bool, Optional[Path]]:
    """Detect IntelliJ IDEA installation on Mac."""
    # Check /Applications/IntelliJ IDEA*.app
    # Check ~/Library/Application Support/JetBrains/
    pass

def verify_opencode_plugin() -> bool:
    """Check if OpenCode plugin is installed in IntelliJ."""
    # Check plugin directory
    # Check IntelliJ plugin list
    pass
```

### 4. `setup.py` - New flow
**Current flow**:
1. Detect hardware
2. Automatically select models (fixed)
3. Pull models
4. Configure Continue.dev

**New flow**:
1. Detect hardware (Mac Silicon check)
2. Display model selection menu
3. Recommend model based on RAM
4. Let user choose model
5. Pull selected model (single model only)
6. Detect IntelliJ + OpenCode
7. Configure OpenCode
8. Display setup instructions

### 5. `lib/models.py` - Update catalog
**Remove**: GPT-OSS, Qwen2.5, StarCoder2, etc.
**Add**: Gemma4 variants only

### 6. `lib/hardware.py` - No major changes
Keep Apple Silicon detection, just update recommendations.

### 7. `lib/validator.py` - Minor changes
Remove multi-model pulling logic (already refactored).

### 8. `lib/uninstaller.py` - Minor updates
Update for single-model uninstall.

---

## Implementation Phases

### Phase 1: Model Selection (lib/model_selector.py)
- [ ] Create GEMMA4_MODELS catalog
- [ ] Implement `select_model_interactive()` with menu
- [ ] Add hardware-based recommendation logic
- [ ] Test model selection UI

### Phase 2: OpenCode Configuration (lib/config.py)
- [ ] Research OpenCode config format
- [ ] Implement `configure_opencode()`
- [ ] Generate config file/settings
- [ ] Add Mac Silicon optimizations

### Phase 3: IDE Detection (lib/ide.py)
- [ ] Implement IntelliJ detection
- [ ] Implement OpenCode plugin verification
- [ ] Add installation instructions

### Phase 4: Setup Flow (setup.py)
- [ ] Update main flow to single-model selection
- [ ] Add interactive menu
- [ ] Remove Continue.dev references
- [ ] Add OpenCode setup instructions

### Phase 5: Documentation
- [ ] Update README.md
- [ ] Create OPENCODE_SETUP_GUIDE.md
- [ ] Update CLAUDE.md

### Phase 6: Testing
- [ ] Test on Mac Silicon (16GB, 24GB, 32GB)
- [ ] Verify OpenCode integration
- [ ] Test each Gemma4 model variant

---

## Breaking Changes

**Users upgrading from v4.1 → v5.0 will need to:**
1. Uninstall Continue.dev setup (if they had it)
2. Install IntelliJ IDEA (if not already)
3. Install OpenCode plugin
4. Run new setup script
5. Select Gemma4 model

**Migration**: Not automatic - this is a complete pivot to a different IDE and model family.

---

## OpenCode Plugin Details (To Research)

**Questions to answer:**
1. How does OpenCode connect to Ollama? (API endpoint? Config file?)
2. Where are OpenCode settings stored? (XML? JSON? IntelliJ settings?)
3. Does OpenCode auto-detect Ollama models or need explicit config?
4. Are there Mac Silicon-specific settings?
5. Does it support model parameters (temperature, context length)?

**Resources:**
- https://plugins.jetbrains.com/plugin/30681-opencode
- https://gist.github.com/greenstevester/fc49b4e60a4fef9effc79066c1033ae5
- OpenCode GitHub repo (if exists)
- IntelliJ plugin settings XML format

---

## Next Steps

1. **Research OpenCode config format** (manual testing or documentation)
2. **Start Phase 1** (model selector refactoring)
3. **Test with actual IntelliJ + OpenCode**
4. **Iterate based on findings**

---

**Status**: Planning phase
**Branch**: Create new `feature/opencode-gemma4` branch
**Target version**: v5.0.0
**Estimated effort**: 1-2 days
