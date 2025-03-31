# macOS Cleanup Utility

An interactive, safety-focused utility script to clean temporary files, caches, and logs on macOS systems.

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)

## Overview

The macOS Cleanup Utility (`mac-cleanup.zsh`) is a comprehensive, interactive cleanup tool designed to help macOS users free up disk space by safely removing temporary files, application caches, logs, and other unnecessary data that accumulates over time.

Key features:
- 🔍 Interactive selection of cleanup operations
- 🔒 Built-in safety measures and confirmations
- 📦 Automatic backups of cleaned data
- 🎨 Color-coded output for better readability
- 🧰 Comprehensive cleaning options
- 🤖 Smart detection of installed applications
- 📊 Disk space savings summary

## System Requirements

- macOS 10.15 (Catalina) or later
- Zsh shell (default on modern macOS)
- Administrative account (d_account) for certain cleanup operations
- Sufficient disk space for temporary backups

## Installation

### Quick Install

1. Download the script:
   ```bash
   curl -o ~/mac-cleanup.zsh https://raw.githubusercontent.com/yourusername/mac-cleanup/main/mac-cleanup.zsh
   ```

2. Make it executable:
   ```bash
   chmod +x ~/mac-cleanup.zsh
   ```

3. Run the script:
   ```bash
   ~/mac-cleanup.zsh
   ```

## Usage

1. Open Terminal.app
2. Run the script:
   ```bash
   ./mac-cleanup.zsh
   ```

3. Follow the interactive prompts to select which cleanup operations you want to perform.
   - Each option shows the size of files that will be cleaned
   - This helps you decide which cleanups are worth your time
4. Confirm your selection and wait for the cleanup to complete.

## Cleanup Operations

The script can clean the following areas of your macOS system:

### User & System Files

- **User Cache** - Cleans the cache files in `~/Library/Caches`
- **System Cache** - Cleans the system-wide cache in `/Library/Caches` (requires admin privileges)
- **Application Logs** - Removes application log files in `~/Library/Logs`
- **System Logs** - Cleans system log files in `/var/log` (requires admin privileges)
- **Temporary Files** - Cleans temporary files in `/tmp`, `$TMPDIR`, and application temp directories

### Application-Specific

- **Safari Cache** - Cleans Safari browser cache and web data
- **Chrome Cache** - Cleans Google Chrome browser cache and web data
- **Application Container Caches** - Cleans cache files in application containers
- **Saved Application States** - Cleans saved application states
- **Developer Tool Temp Files** - Cleans temporary files from IntelliJ IDEA and VS Code

### System Maintenance

- **Corrupted Preference Lockfiles** - Removes orphaned preference lockfiles
- **Empty Trash** - Empties the user's Trash
- **Homebrew Cache** - Cleans Homebrew package manager cache
- **Flush DNS Cache** - Flushes the DNS cache

## Safety Features

The script includes several safety measures to protect your system:

- **Automatic Backups** - Creates backups of all cleaned files before removal
- **Non-root Operation** - Refuses to run as root to prevent system damage
- **Interactive Confirmation** - Requires confirmation before performing potentially impactful operations
- **Selective Cleanup** - Allows you to choose which areas to clean
- **Smart Detection** - Only offers to clean applications that are actually installed
- **Detailed Warnings** - Provides clear warnings for operations with potential side effects
- **Space Saved Summary** - Shows how much disk space was reclaimed after cleanup

## Backup and Restoration

Before cleaning any files, the script automatically creates backups in `~/.mac-cleanup-backups/` with a timestamp.

To restore from a backup:
1. Navigate to the backup directory:
   ```bash
   cd ~/.mac-cleanup-backups/YYYY-MM-DD-HH-MM-SS/
   ```
2. Extract the backup archive:
   ```bash
   tar -xzf backup_name.tar.gz -C /destination/path/
   ```

## Dependencies

The script depends on [gum](https://github.com/charmbracelet/gum) for the interactive interface. If gum is not installed, the script will offer to install it automatically and can remove it after use if desired.

## Troubleshooting

If you encounter any issues:

1. **Permission Denied Errors**: Make sure the script is executable (`chmod +x mac-cleanup.zsh`).
2. **Admin Privileges**: Some operations require admin privileges. Enter your password when prompted.
3. **Backup Failures**: Ensure you have sufficient disk space for backups.
4. **Gum Installation Failures**: If automatic installation fails, try installing gum manually:
   ```bash
   brew install gum
   ```

## License

This script is released under the MIT License. See the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Disclaimer

This script is provided as-is with no warranties. Always ensure you have recent backups of your important data before performing system cleanup operations.