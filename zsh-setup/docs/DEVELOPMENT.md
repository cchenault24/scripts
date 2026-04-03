# Development Guide

This guide helps contributors get started with zsh-setup development.

## Setup

### Prerequisites
- macOS or Linux
- Bash 3.2+ (macOS default) or Bash 4.0+
- git
- shellcheck (for linting)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/zsh-setup.git
cd zsh-setup
```

2. Install shellcheck:
```bash
# macOS
brew install shellcheck

# Ubuntu/Debian
apt install shellcheck

# Fedora
dnf install ShellCheck
```

3. Run tests to verify setup:
```bash
tests/test_runner.sh all
```

## Project Structure

```
zsh-setup/
├── lib/                    # Core library modules
│   ├── core/              # Bootstrap, config, logging
│   ├── plugins/           # Plugin management
│   ├── state/             # State persistence
│   ├── system/            # System operations
│   ├── config/            # Configuration management
│   └── utils/             # Shared utilities
├── commands/              # CLI command implementations
├── tests/                 # Test suite
│   ├── test_helpers.sh   # Test utilities
│   ├── test_security.sh  # Security tests
│   └── run_shellcheck.sh # Linting
├── ARCHITECTURE.md        # Architecture documentation
├── SECURITY.md            # Security policy
└── README.md              # User documentation
```

## Development Workflow

### 1. Create a Branch
```bash
git checkout -b feature/your-feature-name
```

### 2. Make Changes
Follow the [Code Standards](#code-standards) below.

### 3. Test Your Changes
```bash
# Run all tests
tests/test_runner.sh all

# Run shellcheck
tests/run_shellcheck.sh

# Run specific test file
tests/test_security.sh
```

### 4. Commit Changes
```bash
git add .
git commit -m "type: description

Detailed explanation of changes.

Co-Authored-By: Your Name <your.email@example.com>"
```

Commit types: `feat`, `fix`, `refactor`, `test`, `docs`, `security`

### 5. Push and Create PR
```bash
git push origin feature/your-feature-name
```

Then create a pull request on GitHub.

## Code Standards

### Naming Conventions

All functions use namespaced naming:
```bash
zsh_setup::<module>::<submodule>::<function_name>
```

Examples:
- `zsh_setup::core::logger::info`
- `zsh_setup::plugins::installer::install_git`
- `zsh_setup::utils::filesystem::sanitize_name`

### Function Documentation

Every function should have a documentation header:

```bash
#------------------------------------------------------------------------------
# Function: zsh_setup::module::function_name
# Description: What this function does
# Arguments:
#   $1 - First argument (type: string|number|boolean)
#   $2 - Second argument (optional, default: value)
# Returns:
#   0 on success, 1 on failure
# Side Effects:
#   - Creates files in /path/to/location
#   - Modifies global state (specify which)
#------------------------------------------------------------------------------
zsh_setup::module::function_name() {
    local arg1="$1"
    local arg2="${2:-default}"

    # Implementation
}
```

### Shell Script Style

1. **Use strict mode** (where appropriate):
```bash
set -euo pipefail
```

2. **Quote all variables**:
```bash
# Good
echo "$variable"
if [[ "$var" == "value" ]]; then

# Bad
echo $variable
if [[ $var == "value" ]]; then
```

3. **Use `local` for function variables**:
```bash
function_name() {
    local my_var="value"
    local result=$(command)
}
```

4. **Prefer `[[ ]]` over `[ ]`**:
```bash
# Good
if [[ -f "$file" && "$var" == "value" ]]; then

# Avoid
if [ -f "$file" ] && [ "$var" = "value" ]; then
```

5. **Use meaningful variable names**:
```bash
# Good
local plugin_name="$1"
local install_path="$2"

# Avoid
local pn="$1"
local p="$2"
```

### Error Handling

Always check for errors and provide clear messages:

```bash
if ! command_that_might_fail; then
    zsh_setup::core::logger::error "Failed to do X"
    zsh_setup::core::logger::info "Try Y or Z to fix this"
    return 1
fi
```

### Security

1. **Sanitize all user input**:
```bash
local safe_name=$(zsh_setup::utils::filesystem::sanitize_name "$user_input")
```

2. **Set secure file permissions**:
```bash
touch "$file"
chmod 600 "$file"  # Owner read/write only
```

3. **Use secure temporary files**:
```bash
local temp_file=$(mktemp -t prefix.XXXXXX)
chmod 700 "$temp_file"
trap 'rm -f "$temp_file"' EXIT INT TERM
```

4. **No eval of user input**:
```bash
# Never do this
eval "$user_input"

# Always sanitize first
```

## Testing

### Writing Tests

Tests use the test helpers in `tests/test_helpers.sh`:

```bash
#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_helpers.sh"

# Setup
export ZSH_SETUP_ROOT="$PROJECT_ROOT"
source "$PROJECT_ROOT/lib/your/module.sh"

# Test function
test_something() {
    test_start "Test description"

    local result=$(your_function "input")

    assert_equal "expected" "$result" "Result should match" && test_pass
}

# Run tests
main() {
    test_something
    test_summary
}

main "$@"
```

### Test Helpers

Available assertion functions:
- `test_start "description"` - Start a test
- `test_pass` - Mark test as passed
- `test_fail "reason"` - Mark test as failed
- `assert_success "command"` - Assert command succeeds
- `assert_failure "command"` - Assert command fails
- `assert_equal "expected" "actual"` - Assert equality
- `assert_file_exists "path"` - Assert file exists
- `assert_dir_exists "path"` - Assert directory exists
- `assert_contains "haystack" "needle"` - Assert substring

### Running Tests

```bash
# Run all tests
tests/test_runner.sh all

# Run specific test
tests/test_security.sh

# Run with verbose output
VERBOSE=1 tests/test_runner.sh all

# Run shellcheck
tests/run_shellcheck.sh
```

## Shellcheck

All code must pass shellcheck with no warnings.

### Running Shellcheck

```bash
# Check all files
tests/run_shellcheck.sh

# Check specific file
shellcheck -x lib/plugins/manager.sh
```

### Common Shellcheck Issues

1. **SC2086 - Unquoted variable**:
```bash
# Bad
rm $file

# Good
rm "$file"
```

2. **SC2046 - Quote command substitution**:
```bash
# Bad
for file in $(ls); do

# Good
while IFS= read -r file; do
    # ...
done < <(ls)
```

3. **SC2154 - Variable referenced but not assigned**:
```bash
# Add to .shellcheckrc if it's sourced from another file
# Or add comment:
# shellcheck disable=SC2154
```

### Shellcheck Configuration

Project configuration in `.shellcheckrc`:
- SC1090: Disabled (dynamic sourcing)
- SC1091: Disabled (can't follow all sources)
- SC2034: Disabled (variables used by sourced scripts)

## Module Development

### Adding a New Module

1. Create file in appropriate directory:
```bash
lib/category/new_module.sh
```

2. Add standard header:
```bash
#!/usr/bin/env bash

#==============================================================================
# new_module.sh - Module Description
#
# Detailed explanation of what this module does
#==============================================================================

# Load dependencies
if [[ -n "${ZSH_SETUP_ROOT:-}" ]]; then
    source "$ZSH_SETUP_ROOT/lib/core/config.sh"
    source "$ZSH_SETUP_ROOT/lib/core/logger.sh"
fi

#------------------------------------------------------------------------------
# Public Functions
#------------------------------------------------------------------------------

zsh_setup::category::new_module::function_name() {
    # Implementation
}
```

3. Update bootstrap if needed
4. Add tests in `tests/`
5. Update documentation

### Adding a New Command

1. Create file in `commands/`:
```bash
commands/new_command.sh
```

2. Implement command function
3. Add to main CLI dispatcher in `zsh-setup`
4. Add to help text
5. Update README.md

## Debugging

### Enable Debug Logging

```bash
# Set debug flag
export ZSH_SETUP_DEBUG=1

# Run command
./zsh-setup install --verbose
```

### Inspect State

```bash
# View state file
cat ~/.local/state/zsh-setup/state.json | jq .

# Check configuration
zsh_setup::core::config::get oh_my_zsh_dir
```

### Common Issues

1. **Module not loading**: Check `ZSH_SETUP_ROOT` is set
2. **Function not found**: Ensure module is sourced
3. **Permission denied**: Check file permissions
4. **State not persisting**: Verify state file location

## Performance

### Profiling

Use zsh's built-in profiling:

```bash
# Enable profiling
zmodload zsh/zprof

# Source your setup
source ~/.zshrc

# View results
zprof
```

### Optimization Tips

1. Minimize subshells
2. Use built-ins over external commands
3. Lazy-load expensive modules
4. Cache repeated computations

## Documentation

### What to Document

1. **README.md**: User-facing features
2. **ARCHITECTURE.md**: Design decisions
3. **DEVELOPMENT.md**: This file
4. **SECURITY.md**: Security considerations
5. **Inline comments**: Complex logic only

### Documentation Style

- Use clear, concise language
- Include code examples
- Link related documentation
- Keep examples up to date

## Release Process

1. Update CHANGELOG.md
2. Run full test suite
3. Update version in relevant files
4. Create git tag
5. Push to GitHub
6. Create release notes

## Getting Help

- Read existing code for examples
- Check ARCHITECTURE.md for design patterns
- Look at tests for usage examples
- Ask questions in GitHub discussions

## Contributing Guidelines

1. Follow code standards
2. Add tests for new features
3. Update documentation
4. Pass shellcheck
5. Write clear commit messages
6. Be respectful and professional

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.
