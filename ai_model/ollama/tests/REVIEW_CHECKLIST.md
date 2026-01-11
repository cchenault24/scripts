# Test Review Checklist

Use this checklist to manually review tests and ensure they validate **specifications**,
not just **current implementation behavior**.

---

## For Each Test, Verify:

### ✅ 1. Docstring Explains Expected Behavior

- [ ] Test has a docstring
- [ ] Docstring explains WHAT the test validates
- [ ] Docstring references the specification (e.g., "Tier C should reserve 40%")

**Good Example:**
```python
def test_tier_c_reservation():
    """Tier C (16-24GB) should reserve 40% for OS, leaving 60% usable."""
```

**Bad Example:**
```python
def test_ram():
    """Test RAM."""  # What about RAM? What's expected?
```

---

### ✅ 2. Uses Independently Calculated Expected Values

- [ ] Test calculates expected values from specification
- [ ] Does NOT just compare output to itself
- [ ] Does NOT use magic numbers without explanation

**Good Example:**
```python
def test_tier_c_usable_ram():
    """Tier C (16GB) should have 60% usable RAM."""
    hw = HardwareInfo(ram_gb=16.0, tier=HardwareTier.C)
    
    # Calculate expected from specification
    expected = 16.0 * 0.60  # 9.6 GB
    
    assert hw.get_estimated_model_memory() == pytest.approx(expected, abs=0.1)
```

**Bad Example:**
```python
def test_tier_c_usable_ram():
    hw = HardwareInfo(ram_gb=16.0, tier=HardwareTier.C)
    usable = hw.get_estimated_model_memory()
    
    assert usable == usable  # Always passes!
    # or
    assert usable > 0  # Too weak!
```

---

### ✅ 3. Tests Boundary Conditions

- [ ] Tests exact boundary values (16, 24, 32, 64 GB)
- [ ] Tests just below boundaries (23.99, 31.99, 63.99 GB)
- [ ] Tests just above boundaries
- [ ] Tests edge cases (0, negative, very large values)

**Boundary Test Example:**
```python
@pytest.mark.parametrize("ram_gb,expected_tier", [
    (15.99, HardwareTier.D),  # Just under minimum
    (16.0, HardwareTier.C),   # Exact minimum
    (23.99, HardwareTier.C),  # Just under Tier B
    (24.0, HardwareTier.B),   # Exact Tier B boundary
    (31.99, HardwareTier.B),  # Just under Tier A
    (32.0, HardwareTier.A),   # Exact Tier A boundary
])
def test_tier_boundaries(ram_gb, expected_tier):
    """Test tier classification at boundary values."""
```

---

### ✅ 4. Tests Both Success AND Failure Paths

- [ ] Tests happy path (success case)
- [ ] Tests error path (failure case)
- [ ] Tests timeout handling
- [ ] Tests resource not found
- [ ] Tests permission denied

**Example:**
```python
def test_model_pull_success(self):
    """Test successful model pull."""
    
def test_model_pull_failure(self):
    """Test model pull failure handling."""
    
def test_model_pull_timeout(self):
    """Test model pull timeout handling."""
```

---

### ✅ 5. Verifies Critical Requirements

#### SSL Context Usage
- [ ] Tests verify `context=` parameter is passed to urlopen
- [ ] Tests verify SSL context properties (check_hostname=False, verify_mode=CERT_NONE)

**Example:**
```python
@patch('urllib.request.urlopen')
def test_api_uses_ssl_context(self, mock_urlopen):
    """API calls MUST use unverified SSL context."""
    some_api_function()
    
    call_args = mock_urlopen.call_args
    assert 'context' in call_args.kwargs, "SSL context MUST be passed"
    assert call_args.kwargs['context'] is not None
```

#### Process Cleanup
- [ ] Tests verify processes are terminated in finally blocks
- [ ] Tests verify cleanup on exception

#### Models Fit Budget
- [ ] Tests verify total model RAM ≤ usable RAM

---

### ✅ 6. Mathematical/Logical Correctness

Use the specification values to calculate expected results:

| Tier | RAM | Reservation | Usable | Formula |
|------|-----|-------------|--------|---------|
| C | 16 GB | 40% | 9.6 GB | 16 × 0.60 |
| B | 24 GB | 35% | 15.6 GB | 24 × 0.65 |
| A | 32 GB | 30% | 22.4 GB | 32 × 0.70 |
| S | 64 GB | 30% | 44.8 GB | 64 × 0.70 |

**Example:**
```python
def test_tier_a_usable_ram():
    """Tier A (32GB) should have 70% usable (22.4GB)."""
    hw = HardwareInfo(ram_gb=32.0, tier=HardwareTier.A)
    
    # Mathematical verification from specification
    expected = 32.0 * 0.70  # 22.4 GB
    
    actual = hw.get_estimated_model_memory()
    
    assert actual == pytest.approx(expected, abs=0.1), \
        f"Expected {expected}GB, got {actual}GB"
```

---

## Red Flags to Look For

🚩 **Tautological assertions:** `assert x == x`
🚩 **Too weak assertions:** `assert x > 0` (doesn't verify correctness)
🚩 **No docstring:** Test purpose unclear
🚩 **Only one assertion:** May not test edge cases
🚩 **Missing mock verification:** `mock.assert_called()` not used
🚩 **Magic numbers:** Unexplained values like `assert result == 9.6`
🚩 **Implementation-driven:** Test mirrors code instead of specification

---

## Critical Functions Checklist

### lib/hardware.py

| Function | Test Exists | Tests Spec Values | Tests Boundaries |
|----------|-------------|-------------------|------------------|
| `get_tier_ram_reservation()` | [ ] | [ ] | [ ] |
| `get_estimated_model_memory()` | [ ] | [ ] | [ ] |
| `detect_hardware()` (tier logic) | [ ] | [ ] | [ ] |

### lib/model_selector.py

| Function | Test Exists | Tests Spec Values | Tests Boundaries |
|----------|-------------|-------------------|------------------|
| `generate_best_recommendation()` | [ ] | [ ] | [ ] |
| `ModelRecommendation.total_ram()` | [ ] | [ ] | [ ] |

### lib/ollama.py

| Function | Test Exists | Tests Success | Tests Failure |
|----------|-------------|---------------|---------------|
| `setup_ollama_autostart_macos()` | [ ] | [ ] | [ ] |
| `check_ollama_autostart_status_macos()` | [ ] | [ ] | [ ] |
| `remove_ollama_autostart_macos()` | [ ] | [ ] | [ ] |
| `verify_ollama_running()` | [ ] | [ ] | [ ] |

### lib/utils.py

| Function | Test Exists | Tests Spec Values | Tests Errors |
|----------|-------------|-------------------|--------------|
| `get_unverified_ssl_context()` | [ ] | [ ] | [ ] |
| `run_command()` | [ ] | [ ] | [ ] |

### lib/validator.py

| Function | Test Exists | Tests Spec Values | Tests Boundaries |
|----------|-------------|-------------------|------------------|
| `classify_pull_error()` | [ ] | [ ] | [ ] |
| `SetupResult.complete_success` | [ ] | [ ] | [ ] |
| `SetupResult.partial_success` | [ ] | [ ] | [ ] |
| `SetupResult.complete_failure` | [ ] | [ ] | [ ] |

---

## Quick Validation Questions

For each test, ask:

1. **"If I introduced a bug, would this test fail?"**
   - If not, the test is too weak

2. **"Does this test use specification values?"**
   - Values like 0.60, 0.65, 0.70, 9.6, 15.6, 22.4, 44.8

3. **"Does this test check boundaries?"**
   - Values like 16, 24, 32, 64 GB

4. **"Is the expected value calculated independently?"**
   - Not derived from the code being tested

5. **"Does this test have meaningful assertions?"**
   - Not just `assert result is not None`

---

## Example Review

### Before Review:
```python
def test_ram():
    hw = HardwareInfo(ram_gb=16.0, tier=HardwareTier.C)
    result = hw.get_estimated_model_memory()
    assert result > 0
```

**Issues:**
- ❌ Missing docstring
- ❌ Weak assertion (`> 0`)
- ❌ Doesn't use specification values
- ❌ Doesn't test boundaries

### After Review:
```python
def test_tier_c_usable_ram_calculation():
    """
    Tier C (16GB RAM) should reserve 40% for OS, leaving 60% usable.
    
    Specification: SPECIFICATIONS.md Section 1.2
    Formula: 16GB × 0.60 = 9.6GB usable
    """
    hw = HardwareInfo(ram_gb=16.0, tier=HardwareTier.C)
    
    # Calculate expected from specification
    expected = 16.0 * 0.60  # 9.6 GB
    
    actual = hw.get_estimated_model_memory()
    
    assert actual == pytest.approx(expected, abs=0.1), \
        f"Tier C usable RAM should be {expected}GB, got {actual}GB"
```

**Improvements:**
- ✅ Clear docstring with specification reference
- ✅ Uses specification value (0.60)
- ✅ Calculates expected independently
- ✅ Assertion includes explanation
