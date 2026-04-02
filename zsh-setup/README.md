# Zsh Setup Scripts

A collection of shell scripts to automate the installation, configuration, and management of Zsh with Oh My Zsh and useful plugins.

## Overview

This project provides a streamlined way to set up a powerful Zsh environment with popular plugins and sensible defaults. It's designed to work on macOS and most Linux distributions with minimal dependencies.

## Features

- **Automated Installation**: One-command setup of Zsh, Oh My Zsh, and plugins
- **Configurable Plugin Selection**: Interactive menu to choose which plugins to install
- **Smart Configuration**: Generates a comprehensive `.zshrc` based on installed plugins
- **Backup & Safety**: Automatically backs up existing configurations
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
--quiet             Suppress verbose output
--dry-run           Preview changes without executing
```

## Customization

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

## Uninstallation

If you want to revert all changes and remove the Zsh configuration:

```bash
zsh-setup uninstall
```

Or using the direct path:

```bash
./bin/zsh-setup uninstall
```

This will:

- Remove Oh My Zsh and all installed plugins
- Delete Zsh configuration files
- Reset your default shell to Bash (optional)
- Optionally remove Homebrew packages that were installed as dependencies

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

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgments

- Oh My Zsh community for the amazing framework
- Authors of all the plugins included in this setup
