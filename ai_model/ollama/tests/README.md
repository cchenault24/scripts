# Test Suite for Ollama LLM Setup

This directory contains comprehensive tests for the Ollama LLM setup scripts.

## Running Tests

### Prerequisites

Install test dependencies:

```bash
pip install pytest pytest-cov pytest-mock
```

### Running All Tests

```bash
cd ai_model/ollama
python3 -m pytest tests/ -v
```

### Running with Coverage

```bash
python3 -m pytest tests/ --cov=lib --cov-report=term-missing
```

### Running Specific Test Files

```bash
# Unit tests for specific modules
python3 -m pytest tests/test_unit_config.py -v
python3 -m pytest tests/test_unit_hardware.py -v
python3 -m pytest tests/test_unit_validator.py -v

# Integration tests
python3 -m pytest tests/test_integration.py -v

# E2E flow tests
python3 -m pytest tests/test_e2e_flows.py -v
```

### Generating HTML Coverage Report

```bash
python3 -m pytest tests/ --cov=lib --cov-report=html
# Open htmlcov/index.html in browser
```

## Test Structure

```
tests/
├── conftest.py                    # Pytest fixtures
├── mocks.py                       # Shared mock objects
├── test_unit_config.py            # Config generation tests
├── test_unit_hardware.py          # Hardware detection tests
├── test_unit_validator.py         # Model validation tests
├── test_unit_ollama.py            # Ollama service tests
├── test_unit_utils.py             # Utility function tests
├── test_unit_models.py            # Model catalog tests
├── test_unit_ui.py                # UI/terminal output tests
├── test_unit_ide.py               # IDE detection tests
├── test_unit_uninstaller.py       # Uninstaller tests
├── test_unit_model_selector.py    # Model recommendation tests
├── test_config_comprehensive.py   # Extended config tests
├── test_validator_comprehensive.py# Extended validator tests
├── test_model_selector_extended.py# Extended model selector tests
├── test_ollama_extended.py        # Extended ollama tests
├── test_integration.py            # Integration tests
├── test_e2e_flows.py              # End-to-end workflow tests
└── README.md                      # This file
```

## Coverage Summary

Current coverage: **51%** (460 tests passing)

### Fully Covered (100%):
- `lib/models.py` - Model catalog definitions
- `lib/utils.py` - Utility functions

### Well Covered (>80%):
- `lib/ui.py` - 95% - UI/terminal functions
- `lib/__init__.py` - 75% - Module exports

### Partially Covered (50-75%):
- `lib/config.py` - 68% - Config generation
- `lib/ide.py` - 57% - IDE detection
- `lib/validator.py` - 57% - Model validation
- `lib/uninstaller.py` - 49% - Uninstallation

### Lower Coverage (<50%):
- `lib/model_selector.py` - 43% - Model recommendations
- `lib/ollama.py` - 28% - Ollama service management
- `lib/hardware.py` - 27% - Hardware detection

## Untestable Code

Some code is difficult to test without extensive system mocking:

### Hardware Detection (`lib/hardware.py`)
- `detect_hardware()` - Requires real system calls to psutil, platform
- `detect_apple_silicon_details()` - Requires macOS with Apple Silicon
- System exits when RAM is insufficient

### Ollama Service (`lib/ollama.py`)
- `install_ollama()` - Runs system installation commands
- `start_ollama_service()` - Starts background process
- `setup_ollama_autostart_macos()` - Modifies LaunchAgents
- Functions that interact with running Ollama API

### IDE Integration (`lib/ide.py`)
- IDE detection - Checks for installed applications
- Extension installation - Runs IDE CLI commands
- IDE restart - Platform-specific commands

### Model Selection (`lib/model_selector.py`)
- Interactive customization menus (require user input)
- `display_recommendation()` - Console output with formatting
- Functions with complex interactive loops

### Configuration (`lib/config.py`)
- `create_installation_manifest()` - Writes to file system
- Functions that rely on `~/.continue` directory

## Test Categories

### Unit Tests
Test individual functions in isolation with mocked dependencies.

### Integration Tests
Test interactions between modules (e.g., hardware → model selection → config).

### E2E Flow Tests
Test complete user workflows with all components mocked.

## Writing New Tests

1. Place tests in appropriate file based on the module being tested
2. Use `pytest.mark.parametrize` for multiple test cases
3. Mock external dependencies (file system, network, subprocess)
4. Use fixtures from `conftest.py` for common test data
5. Add descriptive docstrings explaining what each test verifies

Example test:

```python
@patch('lib.validator.utils.run_command')
def test_model_verification(self, mock_run):
    """Test that model verification checks ollama list output."""
    mock_run.return_value = (0, "llama3:latest\ncodestral:22b", "")
    
    result = verify_model_exists("llama3:latest")
    
    assert result is True
    mock_run.assert_called_once()
```
