# Zsh Setup Scripts

A collection of shell scripts to automate the installation, configuration, and management of Zsh with Oh My Zsh and useful plugins.

## Overview

This project provides a streamlined way to set up a powerful Zsh environment with popular plugins and sensible defaults. It's designed to work on macOS and most Linux distributions with minimal dependencies.

## Features

- **Automated Installation**: One-command setup of Zsh, Oh My Zsh, and plugins
- **Custom Configuration Preservation**: `.zshrc.local` support keeps your customizations safe across updates
- **Configurable Plugin Selection**: Interactive menu to choose which plugins to install
- **Security Hardened**: Input sanitization, secure file permissions, XDG-compliant state management
- **Idempotent**: Safe to run multiple times without losing custom configurations
- **Smart Configuration**: Generates a comprehensive `.zshrc` based on installed plugins
- **Comprehensive Testing**: 12+ security tests, shellcheck integration, CI-ready
- **Backup & Safety**: Automatically backs up existing configurations with timestamped backups
- **Clean Uninstallation**: Complete removal option if you want to revert changes

## Architecture

This project uses a modern, modular architecture with namespaced functions. See [ARCHITECTURE.md](./ARCHITECTURE.md) for detailed information.

### Main Entry Point

- `zsh-setup`: Unified CLI entry point for all commands

### Key Components

- **Commands**: Individual command implementations in `commands/`
- **Core Libraries**: Infrastructure in `lib/core/` (bootstrap, config, logger, errors)
- **Plugin System**: Plugin management in `lib/plugins/` (registry, resolver, installer, manager)
- **State Management**: JSON-based state store in `lib/state/`
- **Configuration**: Config management in `lib/config/` (validator, backup, generator)
- **System Operations**: System utilities in `lib/system/` (package manager, validation, shell)


## Supported Plugins

The scripts can install and configure many popular Zsh plugins including:

- **Themes**: Powerlevel10k
- **Autocompletion**: zsh-autosuggestions, zsh-completions
- **Syntax Highlighting**: zsh-syntax-highlighting
- **Navigation**: autojump, zoxide, fzf
- **Utilities**: thefuck, bat, fd, ripgrep, eza

## Requirements

- Zsh (4.0 or higher)
- Git
- Curl
- Homebrew (optional, for macOS)

## Quick Links

- 📥 **[Installation Guide](#installation)** - Get started
- 🔄 **[Restore/Undo Guide](./RESTORE.md)** - Rollback or restore from backup
- ⚙️ **[Custom Configs Guide](./CUSTOM_CONFIGS.md)** - Preserve your customizations
- 🔒 **[Security Policy](./SECURITY.md)** - Security measures and best practices
- 🏗️ **[Architecture](./ARCHITECTURE.md)** - Design and code structure
- 👥 **[Development Guide](./docs/DEVELOPMENT.md)** - Contributing and development

## Installation

1. Clone this repository:

   ```bash
   git clone https://github.com/yourusername/scripts.git
   cd scripts/zsh-setup
   ```

2. Make the CLI executable:

   ```bash
   chmod +x zsh-setup
   ```

3. (Optional) Add to PATH for global access:

   ```bash
   # Add to ~/.zshrc or ~/.bashrc
   export PATH="$PATH:$(pwd)"
   ```

4. Run the setup:

   ```bash
   ./zsh-setup install
   ```

   Or if added to PATH:

   ```bash
   zsh-setup install
   ```

   **Interactive Plugin Selection:**
   - Use **↑↓ arrow keys** to navigate
   - Press **Tab** to select/deselect multiple plugins
   - Press **Enter** to confirm and continue
   - Type to search/filter plugins

> **💡 Tip**: Your existing `.zshrc` will be backed up to `~/.zsh_backup/` and custom configs automatically preserved in `~/.zshrc.local`. See the **[Restore Guide](./RESTORE.md)** for rollback options.

## Usage

### New CLI Interface

The project uses a unified CLI interface:

```bash
# Install Zsh, Oh My Zsh, and plugins
zsh-setup install [options]

# Update installed plugins
zsh-setup update

# Remove a specific plugin
zsh-setup remove <plugin-name>

# Check installation status
zsh-setup status

# Monitor performance
zsh-setup monitor [type]

# Self-heal issues
zsh-setup heal

# Uninstall completely
zsh-setup uninstall

# Show help
zsh-setup help
```

### Command Options

Install command options:

```
--no-backup         Skip backup of existing .zshrc
--skip-ohmyzsh      Skip Oh My Zsh installation
--skip-plugins      Skip plugin installation
--no-shell-change   Do not change the default shell to Zsh
--no-privileges     Run without requiring sudo (skips privilege-requiring operations)
--quiet             Suppress verbose output
--dry-run           Preview changes without executing
```

## Custom Configurations

### Preserving Your Custom Settings

zsh-setup supports a **`.zshrc.local`** file for your custom configurations. This file is **never overwritten** and is automatically sourced by the generated `.zshrc`.

**Quick Start:**
```bash
# Option 1: Automatic migration during install
./zsh-setup install
# Your custom configs are automatically extracted to ~/.zshrc.local

# Option 2: Manual migration first
./migrate-custom-configs.sh
./zsh-setup install

# Option 3: Create manually
nano ~/.zshrc.local
# Add your custom aliases, functions, and settings
```

**Benefits:**
- ✅ Your customizations survive updates and reinstalls
- ✅ Clean separation between generated and custom configs
- ✅ Safe to run `zsh-setup install` multiple times
- ✅ Automatic backup of existing configurations

📄 **[Complete Custom Configuration Guide](./CUSTOM_CONFIGS.md)**

### Adding Custom Plugins

You can add or modify available plugins by editing the `plugins.conf` file. Each line follows this format:

```
plugin_name|type|url/package_name|description
```

Where:

- `plugin_name`: Name of the plugin
- `type`: Installation method (git, brew, omz, npm)
- `url/package_name`: Source URL or package name
- `description`: Short description of the plugin

### Modifying Plugin Dependencies

Dependencies are defined in `plugin_dependencies.conf` using this format:

```
plugin_name=dependency1,dependency2,...
```

## Uninstallation & Restoration

### Full Uninstall

If you want to revert all changes and remove the Zsh configuration:

```bash
./zsh-setup uninstall
```

This will:
- Remove Oh My Zsh and all installed plugins
- Delete Zsh configuration files
- Restore your original `.zshrc` from backup
- Reset your default shell to Bash (optional)
- Optionally remove Homebrew packages that were installed as dependencies

### Restore from Backup

If you just want to restore your previous configuration without full uninstall:

```bash
# List available backups
ls -la ~/.zsh_backup/

# Restore specific backup
cp ~/.zsh_backup/.zshrc.YYYYMMDD_HHMMSS ~/.zshrc

# Reload shell
source ~/.zshrc
```

📄 **[Complete Restore & Undo Guide](./RESTORE.md)** - Detailed restoration instructions for all scenarios

## Security

zsh-setup implements multiple security measures to protect your system:

### Input Sanitization
- All plugin names are sanitized to prevent command injection attacks
- Special characters like semicolons, pipes, and backticks are removed
- Path traversal attempts are blocked

### Secure File Handling
- State files stored in `~/.local/state/zsh-setup/` with 600 permissions
- Temporary files created with restrictive 700 permissions
- Cleanup traps ensure no temporary files are left behind

### XDG Compliance
- State files follow XDG Base Directory specification
- User-specific permissions prevent unauthorized access
- Files survive system reboots (not in `/tmp`)

For detailed security information, see [SECURITY.md](./SECURITY.md).

## Testing

The project includes comprehensive test suites:

### Running Tests

```bash
# Run all tests
tests/test_runner.sh all

# Run security tests
tests/test_security.sh

# Run shellcheck linting
tests/run_shellcheck.sh
```

### Test Coverage
- **Security Tests**: 12 tests validating input sanitization and file permissions
- **State Management**: Tests for JSON parsing and storage
- **Integration Tests**: End-to-end workflow validation

### Development
For development guidelines and testing practices, see [docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md).

## Troubleshooting

- **Log Files**: Check log files (retained on failure) for detailed installation information
- **Shell Not Changed**: Log out and log back in for shell changes to take effect
- **Plugin Installation Failures**: Verify internet connection and required dependencies
- **Permission Issues**: Ensure proper file permissions with `./zsh-setup heal`
- **State File Missing**: Check `~/.local/state/zsh-setup/state.json`

Run with `--verbose` flag for detailed output:
```bash
./zsh-setup install --verbose
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Documentation

- **[ARCHITECTURE.md](./ARCHITECTURE.md)** - Modular architecture and design principles
- **[SECURITY.md](./SECURITY.md)** - Security policy and threat model
- **[CUSTOM_CONFIGS.md](./CUSTOM_CONFIGS.md)** - Guide to preserving custom configurations
- **[docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md)** - Development setup and contributing guide

## Contributing

Contributions are welcome! Please read [docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md) for development setup, code standards, and testing guidelines.

Before contributing:
1. Install shellcheck: `brew install shellcheck`
2. Run tests: `tests/test_runner.sh all`
3. Follow code standards and security guidelines
4. Add tests for new features

## Acknowledgments

- Oh My Zsh community for the amazing framework
- Authors of all the plugins included in this setup
