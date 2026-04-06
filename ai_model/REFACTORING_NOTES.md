# Ollama-Only Refactoring Notes

## Day 1: Preparation & Analysis (Completed)

### Branch Created
- Branch: `refactor/ollama-only`
- Created: 2026-04-06

### Backend Comparison Analysis

**Docker-only files:**
- `docker.py` - Docker-specific backend implementation
- `tuning.py` - AI fine-tuning profiles (213 lines)

**Ollama-only files:**
- `ollama.py` - Ollama-specific backend implementation

**Common files (10 files):**
- `__init__.py`, `config.py`, `hardware.py`, `ide.py`, `model_selector.py`
- `models.py`, `ui.py`, `uninstaller.py`, `utils.py`, `validator.py`

### Tuning.py Analysis

**What it does:**
- Provides AI fine-tuning profiles (performance/balanced/quality presets)
- Hardware-aware parameter optimization (temperature, top_p, top_k, max_tokens, etc.)
- Adjusts LLM behavior based on RAM and Apple Silicon generation
- 213 lines of code

**Usage:**
- Docker: `generate_continue_config(model_list, hw_info, tuning_profile, target_ide, output_path)`
- Ollama: `generate_continue_config(model_list, hw_info, output_path, target_ide)` - NO tuning_profile

**Decision: DROP IT**

**Rationale:**
1. Ollama backend doesn't use it (different function signature)
2. Continue.dev allows manual parameter tuning in UI
3. Nice-to-have feature, not essential
4. Can add back later if users request it
5. Simplifies refactoring (don't need to port 213 lines)

### Next Steps (Day 2-3)
- Flatten directory structure
- Move `ollama/lib/*` → `lib/`
- Move `ollama/tests/*` → `tests/`
- Rename entry scripts
- Delete `docker/` directory
- Update imports

### Metrics
- **Before**: 11,000 lines across 2 backends
- **After (estimated)**: 6,500 lines with 1 backend
- **Reduction**: -40% LOC, -50% maintenance burden
