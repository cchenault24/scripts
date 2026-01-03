# macOS Cleanup Utility - Testing Infrastructure

This directory contains comprehensive testing and validation tools for the macOS Cleanup Utility.

## Overview

The testing infrastructure consists of:

1. **Manual Test Plan** - Comprehensive manual testing procedures
2. **Automated Validation Scripts** - Static analysis and code quality checks
3. **Master Test Runner** - Executes all automated validations

## Quick Start

Run all automated tests:

```bash
./tests/run_all_tests.sh
```

Run individual validation scripts:

```bash
./tests/validate_strict_mode.sh
./tests/validate_shellcheck.sh
./tests/validate_variable_quoting.sh
./tests/validate_plugin_registration.sh
./tests/validate_function_existence.sh
./tests/validate_backup_safety.sh
```

## Test Scripts

### 1. `run_all_tests.sh` - Master Test Runner

Executes all validation scripts and provides a comprehensive summary.

**Usage:**
```bash
./tests/run_all_tests.sh
```

**What it checks:**
- Strict mode in all shell scripts
- ShellCheck compliance
- Variable quoting safety
- Plugin registration validity
- Function existence
- Backup safety

---

### 2. `validate_strict_mode.sh` - Strict Mode Validation

Ensures all shell scripts have `set -euo pipefail` for proper error handling.

**Usage:**
```bash
./tests/validate_strict_mode.sh
```

**What it checks:**
- All `.sh` files have `set -euo pipefail` near the top
- Strict mode appears before any actual code execution

**Why it matters:**
- Prevents silent failures
- Catches undefined variables
- Ensures pipe failures are detected

---

### 3. `validate_shellcheck.sh` - ShellCheck Compliance

Runs ShellCheck on all shell scripts to find common issues.

**Usage:**
```bash
./tests/validate_shellcheck.sh
```

**Requirements:**
- ShellCheck must be installed: `brew install shellcheck`

**What it checks:**
- SC2086: Double quote to prevent globbing and word splitting
- SC2068: Double quote array expansions
- SC2046: Quote this to prevent word splitting
- SC2155: Declare and assign separately
- All critical and error level issues

**Why it matters:**
- Catches common shell scripting bugs
- Enforces best practices
- Prevents security vulnerabilities

---

### 4. `validate_variable_quoting.sh` - Variable Quoting Safety

Checks for unquoted variables in dangerous commands (rm, find, tar, etc.).

**Usage:**
```bash
./tests/validate_variable_quoting.sh
```

**What it checks:**
- Variables in `rm`, `find`, `tar`, `mv`, `cp` commands are quoted
- Command substitutions are properly quoted
- No unquoted variables that could expand to dangerous paths

**Why it matters:**
- Prevents accidental deletion of wrong files
- Prevents command injection vulnerabilities
- Ensures safe file operations

**Note:** This is a heuristic check and may have false positives. Manual review is recommended.

---

### 5. `validate_plugin_registration.sh` - Plugin Registration Validation

Validates that all plugins register correctly and their functions exist.

**Usage:**
```bash
./tests/validate_plugin_registration.sh
```

**What it checks:**
- All `register_plugin` calls are valid
- Registered functions actually exist
- Plugin registry is populated
- Size calculation functions exist (if provided)

**Why it matters:**
- Ensures plugins can be executed
- Prevents runtime errors from missing functions
- Validates plugin architecture integrity

---

### 6. `validate_function_existence.sh` - Function Existence Validation

Validates that all functions referenced in plugin registrations actually exist.

**Usage:**
```bash
./tests/validate_function_existence.sh
```

**What it checks:**
- All registered plugin functions exist
- All registered size calculation functions exist
- Functions are callable

**Why it matters:**
- Prevents runtime errors
- Ensures plugin system integrity
- Validates function naming consistency

---

### 7. `validate_backup_safety.sh` - Backup Safety Validation

Validates that all plugins call `backup()` before destructive operations.

**Usage:**
```bash
./tests/validate_backup_safety.sh
```

**What it checks:**
- Destructive operations (`rm -rf`, `safe_remove`, etc.) are preceded by `backup()` calls
- Plugins with destructive operations have backup protection
- Safe functions (`safe_remove`, `safe_clean_dir`) handle backup internally

**Why it matters:**
- **CRITICAL**: Prevents data loss
- Ensures all deletions are backed up
- Validates safety mechanisms

---

## Manual Testing

See `MANUAL_TEST_PLAN.md` for comprehensive manual testing procedures covering:

- Basic operations (help, dry-run, interactive cleanup, undo, schedule)
- Safety tests (interrupt handling, disk space, file locking)
- Edge cases (empty directories, missing tools, corrupted manifests, symlinks)
- Plugin-specific tests (all 39 plugins)
- Platform compatibility (macOS versions, architectures)
- Error handling
- Backup system
- Logging

## Integration with CI/CD

These tests can be integrated into CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Run Validation Tests
  run: |
    cd mac-cleanup
    ./tests/run_all_tests.sh
```

## Test Results Interpretation

### Exit Codes

- `0` - All tests passed
- `1` - One or more tests failed

### Output Colors

- 🟢 Green (`✓`) - Test passed
- 🔴 Red (`✗`) - Test failed
- 🟡 Yellow (`⚠`) - Warning (non-blocking)

### Severity Levels

1. **CRITICAL** - Must fix before release
   - Missing strict mode
   - Unquoted variables in dangerous commands
   - Missing backup calls before deletion

2. **HIGH** - Should fix for production quality
   - ShellCheck errors
   - Missing function implementations
   - Plugin registration failures

3. **MEDIUM** - Recommended fixes
   - ShellCheck warnings
   - Variable quoting warnings (may be false positives)

## Adding New Tests

To add a new validation script:

1. Create `validate_<feature>.sh` in the `tests/` directory
2. Follow the pattern of existing scripts:
   - Use `set -euo pipefail`
   - Provide colored output
   - Track errors/warnings
   - Exit with appropriate code
3. Add to `run_all_tests.sh`
4. Update this README

## Troubleshooting

### ShellCheck not found

```bash
brew install shellcheck
```

### Permission denied

```bash
chmod +x tests/*.sh
```

### Plugin loading errors

Some validation scripts source plugin files. If you see errors:
- Ensure all dependencies are available
- Check that mock functions are sufficient
- Review plugin file syntax

### False positives in variable quoting

The variable quoting check uses heuristics and may flag safe code. Review flagged lines manually to confirm they're actually unsafe.

## Best Practices

1. **Run tests before committing:**
   ```bash
   ./tests/run_all_tests.sh
   ```

2. **Fix critical issues first:**
   - Strict mode
   - Backup safety
   - Unquoted variables

3. **Review warnings:**
   - Some warnings may indicate real issues
   - Use judgment based on context

4. **Update tests when adding features:**
   - New plugins should be covered
   - New functions should be validated

## Related Documentation

- `../README.md` - Main project documentation
- `MANUAL_TEST_PLAN.md` - Manual testing procedures
- `../ARCHITECTURE.md` - System architecture (if exists)

## Contributing

When adding new features:

1. Write tests first (if applicable)
2. Run validation scripts
3. Fix any issues
4. Update manual test plan if needed
5. Document new test procedures

---

**Last Updated:** Phase 7 Implementation
**Version:** 1.0.0
