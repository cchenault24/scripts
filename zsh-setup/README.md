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

## Included Scripts

- `setup_zsh.sh`: Main entry point that orchestrates the entire setup process
- `setup_core.sh`: Core utility functions for system checks, backups, and shell management
- `install_plugins.sh`: Handles the installation of Zsh plugins from various sources
- `install_functions.sh`: Helper functions for plugin installation and verification
- `generate_zshrc.sh`: Creates a customized `.zshrc` file based on installed plugins
- `uninstall_zsh.sh`: Removes Oh My Zsh, plugins, and configurations if needed
- `plugins.conf`: Configuration file listing available plugins
- `plugin_dependencies.conf`: Mapping of plugin dependencies

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

   ```
   git clone https://github.com/yourusername/zsh-setup-scripts.git
   ```

2. Navigate to the directory:

   ```
   cd zsh-setup-scripts
   ```

3. Make the scripts executable:

   ```
   chmod +x *.sh
   ```

4. Run the setup script:
   ```
   ./setup_zsh.sh
   ```

## Usage Options

The main setup script accepts several command-line options:

```
./setup_zsh.sh [options]

Options:
  --no-backup         Skip backup of existing .zshrc
  --skip-ohmyzsh      Skip Oh My Zsh installation
  --skip-plugins      Skip plugin installation
  --no-shell-change   Do not change the default shell to Zsh
  --quiet             Suppress verbose output
  --help              Display this help message
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

```
./uninstall_zsh.sh
```

This will:

- Remove Oh My Zsh and all installed plugins
- Delete Zsh configuration files
- Reset your default shell to Bash
- Optionally remove Homebrew packages that were installed as dependencies

## Troubleshooting

- **Log Files**: Check the log files in `/tmp/` for detailed installation information
- **Shell Not Changed**: You may need to log out and log back in for shell changes to take effect
- **Plugin Installation Failures**: Make sure you have an active internet connection and required dependencies

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgments

- Oh My Zsh community for the amazing framework
- Authors of all the plugins included in this setup
