# Testing Guide for ai_model Project

## Overview

Comprehensive test suite ensuring reliability and correctness of the AI model setup scripts.

## Test Coverage

### Unit Tests (80+ tests)

#### 1. Model Registry Tests (`test-model-registry.sh`)
**New** - Tests the single source of truth for all model specifications.

- ✅ Model weight lookups for all 15 models
- ✅ Context window specifications
- ✅ Minimum RAM requirements
- ✅ KV cache bytes per token calculations
- ✅ Display name formatting
- ✅ Coding priority rankings (benchmark-based)
- ✅ FIM model specifications
- ✅ Registry consistency validation
- ✅ Error handling for unknown models

**Key Tests:**
- All 15 models have complete specifications
- Coding priorities range 1-15 (gemma4:31b = 15, phi4-mini = 1)
- FIM priorities range 1-7 (codestral = 7, codegemma:2b = 1)
- Model weights are reasonable (1-50GB)
- Min RAM >= Model Weight + overhead

#### 2. Hardware Configuration Tests (`test-hardware-config.sh`)
Tests dynamic hardware optimization calculations.

- ✅ Metal memory allocation (95% for 32GB+, 90% for lower)
- ✅ KV cache size calculations
- ✅ GPU fit validation (ensures 100% GPU usage)
- ✅ Context length optimization (speed-optimized 8K-16K)
- ✅ Model recommendations (composite scoring: coding_priority × 10 + weight)
- ✅ FIM model recommendations
- ✅ Parallel request calculations (1-6 based on RAM)
- ✅ Headroom validation (8GB for 48GB+ systems, 6GB for 24-48GB, 4GB for <24GB)

**Key Tests:**
- 48GB RAM → gemma4:31b (not llama3.1:70b that leaves only 3.6GB headroom)
- Context sizes guarantee 100% GPU usage (no CPU/GPU split)
- Recommendations prioritize coding benchmarks (gemma4:31b over granite-code:34b)

#### 3. LaunchAgent Configuration Tests (`test-launchagent.sh`)
**New** - Tests LaunchAgent plist generation and validates only correct environment variables.

- ✅ Only 3 valid Ollama env vars: OLLAMA_HOST, OLLAMA_KEEP_ALIVE, OLLAMA_NUM_PARALLEL
- ✅ No invalid vars: OLLAMA_METAL_MEMORY, OLLAMA_GPU_LAYERS, OLLAMA_CONTEXT_LENGTH, OLLAMA_NUM_CTX, OLLAMA_FLASH_ATTENTION
- ✅ Plist XML validity (plutil -lint)
- ✅ RunAtLoad=true, KeepAlive=true
- ✅ Log paths point to .local/var/log
- ✅ Hardware-specific NUM_PARALLEL value
- ✅ Documentation explains optimizations are in Modelfile

**Key Tests:**
- Exactly 3 environment variables (no more, no less)
- Invalid variables from old version are gone
- Context length is baked into Modelfile, not LaunchAgent

#### 4. Model Warmup Tests (`test-model-warmup.sh`)
**New** - Tests model pre-loading functionality.

- ✅ warmup_model() function exists and documented
- ✅ Uses minimal prompt ("Hi") to trigger GPU load
- ✅ Reports warmup timing
- ✅ Checks if model already loaded (ollama ps)
- ✅ Interactive mode prompts user (Y/n, default Yes)
- ✅ Auto mode skips prompt
- ✅ Failure is non-fatal with helpful message
- ✅ Works with OLLAMA_KEEP_ALIVE=-1 to keep model resident
- ✅ Redirects output (doesn't spam user)
- ✅ Verbose mode shows additional info

**Key Tests:**
- First request is instant after warmup
- Declining warmup shows: "model will load on first request"
- Integration with LaunchAgent's KEEP_ALIVE=-1

#### 5. Input Validation Tests (`test-validation.sh`)
**Updated** - Tests input sanitization and security.

- ✅ All 15+ models from registry are valid
- ✅ Path traversal prevention (../../etc/passwd)
- ✅ Command injection prevention (; && | $() `` )
- ✅ Special character rejection (<script>, emojis, control chars)
- ✅ Unicode and encoding handling (null bytes, tabs, newlines)
- ✅ Case sensitivity (GEMMA4:E2B is invalid)
- ✅ Whitespace rejection (leading, trailing, internal)
- ✅ Multiple colon rejection (gemma4:e2b:extra)
- ✅ Length validation (very long names rejected)
- ✅ Format validation (family:variant required)

**Key Tests:**
- Dynamic validation against model registry (not hardcoded)
- Rejects Chinese models (qwen, deepseek) not in registry
- Length checks prevent buffer overflow attempts

### Integration Tests (40+ tests)

#### 6. Integration Tests (`test-integration.sh`)
Tests library interactions and system integration.

- ✅ Library sourcing without errors
- ✅ Hardware detection returns valid values
- ✅ Model recommendation flow
- ✅ Context length calculation flow
- ✅ Print functions produce output
- ✅ Byte conversion utilities
- ✅ Constants defined correctly
- ✅ Directory structure
- ✅ Script permissions
- ✅ GPU fit validation with recommended models

**Key Tests:**
- Recommended model fits on GPU with adequate headroom
- Hardware profile detection returns chip, RAM, cores
- All library functions work together correctly

### End-to-End Tests (15+ tests)

#### 7. E2E Interactive Flow Tests (`test-e2e-flow.sh`)
Tests complete user workflows.

- ✅ Interactive mode shows all prompts in correct order
- ✅ Auto mode skips all interactive prompts
- ✅ Model override works correctly
- ✅ Flag combinations work as expected
- ✅ User can exit/cancel at various points
- ✅ Help text is comprehensive
- ✅ Version information is correct

### Quality Checks (Critical)

#### 8. Quality Checks (`quality-checks.sh`)
Linting and security auditing.

- ✅ Shellcheck on all .sh files
- ✅ No bashisms in bash scripts
- ✅ Security audit (no hardcoded credentials, unsafe eval, etc.)
- ✅ Consistent shebang lines
- ✅ Error handling present (set -euo pipefail)

## Running Tests

### Run All Tests
```bash
./tests/run_all_tests.sh
```

### Run with Verbose Output
```bash
./tests/run_all_tests.sh --verbose
```

### Run Specific Test Suite
```bash
./tests/test-model-registry.sh
./tests/test-hardware-config.sh
./tests/test-launchagent.sh
./tests/test-model-warmup.sh
./tests/test-validation.sh
./tests/test-integration.sh
```

### Run with Verbose Output (Individual)
```bash
./tests/test-model-registry.sh --verbose
```

## Test Execution Order

Tests run in this order:
1. **Quality Checks** (critical) - Must pass before continuing
2. **Model Registry Tests** (unit) - Foundation for other tests
3. **Hardware Config Tests** (unit) - Core optimization logic
4. **LaunchAgent Tests** (unit) - Configuration correctness
5. **Model Warmup Tests** (unit) - Pre-loading functionality
6. **Validation Tests** (unit) - Input security
7. **Integration Tests** (integration) - Library interactions
8. **E2E Tests** (e2e) - Complete user workflows

## Test Requirements

### Required Tools
- bash 3.2+ (macOS default)
- plutil (macOS default) - for plist validation

### Optional Tools (warnings if missing)
- shellcheck - for linting
- jq - for JSON validation

Install optional tools:
```bash
brew install shellcheck jq
```

## Test Output

### Success
```
╔════════════════════════════════════════╗
║                                        ║
║   ✓ All tests passed successfully!     ║
║                                        ║
╚════════════════════════════════════════╝

Safe to commit changes.
```

### Failure
```
╔════════════════════════════════════════╗
║                                        ║
║   ✗ Some tests failed                  ║
║                                        ║
╚════════════════════════════════════════╝

Please fix the failing tests before committing.

Tip: Run with --verbose for detailed output:
  ./tests/run_all_tests.sh --verbose
```

## Coverage Summary

| Test Suite | Tests | Coverage |
|------------|-------|----------|
| Model Registry | 60+ | All 15 models, FIM models, lookups |
| Hardware Config | 30+ | Metal, KV cache, recommendations, headroom |
| LaunchAgent | 30+ | Plist generation, env vars, validation |
| Model Warmup | 35+ | Function, integration, timing, detection |
| Validation | 50+ | Security, sanitization, all models |
| Integration | 40+ | Library interactions, flows |
| E2E Flow | 15+ | Complete user workflows |
| Quality | 20+ | Linting, security, style |
| **Total** | **280+** | **Comprehensive coverage** |

## What's Tested vs What's Not

### ✅ Fully Tested
- Model registry lookups (all functions)
- Hardware optimization calculations
- LaunchAgent configuration
- Model warmup functionality
- Input validation and security
- Library interactions
- Script syntax and style
- Integration between components

### ⚠️ Partially Tested
- OpenCode JSON configuration (tested in integration, not unit)
- JetBrains config generation (tested in integration, not unit)
- Ollama service interaction (mocked in tests)

### ❌ Not Tested (Manual Testing Required)
- Actual model downloads from Ollama (requires network)
- Real GPU memory allocation (hardware-specific)
- LaunchAgent loading/unloading (requires system permissions)
- OpenCode/JetBrains runtime integration (requires IDEs)
- End-user interactive prompts (requires manual testing)

## Adding New Tests

### 1. Create Test File
```bash
cp tests/test-integration.sh tests/test-new-feature.sh
```

### 2. Update Test Header
```bash
# tests/test-new-feature.sh - Tests for new feature
#
# Tests:
# - Feature behavior 1
# - Feature behavior 2
```

### 3. Add to Test Runner
Edit `tests/run_all_tests.sh`:
```bash
TEST_SUITES=(
    ...
    "test-new-feature.sh|New Feature Tests|unit"
)
```

### 4. Make Executable
```bash
chmod +x tests/test-new-feature.sh
```

### 5. Run Tests
```bash
./tests/run_all_tests.sh
```

## Test Philosophy

1. **Fast** - Tests should run quickly (< 30s total)
2. **Isolated** - Each test is independent
3. **Deterministic** - Same input → same output
4. **Comprehensive** - Cover happy path + edge cases + errors
5. **Readable** - Test names describe what they test
6. **Maintainable** - Easy to add new tests
7. **Self-documenting** - Tests serve as documentation

## Continuous Integration

Tests are designed to run in CI/CD pipelines:

```bash
# In CI pipeline
./tests/run_all_tests.sh || exit 1
```

Exit codes:
- `0` = All tests passed
- `1` = One or more tests failed

## Troubleshooting

### Test Failures

1. Run with verbose output:
   ```bash
   ./tests/run_all_tests.sh --verbose
   ```

2. Run specific failing test:
   ```bash
   ./tests/test-model-registry.sh --verbose
   ```

3. Check for missing dependencies:
   ```bash
   brew install shellcheck jq
   ```

### Common Issues

- **"Model not in registry"** - Update lib/model-registry.sh
- **"Plist validation failed"** - Check XML syntax in lib/launchagent.sh
- **"Context too large for GPU"** - Adjust calculate_context_length() logic
- **"Invalid environment variable"** - Update LaunchAgent to remove invalid vars

## Test Maintenance

### When Adding a New Model
1. Add to lib/model-registry.sh (all lookup functions)
2. Run `./tests/test-model-registry.sh` to verify
3. Run `./tests/test-validation.sh` to ensure validation works

### When Changing Hardware Logic
1. Update lib/hardware-config.sh
2. Run `./tests/test-hardware-config.sh`
3. Update test expectations if calculations change

### When Modifying LaunchAgent
1. Update lib/launchagent.sh
2. Run `./tests/test-launchagent.sh`
3. Verify only valid env vars are set

## Future Test Additions

Potential tests to add:
- [ ] OpenCode JSON config unit tests
- [ ] JetBrains config generation unit tests
- [ ] Model download progress reporting
- [ ] Graceful degradation on limited hardware
- [ ] Interactive prompt edge cases
- [ ] Concurrent script execution handling
- [ ] Network failure scenarios
- [ ] Disk space validation
