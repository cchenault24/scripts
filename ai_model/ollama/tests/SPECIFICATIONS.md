# Ollama Setup - Behavioral Specifications

This document defines the **expected behavior** for all critical functions.
Tests should validate against these specifications, NOT against current implementation.

**Key Principle:** Tests should FAIL if the code has a bug. If a test passes regardless
of the code's correctness, it's not a useful test.

---

## 1. Hardware Detection (`lib/hardware.py`)

### 1.1 RAM Tier Classification

**Function:** `detect_hardware()` (tier classification portion)

**Specification:**
| RAM Amount | Tier | Description |
|------------|------|-------------|
| < 16 GB | Tier D | UNSUPPORTED - Script should exit |
| 16-23.99 GB | Tier C | Entry level (minimum supported) |
| 24-31.99 GB | Tier B | Mid-range |
| 32-63.99 GB | Tier A | High-end |
| ≥ 64 GB | Tier S | Premium/Workstation |

**Boundary Test Cases:**

```text
8 GB   → Tier D (unsupported, script exits)
15.99 GB → Tier D (unsupported)
16.0 GB  → Tier C ✓
23.99 GB → Tier C ✓
24.0 GB  → Tier B ✓
31.99 GB → Tier B ✓
32.0 GB  → Tier A ✓
63.99 GB → Tier A ✓
64.0 GB  → Tier S ✓
128 GB   → Tier S ✓
```

**Critical Boundary:** 24 GB should be Tier B (NOT Tier C)

### 1.2 RAM Reservation Percentages

**Function:** `HardwareInfo.get_tier_ram_reservation()`

**Specification:**
| Tier | Reserved for OS | Available for Models |
|------|-----------------|---------------------|
| Tier S | 30% | 70% |
| Tier A | 30% | 70% |
| Tier B | 35% | 65% |
| Tier C | 40% | 60% |
| Tier D | 50% | 50% (unsupported) |

**Test Cases with Mathematical Verification:**

```python
# Tier C: 16GB * 0.60 = 9.6GB usable
# Tier B: 24GB * 0.65 = 15.6GB usable
# Tier A: 32GB * 0.70 = 22.4GB usable
# Tier S: 64GB * 0.70 = 44.8GB usable

# Tests should calculate expected values independently:
assert hw_16gb.usable_ram == pytest.approx(16.0 * 0.60, abs=0.1)  # 9.6 GB
assert hw_24gb.usable_ram == pytest.approx(24.0 * 0.65, abs=0.1)  # 15.6 GB
assert hw_32gb.usable_ram == pytest.approx(32.0 * 0.70, abs=0.1)  # 22.4 GB
assert hw_64gb.usable_ram == pytest.approx(64.0 * 0.70, abs=0.1)  # 44.8 GB
```

### 1.3 Usable RAM Calculation

**Function:** `HardwareInfo.get_estimated_model_memory()`

**Specification:**
- Returns `usable_ram_gb` if already set (> 0)
- Otherwise calculates: `ram_gb * (1 - get_tier_ram_reservation())`
- For discrete GPU systems: returns max(usable_ram, gpu_vram)
- Result should never be negative

**Test Cases:**

```text
16 GB Tier C → 16 * 0.60 = 9.6 GB
24 GB Tier B → 24 * 0.65 = 15.6 GB
32 GB Tier A → 32 * 0.70 = 22.4 GB
64 GB Tier S → 64 * 0.70 = 44.8 GB
0 GB (edge)  → 0 GB (no negative)
```

---

## 2. Model Selection (`lib/model_selector.py`)

### 2.1 Model Recommendations Must Fit RAM Budget

**Function:** `generate_best_recommendation(hw_info)`

**Specification:**
- Total model RAM ≤ usable RAM from hardware tier
- Must include at least 1 model (primary coding)
- Should include embedding model if space allows
- Should leave reasonable buffer (aim for ~70% of usable RAM)

**Test Cases by Tier:**

```text
Tier C (16GB → 9.6GB usable):
  - Total models ≤ 9.6 GB ✓
  - Should recommend smaller models (3B-7B range)
  - Example: starcoder2:3b (2GB) + nomic-embed-text (0.3GB) ≤ 9.6GB ✓

Tier B (24GB → 15.6GB usable):
  - Total models ≤ 15.6 GB ✓
  - Can include 7B primary model

Tier A (32GB → 22.4GB usable):
  - Total models ≤ 22.4 GB ✓
  - Can include 14B primary model

Tier S (64GB → 44.8GB usable):
  - Total models ≤ 44.8 GB ✓
  - Can include 22B primary model
```

### 2.2 Fallback Model Selection

**Function:** `validator.get_fallback_model(model, tier)`

**Specification:**
- If model has `fallback_name`, use that model first
- Fallback must have same role as original
- Fallback must also fit RAM budget
- Returns `None` if no valid fallback exists

**Test Cases:**

```text
qwen2.5-coder:7b fails → Try fallback_name (codellama:7b) ✓
Fallback succeeds → Return fallback model ✓
Fallback also fails → Return None ✓
Model has no fallback_name → Use role-based fallback ✓
```

### 2.3 No Duplicate Models

**Function:** `generate_best_recommendation(hw_info)`

**Specification:**
- Primary and autocomplete models must be different (different `ollama_name`)
- If same model would be selected for both, only include once

**Test Cases:**

```text
Tier C (limited RAM):
  - If primary == autocomplete, only include primary ✓
  - Check by comparing ollama_name, not object identity ✓
```

---

## 3. SSL/Network (`lib/utils.py`, `lib/ollama.py`)

### 3.1 All Network Calls Must Use SSL Context

**Function:** All `urllib.request.urlopen()` calls

**Specification:**
- MUST include `context=get_unverified_ssl_context()` parameter
- Required for corporate proxies/SSL interception
- Equivalent to curl's `-k` flag

**Verification:**

```python
# Test should FAIL if context is not passed:
@patch('urllib.request.urlopen')
def test_api_uses_ssl_context(mock_urlopen):
    some_function_that_calls_api()
    
    # Verify context was passed
    call_args = mock_urlopen.call_args
    assert 'context' in call_args.kwargs, "SSL context MUST be passed"
    assert call_args.kwargs['context'] is not None, "SSL context cannot be None"
```

### 3.2 SSL Context Properties

**Function:** `utils.get_unverified_ssl_context()`

**Specification:**
- Returns an `ssl.SSLContext` object
- `check_hostname` is `False`
- `verify_mode` is `ssl.CERT_NONE`
- Is cached (singleton pattern) for efficiency
- Handles fallback if `_create_unverified_context` fails

**Test Cases:**

```python
ctx = get_unverified_ssl_context()
assert isinstance(ctx, ssl.SSLContext)
assert ctx.check_hostname is False
assert ctx.verify_mode == ssl.CERT_NONE

# Singleton test
ctx1 = get_unverified_ssl_context()
ctx2 = get_unverified_ssl_context()
assert ctx1 is ctx2  # Same object
```

---

## 4. Command Execution (`lib/utils.py`)

### 4.1 run_command Function

**Function:** `utils.run_command(cmd, timeout=300)`

**Specification:**
- Returns tuple: `(return_code, stdout, stderr)`
- Default timeout: 300 seconds (5 minutes)
- On timeout: returns `(-1, "", "Command timed out...")`
- On not found: returns `(-1, "", "Command not found...")`
- On exception: returns `(-1, "", error_message)`
- Captures output in text mode

**Test Cases:**

```text
Success: (0, "output", "")
Failure: (1, "", "error message")
Timeout: (-1, "", "timed out")
Not found: (-1, "", "not found")
None stdout/stderr: (0, "", "")  # Handle None gracefully
```

---

## 5. Auto-Start (`lib/ollama.py`)

### 5.1 macOS Launch Agent Setup

**Function:** `setup_ollama_autostart_macos()`

**Specification:**
- Only works on macOS (`platform.system() == "Darwin"`)
- Requires Ollama to be installed (`shutil.which("ollama")`)
- Creates plist at: `~/Library/LaunchAgents/com.ollama.server.plist`
- Calls `launchctl load` to activate immediately
- Returns `True` on success, `False` on failure

**Test Cases:**

```text
Linux system → Returns False (no-op)
Ollama not installed → Returns False
macOS + Ollama installed → Creates plist + loads it → Returns True
Plist already exists → Prompts for overwrite or skip
launchctl load fails → Returns False
```

### 5.2 Auto-Start Status Check

**Function:** `check_ollama_autostart_status_macos()`

**Specification:**
- Returns tuple: `(is_configured: bool, details: str)`
- Checks plist file existence
- Checks `launchctl list` for loaded status

**Test Cases:**

```text
Plist exists + in launchctl → (True, "...loaded...")
Plist exists + NOT in launchctl → (True, "...not loaded...")
Plist doesn't exist → (False, "Not configured")
```

### 5.3 Auto-Start Removal

**Function:** `remove_ollama_autostart_macos()`

**Specification:**
- Calls `launchctl unload` first
- Deletes plist file
- Returns `True` on success
- Returns `True` if nothing to remove (idempotent)

---

## 6. Configuration (`lib/config.py`)

### 6.1 File Fingerprinting

**Function:** `add_fingerprint_header(content, file_type)`

**Specification:**
- For YAML/MD files: prepends comment header with generator info
- Header contains: "Generated by ollama-llm-setup.py" and timestamp
- For JSON files: can add metadata field

**Test Cases:**

```python
result = add_fingerprint_header("content", "yaml")
assert "Generated by" in result
assert "ollama-llm-setup" in result
assert "content" in result
```

### 6.2 File Classification

**Function:** `classify_file_type(path)`

**Specification:**
- Returns type based on filename/extension

```text
config.yaml → "config_yaml" or contains "config"
config.json → "config_json" or contains "config"
global-rule.md → "rule" or contains "rule"
.continueignore → "ignore" or contains "ignore"
setup-summary.json → "summary" or contains "summary"
unknown.txt → "other"
```

### 6.3 Manifest Loading

**Function:** `load_installation_manifest()`

**Specification:**
- Returns manifest dict if file exists and is valid JSON
- Returns `None` if file doesn't exist
- Returns `None` (and logs warning) if JSON is corrupt
- Logs specific error type (JSONDecodeError vs IOError)

**Test Cases:**

```python
# File doesn't exist → None
# Valid JSON → returns dict
# Corrupt JSON → None (logs warning)
# Permission error → None (logs warning)
```

### 6.4 UTC Timestamps

**Function:** `_get_utc_timestamp()`

**Specification:**
- Returns ISO 8601 format string
- Must be UTC timezone-aware
- Contains "T" separator and timezone indicator ("+" or "Z")

---

## 7. Model Validation (`lib/validator.py`)

### 7.1 Error Classification

**Function:** `classify_pull_error(error_msg)`

**Specification:**
| Error Pattern | Error Type |
|---------------|------------|
| "ssh: no key found", "SSH_AUTH_SOCK" | SSH_KEY |
| "connection refused", "timeout" | NETWORK |
| "unauthorized", "403" | AUTH |
| "is ollama running" | SERVICE |
| "manifest unknown", "registry" | REGISTRY |
| "no space left", "permission denied" | DISK |
| "model not found", "unknown model" | MODEL_NOT_FOUND |
| anything else | UNKNOWN |

### 7.2 Setup Result Properties

**Function:** `SetupResult` dataclass properties

**Specification:**

```python
# complete_success: All models succeeded, none failed
complete_success = len(successful_models) > 0 and len(failed_models) == 0

# partial_success: Some succeeded, some failed
partial_success = len(successful_models) > 0 and len(failed_models) > 0

# complete_failure: None succeeded, at least one failed
complete_failure = len(successful_models) == 0 and len(failed_models) > 0
```

**Critical:** `complete_failure` should be `False` when there are no models at all.

### 7.3 Model Verification

**Function:** `verify_model_exists(model_name)`

**Specification:**
- Queries Ollama API for installed models
- Checks for exact match or base name match
- Returns `True` if model is installed, `False` otherwise

---

## 8. Test Validation Criteria

### Tests Must Be Specification-Driven

✅ **GOOD Test Pattern:**
```python
def test_tier_c_usable_ram():
    """Tier C (16GB) should have 60% usable (9.6GB)."""
    hw = HardwareInfo(ram_gb=16.0, tier=HardwareTier.C)
    usable = hw.get_estimated_model_memory()
    
    # Calculate expected value independently
    expected = 16.0 * 0.60  # 9.6 GB - from specification
    
    assert usable == pytest.approx(expected, abs=0.1)
```

❌ **BAD Test Pattern:**
```python
def test_tier_c_usable_ram():
    """Test usable RAM for Tier C."""
    hw = HardwareInfo(ram_gb=16.0, tier=HardwareTier.C)
    usable = hw.get_estimated_model_memory()
    
    # BAD: Just validates whatever the code returns
    assert usable == usable  # This always passes!
    # or
    assert usable > 0  # Too weak - doesn't verify correctness
```

### Each Test Should Answer: "Would This Catch a Bug?"

For every test, ask:
1. If I introduced a bug, would this test fail?
2. Does this test use independently calculated expected values?
3. Does this test check boundary conditions?
4. Does this test verify the specification, not just current behavior?

---

## Appendix: Quick Reference

### Tier RAM Calculations

```python
# Formula: usable = total * (1 - reservation)
# Where reservation = {S: 0.30, A: 0.30, B: 0.35, C: 0.40}

EXPECTED_USABLE_RAM = {
    (16, 'C'): 16 * 0.60,   # 9.6 GB
    (24, 'B'): 24 * 0.65,   # 15.6 GB
    (32, 'A'): 32 * 0.70,   # 22.4 GB
    (48, 'A'): 48 * 0.70,   # 33.6 GB
    (64, 'S'): 64 * 0.70,   # 44.8 GB
    (96, 'S'): 96 * 0.70,   # 67.2 GB
    (128, 'S'): 128 * 0.70, # 89.6 GB
}
```

### Tier Boundary Values (for boundary testing)

```python
TIER_BOUNDARIES = [
    (15.99, 'D'),  # Just under 16 - unsupported
    (16.0, 'C'),   # Exact boundary
    (23.99, 'C'), # Just under 24
    (24.0, 'B'),   # Exact boundary
    (31.99, 'B'), # Just under 32
    (32.0, 'A'),   # Exact boundary
    (63.99, 'A'), # Just under 64
    (64.0, 'S'),   # Exact boundary
]
```
