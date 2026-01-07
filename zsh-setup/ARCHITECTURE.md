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

## Benefits

1. **Modularity**: Clear separation of concerns
2. **Testability**: Isolated modules are easier to test
3. **Maintainability**: Organized codebase with clear dependencies
4. **Extensibility**: Easy to add new commands and modules
5. **Namespace Safety**: No function name conflicts

## Future Enhancements

- Unit tests for each module
- Plugin system for custom commands
- Configuration file validation
- Performance monitoring dashboard
- Automated dependency updates
