# Zsh Setup - Modern Architecture

## Overview

The zsh-setup project uses a modern, modular architecture with namespaced functions that improves maintainability, testability, and extensibility.

## Directory Structure

```
zsh-setup/
├── zsh-setup                   # Main CLI entry point
├── lib/
│   ├── core/                  # Core infrastructure
│   │   ├── bootstrap.sh       # Module loader
│   │   ├── config.sh          # Configuration management
│   │   ├── logger.sh           # Logging interface
│   │   └── errors.sh            # Error handling
│   ├── state/                 # State management
│   │   └── store.sh           # JSON-based state store
│   ├── system/                # System operations
│   │   ├── package_manager.sh # Package manager abstraction
│   │   ├── validation.sh      # System validation
│   │   └── shell.sh           # Shell management
│   ├── plugins/                # Plugin system
│   │   ├── registry.sh         # Plugin registry
│   │   ├── resolver.sh         # Dependency resolution
│   │   ├── installer.sh        # Installation methods
│   │   └── manager.sh          # Plugin orchestration
│   ├── config/                # Configuration management
│   │   ├── validator.sh        # Config validation
│   │   ├── backup.sh           # Backup/restore
│   │   └── generator.sh        # .zshrc generation
│   ├── utils/                 # Utilities
│   │   ├── network.sh         # Network operations
│   │   └── filesystem.sh      # File operations
│   └── monitoring/            # Monitoring (future)
├── commands/                  # Command implementations
│   ├── install.sh
│   ├── update.sh
│   ├── remove.sh
│   ├── status.sh
│   ├── monitor.sh
│   ├── heal.sh
│   └── uninstall.sh
├── config/                    # Configuration files
│   └── defaults.conf          # Default settings
└── plugins.conf               # Plugin definitions
```

## Architecture Principles

### 1. Namespacing
All functions use the `zsh_setup::` namespace prefix with module hierarchy:
- `zsh_setup::core::logger::info()` - Core logging
- `zsh_setup::plugins::manager::install_list()` - Plugin management
- `zsh_setup::system::package_manager::install()` - Package operations

### 2. Module Loading
The bootstrap system handles dependency resolution and lazy loading:
```bash
source "$ZSH_SETUP_ROOT/lib/core/bootstrap.sh"
zsh_setup::core::bootstrap::load_module "plugins::manager"
```

### 3. Configuration Management
Centralized configuration with environment variable overrides:
```bash
zsh_setup::core::config::get "oh_my_zsh_dir"
zsh_setup::core::config::set "verbose" "false"
```

### 4. State Management
JSON-based state store for cross-script communication:
```bash
zsh_setup::state::store::add_plugin "powerlevel10k" "git" "abc123"
zsh_setup::state::store::get_installed_plugins
```

## Usage

### New CLI Interface

```bash
# Install
zsh-setup install [options]

# Update plugins
zsh-setup update

# Remove plugin
zsh-setup remove <plugin-name>

# Check status
zsh-setup status

# Monitor performance
zsh-setup monitor [type]

# Self-heal
zsh-setup heal

# Uninstall
zsh-setup uninstall
```


## Module Dependencies

```
core::bootstrap
  ├── core::config
  ├── core::logger
  └── core::errors

plugins::manager
  ├── plugins::registry
  ├── plugins::resolver
  └── plugins::installer
      ├── system::package_manager
      └── utils::network

config::generator
  └── state::store
```

## Migration Guide

### For Developers
1. Use namespaced functions instead of global ones
2. Load modules via bootstrap instead of direct sourcing
3. Use state store instead of exported arrays
4. Follow the module structure for new features

## Security Architecture

### Input Sanitization
All user-provided input is sanitized before use in file operations or commands:

```bash
# Plugin names are sanitized to prevent command injection
zsh_setup::utils::filesystem::sanitize_name "$plugin_name"
# Removes all characters except: alphanumeric, dash, underscore, dot
```

### File Permissions
Secure defaults for all created files and directories:

| Type | Permissions | Reason |
|------|-------------|--------|
| State directory | 700 | Owner-only access |
| State file | 600 | Owner read/write only |
| Worker scripts | 700 | Owner execute only |
| Config backups | 644 | Standard read/write |

### State File Location
State files follow XDG Base Directory specification:
- Location: `$XDG_STATE_HOME/zsh-setup/state.json`
- Fallback: `~/.local/state/zsh-setup/state.json`
- Benefits: Survives reboots, proper permissions, user-specific

### Temporary Files
Temporary files are created with secure patterns:
- Use `mktemp` with random suffixes (`.XXXXXX`)
- Set restrictive permissions immediately after creation
- Cleanup traps ensure removal on exit/interrupt

### Command Injection Prevention
- All plugin names sanitized before use in shell commands
- No direct `eval` of user input
- Proper quoting in all command constructions
- Validation before git operations

### Testing
Security features are validated with comprehensive tests:
- `tests/test_security.sh` - 12 security-focused tests
- Input sanitization verification
- Permission validation
- Temp file security checks

## Benefits

1. **Modularity**: Clear separation of concerns
2. **Testability**: Isolated modules are easier to test
3. **Maintainability**: Organized codebase with clear dependencies
4. **Extensibility**: Easy to add new commands and modules
5. **Namespace Safety**: No function name conflicts
6. **Security**: Input sanitization and secure file handling

## Testing Guidelines

### Running Tests
```bash
# Run all tests
tests/test_runner.sh all

# Run security tests
tests/test_security.sh

# Run shellcheck
tests/run_shellcheck.sh
```

### Writing Tests
1. Use test_helpers.sh for consistency
2. Test both success and failure cases
3. Clean up test artifacts
4. Mock external dependencies when possible

### Test Coverage
- Security features: input sanitization, permissions, temp files
- State management: JSON parsing, file operations
- Bootstrap: module loading, dependency resolution

## Future Enhancements

- Unit tests for each module
- Plugin system for custom commands
- Configuration file validation
- Performance monitoring dashboard
- Automated dependency updates
- Continuous integration with GitHub Actions
